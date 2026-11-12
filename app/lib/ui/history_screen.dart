import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_controller.dart';
import '../core/models.dart';
import 'set_tile.dart';

/// Valores especiales del filtro de deportista.
const kFilterAll = '_all';
const kFilterNone = '_none';

/// ¿La serie pasa el filtro? [filter] es [kFilterAll], [kFilterNone] o un id.
bool setMatchesPlayerFilter(WorkSet s, String filter) => switch (filter) {
  kFilterAll => true,
  kFilterNone => s.playerId == null,
  _ => s.playerId == filter,
};

class HistoryScreen extends StatefulWidget {
  final AppController c;
  const HistoryScreen({super.key, required this.c});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String filter = kFilterAll;

  /// null = todas las sesiones.
  String? sessionFilter;

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        // Si el deportista filtrado se borró, volver a "Todos".
        if (filter != kFilterAll &&
            filter != kFilterNone &&
            c.playerById(filter) == null) {
          filter = kFilterAll;
        }
        if (sessionFilter != null && c.sessionById(sessionFilter) == null) {
          sessionFilter = null;
        }
        final sets = c
            .recentSets()
            .where((s) => setMatchesPlayerFilter(s, filter))
            .where((s) => sessionFilter == null || s.sessionId == sessionFilter)
            .toList();
        final byDay = groupBy(
          sets,
          (s) => DateTime(s.start.year, s.start.month, s.start.day),
        );
        final players = [
          ...c.players,
        ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

        DropdownMenuItem<String> divider(String key) =>
            DropdownMenuItem<String>(
              value: key,
              enabled: false,
              child: const Divider(height: 1),
            );

        return Scaffold(
          appBar: AppBar(
            title: const Text('Historial'),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(44),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      key: const Key('history-session-filter'),
                      value: sessionFilter,
                      isDense: true,
                      borderRadius: BorderRadius.circular(12),
                      icon: const Icon(Icons.arrow_drop_down),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Todas las sesiones'),
                        ),
                        for (final ss in c.recentSessions)
                          DropdownMenuItem<String?>(
                            value: ss.id,
                            child: Text('Sesión: ${ss.name}'),
                          ),
                      ],
                      onChanged: (v) => setState(() => sessionFilter = v),
                    ),
                  ),
                ),
              ),
            ),
            actions: [
              DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: filter,
                  borderRadius: BorderRadius.circular(12),
                  items: [
                    const DropdownMenuItem(
                      value: kFilterAll,
                      child: Text('Todos'),
                    ),
                    divider('_div1'),
                    const DropdownMenuItem(
                      value: kFilterNone,
                      child: Text('Sin asignar'),
                    ),
                    if (players.isNotEmpty) divider('_div2'),
                    for (final p in players)
                      DropdownMenuItem(
                        value: p.id,
                        child: Text(
                          p.name,
                          style: TextStyle(
                            color: p.archived ? Colors.white38 : null,
                          ),
                        ),
                      ),
                  ],
                  onChanged: (v) =>
                      v == null ? null : setState(() => filter = v),
                ),
              ),
              const SizedBox(width: 12),
            ],
          ),
          body: sets.isEmpty
              ? Center(
                  child: Text(
                    filter == kFilterAll && sessionFilter == null
                        ? 'Todavía no hay series.'
                        : 'No hay series con este filtro.',
                  ),
                )
              : ListView(
                  children: [
                    for (final day in byDay.keys) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                        child: Text(
                          DateFormat('EEEE d MMMM y', 'es').format(day),
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(color: Colors.white70),
                        ),
                      ),
                      for (final s in byDay[day]!) SetTile(c: c, set: s),
                    ],
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Toca una serie para ver y mover sus repeticiones. Toca el nombre '
                        'para asignar la serie entera. Mantén pulsada una serie (o deslízala '
                        'a la izquierda) para borrarla.',
                        style: TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}
