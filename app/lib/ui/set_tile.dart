import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_controller.dart';
import '../core/analysis.dart';
import '../core/models.dart';
import 'common.dart';

/// Fondo rojo con papelera que aparece al deslizar para borrar.
Widget swipeDeleteBackground() => Container(
  color: Colors.red.shade700,
  alignment: Alignment.centerRight,
  padding: const EdgeInsets.symmetric(horizontal: 20),
  child: const Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text('Borrar', style: TextStyle(color: Colors.white)),
      SizedBox(width: 8),
      Icon(Icons.delete_outline, color: Colors.white),
    ],
  ),
);

/// Una serie con su resumen. Toque = ver/corregir sus repeticiones;
/// botón de la derecha = reasignar la serie entera; deslizar a la izquierda = borrar
/// (con "Deshacer").
class SetTile extends StatelessWidget {
  final AppController c;
  final WorkSet set;
  const SetTile({super.key, required this.c, required this.set});

  @override
  Widget build(BuildContext context) {
    final rs = c.repsOfSet(set.id);
    final m = c.settings.metric;
    final sum = summarizeSet(rs, m);
    final player = c.playerById(set.playerId);
    final load = rs.isEmpty ? 0.0 : rs.first.loadKg;
    final level = c.levelFor(sum?.lossPercent ?? 0, setId: set.id);
    final dayRm = c.settings.compareProfileRm ? c.dayRmFor(set.id) : null;
    final romSum = summarizeSetRom(rs, c.romRefForSet(set.id));
    final romText = romSum == null ? null : setRomText(romSum);

    Future<void> delete() async {
      final messenger = ScaffoldMessenger.of(context);
      final theme = Theme.of(context);
      final deleted = await c.deleteSet(set.id);
      if (deleted == null) return;
      final n = deleted.reps.length;
      if (!messenger.mounted) return;
      showAppSnackOn(
        messenger,
        theme,
        'Serie borrada ($n rep${n == 1 ? '' : 's'})',
        actionLabel: 'Deshacer',
        onAction: () => c.restore(deleted),
      );
    }

    return Dismissible(
      key: ValueKey('set-${set.id}'),
      direction: DismissDirection.endToStart,
      background: swipeDeleteBackground(),
      onDismissed: (_) => delete(),
      child: ListTile(
        onLongPress: () async {
          final ok = await showModalBottomSheet<bool>(
            context: context,
            showDragHandle: true,
            builder: (ctx) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      '${c.exerciseById(set.exerciseId).name} · ${kg(load)} kg · '
                      '${player?.name ?? 'Sin asignar'}',
                      style: Theme.of(ctx).textTheme.titleMedium,
                    ),
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.delete_outline,
                      color: Colors.red,
                    ),
                    title: Text(
                      'Eliminar serie (${rs.length} rep${rs.length == 1 ? '' : 's'})',
                      style: const TextStyle(color: Colors.red),
                    ),
                    onTap: () => Navigator.pop(ctx, true),
                  ),
                ],
              ),
            ),
          );
          if (ok == true) await delete();
        },
        leading: CircleAvatar(
          backgroundColor: fatigueColor(level).withValues(alpha: 0.25),
          child: Text(
            '${rs.length}',
            style: TextStyle(
              color: fatigueColor(level),
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text('${c.exerciseById(set.exerciseId).name} · ${kg(load)} kg'),
        subtitle: Text.rich(
          TextSpan(
            text: sum == null
                ? DateFormat('HH:mm').format(set.start)
                : '${DateFormat('HH:mm').format(set.start)} · mejor ${v2(sum.best)} ${m.label} · '
                      '${lossText(sum.lossPercent)}',
            children: [
              if (dayRm != null)
                TextSpan(
                  text: ' · 1RM hoy ${dayRmText(dayRm)}',
                  style: TextStyle(color: dayRmColor(dayRm.level)),
                ),
              if (romText != null)
                TextSpan(
                  text: ' · $romText',
                  style: const TextStyle(color: kWarning),
                ),
            ],
          ),
        ),
        trailing: TextButton(
          onPressed: () async {
            final r = await pickPlayer(
              context,
              c,
              current: set.playerId,
              title: 'Asignar la serie entera a…',
            );
            if (r != null) c.reassign(set.id, r.id);
          },
          child: Text(
            player?.name ?? 'Asignar',
            style: TextStyle(color: player == null ? Colors.amber : null),
          ),
        ),
        onTap: () => showSetDetail(context, c, set.id),
      ),
    );
  }
}

/// Resultado de elegir deportista: [id] null = sin asignar.
class PickedPlayer {
  final String? id;
  const PickedPlayer(this.id);
}

Future<PickedPlayer?> pickPlayer(
  BuildContext context,
  AppController c, {
  required String? current,
  required String title,
}) {
  return showModalBottomSheet<PickedPlayer>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.7,
        ),
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(title, style: Theme.of(ctx).textTheme.titleMedium),
            ),
            ListTile(
              leading: const Icon(Icons.person_off_outlined),
              title: const Text('Sin asignar'),
              selected: current == null,
              onTap: () => Navigator.pop(ctx, const PickedPlayer(null)),
            ),
            for (final p in c.activePlayers)
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(p.name),
                selected: current == p.id,
                onTap: () => Navigator.pop(ctx, PickedPlayer(p.id)),
              ),
          ],
        ),
      ),
    ),
  );
}

/// Borra una repetición y ofrece deshacer en [messenger].
Future<void> deleteRepWithUndo(
  ScaffoldMessengerState messenger,
  ThemeData theme,
  AppController c,
  Rep r,
  int number,
) async {
  final deleted = await c.deleteRep(r.id);
  if (deleted == null || !messenger.mounted) return;
  showAppSnackOn(
    messenger,
    theme,
    'Repetición $number borrada (${v2(r.velocity(c.settings.metric))} m/s)',
    actionLabel: 'Deshacer',
    onAction: () => c.restore(deleted),
  );
}

/// Repeticiones de una serie: deslizar para borrar, "Mover" para reasignar.
Future<void> showSetDetail(
  BuildContext context,
  AppController c,
  String setId,
) {
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      builder: (_, sc) => sheetWithMessenger(
        ListenableBuilder(
          listenable: c,
          builder: (ctx, _) {
            final set = c.setById(setId);
            final rs = set == null ? const <Rep>[] : c.repsOfSet(setId);
            if (set == null || rs.isEmpty) {
              return const Center(
                child: Text('La serie ya no tiene repeticiones.'),
              );
            }
            final m = c.settings.metric;
            var best = 0.0;
            return ListView(
              controller: sc,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Text(
                    '${c.exerciseById(set.exerciseId).name} · ${kg(rs.first.loadKg)} kg · '
                    '${c.playerById(set.playerId)?.name ?? 'Sin asignar'}',
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    'Desliza una repetición a la izquierda para borrarla.',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ),
                for (var i = 0; i < rs.length; i++)
                  Builder(
                    builder: (itemCtx) {
                      final r = rs[i];
                      final v = r.velocity(m);
                      if (v > best) best = v;
                      final loss = velocityLossPercent(best, v);
                      final level = c.levelFor(loss, setId: r.setId);
                      return Dismissible(
                        key: ValueKey('rep-${r.id}'),
                        direction: DismissDirection.endToStart,
                        background: swipeDeleteBackground(),
                        onDismissed: (_) => deleteRepWithUndo(
                          ScaffoldMessenger.of(itemCtx),
                          Theme.of(itemCtx),
                          c,
                          r,
                          i + 1,
                        ),
                        child: ListTile(
                          dense: true,
                          leading: Text(
                            '${i + 1}',
                            style: const TextStyle(fontSize: 16),
                          ),
                          title: Text(
                            '${v2(v)} ${m.label}  ·  ${lossText(loss)}',
                            style: TextStyle(color: fatigueColor(level)),
                          ),
                          subtitle: Text(
                            '${DateFormat('HH:mm:ss').format(r.time)} · ROM ${r.romCm.toStringAsFixed(0)} cm',
                          ),
                          trailing: TextButton.icon(
                            icon: const Icon(Icons.swap_horiz, size: 18),
                            label: const Text('Mover'),
                            onPressed: () async {
                              final p = await pickPlayer(
                                ctx,
                                c,
                                current: set.playerId,
                                title: 'Mover la repetición ${i + 1} a…',
                              );
                              if (p != null) await c.moveRep(r.id, p.id);
                            },
                          ),
                        ),
                      );
                    },
                  ),
              ],
            );
          },
        ),
      ),
    ),
  );
}
