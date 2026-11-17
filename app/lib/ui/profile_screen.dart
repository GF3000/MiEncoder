import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_controller.dart';
import '../core/analysis.dart';
import '../core/models.dart';
import 'common.dart';
import 'compare_view.dart';
import 'player_picker.dart';
import 'value_sheets.dart';

const _tabular = [FontFeature.tabularFigures()];

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

  /// true = comparar varios deportistas; false = perfil de uno.
  bool compare = false;

  /// Vistos hace poco (el primero, el último), para el carrusel.
  final List<String> _recent = [];

  void _select(String id) => setState(() {
    playerId = id;
    _recent
      ..remove(id)
      ..insert(0, id);
    if (_recent.length > 8) _recent.removeLast();
  });

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
            appBar: AppBar(title: const Text('Perfil')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  c.activePlayers.isEmpty
                      ? 'Añade jugadores para ver su perfil.'
                      : 'Aún no hay medidas. Registra alguna serie para ver el perfil.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }
        playerId = players.any((p) => p.id == playerId)
            ? playerId
            : (c.sessionPlayerIds.firstWhereOrNull(
                    (id) => players.any((p) => p.id == id),
                  ) ??
                  players.first.id);
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
        final analysis = c.profileFor(
          playerId: playerId!,
          exerciseId: ex.id,
          since: sinceForPeriod(period),
        );

        return Scaffold(
          appBar: AppBar(
            title: Text(compare ? 'Comparar' : 'Perfil'),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: SegmentedButton<bool>(
                  key: const Key('profile-mode'),
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                  segments: const [
                    ButtonSegment(
                      value: false,
                      icon: Icon(Icons.person),
                      tooltip: 'Un deportista',
                    ),
                    ButtonSegment(
                      value: true,
                      icon: Icon(Icons.groups),
                      label: Text('Equipo'),
                      tooltip: 'Comparar deportistas',
                    ),
                  ],
                  selected: {compare},
                  onSelectionChanged: (v) => setState(() => compare = v.first),
                ),
              ),
            ],
          ),
          floatingActionButton: compare
              ? null
              : FloatingActionButton.extended(
                  onPressed: () => _addManual(
                    context,
                    c,
                    playerId!,
                    ex.id,
                    analysis.profile,
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('Punto manual'),
                ),
          body: IndexedStack(
            index: compare ? 1 : 0,
            children: [
              _individual(
                context,
                c,
                players,
                done,
                playerExercises,
                ex,
                analysis,
              ),
              CompareView(
                c: c,
                period: period,
                onPeriod: (v) => setState(() => period = v),
                exerciseId: exerciseId,
                onExercise: (id) => setState(() => exerciseId = id),
                onOpenProfile: (pid, exId) {
                  _select(pid);
                  setState(() {
                    exerciseId = exId;
                    compare = false;
                  });
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // ------------------------------------------------------------ individual

  Widget _individual(
    BuildContext context,
    AppController c,
    List<Player> players,
    Map<String, Set<String>> done,
    List<Exercise> playerExercises,
    Exercise ex,
    LvAnalysis analysis,
  ) {
    final points = analysis.points;
    final profile = analysis.profile;
    final session = c.sessionPlayerIds;
    final carousel = carouselPlayers(
      all: players,
      session: session,
      recent: _recent,
      selected: playerId!,
    );

    // Orden para pasar al siguiente deslizando: la sesión si el elegido
    // está en ella; si no, todos.
    final inSession = [
      for (final id in session)
        if (players.any((p) => p.id == id)) id,
    ];
    final order = inSession.contains(playerId)
        ? inSession
        : [for (final p in players) p.id];
    void step(int d) {
      final i = order.indexOf(playerId!);
      if (i < 0 || order.length < 2) return;
      _select(order[(i + d) % order.length]);
    }

    final prev = previousPeriod(period);
    final prevProfile = prev == null
        ? null
        : c
              .profileFor(
                playerId: playerId!,
                exerciseId: ex.id,
                since: prev.$1,
                until: prev.$2,
              )
              .profile;
    final trend = c.oneRmTrendFor(playerId!, ex.id);

    // En pantallas anchas, el contenido centrado y con ancho máximo.
    final side = math.max(16.0, (MediaQuery.sizeOf(context).width - 1000) / 2);
    return ListView(
      key: const Key('profile-list'),
      padding: EdgeInsets.fromLTRB(side, 8, side, 96),
      children: [
        PillRow(
          key: const Key('player-carousel'),
          children: [
            for (final p in carousel)
              Pill(
                key: ValueKey('player-${p.id}'),
                label: p.name,
                avatar: initialsOf(p.name),
                icon: session.contains(p.id) ? Icons.event_available : null,
                selected: p.id == playerId,
                onTap: () => _select(p.id),
              ),
            if (players.length > carousel.length || players.length > 4)
              Pill(
                key: const Key('player-all'),
                label: 'Todos (${players.length})',
                icon: Icons.search,
                dashed: true,
                onTap: () => _searchPlayer(context, c, players, done, ex),
              ),
          ],
        ),
        const SizedBox(height: 12),
        ExercisePeriodBar(
          exercises: [for (final e in playerExercises) (e.id, e.name)],
          selected: ex.id,
          onExercise: (id) => setState(() => exerciseId = id),
          period: period,
          periods: kPeriods.keys.toList(),
          onPeriod: (v) => setState(() => period = v),
        ),
        const SizedBox(height: 16),
        GestureDetector(
          key: const Key('profile-hero'),
          behavior: HitTestBehavior.opaque,
          onHorizontalDragEnd: (d) {
            final v = d.primaryVelocity ?? 0;
            if (v.abs() > 250) step(v < 0 ? 1 : -1);
          },
          child: _Hero(
            analysis: analysis,
            mvt: ex.mvt,
            prevProfile: prevProfile,
            prevLabel: previousPeriodLabel(period),
            band: c.rmBandFor(playerId!, ex.id),
            trend: trend,
            position: order.length > 1
                ? '${order.indexOf(playerId!) + 1}/${order.length}'
                : null,
            onPrev: () => step(-1),
            onNext: () => step(1),
          ),
        ),
        const SizedBox(height: 16),
        if (points.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(
              child: Text(
                'Sin repeticiones en este periodo.',
                textAlign: TextAlign.center,
              ),
            ),
          )
        else ...[
          SizedBox(
            height: 260,
            child: _Chart(
              points: points,
              profile: profile,
              prevProfile: prevProfile,
              mvt: ex.mvt,
              onTapPoint: (p) => _togglePoint(context, c, p),
            ),
          ),
          const SizedBox(height: 8),
          _Legend(showPrevious: prevProfile != null && profile != null),
          if (profile != null) ...[
            const SizedBox(height: 16),
            _LoadTable(profile: profile, mvt: ex.mvt),
            const SizedBox(height: 4),
            Text(
              '1RM a ${c.settings.metric.label} = ${v2(ex.mvt)} m/s '
              '(ajústalo en Ajustes › Ejercicios).',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
        ],
        const SizedBox(height: 12),
        const Divider(height: 1),
        _RomRow(c: c, playerId: playerId!, exerciseId: ex.id),
        if (points.isNotEmpty)
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              key: const Key('points-tile'),
              tilePadding: EdgeInsets.zero,
              leading: const Icon(Icons.scatter_plot_outlined, size: 20),
              title: Text(
                '${points.length} cargas · '
                '${points.length - analysis.used.length} fuera del perfil',
              ),
              subtitle: const Text(
                'Toca una para quitarla o volver a meterla.',
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
              children: [
                for (final p in points)
                  _PointTile(
                    point: p,
                    mark: c.setById(p.setId)?.profileMark,
                    onTap: () => _togglePoint(context, c, p),
                    onAuto: () => c.setProfileMark(p.setId!, null),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _searchPlayer(
    BuildContext context,
    AppController c,
    List<Player> players,
    Map<String, Set<String>> done,
    Exercise ex,
  ) async {
    final session = c.sessionPlayerIds.toSet();
    final fmt = DateFormat('d MMM', 'es');
    final since = sinceForPeriod(period);
    final entries = [
      for (final p in players)
        () {
          final has = done[p.id]?.contains(ex.id) ?? false;
          final last = c.lastDataFor(p.id, has ? ex.id : null);
          final rm = has
              ? c
                    .profileFor(playerId: p.id, exerciseId: ex.id, since: since)
                    .profile
                    ?.estimated1Rm(ex.mvt)
              : null;
          return PickerEntry(
            p,
            highlighted: has,
            inSession: session.contains(p.id),
            subtitle: [
              if (!has)
                'Sin datos en ${ex.name}'
              else if (rm != null && rm.isFinite && rm > 0)
                '1RM ${kg(rm.roundToDouble())} kg'
              else
                'Sin perfil en $period',
              if (last != null) 'último: ${fmt.format(last)}',
            ].join(' · '),
          );
        }(),
    ];
    final id = await showPlayerSearchSheet(
      context,
      entries: entries,
      selectedId: playerId,
    );
    if (id != null) _select(id);
  }

  /// Si el punto cuenta, se excluye; si no cuenta, se incluye a mano.
  void _togglePoint(BuildContext context, AppController c, LvPoint p) {
    final setId = p.setId;
    if (setId == null) return;
    final counts = p.status.counts;
    c.setProfileMark(setId, counts ? ProfileMark.exclude : ProfileMark.include);
    showAppSnack(
      context,
      counts
          ? '${kg(p.loadKg)} kg excluido del perfil'
          : '${kg(p.loadKg)} kg incluido en el perfil',
      actionLabel: 'Deshacer',
      onAction: () => c.setProfileMark(
        setId,
        p.status == LvPointStatus.excluded
            ? ProfileMark.exclude
            : p.status == LvPointStatus.forced
            ? ProfileMark.include
            : null,
      ),
    );
  }

  Future<void> _addManual(
    BuildContext context,
    AppController c,
    String playerId,
    String exerciseId,
    LvProfile? profile,
  ) async {
    final p = await showManualPointSheet(
      context,
      initialLoad: c.loadKg,
      metricLabel: c.settings.metric.label,
      velocityAt: profile?.velocityAt,
    );
    if (p == null) return;
    await c.addManualPoint(
      playerId: playerId,
      exerciseId: exerciseId,
      loadKg: p.load,
      velocity: p.velocity,
      date: DateTime(p.date.year, p.date.month, p.date.day, 12),
    );
  }
}

// ------------------------------------------------------------ cifras

/// Tarjeta principal: 1RM grande, cambio respecto al periodo anterior,
/// evolución y cifras secundarias.
class _Hero extends StatelessWidget {
  final LvAnalysis analysis;
  final double mvt;
  final LvProfile? prevProfile;
  final String prevLabel;

  /// Rango normal (±%) del 1RM de la persona: por debajo, el cambio es ruido.
  final double band;
  final List<TrendPoint> trend;

  /// "4/7" en el orden que se recorre deslizando o con las flechas.
  final String? position;
  final VoidCallback onPrev, onNext;

  const _Hero({
    required this.analysis,
    required this.mvt,
    required this.prevProfile,
    required this.prevLabel,
    required this.band,
    required this.trend,
    required this.position,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final profile = analysis.profile;
    final rm = profile?.estimated1Rm(mvt);
    final valid = rm != null && rm.isFinite && rm > 0;
    final prevRm = prevProfile?.estimated1Rm(mvt);
    final delta = valid && prevRm != null && prevRm.isFinite && prevRm > 0
        ? rm - prevRm
        : null;
    final loads = analysis.used.length;

    Widget stat(String value, String label, {Widget? lead}) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (lead != null) ...[lead, const SizedBox(width: 4)],
              Flexible(
                child: Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    fontFeatures: _tabular,
                  ),
                ),
              ),
            ],
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Colors.white54),
          ),
        ],
      ),
    );

    final reliable =
        profile != null &&
        loads >= kDayRmMinLoads &&
        profile.r2 >= kCompareMinR2;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '1RM estimado',
                style: TextStyle(color: Colors.white60, fontSize: 13),
              ),
              const Spacer(),
              if (position != null) ...[
                IconButton(
                  key: const Key('player-prev'),
                  tooltip: 'Anterior',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.chevron_left),
                  onPressed: onPrev,
                ),
                Text(
                  position!,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                IconButton(
                  key: const Key('player-next'),
                  tooltip: 'Siguiente',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.chevron_right),
                  onPressed: onNext,
                ),
              ],
            ],
          ),
          if (!valid)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                analysis.points.isEmpty
                    ? 'Sin datos en este periodo.'
                    : loads < 2
                    ? 'Hace falta al menos otra carga distinta para trazar el perfil.'
                    : 'Perfil no válido: la velocidad no baja con la carga.',
                style: const TextStyle(color: Colors.white70),
              ),
            )
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  kg(rm.roundToDouble()),
                  key: const Key('hero-1rm'),
                  style: const TextStyle(
                    fontSize: 48,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                    fontFeatures: _tabular,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(left: 4, bottom: 8),
                  child: Text(
                    'kg',
                    style: TextStyle(fontSize: 16, color: Colors.white60),
                  ),
                ),
                const SizedBox(width: 12),
                if (trendIsMeaningful(trend))
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 260),
                        child: SizedBox(
                          height: 44,
                          child: _Sparkline(trend: trend),
                        ),
                      ),
                    ),
                  )
                else
                  const Spacer(),
              ],
            ),
            if (delta != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: _DeltaBadge(
                  delta: delta,
                  percent: rmChangePercent(rm, prevRm!),
                  band: band,
                  label: prevLabel,
                ),
              ),
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 10),
            Row(
              children: [
                stat('${v2(profile!.intercept)} m/s', 'V0 · vel. a carga 0'),
                stat(
                  '${(kGravity * profile.intercept * (-profile.intercept / profile.slope) / 4).round()} W',
                  'Pmax · carga ${kg((-profile.intercept / profile.slope / 2).roundToDouble())} kg',
                ),
                stat(
                  'R² ${profile.r2.toStringAsFixed(2)}',
                  '$loads cargas',
                  lead: Icon(
                    reliable ? Icons.check_circle : Icons.warning_amber,
                    size: 16,
                    color: reliable ? kFresh : kWarning,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DeltaBadge extends StatelessWidget {
  final double delta, percent, band;
  final String label;
  const _DeltaBadge({
    required this.delta,
    required this.percent,
    required this.band,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final real = percent.abs() >= band;
    final r = real ? delta.round() : 0;
    final color = r > 0 ? kFresh : (r < 0 ? kStop : Colors.white54);
    final signed =
        '${delta >= 0 ? '+' : '−'}${kg(delta.abs().roundToDouble())}';
    final text = r == 0
        ? '≈ igual $label'
        : '${r > 0 ? '+' : '−'}${r.abs()} kg $label';
    return Tooltip(
      message:
          '$signed kg (${percent >= 0 ? '+' : '−'}${percent.abs().toStringAsFixed(1)} %). '
          'Su rango normal es ±${band.toStringAsFixed(0)} %: '
          '${real ? 'el cambio lo supera' : 'el cambio entra en lo normal'}.',
      triggerMode: TooltipTriggerMode.tap,
      child: Container(
        key: const Key('hero-delta'),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              r > 0
                  ? Icons.trending_up
                  : (r < 0 ? Icons.trending_down : Icons.trending_flat),
              size: 14,
              color: color,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                text,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: color, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Evolución semanal del 1RM, sin ejes.
class _Sparkline extends StatelessWidget {
  final List<TrendPoint> trend;
  const _Sparkline({required this.trend});

  @override
  Widget build(BuildContext context) {
    final t0 = trend.first.end.millisecondsSinceEpoch;
    final ys = trend.map((t) => t.oneRm);
    final lo = ys.reduce(math.min), hi = ys.reduce(math.max);
    final pad = math.max((hi - lo) * 0.15, 1.0);
    return Tooltip(
      message:
          '1RM por semana (${trend.length} semanas): '
          '${kg(trend.first.oneRm.roundToDouble())} → '
          '${kg(trend.last.oneRm.roundToDouble())} kg',
      child: LineChart(
        LineChartData(
          minY: lo - pad,
          maxY: hi + pad,
          lineTouchData: const LineTouchData(enabled: false),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: const FlTitlesData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (final t in trend)
                  FlSpot(
                    (t.end.millisecondsSinceEpoch - t0) / 86400000,
                    t.oneRm,
                  ),
              ],
              isCurved: true,
              preventCurveOverShooting: true,
              color: Colors.lightBlueAccent,
              barWidth: 2,
              dotData: FlDotData(
                show: true,
                checkToShowDot: (s, bar) => s == bar.spots.last,
                getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                  radius: 3,
                  color: Colors.lightBlueAccent,
                  strokeWidth: 0,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                color: Colors.lightBlueAccent.withValues(alpha: 0.1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Carga y velocidad para cada % del 1RM, en una fila.
class _LoadTable extends StatelessWidget {
  final LvProfile profile;
  final double mvt;
  const _LoadTable({required this.profile, required this.mvt});

  @override
  Widget build(BuildContext context) {
    const pcts = [50, 60, 70, 80, 90];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Cargas de trabajo',
          style: TextStyle(color: Colors.white60, fontSize: 13),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              for (var i = 0; i < pcts.length; i++)
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      border: i == 0
                          ? null
                          : const Border(
                              left: BorderSide(color: Colors.white12),
                            ),
                    ),
                    child: () {
                      final load = profile.loadForPercent(
                        pcts[i].toDouble(),
                        mvt,
                      );
                      return Column(
                        children: [
                          Text(
                            '${pcts[i]} %',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.white54,
                            ),
                          ),
                          Text(
                            kg(load.roundToDouble()),
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              fontFeatures: _tabular,
                            ),
                          ),
                          Text(
                            v2(profile.velocityAt(load)),
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.white54,
                              fontFeatures: _tabular,
                            ),
                          ),
                        ],
                      );
                    }(),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'kg · m/s esperada',
          style: TextStyle(color: Colors.white38, fontSize: 11),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------ gráfico

const _zoneColors = [Color(0xFF5DCAA5), Color(0xFFEF9F27), Color(0xFFE24B4A)];

class _Chart extends StatelessWidget {
  final List<LvPoint> points;
  final LvProfile? profile;
  final LvProfile? prevProfile;
  final double mvt;
  final ValueChanged<LvPoint> onTapPoint;
  const _Chart({
    required this.points,
    required this.profile,
    required this.prevProfile,
    required this.mvt,
    required this.onTapPoint,
  });

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final rm = p?.estimated1Rm(mvt);
    final valid = rm != null && rm.isFinite && rm > 0;
    final maxLoadPts = points.map((p) => p.loadKg).reduce(math.max);
    final maxX = (math.max(maxLoadPts, valid ? rm : 0) * 1.08).ceilToDouble();
    final maxY =
        (math.max(
          points.map((p) => p.velocity).reduce(math.max),
          p?.velocityAt(0) ?? 0,
        ) *
        1.1);
    final newest = points.map((p) => p.time).max;
    final prev = prevProfile;
    final prevRm = prev?.estimated1Rm(mvt);
    final showPrev = valid && prevRm != null && prevRm.isFinite && prevRm > 0;
    final pointsBar = (valid ? 1 : 0) + (showPrev ? 1 : 0);
    final optimal = valid ? -p!.intercept / p.slope / 2 : null;

    VerticalLine boundary(double x, String label, Color color) => VerticalLine(
      x: x,
      color: color.withValues(alpha: 0.5),
      strokeWidth: 1,
      dashArray: [4, 4],
      label: VerticalLineLabel(
        show: true,
        alignment: Alignment.topLeft,
        labelResolver: (_) => label,
        style: TextStyle(fontSize: 10, color: color),
      ),
    );

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
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: Colors.white10, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        rangeAnnotations: RangeAnnotations(
          verticalRangeAnnotations: [
            if (valid)
              for (var i = 0; i < kLoadZones.length; i++)
                VerticalRangeAnnotation(
                  x1: rm * kLoadZones[i].$1 / 100,
                  x2: math.min(rm * kLoadZones[i].$2 / 100, maxX),
                  color: _zoneColors[i].withValues(alpha: 0.07),
                ),
          ],
        ),
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
              style: TextStyle(fontSize: 11, color: Colors.white54),
            ),
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              getTitlesWidget: (v, m) => _offGrid(v, m)
                  ? const SizedBox.shrink()
                  : Text(
                      m.formattedValue,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.white54,
                      ),
                    ),
            ),
          ),
          leftTitles: AxisTitles(
            axisNameWidget: const Text(
              'm/s',
              style: TextStyle(fontSize: 11, color: Colors.white54),
            ),
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              getTitlesWidget: (v, m) => _offGrid(v, m)
                  ? const SizedBox.shrink()
                  : Text(
                      v.toStringAsFixed(1),
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.white54,
                      ),
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
          verticalLines: [
            if (valid) ...[
              boundary(rm * 0.6, '60 %', _zoneColors[1]),
              boundary(rm * 0.8, '80 %', _zoneColors[2]),
            ],
            if (optimal != null && optimal > 0 && optimal < maxX)
              VerticalLine(
                x: optimal,
                color: Colors.lightBlueAccent.withValues(alpha: 0.35),
                strokeWidth: 1,
                dashArray: [2, 3],
                label: VerticalLineLabel(
                  show: true,
                  alignment: Alignment.bottomRight,
                  labelResolver: (_) => 'Pmax',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.lightBlueAccent,
                  ),
                ),
              ),
          ],
        ),
        lineBarsData: [
          if (valid)
            LineChartBarData(
              spots: [FlSpot(0, p!.velocityAt(0)), FlSpot(rm, mvt)],
              color: Colors.lightBlueAccent,
              barWidth: 2.5,
              dotData: const FlDotData(show: false),
            ),
          if (showPrev)
            LineChartBarData(
              spots: [FlSpot(0, prev!.velocityAt(0)), FlSpot(prevRm, mvt)],
              color: Colors.white30,
              barWidth: 1.5,
              dashArray: [5, 4],
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

/// El extremo del eje que no cae en la rejilla (p. ej. 1.53 junto a 1.5):
/// no se rotula para que no se pisen.
bool _offGrid(double v, TitleMeta m) {
  final r = v / m.appliedInterval;
  return (r - r.round()).abs() > 1e-6;
}

Color _statusColor(LvPointStatus s) => switch (s) {
  LvPointStatus.used || LvPointStatus.forced => Colors.amber,
  LvPointStatus.outlier => Colors.deepOrangeAccent,
  LvPointStatus.excluded => Colors.white38,
};

class _Legend extends StatelessWidget {
  final bool showPrevious;
  const _Legend({required this.showPrevious});

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontSize: 11, color: Colors.white60);
    Widget dot(Color fill, Color stroke, String label) => Row(
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
        Text(label, style: style),
      ],
    );
    Widget swatch(Color c, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 10,
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: style),
      ],
    );
    return Wrap(
      spacing: 14,
      runSpacing: 4,
      children: [
        dot(Colors.amber, Colors.amber, 'En el perfil'),
        dot(Colors.transparent, _statusColor(LvPointStatus.outlier), 'Atípico'),
        dot(
          Colors.transparent,
          _statusColor(LvPointStatus.excluded),
          'Excluido',
        ),
        if (showPrevious)
          const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 14,
                child: Divider(color: Colors.white38, thickness: 1.5),
              ),
              SizedBox(width: 4),
              Text('Periodo anterior', style: style),
            ],
          ),
        for (var i = 0; i < kLoadZones.length; i++)
          swatch(_zoneColors[i], kLoadZones[i].$3),
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
      contentPadding: EdgeInsets.zero,
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

/// ROM de referencia del deportista en el ejercicio, con opción de fijar un
/// objetivo a mano (p. ej. sentadilla a cajón) o volver al automático.
class _RomRow extends StatelessWidget {
  final AppController c;
  final String playerId, exerciseId;
  const _RomRow({
    required this.c,
    required this.playerId,
    required this.exerciseId,
  });

  @override
  Widget build(BuildContext context) {
    final ref = c.romRefFor(playerId, exerciseId);
    final text = ref == null
        ? 'ROM: faltan repeticiones (mín. $kRomMinReps)'
        : 'ROM ${ref.target.round()} ± ${ref.band.round()} cm '
              '· ${ref.manual ? 'fijado a mano' : 'automático'}';
    return Row(
      children: [
        const Icon(Icons.straighten, size: 20, color: Colors.white54),
        const SizedBox(width: 16),
        Expanded(
          child: Text(text, style: const TextStyle(color: Colors.white70)),
        ),
        TextButton(
          key: const Key('rom-target-open'),
          onPressed: () async {
            final r = await showRomTargetSheet(
              context,
              initial: ref?.target ?? 50,
              canReset: ref?.manual ?? false,
            );
            if (r != null) await c.setRomTarget(playerId, exerciseId, r.cm);
          },
          child: Text(ref?.manual ?? false ? 'Cambiar' : 'Fijar objetivo'),
        ),
      ],
    );
  }
}
