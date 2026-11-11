import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_controller.dart';
import 'common.dart';

/// Normaliza para buscar sin tildes ni mayúsculas.
String _norm(String s) {
  const from = 'áàäâéèëêíìïîóòöôúùüûñç';
  const to = 'aaaaeeeeiiiioooouuuunc';
  final lower = s.toLowerCase().trim();
  final b = StringBuffer();
  for (final ch in lower.split('')) {
    final i = from.indexOf(ch);
    b.write(i < 0 ? ch : to[i]);
  }
  return b.toString();
}

/// "+": buscar, convocar/desconvocar deportistas existentes o crear nuevos.
Future<void> showConvokeSheet(BuildContext context, AppController c) {
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(ctx).height * 0.85,
        child: _ConvokeSheet(c: c),
      ),
    ),
  );
}

class _ConvokeSheet extends StatefulWidget {
  final AppController c;
  const _ConvokeSheet({required this.c});

  @override
  State<_ConvokeSheet> createState() => _ConvokeSheetState();
}

class _ConvokeSheetState extends State<_ConvokeSheet> {
  final query = TextEditingController();

  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  Future<void> _create(String name) async {
    await widget.c.createAndAddToSession(name);
    query.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final q = _norm(query.text);
        final all = c.activePlayers; // sin archivados, por nombre
        final matches = q.isEmpty
            ? all
            : all.where((p) => _norm(p.name).contains(q)).toList();
        final inSession = matches.where((p) => c.isInSession(p.id)).toList();
        final others = matches.where((p) => !c.isInSession(p.id)).toList();
        final exact = all.any((p) => _norm(p.name) == q);
        final typed = query.text.trim();
        final count = c.sessionPlayers.length;

        Widget tile(String id, String name, bool checked) => CheckboxListTile(
          key: Key('convoke-$id'),
          value: checked,
          title: Text(name, style: const TextStyle(fontSize: 17)),
          controlAffinity: ListTileControlAffinity.leading,
          onChanged: (v) =>
              v == true ? c.addToSession(id) : c.removeFromSession(id),
        );

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Convocados en ${c.activeSession?.name ?? 'la sesión'}',
                      style: Theme.of(context).textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                key: const Key('convoke-search'),
                controller: query,
                autofocus: all.isEmpty,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Buscar o escribir un nombre nuevo',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (v) {
                  if (v.trim().isNotEmpty && !exact) _create(v.trim());
                },
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: ListView(
                children: [
                  if (typed.isNotEmpty && !exact)
                    ListTile(
                      key: const Key('convoke-create'),
                      leading: const Icon(Icons.person_add_alt_1),
                      title: Text('Crear «$typed» y añadirlo'),
                      onTap: () => _create(typed),
                    ),
                  if (inSession.isNotEmpty) ...[
                    const _Section('En la sesión'),
                    for (final p in inSession) tile(p.id, p.name, true),
                  ],
                  if (others.isNotEmpty) ...[
                    _Section(
                      q.isEmpty ? 'Resto de deportistas' : 'Otros resultados',
                    ),
                    for (final p in others) tile(p.id, p.name, false),
                  ],
                  if (all.isEmpty && typed.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Todavía no hay deportistas. Escribe un nombre arriba para crearlo.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white60),
                      ),
                    ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Listo'),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Section extends StatelessWidget {
  final String text;
  const _Section(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Text(
      text,
      style: TextStyle(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

/// Panel de la sesión: renombrar, nueva sesión y retomar una reciente.
Future<void> showSessionSheet(BuildContext context, AppController c) {
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SizedBox(
      height: MediaQuery.sizeOf(ctx).height * 0.75,
      child: ListenableBuilder(
        listenable: c,
        builder: (ctx, _) {
          final s = c.activeSession;
          final recent = c.recentSessions
              .where((x) => x.id != s?.id)
              .take(10)
              .toList();
          final fmt = DateFormat("d MMM · HH:mm", 'es');
          return ListView(
            children: [
              if (s != null)
                ListTile(
                  key: const Key('session-rename'),
                  leading: const Icon(Icons.event_note),
                  title: Text(
                    s.name,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    'Sesión actual · ${fmt.format(s.start)} · '
                    '${s.playerIds.length} convocados · ${c.setsInSession(s.id)} series',
                  ),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () async {
                    final n = await askText(
                      ctx,
                      title: 'Nombre de la sesión',
                      initial: s.name,
                    );
                    if (n != null) await c.renameSession(s.id, n);
                  },
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: FilledButton.icon(
                  key: const Key('session-new'),
                  icon: const Icon(Icons.add),
                  label: const Text('Nueva sesión'),
                  onPressed: () async {
                    final copy = await askNewSessionCopy(ctx, c);
                    if (copy == null) return;
                    await c.newSession(copyPlayers: copy);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                ),
              ),
              if (recent.isNotEmpty)
                const _Section('Retomar una sesión anterior'),
              for (final r in recent)
                ListTile(
                  leading: const Icon(Icons.history),
                  title: Text(r.name),
                  subtitle: Text(
                    '${fmt.format(r.start)} · ${r.playerIds.length} convocados · '
                    '${c.setsInSession(r.id)} series',
                  ),
                  onTap: () {
                    c.resumeSession(r.id);
                    Navigator.pop(ctx);
                  },
                ),
            ],
          );
        },
      ),
    ),
  );
}

/// ¿Copiar los convocados de la sesión actual? null = cancelar.
Future<bool?> askNewSessionCopy(BuildContext context, AppController c) {
  final n = c.activeSession?.playerIds.length ?? 0;
  if (n == 0) return Future.value(false);
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Nueva sesión'),
      content: Text('¿Empezar con los mismos $n convocados o vacía?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Vacía'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text('Con los $n'),
        ),
      ],
    ),
  );
}

/// Al abrir la app otro día: ¿continuar la sesión o empezar una nueva?
Future<void> askContinueOrNewSession(
  BuildContext context,
  AppController c,
) async {
  final s = c.activeSession;
  if (s == null) return;
  final n = s.playerIds.length;
  final choice = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('¿Nueva sesión?'),
      content: Text(
        'La sesión activa es «${s.name}». ¿Continuarla o empezar una nueva hoy?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, 'continue'),
          child: const Text('Continuar'),
        ),
        if (n > 0)
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'empty'),
            child: const Text('Nueva vacía'),
          ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, 'copy'),
          child: Text(n > 0 ? 'Nueva con los $n' : 'Nueva'),
        ),
      ],
    ),
  );
  if (choice == 'copy') await c.newSession(copyPlayers: true);
  if (choice == 'empty') await c.newSession(copyPlayers: false);
}
