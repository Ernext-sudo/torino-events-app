import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:yaml/yaml.dart';

import '../models/models.dart';

/// Gestisce sources.yaml sul repo via GitHub Contents API
/// e lancia lo scrape con workflow_dispatch.
///
/// Serve un fine-grained PAT con permesso "Contents: read/write"
/// (e "Actions: write" per il dispatch) sul solo repo degli eventi.
class GithubService {
  static const _storage = FlutterSecureStorage();
  String? _token;

  bool get configured => _token != null && _token!.isNotEmpty;

  Future<void> loadToken() async => _token = await _storage.read(key: 'gh_pat');

  Future<void> saveToken(String t) async {
    _token = t.trim();
    await _storage.write(key: 'gh_pat', value: _token);
  }

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $_token',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      };

  Uri _contentsUri(String owner, String repo) => Uri.parse(
      'https://api.github.com/repos/$owner/$repo/contents/sources.yaml');

  /// Legge sources.yaml -> (lista fonti complete, sha del file).
  Future<(List<SourceItem>, String)> fetchSources(
      String owner, String repo, String branch) async {
    final resp = await http.get(
        _contentsUri(owner, repo).replace(queryParameters: {'ref': branch}),
        headers: _headers);
    if (resp.statusCode != 200) {
      throw Exception('GitHub GET sources.yaml: HTTP ${resp.statusCode}');
    }
    final body = jsonDecode(resp.body);
    final content =
        utf8.decode(base64.decode((body['content'] as String).replaceAll('\n', '')));
    final doc = loadYaml(content);
    final list = <SourceItem>[
      for (final s in (doc['sources'] as YamlList))
        SourceItem(
          id: s['id'],
          name: s['name'] ?? s['id'],
          type: s['type'] ?? 'rss',
          url: s['url'] ?? '',
          defaultCategory: s['default_category'] ?? 'eventi',
          enabled: s['enabled'] ?? false,
        )
    ];
    return (list, body['sha'] as String);
  }

  /// Riscrive sources.yaml. NB: i commenti nel file vengono persi
  /// (il file viene rigenerato dalla lista).
  Future<void> writeSources(String owner, String repo, String branch,
      List<SourceItem> sources, String sha, String message) async {
    final yamlText = _toYaml(sources);
    final resp = await http.put(
      _contentsUri(owner, repo),
      headers: _headers,
      body: jsonEncode({
        'message': message,
        'content': base64.encode(utf8.encode(yamlText)),
        'sha': sha,
        'branch': branch,
      }),
    );
    if (resp.statusCode >= 300) {
      throw Exception('GitHub PUT sources.yaml: HTTP ${resp.statusCode}');
    }
  }

  /// Avvia subito lo scraper (senza aspettare il cron).
  Future<void> triggerScrape(String owner, String repo, String branch) async {
    final uri = Uri.parse(
        'https://api.github.com/repos/$owner/$repo/actions/workflows/scrape.yml/dispatches');
    final resp = await http.post(uri,
        headers: _headers, body: jsonEncode({'ref': branch}));
    if (resp.statusCode != 204) {
      throw Exception('workflow_dispatch: HTTP ${resp.statusCode}');
    }
  }

  String _yamlEscape(String s) => "'${s.replaceAll("'", "''")}'";

  String _toYaml(List<SourceItem> sources) {
    final b = StringBuffer('# Generato dall\'app Torino Events\nsources:\n');
    for (final s in sources) {
      b.writeln('  - id: ${s.id}');
      b.writeln('    name: ${_yamlEscape(s.name)}');
      b.writeln('    type: ${s.type}');
      b.writeln('    url: ${_yamlEscape(s.url)}');
      b.writeln('    default_category: ${s.defaultCategory}');
      b.writeln('    enabled: ${s.enabled}');
    }
    return b.toString();
  }
}
