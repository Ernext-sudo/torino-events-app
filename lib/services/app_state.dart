import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'github_service.dart';

enum DateWindow {
  oggi,
  domani,
  weekend,
  settimana,
  mese,
  tutti,
}

extension DateWindowLabel on DateWindow {
  String get label => switch (this) {
        DateWindow.oggi => 'Oggi',
        DateWindow.domani => 'Domani',
        DateWindow.weekend => 'Weekend',
        DateWindow.settimana => 'Questa settimana',
        DateWindow.mese => 'Prossimi 30 giorni',
        DateWindow.tutti => 'Tutti',
      };
}

class AppState extends ChangeNotifier {
  String owner = '';
  String repo = '';
  String branch = 'main';

  String get rawEventsUrl =>
      'https://raw.githubusercontent.com/$owner/$repo/$branch/events.json';

  final GithubService github = GithubService();

  List<EventItem> events = [];
  List<SourceItem> sources = [];
  DateTime? generatedAt;
  bool loading = false;
  String? error;

  final Set<String> liked = {};
  final Set<String> discarded = {};

  /// Eventi rimandati (swipe a sinistra): restano nel mazzo, in coda, e si
  /// ripresentano. Lista e non Set perché l'ordine di rinvio è l'ordine in cui
  /// torneranno. Volutamente NON persistita: è uno stato di sessione, alla
  /// riapertura il mazzo torna nell'ordine naturale.
  final List<String> deferred = [];

  /// Cambia a ogni azione sul mazzo. Serve alla tab Scopri per ricostruire il
  /// CardSwiper: se resta un solo evento e lo si rimanda, la lista di id non
  /// cambia e senza questo il widget non si accorgerebbe di nulla.
  int deckRevision = 0;
  final Set<String> activeCategories = {};
  final Set<String> disabledSourcesLocal = {};

  // Filtro finestra temporale
  DateWindow dateWindow = DateWindow.tutti;

  static const _prefsKeys = (
    liked: 'liked',
    discarded: 'discarded',
    hiddenSources: 'hidden_sources',
    owner: 'gh_owner',
    repo: 'gh_repo',
    branch: 'gh_branch',
    cache: 'events_cache',
    dateWindow: 'date_window',
  );

  Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    liked.addAll(p.getStringList(_prefsKeys.liked) ?? []);
    discarded.addAll(p.getStringList(_prefsKeys.discarded) ?? []);
    disabledSourcesLocal.addAll(p.getStringList(_prefsKeys.hiddenSources) ?? []);
    owner = p.getString(_prefsKeys.owner) ?? '';
    repo = p.getString(_prefsKeys.repo) ?? '';
    branch = p.getString(_prefsKeys.branch) ?? 'main';
    final dwIndex = p.getInt(_prefsKeys.dateWindow) ?? DateWindow.tutti.index;
    dateWindow = DateWindow.values[dwIndex];
    await github.loadToken();
    final cached = p.getString(_prefsKeys.cache);
    if (cached != null) _applyPayload(jsonDecode(cached));
    notifyListeners();
    if (owner.isNotEmpty && repo.isNotEmpty) await refresh();
  }

  Future<void> saveRepoConfig(String o, String r, String b) async {
    owner = o.trim();
    repo = r.trim();
    branch = b.trim().isEmpty ? 'main' : b.trim();
    final p = await SharedPreferences.getInstance();
    await p.setString(_prefsKeys.owner, owner);
    await p.setString(_prefsKeys.repo, repo);
    await p.setString(_prefsKeys.branch, branch);
    notifyListeners();
    await refresh();
  }

  Future<void> refresh() async {
    if (owner.isEmpty || repo.isEmpty) {
      error = 'Configura il repo GitHub nella tab Fonti';
      notifyListeners();
      return;
    }
    loading = true;
    error = null;
    notifyListeners();
    try {
      final resp = await http.get(Uri.parse(rawEventsUrl));
      if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
      final payload = jsonDecode(utf8.decode(resp.bodyBytes));
      _applyPayload(payload);
      final p = await SharedPreferences.getInstance();
      await p.setString(_prefsKeys.cache, utf8.decode(resp.bodyBytes));
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void _applyPayload(Map<String, dynamic> payload) {
    events = [
      for (final e in (payload['events'] as List? ?? []))
        EventItem.fromJson(e as Map<String, dynamic>)
    ];
    sources = [
      for (final s in (payload['sources'] as List? ?? []))
        SourceItem(
          id: s['id'],
          name: s['name'] ?? s['id'],
          enabled: s['enabled'] ?? true,
        )
    ];
    generatedAt = DateTime.tryParse(payload['generated_at'] ?? '');
  }

  // ------- finestra temporale -------
  bool _inWindow(EventItem e) {
    if (dateWindow == DateWindow.tutti) return true;
    if (e.start == null) return dateWindow == DateWindow.tutti;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final eDay = DateTime(e.start!.year, e.start!.month, e.start!.day);

    return switch (dateWindow) {
      DateWindow.oggi => eDay == today,
      DateWindow.domani => eDay == today.add(const Duration(days: 1)),
      DateWindow.weekend => () {
          // Weekend CORRENTE: se oggi è sabato o domenica il weekend è questo,
          // non il prossimo — altrimenti di sabato il filtro nasconde
          // proprio gli eventi di oggi.
          final wd = today.weekday; // 1=lun … 7=dom
          final sat = switch (wd) {
            DateTime.saturday => today,
            DateTime.sunday => today.subtract(const Duration(days: 1)),
            _ => today.add(Duration(days: DateTime.saturday - wd)),
          };
          final sun = sat.add(const Duration(days: 1));
          return eDay == sat || eDay == sun;
        }(),
      DateWindow.settimana => eDay.isAfter(today.subtract(const Duration(days: 1))) &&
          eDay.isBefore(today.add(const Duration(days: 7))),
      DateWindow.mese => eDay.isAfter(today.subtract(const Duration(days: 1))) &&
          eDay.isBefore(today.add(const Duration(days: 30))),
      DateWindow.tutti => true,
    };
  }

  bool _visible(EventItem e) {
    if (disabledSourcesLocal.contains(e.sourceId)) return false;
    if (activeCategories.isNotEmpty && !activeCategories.contains(e.category)) return false;
    if (!_inWindow(e)) return false;
    return true;
  }

  /// Il mazzo: prima gli eventi non ancora visti, poi in coda quelli rimandati
  /// (swipe a sinistra), nell'ordine in cui sono stati rimandati. Un evento
  /// rimandato si ripresenta; solo lo scarto (swipe in giù) lo toglie di mezzo.
  List<EventItem> get deck {
    final nuovi = <EventItem>[];
    final rimandati = <EventItem>[];
    for (final e in events) {
      if (!_visible(e) || liked.contains(e.id) || discarded.contains(e.id)) {
        continue;
      }
      (deferred.contains(e.id) ? rimandati : nuovi).add(e);
    }
    // in coda nell'ordine di rinvio, non in quello di events
    rimandati.sort((a, b) =>
        deferred.indexOf(a.id).compareTo(deferred.indexOf(b.id)));
    return [...nuovi, ...rimandati];
  }

  List<EventItem> get likedEvents =>
      [for (final e in events) if (liked.contains(e.id)) e];

  List<EventItem> eventsOn(DateTime day, {bool onlyLiked = false}) => [
        for (final e in events)
          if (e.start != null &&
              e.start!.year == day.year &&
              e.start!.month == day.month &&
              e.start!.day == day.day &&
              _visible(e) &&
              !discarded.contains(e.id) &&
              (!onlyLiked || liked.contains(e.id)))
            e
      ];

  // ------- azioni -------
  Future<void> _persistSets() async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_prefsKeys.liked, liked.toList());
    await p.setStringList(_prefsKeys.discarded, discarded.toList());
    await p.setStringList(_prefsKeys.hiddenSources, disabledSourcesLocal.toList());
  }

  void swipe(EventItem e, {required bool likedIt}) {
    (likedIt ? liked : discarded).add(e.id);
    deferred.remove(e.id);
    deckRevision++;
    _persistSets();
    notifyListeners();
  }

  /// Rimanda l'evento in fondo al mazzo: si ripresenterà.
  void defer(EventItem e) {
    deferred
      ..remove(e.id) // se era già stato rimandato, torna in ultima posizione
      ..add(e.id);
    deckRevision++;
    notifyListeners();
  }

  void undo(EventItem e) {
    liked.remove(e.id);
    discarded.remove(e.id);
    deferred.remove(e.id);
    deckRevision++;
    _persistSets();
    notifyListeners();
  }

  void toggleCategory(String c) {
    activeCategories.contains(c) ? activeCategories.remove(c) : activeCategories.add(c);
    notifyListeners();
  }

  void toggleSourceLocal(String id) {
    disabledSourcesLocal.contains(id)
        ? disabledSourcesLocal.remove(id)
        : disabledSourcesLocal.add(id);
    _persistSets();
    notifyListeners();
  }

  Future<void> setDateWindow(DateWindow w) async {
    dateWindow = w;
    final p = await SharedPreferences.getInstance();
    await p.setInt(_prefsKeys.dateWindow, w.index);
    notifyListeners();
  }
}
