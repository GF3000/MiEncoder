import 'package:flutter/material.dart';

import '../app_controller.dart';
import 'common.dart';
import 'player_detail_screen.dart';

class PlayersScreen extends StatelessWidget {
  final AppController c;
  const PlayersScreen({super.key, required this.c});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final list = [...c.players]
          ..sort((a, b) {
            if (a.archived != b.archived) return a.archived ? 1 : -1;
            return a.name.compareTo(b.name);
          });
        return Scaffold(
          appBar: AppBar(title: const Text('Jugadores')),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () async {
              final name = await askText(
                context,
                title: 'Nuevo jugador',
                hint: 'Nombre o dorsal',
              );
              if (name != null && name.trim().isNotEmpty)
                await c.addPlayer(name);
            },
            icon: const Icon(Icons.person_add),
            label: const Text('Añadir'),
          ),
          body: list.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Añade a tus jugadores. Un nombre corto o el dorsal es suficiente: '
                      'aparecerán como botones en la pantalla En vivo.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.only(bottom: 96),
                  children: [
                    for (final p in list)
                      ListTile(
                        leading: Icon(
                          p.archived ? Icons.archive_outlined : Icons.person,
                        ),
                        title: Text(
                          p.name,
                          style: TextStyle(
                            color: p.archived ? Colors.white38 : null,
                          ),
                        ),
                        subtitle: Text(
                          '${c.sets.where((s) => s.playerId == p.id).length} series',
                        ),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                PlayerDetailScreen(c: c, playerId: p.id),
                          ),
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (v) async {
                            if (v == 'rename') {
                              final n = await askText(
                                context,
                                title: 'Renombrar',
                                initial: p.name,
                              );
                              if (n != null && n.trim().isNotEmpty)
                                c.updatePlayer(p.copyWith(name: n.trim()));
                            } else if (v == 'archive') {
                              c.updatePlayer(p.copyWith(archived: !p.archived));
                            } else if (v == 'delete') {
                              final n = c.setsOfPlayer(p.id);
                              final choice = await showDialog<String>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: Text('¿Borrar a ${p.name}?'),
                                  content: Text(
                                    n == 0
                                        ? 'No tiene series registradas.'
                                        : 'Tiene $n series. Puedes conservarlas '
                                              'como "Sin asignar" o borrarlas también. '
                                              'No se puede deshacer.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx),
                                      child: const Text('Cancelar'),
                                    ),
                                    if (n > 0)
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, 'all'),
                                        style: TextButton.styleFrom(
                                          foregroundColor: Colors.redAccent,
                                        ),
                                        child: const Text('Borrar series'),
                                      ),
                                    FilledButton(
                                      onPressed: () =>
                                          Navigator.pop(ctx, 'keep'),
                                      child: Text(
                                        n > 0 ? 'Conservar series' : 'Borrar',
                                      ),
                                    ),
                                  ],
                                ),
                              );
                              if (choice != null) {
                                await c.deletePlayer(
                                  p.id,
                                  deleteData: choice == 'all',
                                );
                              }
                            }
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                              value: 'rename',
                              child: Text('Renombrar'),
                            ),
                            PopupMenuItem(
                              value: 'archive',
                              child: Text(
                                p.archived ? 'Recuperar' : 'Archivar',
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Text(
                                'Borrar',
                                style: TextStyle(color: Colors.redAccent),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        );
      },
    );
  }
}
