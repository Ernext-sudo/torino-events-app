import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:torino_events/models/models.dart';
import 'package:torino_events/services/app_state.dart';

EventItem _ev(String id, DateTime? start) => EventItem(
      id: id,
      title: 'Evento $id',
      sourceId: 'test',
      start: start,
    );

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

void main() {
  // swipe()/undo() persistono su SharedPreferences: senza binding e mock il
  // plugin non è disponibile e i test falliscono prima di arrivare alla logica.
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final today = _day(DateTime.now());
  final tomorrow = today.add(const Duration(days: 1));

  // Sabato del weekend CORRENTE (se oggi è sab/dom è questo, non il prossimo).
  final wd = today.weekday;
  final saturday = switch (wd) {
    DateTime.saturday => today,
    DateTime.sunday => today.subtract(const Duration(days: 1)),
    _ => today.add(Duration(days: DateTime.saturday - wd)),
  };
  final sunday = saturday.add(const Duration(days: 1));

  AppState stateWith(List<EventItem> events, DateWindow w) => AppState()
    ..events = events
    ..dateWindow = w;

  List<String> ids(AppState s) => s.deck.map((e) => e.id).toList();

  test('DateWindow.oggi tiene solo gli eventi di oggi', () {
    final s = stateWith([
      _ev('oggi', today.add(const Duration(hours: 21))),
      _ev('domani', tomorrow),
      _ev('senza_data', null),
    ], DateWindow.oggi);

    expect(ids(s), ['oggi']);
  });

  test('DateWindow.domani tiene solo gli eventi di domani', () {
    final s = stateWith([
      _ev('oggi', today),
      _ev('domani', tomorrow.add(const Duration(hours: 20))),
    ], DateWindow.domani);

    expect(ids(s), ['domani']);
  });

  test('DateWindow.weekend copre sabato e domenica di questo weekend', () {
    final s = stateWith([
      _ev('sabato', saturday.add(const Duration(hours: 22))),
      _ev('domenica', sunday.add(const Duration(hours: 15))),
      _ev('fra_tre_settimane', today.add(const Duration(days: 21))),
    ], DateWindow.weekend);

    expect(ids(s), containsAll(['sabato', 'domenica']));
    expect(ids(s), isNot(contains('fra_tre_settimane')));
  });

  test('se oggi è sabato o domenica, il weekend è QUESTO, non il prossimo', () {
    // Regressione: la vecchia formula saltava al weekend successivo quando
    // oggi era già sabato/domenica, nascondendo gli eventi del giorno stesso.
    final s = stateWith(
      [_ev('oggi', today.add(const Duration(hours: 18)))],
      DateWindow.weekend,
    );

    final isWeekend = wd == DateTime.saturday || wd == DateTime.sunday;
    expect(ids(s), isWeekend ? ['oggi'] : isEmpty);
  });

  test('DateWindow.tutti non filtra nulla, nemmeno gli eventi senza data', () {
    final s = stateWith([
      _ev('oggi', today),
      _ev('lontano', today.add(const Duration(days: 200))),
      _ev('senza_data', null),
    ], DateWindow.tutti);

    expect(ids(s), ['oggi', 'lontano', 'senza_data']);
  });

  test('gli eventi senza data sono esclusi da ogni finestra tranne "tutti"', () {
    for (final w in DateWindow.values.where((w) => w != DateWindow.tutti)) {
      final s = stateWith([_ev('senza_data', null)], w);
      expect(ids(s), isEmpty, reason: 'finestra $w');
    }
  });

  // ── mazzo: rimanda (swipe sinistra) vs scarta (swipe giù) ────────────────
  group('mazzo', () {
    AppState treEventi() => stateWith([
          _ev('a', today),
          _ev('b', today),
          _ev('c', today),
        ], DateWindow.tutti);

    test('rimandare sposta la carta in fondo, non la elimina', () {
      final s = treEventi();
      s.defer(s.deck.first); // rimanda "a"

      expect(ids(s), ['b', 'c', 'a']);
    });

    test('una carta rimandata si ripresenta anche se è rimasta l\'unica', () {
      final s = stateWith([_ev('solo', today)], DateWindow.tutti);
      s.defer(s.deck.first);

      expect(ids(s), ['solo']);
      // il mazzo non cambia lunghezza: è deckRevision a dire alla UI di
      // ricostruire il CardSwiper, altrimenti resterebbe una schermata vuota
      expect(s.deckRevision, 1);
    });

    test('scartare toglie la carta dal mazzo per sempre', () {
      final s = treEventi();
      s.swipe(s.deck.first, likedIt: false); // scarta "a"

      expect(ids(s), ['b', 'c']);
      expect(s.discarded, contains('a'));
    });

    test('salvare toglie la carta dal mazzo', () {
      final s = treEventi();
      s.swipe(s.deck.first, likedIt: true);

      expect(ids(s), ['b', 'c']);
      expect(s.likedEvents.map((e) => e.id), ['a']);
    });

    test('rimandare due volte la stessa carta la rimette in ultima posizione', () {
      final s = treEventi();
      s.defer(s.deck.first); // a -> in fondo:  b c a
      s.defer(s.deck.first); // b -> in fondo:  c a b

      expect(ids(s), ['c', 'a', 'b']);
    });

    test('una carta rimandata può poi essere scartata e sparisce', () {
      final s = treEventi();
      s.defer(s.deck.first); // b c a
      s.swipe(s.deck.last, likedIt: false); // scarta "a"

      expect(ids(s), ['b', 'c']);
      expect(s.deferred, isNot(contains('a')));
    });

    test('scorrendo tutto il mazzo di rimandi si torna alla prima carta', () {
      final s = treEventi();
      for (var i = 0; i < 3; i++) {
        s.defer(s.deck.first);
      }
      // rimandate tutte e tre nell'ordine a, b, c: il mazzo si ripresenta uguale
      expect(ids(s), ['a', 'b', 'c']);
    });
  });
}
