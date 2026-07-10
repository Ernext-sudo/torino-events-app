import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/app_state.dart';

/// Gestione fonti a due livelli:
///  - senza PAT: gli switch nascondono/mostrano gli eventi solo nell'app
///  - con PAT: gli switch (e +/cestino) modificano sources.yaml sul repo
///    e rilanciano subito lo scraper
class SourcesScreen extends StatefulWidget {
  const SourcesScreen({super.key});

  @override
  State<SourcesScreen> createState() => _SourcesScreenState();
}

class _SourcesScreenState extends State<SourcesScreen> {
  List<SourceItem>? _remote; // fonti complete lette da sources.yaml
  String? _sha;
  bool _busy = false;

  Future<void> _loadRemote(AppState state) async {
    if (!state.github.configured) return;
    setState(() => _busy = true);
    try {
      final (list, sha) =
          await state.github.fetchSources(state.owner, state.repo, state.branch);
      setState(() { _remote = list; _sha = sha; });
    } catch (e) {
      _snack('Errore lettura sources.yaml: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _saveRemote(AppState state, String message) async {
    if (_remote == null || _sha == null) return;
    setState(() => _busy = true);
    try {
      await state.github.writeSources(
          state.owner, state.repo, state.branch, _remote!, _sha!, message);
      await state.github.triggerScrape(state.owner, state.repo, state.branch);
      _snack('Salvato. Scrape avviato: eventi aggiornati tra ~1 minuto.');
      await _loadRemote(state); // ricarica lo sha nuovo
    } catch (e) {
      _snack('Errore: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final github = state.github.configured;
    // con PAT mostriamo la lista completa dal repo, altrimenti quella
    // (solo id+nome) presente in events.json
    final list = _remote ??
        [for (final s in state.sources) s];

    return Scaffold(
      body: ListView(
        children: [
          _ConfigTile(onSaved: () => _loadRemote(state)),
          if (github && _remote == null)
            ListTile(
              leading: const Icon(Icons.cloud_download),
              title: const Text('Carica fonti dal repo'),
              subtitle: const Text('Legge sources.yaml completo'),
              trailing: _busy
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : null,
              onTap: _busy ? null : () => _loadRemote(state),
            ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('FONTI',
                style: TextStyle(
                    fontSize: 12,
                    letterSpacing: 1.5,
                    color: Colors.white54)),
          ),
          if (list.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Nessuna fonte. Configura il repo qui sopra.',
                  style: TextStyle(color: Colors.white54)),
            ),
          for (final s in list)
            Dismissible(
              key: ValueKey(s.id),
              direction: _remote != null
                  ? DismissDirection.endToStart
                  : DismissDirection.none,
              background: Container(
                color: Colors.red.withOpacity(.7),
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                child: const Icon(Icons.delete),
              ),
              confirmDismiss: (_) => showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text('Eliminare "${s.name}"?'),
                  content: const Text(
                      'La fonte viene rimossa da sources.yaml sul repo.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Annulla')),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Elimina')),
                  ],
                ),
              ),
              onDismissed: (_) {
                _remote!.removeWhere((x) => x.id == s.id);
                _saveRemote(state, 'rimossa fonte ${s.id}');
              },
              child: SwitchListTile(
                title: Text(s.name),
                subtitle: Text(
                  _remote != null
                      ? '${s.type} · ${s.url}'
                      : (state.disabledSourcesLocal.contains(s.id)
                          ? 'Nascosta nell\'app'
                          : 'Visibile'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                value: _remote != null
                    ? s.enabled
                    : !state.disabledSourcesLocal.contains(s.id),
                onChanged: _busy
                    ? null
                    : (v) {
                        if (_remote != null) {
                          setState(() => s.enabled = v);
                          _saveRemote(state,
                              '${v ? "attivata" : "disattivata"} fonte ${s.id}');
                        } else {
                          state.toggleSourceLocal(s.id);
                        }
                      },
              ),
            ),
          const SizedBox(height: 80),
        ],
      ),
      floatingActionButton: _remote != null
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text('Fonte RSS'),
              onPressed: _busy ? null : () => _addDialog(state),
            )
          : null,
    );
  }

  Future<void> _addDialog(AppState state) async {
    final name = TextEditingController();
    final url = TextEditingController();
    String category = 'eventi';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nuova fonte RSS'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Nome')),
            TextField(
                controller: url,
                keyboardType: TextInputType.url,
                decoration:
                    const InputDecoration(labelText: 'URL del feed RSS')),
            const SizedBox(height: 8),
            StatefulBuilder(
              builder: (_, setS) => DropdownButtonFormField<String>(
                value: category,
                decoration:
                    const InputDecoration(labelText: 'Categoria di default'),
                items: [
                  for (final c in categoryMeta.keys)
                    DropdownMenuItem(value: c, child: Text(categoryLabel(c)))
                ],
                onChanged: (v) => setS(() => category = v ?? 'eventi'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annulla')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Aggiungi')),
        ],
      ),
    );

    if (ok != true || name.text.trim().isEmpty || url.text.trim().isEmpty) {
      return;
    }
    final id = name.text
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    _remote!.add(SourceItem(
      id: id,
      name: name.text.trim(),
      type: 'rss',
      url: url.text.trim(),
      defaultCategory: category,
      enabled: true,
    ));
    await _saveRemote(state, 'aggiunta fonte $id');
  }
}

/// Configurazione repo + token, in un ExpansionTile.
class _ConfigTile extends StatefulWidget {
  final VoidCallback onSaved;
  const _ConfigTile({required this.onSaved});

  @override
  State<_ConfigTile> createState() => _ConfigTileState();
}

class _ConfigTileState extends State<_ConfigTile> {
  final _owner = TextEditingController();
  final _repo = TextEditingController();
  final _branch = TextEditingController();
  final _token = TextEditingController();

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    _owner.text = state.owner;
    _repo.text = state.repo;
    _branch.text = state.branch;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return ExpansionTile(
      leading: const Icon(Icons.settings),
      title: const Text('Repo GitHub'),
      subtitle: Text(state.owner.isEmpty
          ? 'Non configurato'
          : '${state.owner}/${state.repo} · ${state.github.configured ? "token ok" : "senza token (solo lettura)"}'),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        TextField(
            controller: _owner,
            decoration: const InputDecoration(labelText: 'Owner (utente)')),
        TextField(
            controller: _repo,
            decoration: const InputDecoration(labelText: 'Repository')),
        TextField(
            controller: _branch,
            decoration:
                const InputDecoration(labelText: 'Branch (default: main)')),
        TextField(
          controller: _token,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Fine-grained PAT (opzionale)',
            helperText:
                'Permessi: Contents read/write + Actions write sul repo',
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          icon: const Icon(Icons.save),
          label: const Text('Salva configurazione'),
          onPressed: () async {
            if (_token.text.trim().isNotEmpty) {
              await state.github.saveToken(_token.text);
              _token.clear();
            }
            await state.saveRepoConfig(
                _owner.text, _repo.text, _branch.text);
            widget.onSaved();
          },
        ),
      ],
    );
  }
}
