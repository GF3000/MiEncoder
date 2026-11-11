import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_controller.dart';
import '../core/analysis.dart';
import '../core/models.dart';
import 'common.dart';
import 'load_picker.dart';

class ProfileScreen extends StatefulWidget {
  final AppController c;
  final String? initialPlayerId;
  final String? initialExerciseId;
  final String? initialPeriod;
  const ProfileScreen({
    super.key,
    required this.c,
    this.initialPlayerId,
    this.initialExerciseId,
    this.initialPeriod,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late String? playerId = widget.initialPlayerId;
  late String? exerciseId = widget.initialExerciseId;
  late String period = widget.initialPeriod ?? '30 días';

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        // Solo jugadores con medidas y, para cada uno, solo los ejercicios
        // que ha hecho.
        final done = c.exercisesWithRepsByPlayer();
        final known = c.exercises.map((e) => e.id).toSet();
        final players = c.activePlayers
            .where((p) => done[p.id]?.any(known.contains) ?? false)
            .toList();
        if (players.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: const Text('Perfil carga-velocidad')),
            body: Center(
              child: Text(
                c.activePlayers.isEmpty
                    ? 'Añade jugadores para ver su perfil.'
                    : 'Aún no hay medidas. Registra alguna serie para ver el perfil.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        playerId = players.any((p) => p.id == playerId)
            ? playerId
            : players.first.id;
        final playerExercises = c.exercises
            .where((e) => done[playerId]!.contains(e.id))
            .toList();
        final exIds = playerExercises.map((e) => e.id).toSet();
        if (!exIds.contains(exerciseId)) {
          exerciseId = exIds.contains(c.exerciseId)
              ? c.exerciseId
              : playerExercises.first.id;
        }
        final ex = c.exerciseById(exerciseId!);
        final since = sinceForPeriod(period);
        final metric = c.settings.metric;
        final analysis = c.profileFor(
          playerId: playerId!,
          exerciseId: ex.id,
          since: since,
        );
        final points = analysis.points;
        final profile = analysis.profile;

        return Scaffold(
          appBar: AppBar(title: const Text('Perfil carga-velocidad')),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _addManual(context, c, playerId!, ex.id),
            icon: const Icon(Icons.add),
            label: const Text('Punto manual'),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  _drop('Jugador', playerId!, {
                    for (final p in players) p.id: p.name,
                  }, (v) => setState(() => playerId = v)),
                  _drop('Ejercicio', ex.id, {
                    for (final e in playerExercises) e.id: e.name,
                  }, (v) => setState(() => exerciseId = v)),
                  _drop('Periodo', period, {
                    for (final k in kPeriods.keys) k: k,
                  }, (v) => setState(() => period = v)),
                ],
              ),
              const SizedBox(height: 16),
              if (points.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(
                    child: Text(
                      'Sin repeticiones asignadas en este periodo.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              else ...[
                SizedBox(
                  height: 280,
                  child: _Chart(
                    points: points,
                    profile: profile,
                    mvt: ex.mvt,
                    onTapPoint: (p) => _togglePoint(context, c, p),
                  ),
                ),
                const SizedBox(height: 8),
                const _Legend(),
                const SizedBox(height: 12),
                if (profile == null)
                  const Text(
                    'Hacen falta al menos 2 cargas distintas (y que la velocidad baje con la carga) para trazar el perfil.',
                    style: TextStyle(color: Colors.white60),
                  )
                else
                  _Summary(
                    profile: profile,
                    mvt: ex.mvt,
                    metricLabel: metric.label,
                  ),
                const SizedBox(height: 16),
                Text(
                  'Mejor repetición por carga '
                  '(${analysis.used.length} de ${points.length} en el perfil)',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const Text(
                  'Toca un punto para quitarlo o volver a meterlo en el perfil.',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
                for (final p in points)
                  _PointTile(
                    point: p,
                    mark: c.setById(p.setId)?.profileMark,
                    onTap: () => _togglePoint(context, c, p),
                    onAuto: () => c.setProfileMark(p.setId!, null),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }

  /// Si el punto cuenta, se excluye; si no cuenta, se incluye a mano.
  void _togglePoint(BuildContext context, AppController c, LvPoint p) {
    final setId = p.setId;
    if (setId == null) return;
    final counts = p.status.counts;
    c.setProfileMark(setId, counts ? ProfileMark.exclude : ProfileMark.include);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            counts
                ? '${kg(p.loadKg)} kg excluido del perfil'
                : '${kg(p.loadKg)} kg incluido en el perfil',
          ),
          action: SnackBarAction(
            label: 'Deshacer',
            onPressed: () => c.setProfileMark(
              setId,
              p.status == LvPointStatus.excluded
                  ? ProfileMark.exclude
                  : p.status == LvPointStatus.forced
                  ? ProfileMark.include
                  : null,
            ),
          ),
        ),
      );
  }

  Widget _drop(
    String label,
    String value,
    Map<String, String> items,
    ValueChanged<String> onChanged,
  ) {
    return SizedBox(
      width: 170,
      child: DropdownButtonFormField<String>(
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
            DropdownMenuItem(value: e.key, child: Text(e.value)),
        ],
        onChanged: (v) => v == null ? null : onChanged(v),
      ),
    );
  }

  Future<void> _addManual(
    BuildContext context,
    AppController c,
    String playerId,
    String exerciseId,
  ) async {
    final load = await showLoadPicker(
      context,
      initial: c.loadKg,
      title: 'Carga del punto manual',
    );
    if (load == null || !context.mounted) return;
    final vel = parseNum(
      await askText(
        context,
        title: 'Velocidad (${c.settings.metric.label}, m/s)',
        hint: 'p. ej. 0.85',
        keyboard: const TextInputType.numberWithOptions(decimal: true),
      ),
    );
    if (vel == null || !context.mounted) return;
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (date == null) return;
    await c.addManualPoint(
      playerId: playerId,
      exerciseId: exerciseId,
      loadKg: load,
      velocity: vel,
      date: DateTime(date.year, date.month, date.day, 12),
    );
  }
}

class _Summary extends StatelessWidget {
  final LvProfile profile;
  final double mvt;
  final String metricLabel;
  const _Summary({
    required this.profile,
    required this.mvt,
    required this.metricLabel,
  });

  @override
  Widget build(BuildContext context) {
    final rm = profile.estimated1Rm(mvt);
    Widget cell(String v, String l) => Expanded(
      child: Column(
        children: [
          Text(
            v,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          Text(l, style: const TextStyle(color: Colors.white60, fontSize: 12)),
        ],
      ),
    );
    return Column(
      children: [
        Row(
          children: [
            cell('${kg(rm)} kg', '1RM estimado'),
            cell(profile.r2.toStringAsFixed(2), 'R²'),
            cell('${v2(profile.velocityAt(0))} m/s', 'V a carga 0'),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final pct in [50, 60, 70, 80, 90])
              Chip(
                label: Text(
                  '$pct % → ${kg(profile.loadForPercent(pct.toDouble(), mvt))} kg · '
                  '${v2(profile.velocityAt(profile.loadForPercent(pct.toDouble(), mvt)))}',
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '1RM calculado a $metricLabel = ${v2(mvt)} m/s (ajústalo en Ajustes › Ejercicios).',
          style: const TextStyle(color: Colors.white38, fontSize: 12),
        ),
      ],
    );
  }
}

class _Chart extends StatelessWidget {
  final List<LvPoint> points;
  final LvProfile? profile;
  final double mvt;
  final ValueChanged<LvPoint> onTapPoint;
  const _Chart({
    required this.points,
    required this.profile,
    required this.mvt,
    required this.onTapPoint,
  });

  @override
  Widget build(BuildContext context) {
    final maxLoadPts = points.map((p) => p.loadKg).reduce(math.max);
    final rm = profile?.estimated1Rm(mvt);
    final maxX = (math.max(maxLoadPts, rm ?? 0) * 1.08).ceilToDouble();
    final maxY =
        (math.max(
          points.map((p) => p.velocity).reduce(math.max),
          profile?.velocityAt(0) ?? 0,
        ) *
        1.1);
    final newest = points.map((p) => p.time).max;
    final pointsBar = profile != null ? 1 : 0;

    return LineChart(
      LineChartData(
        lineTouchData: LineTouchData(
          handleBuiltInTouches: false,
          touchSpotThreshold: 24,
          touchCallback: (event, response) {
            if (event is! FlTapUpEvent) return;
            final hit = response?.lineBarSpots?.firstWhereOrNull(
              (s) => s.barIndex == pointsBar,
            );
            if (hit != null) onTapPoint(points[hit.spotIndex]);
          },
        ),
        minX: 0,
        maxX: maxX,
        minY: 0,
        maxY: maxY,
        gridData: const FlGridData(show: true),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            axisNameWidget: const Text(
              'Carga (kg)',
              style: TextStyle(fontSize: 11),
            ),
            sideTitles: SideTitles(showTitles: true, reservedSize: 26),
          ),
          leftTitles: AxisTitles(
            axisNameWidget: const Text('m/s', style: TextStyle(fontSize: 11)),
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              getTitlesWidget: (v, m) => Text(
                v.toStringAsFixed(1),
                style: const TextStyle(fontSize: 10),
              ),
            ),
          ),
        ),
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            HorizontalLine(
              y: mvt,
              color: Colors.redAccent.withValues(alpha: 0.6),
              dashArray: [6, 4],
              label: HorizontalLineLabel(
                show: true,
                labelResolver: (_) => 'VMT',
                style: const TextStyle(fontSize: 10),
              ),
            ),
          ],
        ),
        lineBarsData: [
          if (profile != null)
            LineChartBarData(
              spots: [FlSpot(0, profile!.velocityAt(0)), FlSpot(rm!, mvt)],
              color: Colors.lightBlueAccent,
              barWidth: 2,
              dotData: const FlDotData(show: false),
            ),
          LineChartBarData(
            spots: [for (final p in points) FlSpot(p.loadKg, p.velocity)],
            barWidth: 0,
            color: Colors.transparent,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, _, _, i) {
                final p = points[i];
                if (!p.status.counts) {
                  // Fuera del perfil: hueco, sin relleno.
                  return FlDotCirclePainter(
                    radius: 5,
                    color: Colors.transparent,
                    strokeWidth: 2,
                    strokeColor: _statusColor(p.status),
                  );
                }
                return FlDotCirclePainter(
                  radius: 6,
                  // Los puntos más recientes, más intensos.
                  color: Colors.amber.withValues(
                    alpha: p.time == newest ? 1 : 0.55,
                  ),
                  strokeWidth: p.status == LvPointStatus.forced ? 2 : 0,
                  strokeColor: Colors.white,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

Color _statusColor(LvPointStatus s) => switch (s) {
  LvPointStatus.used || LvPointStatus.forced => Colors.amber,
  LvPointStatus.outlier => Colors.deepOrangeAccent,
  LvPointStatus.excluded => Colors.white38,
};

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    Widget item(Color fill, Color stroke, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: fill,
            shape: BoxShape.circle,
            border: Border.all(color: stroke, width: 2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Colors.white60),
        ),
      ],
    );
    return Wrap(
      spacing: 14,
      runSpacing: 4,
      children: [
        item(Colors.amber, Colors.amber, 'En el perfil'),
        item(
          Colors.transparent,
          _statusColor(LvPointStatus.outlier),
          'Atípico (descartado)',
        ),
        item(
          Colors.transparent,
          _statusColor(LvPointStatus.excluded),
          'Excluido a mano',
        ),
      ],
    );
  }
}

class _PointTile extends StatelessWidget {
  final LvPoint point;
  final ProfileMark? mark;
  final VoidCallback onTap;
  final VoidCallback onAuto;
  const _PointTile({
    required this.point,
    required this.mark,
    required this.onTap,
    required this.onAuto,
  });

  @override
  Widget build(BuildContext context) {
    final p = point;
    final r = p.residual;
    final dist = r == null
        ? ''
        : ' (${r < 0 ? '' : '+'}${v2(r)} m/s respecto a la recta)';
    final subtitle = switch (p.status) {
      LvPointStatus.used => null,
      LvPointStatus.outlier => 'Descartado: se sale de la tendencia$dist',
      LvPointStatus.excluded => 'Excluido a mano',
      LvPointStatus.forced => 'Incluido a mano',
    };
    final counts = p.status.counts;
    return ListTile(
      dense: true,
      onTap: onTap,
      leading: Icon(
        counts ? Icons.check_circle : Icons.remove_circle_outline,
        color: _statusColor(p.status),
        size: 20,
      ),
      title: Text(
        '${kg(p.loadKg)} kg → ${v2(p.velocity)} m/s',
        style: counts
            ? null
            : const TextStyle(
                color: Colors.white54,
                decoration: TextDecoration.lineThrough,
              ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(DateFormat('d MMM', 'es').format(p.time)),
          if (mark != null)
            IconButton(
              tooltip: 'Que decida la app',
              icon: const Icon(Icons.restart_alt, size: 20),
              onPressed: onAuto,
            ),
        ],
      ),
    );
  }
}
