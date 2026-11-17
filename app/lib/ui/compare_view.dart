import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../core/analysis.dart';
import '../core/models.dart';
import 'common.dart';
import 'player_picker.dart';

const _tabular = [FontFeature.tabularFigures()];

/// Ancho a partir del cual tabla y dispersión van una al lado de la otra.
const double kCompareSideBySide = 1100;

/// A quién se compara.
enum CompareGroup { session, all, custom }

/// Comparar varios deportistas en un ejercicio: tabla (deportistas ×
/// métricas) y gráfico de dispersión (un punto por deportista).
class CompareView extends StatefulWidget {
  final AppController c;
  final String period;
  final ValueChanged<String> onPeriod;

  /// Ejercicio compartido con el perfil individual.
  final String? exerciseId;
  final ValueChanged<String> onExercise;

  /// Abre el perfil individual de un deportista en un ejercicio.
  final void Function(String playerId, String exerciseId) onOpenProfile;

  const CompareView({
    super.key,
    required this.c,
    required this.period,
    required this.onPeriod,
    required this.exerciseId,
    required this.onExercise,
    required this.onOpenProfile,
  });

  @override
  State<CompareView> createState() => _CompareViewState();
}

class _CompareViewState extends State<CompareView> {
  CompareGroup? group;
  Set<String> custom = {};

  List<CompareMetric> metrics = [
    CompareMetric.oneRm,
    CompareMetric.v0,
    CompareMetric.pmax,
  ];

  /// null = por nombre.
  CompareMetric? sortBy = CompareMetric.oneRm;
  bool ascending = false;

  bool scatter = false;
  CompareMetric x = CompareMetric.oneRm, y = CompareMetric.v0;
  bool quadrants = true;

  /// Deportista resaltado (ficha bajo la dispersión).
  String? focus;

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final done = c.exercisesWithRepsByPlayer();
    final known = c.exercises.map((e) => e.id).toSet();
    final eligible = c.activePlayers
        .where((p) => done[p.id]?.any(known.contains) ?? false)
        .toList();
    final doneAny = {for (final s in done.values) ...s};
    final exs = c.exercises.where((e) => doneAny.contains(e.id)).toList();
    if (eligible.isEmpty || exs.isEmpty) return const SizedBox.shrink();

    final exIds = exs.map((e) => e.id).toList();
    final exId = exIds.contains(widget.exerciseId)
        ? widget.exerciseId!
        : (exIds.contains(c.exerciseId) ? c.exerciseId : exIds.first);
    final ex = c.exerciseById(exId);

    final sessionIds = c.sessionPlayerIds.toSet();
    final session = c.activePlayers
        .where((p) => sessionIds.contains(p.id))
        .toList();
    var g =
        group ?? (session.isNotEmpty ? CompareGroup.session : CompareGroup.all);
    if (g == CompareGroup.session && session.isEmpty) g = CompareGroup.all;
    final shown = switch (g) {
      CompareGroup.session => session,
      CompareGroup.all => eligible,
      CompareGroup.custom =>
        c.activePlayers.where((p) => custom.contains(p.id)).toList(),
    };

    final since = sinceForPeriod(widget.period);
    final cache = <(String, String), LvAnalysis>{};
    final values = <String, Map<CompareMetric, MetricValue>>{
      for (final p in shown)
        p.id: {
          for (final m in {...metrics, x, y})
            m: c.compareMetric(
              playerId: p.id,
              exerciseId: exId,
              metric: m,
              done: done,
              since: since,
              cache: cache,
            ),
        },
    };

    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= kCompareSideBySide;
    final side = math.max(16.0, (width - 1500) / 2);

    void open(String pid) => widget.onOpenProfile(pid, exId);

    final table = _MetricTable(
      players: shown,
      values: values,
      metrics: metrics,
      sortBy: sortBy,
      ascending: ascending,
      focus: wide ? focus : null,
      showAdd: wide,
      onSort: (m) => setState(() {
        if (sortBy == m) {
          ascending = !ascending;
        } else {
          sortBy = m;
          ascending = m == null; // nombres A→Z; métricas, mayor primero
        }
      }),
      onAddMetric: () => _pickMetrics(context),
      onTapRow: (pid) => wide ? setState(() => focus = pid) : open(pid),
    );
    final scatterPanel = _ScatterPanel(
      players: shown,
      values: values,
      x: x,
      y: y,
      quadrants: quadrants,
      focus: focus,
      onX: (m) => setState(() => x = m),
      onY: (m) => setState(() => y = m),
      onSwap: () => setState(() {
        final t = x;
        x = y;
        y = t;
      }),
      onQuadrants: (v) => setState(() => quadrants = v),
      onFocus: (pid) => setState(() => focus = pid),
      onOpen: open,
    );

    return ListView(
      key: const Key('compare-list'),
      padding: EdgeInsets.fromLTRB(side, 8, side, 32),
      children: [
        PillRow(
          key: const Key('compare-groups'),
          children: [
            if (session.isNotEmpty)
              Pill(
                key: const Key('compare-group-session'),
                label: 'Sesión de hoy · ${session.length}',
                icon: Icons.event_available,
                selected: g == CompareGroup.session,
                onTap: () => setState(() => group = CompareGroup.session),
              ),
            Pill(
              key: const Key('compare-group-all'),
              label: 'Todos · ${eligible.length}',
              icon: Icons.groups,
              selected: g == CompareGroup.all,
              onTap: () => setState(() => group = CompareGroup.all),
            ),
            Pill(
              key: const Key('compare-players'),
              label: g == CompareGroup.custom
                  ? 'Elegidos · ${shown.length}'
                  : 'Elegir',
              icon: Icons.edit,
              selected: g == CompareGroup.custom,
              dashed: true,
              onTap: () => _pickPlayers(context, eligible, session, shown),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ExercisePeriodBar(
          exercises: [for (final e in exs) (e.id, e.name)],
          selected: ex.id,
          onExercise: widget.onExercise,
          period: widget.period,
          periods: kPeriods.keys.toList(),
          onPeriod: widget.onPeriod,
        ),
        const SizedBox(height: 12),
        if (shown.isEmpty)
          const _Empty('Elige al menos un deportista.')
        else if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: table),
              const SizedBox(width: 24),
              Expanded(child: scatterPanel),
            ],
          )
        else ...[
          Row(
            children: [
              Expanded(
                child: UnderlineTabs<bool>(
                  key: const Key('compare-view'),
                  items: const [(false, 'Tabla'), (true, 'Dispersión')],
                  selected: scatter,
                  onSelect: (v) => setState(() => scatter = v),
                ),
              ),
              if (!scatter)
                TextButton.icon(
                  key: const Key('compare-metrics'),
                  onPressed: () => _pickMetrics(context),
                  icon: const Icon(Icons.view_column_outlined, size: 18),
                  label: const Text('Columnas'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          scatter ? scatterPanel : table,
        ],
      ],
    );
  }

  // ------------------------------------------------------------ selección

  Future<void> _pickPlayers(
    BuildContext context,
    List<Player> players,
    List<Player> session,
    List<Player> shown,
  ) {
    var query = '';
    final sessionIds = {for (final p in session) p.id};
    final all = {for (final p in players) p.id};
    var sel = {for (final p in shown) p.id};
    void apply(Set<String> s) => setState(() {
      sel = s;
      custom = s;
      group = CompareGroup.custom;
    });

    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          void set(Set<String> s) {
            apply(s);
            setSheet(() {});
          }

          final q = searchKey(query.trim());
          final list = [
            for (final p in players)
              if (q.isEmpty || searchKey(p.name).contains(q)) p,
          ];
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(ctx).bottom,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(ctx).height * 0.75,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${sel.length} elegidos',
                              style: Theme.of(ctx).textTheme.titleMedium,
                            ),
                          ),
                          if (sessionIds.isNotEmpty)
                            TextButton(
                              key: const Key('compare-session'),
                              onPressed: () => set({...sessionIds}),
                              child: const Text('Sesión'),
                            ),
                          TextButton(
                            onPressed: () => set({...all}),
                            child: const Text('Todos'),
                          ),
                          TextButton(
                            onPressed: () => set({}),
                            child: const Text('Ninguno'),
                          ),
                        ],
                      ),
                    ),
                    if (players.length > 8)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                        child: TextField(
                          key: const Key('compare-search'),
                          decoration: InputDecoration(
                            hintText: 'Buscar entre ${players.length}',
                            prefixIcon: const Icon(Icons.search),
                            isDense: true,
                            border: const OutlineInputBorder(),
                          ),
                          onChanged: (v) => setSheet(() => query = v),
                        ),
                      ),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final p in list)
                            CheckboxListTile(
                              value: sel.contains(p.id),
                              secondary: sessionIds.contains(p.id)
                                  ? const Icon(Icons.event_available, size: 18)
                                  : null,
                              title: Text(p.name),
                              onChanged: (v) => set(
                                v == true
                                    ? {...sel, p.id}
                                    : ({...sel}..remove(p.id)),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _pickMetrics(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Columnas', style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final m in CompareMetric.values)
                    FilterChip(
                      label: Text('${m.label} (${m.unit})'),
                      selected: metrics.contains(m),
                      onSelected: (on) {
                        setState(() {
                          final next = on
                              ? {...metrics, m}
                              : ({...metrics}..remove(m));
                          metrics = CompareMetric.values
                              .where(next.contains)
                              .toList();
                          if (!metrics.contains(sortBy)) sortBy = null;
                        });
                        setSheet(() {});
                      },
                    ),
                ],
              ),
              const SizedBox(height: 12),
              const _Note(
                'V0: velocidad teórica a carga 0 · L0: carga teórica a '
                'velocidad 0 · Pmax: potencia máxima teórica (g·V0·L0/4, de '
                'la barra) · Carga Pmax: carga a la que se da (L0/2).',
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

// ------------------------------------------------------------ tabla

class _MetricTable extends StatelessWidget {
  final List<Player> players;
  final Map<String, Map<CompareMetric, MetricValue>> values;
  final List<CompareMetric> metrics;
  final CompareMetric? sortBy;
  final bool ascending;
  final String? focus;

  /// Botón "+" para añadir columnas al final de la cabecera (en ancho; en
  /// móvil va junto a las pestañas para que no quede fuera de la vista).
  final bool showAdd;
  final ValueChanged<CompareMetric?> onSort;
  final VoidCallback onAddMetric;
  final ValueChanged<String> onTapRow;

  const _MetricTable({
    required this.players,
    required this.values,
    required this.metrics,
    required this.sortBy,
    required this.ascending,
    required this.focus,
    required this.showAdd,
    required this.onSort,
    required this.onAddMetric,
    required this.onTapRow,
  });

  static const double _nameW = 116, _addW = 44, _rowH = 58;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    double? v(Player p, CompareMetric m) => values[p.id]![m]!.value;
    bool hasAny(Player p) => metrics.any((m) => v(p, m) != null);

    final rows = [...players]
      ..sort((a, b) {
        // Sin ningún dato, siempre al final.
        if (hasAny(a) != hasAny(b)) return hasAny(a) ? -1 : 1;
        final s = sortBy;
        if (s == null) {
          final r = searchKey(a.name).compareTo(searchKey(b.name));
          return ascending ? r : -r;
        }
        return compareNullableLast(v(a, s), v(b, s), ascending: ascending);
      });

    // Rango de cada métrica en el grupo, para las barras.
    final ranges = <CompareMetric, (double, double)>{};
    final means = <CompareMetric, double>{};
    for (final m in metrics) {
      final vs = [
        for (final p in players)
          if (v(p, m) != null) v(p, m)!,
      ];
      if (vs.isEmpty) continue;
      ranges[m] = (vs.reduce(math.min), vs.reduce(math.max));
      means[m] = vs.reduce((a, b) => a + b) / vs.length;
    }

    return LayoutBuilder(
      builder: (context, box) {
        final addW = showAdd ? _addW : 0.0;
        final colW = math.max(
          84.0,
          (box.maxWidth - _nameW - addW) / math.max(metrics.length, 1),
        );
        final total = _nameW + colW * metrics.length + addW;

        Widget header() => Row(
          children: [
            SizedBox(
              width: _nameW,
              child: InkWell(
                key: const Key('compare-sort-name'),
                onTap: () => onSort(null),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          'Nombre',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: sortBy == null
                                ? Colors.white
                                : Colors.white54,
                          ),
                        ),
                      ),
                      if (sortBy == null)
                        Icon(
                          ascending ? Icons.arrow_upward : Icons.arrow_downward,
                          size: 14,
                        ),
                    ],
                  ),
                ),
              ),
            ),
            for (final m in metrics)
              SizedBox(
                width: colW,
                child: Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: _MetricCard(
                    key: ValueKey('compare-col-${m.name}'),
                    metric: m,
                    mean: means[m],
                    sorted: sortBy == m,
                    ascending: ascending,
                    onTap: () => onSort(m),
                  ),
                ),
              ),
            if (showAdd)
              SizedBox(
                width: _addW,
                child: Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Material(
                    color: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: Colors.white24),
                    ),
                    child: InkWell(
                      key: const Key('compare-metrics'),
                      borderRadius: BorderRadius.circular(12),
                      onTap: onAddMetric,
                      child: const SizedBox(
                        height: 56,
                        child: Icon(Icons.add, size: 20, color: Colors.white70),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );

        Widget cell(Player p, CompareMetric m, bool firstGap) {
          final mv = values[p.id]![m]!;
          final value = mv.value;
          if (value == null) {
            return Text(
              firstGap ? mv.gap!.short : '—',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Colors.white38),
            );
          }
          final sorted = sortBy == m;
          final (lo, hi) = ranges[m]!;
          final frac = hi > lo ? (value - lo) / (hi - lo) : 1.0;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${mv.weak ? '≈' : ''}${m.format(value)}',
                style: TextStyle(
                  fontSize: sorted ? 16 : 15,
                  fontWeight: sorted ? FontWeight.w700 : FontWeight.w500,
                  color: mv.weak ? Colors.white54 : null,
                  fontFeatures: _tabular,
                ),
              ),
              if (sorted) ...[
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: SizedBox(
                    height: 4,
                    child: Stack(
                      children: [
                        Container(color: Colors.white10),
                        FractionallySizedBox(
                          widthFactor: 0.08 + 0.92 * frac,
                          child: Container(
                            color: mv.weak ? Colors.white30 : scheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          );
        }

        Widget row(Player p) {
          final any = hasAny(p);
          var gapShown = false;
          return Material(
            color: p.id == focus
                ? scheme.primary.withValues(alpha: 0.12)
                : Colors.transparent,
            child: InkWell(
              key: ValueKey('compare-row-${p.id}'),
              onTap: () => onTapRow(p.id),
              child: Container(
                height: _rowH,
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Colors.white10)),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: _nameW,
                      child: Text(
                        p.name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: any ? null : Colors.white38,
                        ),
                      ),
                    ),
                    for (final m in metrics)
                      SizedBox(
                        width: colW,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 12, right: 8),
                          child: () {
                            final isGap = values[p.id]![m]!.value == null;
                            final first = isGap && !gapShown;
                            if (isGap) gapShown = true;
                            return cell(p, m, first);
                          }(),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        }

        final content = SizedBox(
          width: math.max(total, box.maxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              header(),
              const SizedBox(height: 4),
              for (final p in rows) row(p),
            ],
          ),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            total > box.maxWidth
                ? SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: content,
                  )
                : content,
            const SizedBox(height: 8),
            const _Note(
              'Toca una métrica para ordenar · ≈ poco fiable (menos de '
              '$kDayRmMinLoads cargas o R² < 0.90) · Toca una fila para ver '
              'su perfil.',
            ),
          ],
        );
      },
    );
  }
}

/// Cabecera de columna: métrica, media del grupo y orden.
class _MetricCard extends StatelessWidget {
  final CompareMetric metric;
  final double? mean;
  final bool sorted, ascending;
  final VoidCallback onTap;

  const _MetricCard({
    super.key,
    required this.metric,
    required this.mean,
    required this.sorted,
    required this.ascending,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: sorted
          ? scheme.primary.withValues(alpha: 0.12)
          : Colors.white.withValues(alpha: 0.04),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: sorted ? scheme.primary : Colors.white12,
          width: sorted ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      '${metric.label} ${metric.unit}',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: sorted ? Colors.white : Colors.white60,
                        fontWeight: sorted ? FontWeight.w700 : null,
                      ),
                    ),
                  ),
                  if (sorted)
                    Icon(
                      ascending ? Icons.arrow_upward : Icons.arrow_downward,
                      size: 14,
                    ),
                ],
              ),
              Text(
                mean == null ? '—' : 'media ${metric.format(mean!)}',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.white38,
                  fontFeatures: _tabular,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ dispersión

class _ScatterPanel extends StatelessWidget {
  final List<Player> players;
  final Map<String, Map<CompareMetric, MetricValue>> values;
  final CompareMetric x, y;
  final bool quadrants;
  final String? focus;
  final ValueChanged<CompareMetric> onX, onY;
  final VoidCallback onSwap;
  final ValueChanged<bool> onQuadrants;
  final ValueChanged<String?> onFocus;
  final ValueChanged<String> onOpen;

  const _ScatterPanel({
    required this.players,
    required this.values,
    required this.x,
    required this.y,
    required this.quadrants,
    required this.focus,
    required this.onX,
    required this.onY,
    required this.onSwap,
    required this.onQuadrants,
    required this.onFocus,
    required this.onOpen,
  });

  Widget _axis(
    String key,
    String axis,
    CompareMetric m,
    ValueChanged<CompareMetric> on,
  ) => PopupMenuButton<CompareMetric>(
    key: Key(key),
    tooltip: 'Eje $axis',
    initialValue: m,
    onSelected: on,
    itemBuilder: (_) => [
      for (final o in CompareMetric.values)
        PopupMenuItem(value: o, child: Text('${o.label} (${o.unit})')),
    ],
    child: IgnorePointer(
      child: Pill(label: '$axis · ${m.label}', icon: Icons.unfold_more),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final pts = <(Player, double, double, bool)>[];
    final missing = <String>[];
    for (final p in players) {
      final vx = values[p.id]![x]!, vy = values[p.id]![y]!;
      if (vx.value != null && vy.value != null) {
        pts.add((p, vx.value!, vy.value!, vx.weak || vy.weak));
      } else {
        missing.add('${p.name} (${(vx.gap ?? vy.gap)!.short.toLowerCase()})');
      }
    }
    final showQuadrants = quadrants && pts.length >= 2;
    final mx = pts.isEmpty ? 0.0 : median([for (final p in pts) p.$2]);
    final my = pts.isEmpty ? 0.0 : median([for (final p in pts) p.$3]);
    final focused = pts.where((p) => p.$1.id == focus).firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _axis('compare-axis-x', 'X', x, onX),
            _axis('compare-axis-y', 'Y', y, onY),
            IconButton(
              key: const Key('compare-swap'),
              tooltip: 'Intercambiar ejes',
              icon: const Icon(Icons.swap_horiz),
              onPressed: onSwap,
            ),
            Pill(
              key: const Key('compare-quadrants'),
              label: 'Cuadrantes',
              icon: Icons.grid_view,
              selected: quadrants,
              onTap: () => onQuadrants(!quadrants),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (pts.isEmpty)
          const _Empty('Nadie tiene datos para estos dos ejes.')
        else
          SizedBox(
            height: 320,
            child: _ScatterChart(
              points: pts,
              x: x,
              y: y,
              quadrants: showQuadrants,
              focus: focus,
              onTap: (p) => onFocus(p.id == focus ? null : p.id),
            ),
          ),
        if (focused != null)
          _FocusCard(
            player: focused.$1,
            text:
                '${x.format(focused.$2)} ${x.unit} · '
                '${y.format(focused.$3)} ${y.unit}',
            quadrant: showQuadrants
                ? (quadrantName(x, y, focused.$2 >= mx, focused.$3 >= my) ??
                      '${focused.$2 >= mx ? '↑' : '↓'} ${x.label}  '
                          '${focused.$3 >= my ? '↑' : '↓'} ${y.label}')
                : null,
            weak: focused.$4,
            onOpen: () => onOpen(focused.$1.id),
            onClose: () => onFocus(null),
          ),
        if (missing.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Fuera del gráfico: ${missing.join(', ')}',
              key: const Key('compare-missing'),
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
        if (pts.isNotEmpty) ...[
          const SizedBox(height: 6),
          _Note(
            [
              'Toca un punto para ver su ficha.',
              'Hueco = poco fiable.',
              if (pts.length > kScatterAllLabels)
                'Con muchos, solo se rotulan los extremos.',
              if (showQuadrants)
                'Cuadrantes por la mediana del grupo '
                    '(${x.label} ${x.format(mx)} · ${y.label} ${y.format(my)}).',
            ].join(' '),
          ),
        ],
      ],
    );
  }
}

class _FocusCard extends StatelessWidget {
  final Player player;
  final String text;
  final String? quadrant;
  final bool weak;
  final VoidCallback onOpen, onClose;

  const _FocusCard({
    required this.player,
    required this.text,
    required this.quadrant,
    required this.weak,
    required this.onOpen,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const Key('compare-focus'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: scheme.primary,
            child: Text(
              initialsOf(player.name),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: scheme.onPrimary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${player.name} · $text${weak ? ' (poco fiable)' : ''}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (quadrant != null)
                  Text(
                    quadrant!,
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
              ],
            ),
          ),
          TextButton(
            key: const Key('compare-open-profile'),
            onPressed: onOpen,
            child: const Text('Ver perfil ›'),
          ),
          IconButton(
            tooltip: 'Cerrar',
            icon: const Icon(Icons.close, size: 18),
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

class _ScatterChart extends StatelessWidget {
  /// (deportista, x, y, poco fiable).
  final List<(Player, double, double, bool)> points;
  final CompareMetric x, y;
  final bool quadrants;
  final String? focus;
  final ValueChanged<Player> onTap;

  const _ScatterChart({
    required this.points,
    required this.x,
    required this.y,
    required this.quadrants,
    required this.focus,
    required this.onTap,
  });

  /// Espacio que ocupan los títulos de los ejes (izquierda y abajo).
  static const double _axisName = 16, _leftTicks = 44, _bottomTicks = 26;

  /// Margen alrededor de los datos (12 % del rango; si todos coinciden,
  /// 10 % del valor).
  static (double, double) _range(Iterable<double> vs) {
    final lo = vs.reduce(math.min), hi = vs.reduce(math.max);
    final span = hi - lo;
    final pad = span > 0 ? span * 0.12 : math.max(hi.abs() * 0.1, 0.1);
    return (lo - pad, hi + pad);
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final (minX, maxX) = _range(points.map((p) => p.$2));
    final (minY, maxY) = _range(points.map((p) => p.$3));
    final labelled = labelledIndexes([for (final p in points) (p.$2, p.$3)]);
    if (focus != null) {
      final i = points.indexWhere((p) => p.$1.id == focus);
      if (i >= 0) labelled.add(i);
    }
    Widget tick(double v, TitleMeta m) {
      final r = v / m.appliedInterval;
      if ((r - r.round()).abs() > 1e-6) return const SizedBox.shrink();
      return Text(
        m.formattedValue,
        style: const TextStyle(fontSize: 10, color: Colors.white54),
      );
    }

    final chart = ScatterChart(
      ScatterChartData(
        minX: minX,
        maxX: maxX,
        minY: minY,
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: Colors.white10, strokeWidth: 1),
          getDrawingVerticalLine: (_) =>
              const FlLine(color: Colors.white10, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        scatterSpots: [
          for (final (p, vx, vy, weak) in points)
            ScatterSpot(
              vx,
              vy,
              dotPainter: FlDotCirclePainter(
                radius: p.id == focus ? 9 : 7,
                color: weak ? Colors.transparent : Colors.amber,
                strokeWidth: p.id == focus ? 3 : (weak ? 2 : 0),
                strokeColor: p.id == focus ? primary : Colors.amber,
              ),
            ),
        ],
        scatterLabelSettings: ScatterLabelSettings(
          showLabel: true,
          getLabelFunction: (i, _) =>
              labelled.contains(i) ? points[i].$1.name : '',
          getLabelTextStyleFunction: (i, _) => TextStyle(
            fontSize: 11,
            color: points[i].$1.id == focus ? Colors.white : Colors.white70,
            fontWeight: points[i].$1.id == focus ? FontWeight.w700 : null,
          ),
        ),
        scatterTouchData: ScatterTouchData(
          enabled: true,
          handleBuiltInTouches: false,
          touchSpotThreshold: 18,
          touchCallback: (event, response) {
            if (event is! FlTapUpEvent) return;
            final hit = response?.touchedSpot;
            if (hit != null) onTap(points[hit.spotIndex].$1);
          },
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            axisNameSize: _axisName,
            axisNameWidget: Text(
              '${x.label} (${x.unit})',
              style: const TextStyle(fontSize: 11, color: Colors.white54),
            ),
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: _bottomTicks,
              getTitlesWidget: tick,
            ),
          ),
          leftTitles: AxisTitles(
            axisNameSize: _axisName,
            axisNameWidget: Text(
              '${y.label} (${y.unit})',
              style: const TextStyle(fontSize: 11, color: Colors.white54),
            ),
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: _leftTicks,
              getTitlesWidget: tick,
            ),
          ),
        ),
      ),
    );
    if (!quadrants) return chart;

    final mx = median([for (final p in points) p.$2]);
    final my = median([for (final p in points) p.$3]);
    String label(bool hiX, bool hiY) =>
        quadrantName(x, y, hiX, hiY) ??
        '${hiX ? '↑' : '↓'} ${x.label}  ${hiY ? '↑' : '↓'} ${y.label}';
    Widget corner(Alignment a, bool hiX, bool hiY) => Align(
      alignment: a,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Text(
          label(hiX, hiY),
          style: const TextStyle(fontSize: 11, color: Colors.white38),
        ),
      ),
    );
    return Stack(
      children: [
        // Detrás del gráfico, en el área de dibujo (sin los títulos).
        Positioned.fill(
          left: _axisName + _leftTicks,
          bottom: _axisName + _bottomTicks,
          child: CustomPaint(
            painter: _QuadrantPainter(
              fx: (mx - minX) / (maxX - minX),
              fy: (maxY - my) / (maxY - minY),
              tint: x.higherIsBetter && y.higherIsBetter,
            ),
            child: Stack(
              children: [
                corner(Alignment.topRight, true, true),
                corner(Alignment.topLeft, false, true),
                corner(Alignment.bottomLeft, false, false),
                corner(Alignment.bottomRight, true, false),
              ],
            ),
          ),
        ),
        Positioned.fill(child: chart),
      ],
    );
  }
}

/// Dos líneas discontinuas que cruzan en (fx, fy), fracciones del área.
/// Con [tint], el cuadrante bueno (arriba a la derecha) en verde y el de
/// trabajar (abajo a la izquierda) en rojo, muy suaves.
class _QuadrantPainter extends CustomPainter {
  final double fx, fy;
  final bool tint;
  const _QuadrantPainter({
    required this.fx,
    required this.fy,
    required this.tint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final x = fx * size.width, y = fy * size.height;
    if (tint) {
      canvas.drawRect(
        Rect.fromLTRB(x, 0, size.width, y),
        Paint()..color = kFresh.withValues(alpha: 0.08),
      );
      canvas.drawRect(
        Rect.fromLTRB(0, y, x, size.height),
        Paint()..color = kStop.withValues(alpha: 0.06),
      );
    }
    final paint = Paint()
      ..color = Colors.white38
      ..strokeWidth = 1;
    void dashed(Offset a, Offset b) {
      final len = (b - a).distance;
      final dir = (b - a) / len;
      for (var d = 0.0; d < len; d += 10) {
        canvas.drawLine(a + dir * d, a + dir * math.min(d + 6, len), paint);
      }
    }

    dashed(Offset(x, 0), Offset(x, size.height));
    dashed(Offset(0, y), Offset(size.width, y));
  }

  @override
  bool shouldRepaint(_QuadrantPainter old) =>
      old.fx != fx || old.fy != fy || old.tint != tint;
}

class _Empty extends StatelessWidget {
  final String text;
  const _Empty(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 48),
    child: Center(child: Text(text, textAlign: TextAlign.center)),
  );
}

class _Note extends StatelessWidget {
  final String text;
  const _Note(this.text);

  @override
  Widget build(BuildContext context) =>
      Text(text, style: const TextStyle(color: Colors.white38, fontSize: 12));
}

/// Con muchos puntos los nombres se pisan: hasta [kScatterAllLabels] se
/// rotulan todos; si hay más, solo los extremos de cada eje (los 2 más altos
/// y los 2 más bajos).
const int kScatterAllLabels = 12;

Set<int> labelledIndexes(List<(double, double)> pts) {
  final all = {for (var i = 0; i < pts.length; i++) i};
  if (pts.length <= kScatterAllLabels) return all;
  final out = <int>{};
  for (final axis in [0, 1]) {
    double v(int i) => axis == 0 ? pts[i].$1 : pts[i].$2;
    final sorted = all.toList()..sort((a, b) => v(a).compareTo(v(b)));
    out
      ..addAll(sorted.take(2))
      ..addAll(sorted.skip(sorted.length - 2));
  }
  return out;
}
