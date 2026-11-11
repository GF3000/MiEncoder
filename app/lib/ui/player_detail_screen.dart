import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_controller.dart';
import '../core/analysis.dart';
import '../core/models.dart';
import 'common.dart';
import 'profile_screen.dart';
import 'set_tile.dart';

/// Ficha de un deportista: resumen, 1RM estimado por ejercicio y sus series,
/// todo filtrado por periodo y ejercicio.
class PlayerDetailScreen extends StatefulWidget {
  final AppController c;
  final String playerId;
  const PlayerDetailScreen({
    super.key,
    required this.c,
    required this.playerId,
  });

  @override
  State<PlayerDetailScreen> createState() => _PlayerDetailScreenState();
}

/// Resumen de 1RM de un ejercicio para un deportista.
class ExerciseEstimate {
  final Exercise exercise;
  final int loads;
  final LvProfile? profile;
  const ExerciseEstimate(this.exercise, this.loads, this.profile);
}

/// Calcula, para cada ejercicio con repeticiones del deportista en el
/// periodo, su perfil carga-velocidad (si hay datos suficientes).
List<ExerciseEstimate> estimatesFor(
  AppController c,
  String playerId, {
  DateTime? since,
  String? exerciseId,
}) {
  final out = <ExerciseEstimate>[];
  for (final e in c.exercises) {
    if (exerciseId != null && e.id != exerciseId) continue;
    final a = c.profileFor(playerId: playerId, exerciseId: e.id, since: since);
    if (a.points.isEmpty) continue;
    out.add(ExerciseEstimate(e, a.used.length, a.profile));
  }
  return out;
}

class _PlayerDetailScreenState extends State<PlayerDetailScreen> {
  String period = '30 días';
  String? exerciseId; // null = todos

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final player = c.playerById(widget.playerId);
        if (player == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('Este deportista ya no existe.')),
          );
        }
        final since = sinceForPeriod(period);
        final sets = c
            .recentSets()
            .where((s) => s.playerId == player.id)
            .where((s) => exerciseId == null || s.exerciseId == exerciseId)
            .where((s) {
              final last = c.repsOfSet(s.id).lastOrNull;
              return last != null &&
                  (since == null || !last.time.isBefore(since));
            })
            .toList();
        final repsCount = sets.fold<int>(
          0,
          (n, s) => n + c.repsOfSet(s.id).length,
        );
        final lastDay = sets.isEmpty
            ? null
            : c.repsOfSet(sets.first.id).last.time;
        final estimates = estimatesFor(
          c,
          player.id,
          since: since,
          exerciseId: exerciseId,
        );

        return Scaffold(
          appBar: AppBar(title: Text(player.name)),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    _Drop(
                      label: 'Periodo',
                      value: period,
                      items: {for (final k in kPeriods.keys) k: k},
                      onChanged: (v) => setState(() => period = v!),
                    ),
                    _Drop(
                      label: 'Ejercicio',
                      value: exerciseId,
                      items: {
                        null: 'Todos',
                        for (final e in c.exercises) e.id: e.name,
                      },
                      onChanged: (v) => setState(() => exerciseId = v),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    _Big('${sets.length}', 'series'),
                    _Big('$repsCount', 'repeticiones'),
                    _Big(
                      lastDay == null
                          ? '–'
                          : DateFormat('d MMM', 'es').format(lastDay),
                      'último día',
                    ),
                  ],
                ),
              ),
              const _Header('1RM estimado'),
              if (estimates.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    'Sin repeticiones en este periodo.',
                    style: TextStyle(color: Colors.white60),
                  ),
                ),
              for (final est in estimates)
                ListTile(
                  title: Text(est.exercise.name),
                  subtitle: Text(
                    est.profile == null
                        ? '${est.loads} carga${est.loads == 1 ? '' : 's'} · '
                              'faltan cargas distintas para estimar'
                        : '${est.loads} cargas · R² ${est.profile!.r2.toStringAsFixed(2)} · '
                              'VMT ${v2(est.exercise.mvt)}',
                  ),
                  trailing: Text(
                    est.profile == null
                        ? '–'
                        : '${kg(est.profile!.estimated1Rm(est.exercise.mvt))} kg',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ProfileScreen(
                        c: c,
                        initialPlayerId: player.id,
                        initialExerciseId: est.exercise.id,
                        initialPeriod: period,
                      ),
                    ),
                  ),
                ),
              const _Header('Series medidas'),
              if (sets.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    'Sin series en este periodo.',
                    style: TextStyle(color: Colors.white60),
                  ),
                ),
              ...groupBy(sets, (WorkSet s) {
                final t = c.repsOfSet(s.id).last.time;
                return DateTime(t.year, t.month, t.day);
              }).entries.expand(
                (e) => [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Text(
                      DateFormat('EEEE d MMMM', 'es').format(e.key),
                      style: const TextStyle(color: Colors.white54),
                    ),
                  ),
                  for (final s in e.value) SetTile(c: c, set: s),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Drop<T> extends StatelessWidget {
  final String label;
  final T value;
  final Map<T, String> items;
  final ValueChanged<T?> onChanged;
  const _Drop({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 170,
    child: DropdownButtonFormField<T>(
      key: ValueKey(value),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
      items: [
        for (final e in items.entries)
          DropdownMenuItem(
            value: e.key,
            child: Text(e.value, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: onChanged,
    ),
  );
}

class _Big extends StatelessWidget {
  final String value, label;
  const _Big(this.value, this.label);

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.white60, fontSize: 12),
        ),
      ],
    ),
  );
}

class _Header extends StatelessWidget {
  final String text;
  const _Header(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(
      text,
      style: TextStyle(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}
