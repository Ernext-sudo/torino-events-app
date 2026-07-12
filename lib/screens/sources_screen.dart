import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/app_state.dart';

class SourcesScreen extends StatefulWidget {
  const SourcesScreen({super.key});
  @override
  State<SourcesScreen> createState() => _SourcesScreenState();
}

class _SourcesScreenState extends State<SourcesScreen> {
  List<SourceItem> _list = [];
  bool _busy = false;
  bool _loaded = false;

  AppState get _state => context.read<AppState>();

  // Ogni operazione di scrittura legge PRIMA lo SHA fresco,
  // poi scrive — così il 409 non può mai verificarsi.
  Future<void> _reload({bool showSpinner = true}) async {
    if (!_state.github.configured) return;
    if (showSpinner) setState(() => _busy = true);
    try {
      final (list, _) = await _state.github.fetchSources(
          _state.owner, _state.repo, _state.branch);
      if (mounted) setState(() { _list = list; _loaded = true; });
    } catch (e) {
      _snack('Errore lettura fonti: $e');
    } finally {
      if (mounted && showSpinner) setState(() => _busy = false);
    }
  }

  Future<void> _save(String message) async {
    setState(() => _busy = true);
    try {
      // Legge SHA fresco ogni volta
      final (_, sha) = await _state.github.fetchSources(
          _state.owner, _state.repo, _state.branch);
      await _state.github.writeSources(
          _state.owner, _state.repo, _state.branch, _list, sha, message);
      _state.github.triggerScrape(
          _state.owner, _state.repo, _state.branch).catchError((_) {});
      _snack('Salvato. Scrape avviato, eventi freschi tra ~1 min.');
    } catch (e) {
      _snack('Errore salvataggio: $e');
      await _reload(showSpinner: false);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 4)));
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final hasToken = state.github.configured;
    // Se non abbiamo caricato dal repo, mostriamo la lista da events.json
    final displayList = _loaded ? _list : state.sources;

    return Scaffold(
      body: ListView(
        children: [
          // ── Config repo ──────────────────────────────────────────
          _ConfigTile(onSaved: _reload),

          // ── Pulsante carica/ricarica ─────────────────────────────
          if (hasToken)
            ListTile(
              leading: _busy
                  ? const SizedBox(width: 24, height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(_loaded ? Icons.sync : Icons.cloud_download),
              title: Text(_loaded ? 'Ricarica fonti dal repo' : 'Carica fonti dal repo'),
              subtitle: _loaded ? null : const Text('Legge sources.yaml completo'),
              onTap: _busy ? null : _reload,
            ),

          // ── Titolo sezione ───────────────────────────────────────
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text('FONTI',
                style: TextStyle(fontSize: 12, letterSpacing: 1.5, color: Colors.white54)),
          ),

          if (displayList.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Nessuna fonte. Configura il repo e carica le fonti.',
                  style: TextStyle(color: Colors.white54)),
            ),

          // ── Lista fonti ──────────────────────────────────────────
          for (final s in displayList)
            Dismissible(
              key: ValueKey(s.id),
              direction: _loaded ? DismissDirection.endToStart : DismissDirection.none,
              background: Container(
                color: Colors.red.withOpacity(.75),
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 24),
                child: const Icon(Icons.delete, color: Colors.white),
              ),
              confirmDismiss: (_) => showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text('Eliminare "${s.name}"?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Annulla')),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Elimina')),
                  ],
                ),
              ),
              onDismissed: (_) {
                setState(() => _list.removeWhere((x) => x.id == s.id));
                _save('rimossa fonte ${s.id}');
              },
              child: ListTile(
                leading: Switch(
                  value: _loaded ? s.enabled : !state.disabledSourcesLocal.contains(s.id),
                  onChanged: _busy ? null : (v) {
                    if (_loaded) {
                      setState(() => s.enabled = v);
                      _save('${v ? "attivata" : "disattivata"} fonte ${s.id}');
                    } else {
                      state.toggleSourceLocal(s.id);
                    }
                  },
                ),
                title: Text(s.name),
                subtitle: Text(
                  _loaded ? '${s.type} · ${s.url}' : s.id,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: _loaded
                    ? IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: _busy ? null : () => _editDialog(s),
                      )
                    : null,
              ),
            ),
          const SizedBox(height: 100),
        ],
      ),

      // ── FAB sempre visibile se token configurato ─────────────────
      floatingActionButton: hasToken
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text('Nuova fonte'),
              onPressed: _busy ? null : _addDialog,
            )
          : null,
    );
  }

  // ── Dialog modifica fonte ────────────────────────────────────────
  Future<void> _editDialog(SourceItem s) async {
    final name = TextEditingController(text: s.name);
    final url = TextEditingController(text: s.url);
    String category = s.defaultCategory;
    // Se la fonte ha un type che l'app non conosce (es. 'todo'), lo teniamo
    // come opzione invece di sovrascriverlo silenziosamente.
    String type = s.type;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Modifica fonte'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name,
                decoration: const InputDecoration(labelText: 'Nome')),
            TextField(controller: url,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(labelText: 'URL della fonte')),
            const SizedBox(height: 8),
            StatefulBuilder(builder: (_, ss) =>
              DropdownButtonFormField<String>(
                value: type,
                decoration: const InputDecoration(
                  labelText: 'Parser',
                  helperText: 'Sceglie come leggere la fonte',
                ),
                items: [
                  for (final t in {...sourceTypes.keys, s.type})
                    DropdownMenuItem(value: t, child: Text(sourceTypeLabel(t))),
                ],
                onChanged: (v) => ss(() => type = v ?? type),
              ),
            ),
            const SizedBox(height: 8),
            StatefulBuilder(builder: (_, ss) =>
              DropdownButtonFormField<String>(
                value: category,
                decoration: const InputDecoration(labelText: 'Categoria'),
                items: [for (final c in categoryMeta.keys)
                  DropdownMenuItem(value: c, child: Text(categoryLabel(c)))],
                onChanged: (v) => ss(() => category = v ?? category),
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annulla')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Salva')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      s.name = name.text.trim();
      s.url = url.text.trim();
      s.defaultCategory = category;
      s.type = type;
    });
    await _save('modificata fonte ${s.id}');
  }

  // ── Dialog aggiungi fonte ────────────────────────────────────────
  Future<void> _addDialog() async {
    // Se non abbiamo ancora caricato le fonti, carichiamo prima
    if (!_loaded) await _reload();

    final name = TextEditingController();
    final url = TextEditingController();
    String category = 'eventi';
    String type = 'rss';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nuova fonte'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name,
                decoration: const InputDecoration(labelText: 'Nome')),
            TextField(controller: url,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(labelText: 'URL della fonte')),
            const SizedBox(height: 8),
            StatefulBuilder(builder: (_, ss) =>
              DropdownButtonFormField<String>(
                value: type,
                decoration: const InputDecoration(
                  labelText: 'Parser',
                  helperText: 'Sceglie come leggere la fonte',
                ),
                items: [for (final t in sourceTypes.keys)
                  DropdownMenuItem(value: t, child: Text(sourceTypeLabel(t)))],
                onChanged: (v) => ss(() => type = v ?? type),
              ),
            ),
            const SizedBox(height: 8),
            StatefulBuilder(builder: (_, ss) =>
              DropdownButtonFormField<String>(
                value: category,
                decoration: const InputDecoration(labelText: 'Categoria'),
                items: [for (final c in categoryMeta.keys)
                  DropdownMenuItem(value: c, child: Text(categoryLabel(c)))],
                onChanged: (v) => ss(() => category = v ?? category),
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annulla')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Aggiungi')),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty || url.text.trim().isEmpty) return;

    final baseId = name.text.trim().toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    final id = _list.any((s) => s.id == baseId)
        ? '${baseId}_${DateTime.now().millisecondsSinceEpoch}'
        : baseId;

    setState(() => _list.add(SourceItem(
      id: id, name: name.text.trim(), type: type,
      url: url.text.trim(), defaultCategory: category, enabled: true,
    )));
    await _save('aggiunta fonte $id');
  }
}

// ── Config repo + token ───────────────────────────────────────────────
class _ConfigTile extends StatefulWidget {
  final VoidCallback onSaved;
  const _ConfigTile({required this.onSaved});
  @override
  State<_ConfigTile> createState() => _ConfigTileState();
}

class _ConfigTileState extends State<_ConfigTile> {
  final _owner  = TextEditingController();
  final _repo   = TextEditingController();
  final _branch = TextEditingController();
  final _token  = TextEditingController();

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>();
    _owner.text  = s.owner;
    _repo.text   = s.repo;
    _branch.text = s.branch;
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return ExpansionTile(
      leading: const Icon(Icons.settings),
      title: const Text('Repo GitHub'),
      subtitle: Text(s.owner.isEmpty
          ? 'Non configurato'
          : '${s.owner}/${s.repo} · ${s.github.configured ? "token ok" : "senza token"}'),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        TextField(controller: _owner,
            decoration: const InputDecoration(labelText: 'Owner')),
        TextField(controller: _repo,
            decoration: const InputDecoration(labelText: 'Repository')),
        TextField(controller: _branch,
            decoration: const InputDecoration(labelText: 'Branch (default: main)')),
        TextField(controller: _token, obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Fine-grained PAT',
              helperText: 'Contents read/write + Actions write',
            )),
        const SizedBox(height: 12),
        FilledButton.icon(
          icon: const Icon(Icons.save),
          label: const Text('Salva configurazione'),
          onPressed: () async {
            if (_token.text.trim().isNotEmpty) {
              await s.github.saveToken(_token.text);
              _token.clear();
            }
            await s.saveRepoConfig(_owner.text, _repo.text, _branch.text);
            widget.onSaved();
          },
        ),
      ],
    );
  }
}
