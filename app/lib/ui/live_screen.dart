import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_controller.dart';
import '../core/analysis.dart';
import '../core/models.dart';
import '../services/encoder.dart';
import 'common.dart';
import 'connect_sheet.dart';
import 'load_picker.dart';
import 'session_sheets.dart';
import 'set_tile.dart';

class LiveScreen extends StatelessWidget {
  final AppController c;
  const LiveScreen({super.key, required this.c});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          toolbarHeight: _narrow(context) ? 68 : 56,
          titleSpacing: 16,
          title: _narrow(context)
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ExercisePicker(c: c),
                    _SessionPicker(c: c, compact: true),
                  ],
                )
              : Row(
                  children: [
                    Flexible(child: _ExercisePicker(c: c)),
                    Container(
                      width: 1,
                      height: 28,
                      margin: const EdgeInsets.symmetric(horizontal: 14),
                      color: Colors.white24,
                    ),
                    Flexible(child: _SessionPicker(c: c)),
                  ],
                ),
          actions: [
            _ConnectionChip(c: c, compact: _narrow(context)),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, box) {
              // En horizontal: velocidad a la izquierda, controles a la derecha.
              if (box.maxWidth > box.maxHeight * 1.2) {
                return Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        children: [
                          // La tarjeta toma lo que necesita (con tope) y las
                          // barras se quedan con todo lo que sobra.
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight: box.maxHeight * 0.62,
                            ),
                            child: _BigReadout(c: c),
                          ),
                          Expanded(child: _SetBars(c: c)),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      // Con altura de sobra (tablet, móvil normal): cuadrícula
                      // grande de deportistas. En pantallas muy bajas: chips
                      // compactos y columna desplazable.
                      child: box.maxHeight >= 300
                          ? Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Column(
                                children: [
                                  _LoadControl(c: c),
                                  const SizedBox(height: 8),
                                  Expanded(
                                    child: _PlayerStrip(c: c, large: true),
                                  ),
                                  const SizedBox(height: 8),
                                  _ActionsRow(c: c),
                                  const SizedBox(height: 8),
                                ],
                              ),
                            )
                          : Center(
                              child: SingleChildScrollView(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _LoadControl(c: c),
                                    const SizedBox(height: 6),
                                    _PlayerStrip(c: c),
                                    const SizedBox(height: 6),
                                    _ActionsRow(c: c),
                                    const SizedBox(height: 8),
                                  ],
                                ),
                              ),
                            ),
                    ),
                  ],
                );
              }
              return Column(
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: box.maxHeight * 0.42,
                    ),
                    child: _BigReadout(c: c),
                  ),
                  Expanded(child: _SetBars(c: c)),
                  _LoadControl(c: c),
                  const SizedBox(height: 6),
                  _PlayerStrip(c: c),
                  const SizedBox(height: 6),
                  _ActionsRow(c: c),
                  const SizedBox(height: 8),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ExercisePicker extends StatelessWidget {
  final AppController c;
  const _ExercisePicker({required this.c});

  /// Botón compacto con el ejercicio actual; el menú se ajusta al texto
  /// en lugar de ocupar todo el ancho de la cabecera.
  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      widthFactor: 1, // ocupar solo lo que mide el texto
      child: PopupMenuButton<String>(
        key: const Key('exercise-picker'),
        tooltip: 'Cambiar ejercicio',
        initialValue: c.exerciseId,
        position: PopupMenuPosition.under,
        constraints: const BoxConstraints(minWidth: 180, maxWidth: 280),
        onSelected: c.setExercise,
        itemBuilder: (_) => [
          for (final e in c.exercises)
            PopupMenuItem(
              value: e.id,
              child: Row(
                children: [
                  SizedBox(
                    width: 28,
                    child: e.id == c.exerciseId
                        ? const Icon(Icons.check, size: 20)
                        : null,
                  ),
                  Flexible(
                    child: Text(e.name, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  c.exercise.name,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const Icon(Icons.arrow_drop_down),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConnectionChip extends StatelessWidget {
  final AppController c;
  final bool compact;
  const _ConnectionChip({required this.c, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final enc = c.encoder;
    return ValueListenableBuilder(
      valueListenable: enc.status,
      builder: (context, s, _) {
        final (icon, color, label) = switch (s) {
          EncoderStatus.connected => (
            Icons.bluetooth_connected,
            kFresh,
            c.simulated ? 'Simulado' : 'Conectado',
          ),
          EncoderStatus.connecting => (
            Icons.bluetooth_searching,
            kWarning,
            'Conectando…',
          ),
          EncoderStatus.reconnecting => (
            Icons.bluetooth_searching,
            kWarning,
            'Reconectando…',
          ),
          EncoderStatus.scanning => (
            Icons.bluetooth_searching,
            kWarning,
            'Buscando…',
          ),
          EncoderStatus.disconnected => (
            Icons.bluetooth_disabled,
            Colors.white54,
            'Conectar',
          ),
        };
        if (compact) {
          return IconButton.outlined(
            key: const Key('connection-chip'),
            tooltip: label,
            icon: Icon(icon, color: color),
            onPressed: () => showConnectSheet(context, c),
          );
        }
        return ActionChip(
          key: const Key('connection-chip'),
          avatar: Icon(icon, color: color, size: 18),
          label: Text(label),
          onPressed: () => showConnectSheet(context, c),
        );
      },
    );
  }
}

class _BigReadout extends StatelessWidget {
  final AppController c;
  const _BigReadout({required this.c});

  @override
  Widget build(BuildContext context) {
    final live = c.lastLive;
    final metric = c.settings.metric;

    return ValueListenableBuilder(
      valueListenable: c.encoder.error,
      builder: (context, err, _) {
        if (live == null) {
          final who = c.playerById(c.activePlayerId)?.name;
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.speed, size: 40, color: Colors.white24),
                const SizedBox(height: 8),
                Text(
                  c.encoder.status.value == EncoderStatus.connected
                      ? 'Esperando repetición${who == null ? '' : ' de $who'}…'
                      : 'Conecta el encoder para empezar',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                if (err != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    err,
                    style: const TextStyle(color: Colors.redAccent),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          );
        }

        final r = live.rep;
        final color = fatigueColor(live.level);
        final player = c.playerById(c.setById(r.setId)?.playerId);
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            border: Border.all(color: color, width: 3),
            borderRadius: BorderRadius.circular(20),
          ),
          child: LayoutBuilder(
            builder: (context, box) {
              var big = (box.maxWidth * 0.30).clamp(56.0, 150.0);
              if (box.maxHeight.isFinite) {
                // ~95 px para cabecera y fila de datos; el resto, para el número.
                big = big.clamp(
                  32.0,
                  math.max(32.0, (box.maxHeight - 95) * 0.95),
                );
              }
              final content = Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${player?.name ?? 'Sin asignar'} · rep ${live.indexInSet}',
                          style: Theme.of(context).textTheme.titleMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (live.level != FatigueLevel.off)
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              live.lossPercent < 0.5
                                  ? 'Mejor de la serie'
                                  : '${lossText(live.lossPercent)} vs mejor',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: color,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          v2(r.velocity(metric)),
                          style: TextStyle(
                            fontSize: big,
                            fontWeight: FontWeight.w800,
                            color: color,
                            height: 1.0,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${metric.label}\nm/s',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _Stat(
                        metric == VelocityMetric.mpv ? 'VM' : 'VMP',
                        v2(metric == VelocityMetric.mpv ? r.mv : r.mpv),
                      ),
                      _Stat(
                        'VMAX',
                        r.vmax == null
                            ? '–'
                            : '${r.vmax!.toStringAsFixed(r.vmaxTruncated ? 1 : 2)}${r.vmaxTruncated ? '*' : ''}',
                      ),
                      _Stat('ROM', '${r.romCm.toStringAsFixed(0)} cm'),
                      _Stat(
                        'Potencia',
                        r.loadKg > 0 ? '${r.meanPowerW.round()} W' : '–',
                      ),
                    ],
                  ),
                ],
              );
              if (!box.maxHeight.isFinite) return content;
              return FittedBox(
                fit: BoxFit.scaleDown,
                child: SizedBox(width: box.maxWidth, child: content),
              );
            },
          ),
        );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  final String label, value;
  const _Stat(this.label, this.value);

  @override
  Widget build(BuildContext context) => Expanded(
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.white60),
          ),
        ],
      ),
    ),
  );
}

/// Barras de la serie actual: ocupan todo el espacio libre. Valor encima,
/// número de repetición debajo y línea discontinua en el umbral de fatiga.
class _SetBars extends StatelessWidget {
  final AppController c;
  const _SetBars({required this.c});

  static const _maxBars = 12;

  @override
  Widget build(BuildContext context) {
    final all = c.lastLive == null
        ? const <Rep>[]
        : c.repsOfSet(c.lastLive!.rep.setId);
    if (all.isEmpty) return const SizedBox.expand();
    final m = c.settings.metric;
    final threshold = c.settings.velocityLossThreshold;
    final vsAll = all.map((r) => r.velocity(m)).toList();
    final best = vsAll.reduce(math.max);
    final start = math.max(0, all.length - _maxBars);
    final vs = vsAll.sublist(start);
    final runningBest = runningMax(vsAll);
    final limit = best * (1 - threshold / 100);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: LayoutBuilder(
        builder: (context, box) {
          const indexH = 16.0;
          // Con poca altura se omite la cifra sobre cada barra.
          final labelH = box.maxHeight < 90 ? 0.0 : 18.0;
          final barArea = math.max(0.0, box.maxHeight - labelH - indexH);
          // Sin altura suficiente (pantallas muy pequeñas): no dibujar barras.
          if (barArea < 16) return const SizedBox.shrink();
          final limitY = indexH + barArea * (limit / best);
          return Stack(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < vs.length; i++)
                    Expanded(
                      child: GestureDetector(
                        key: Key('bar-${start + i + 1}'),
                        behavior: HitTestBehavior.opaque,
                        onTap: () => showRepActions(
                          context,
                          c,
                          all[start + i],
                          start + i + 1,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              if (labelH > 0)
                                SizedBox(
                                  height: labelH,
                                  child: FittedBox(
                                    child: Text(
                                      v2(vs[i]),
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ),
                                ),
                              Container(
                                height: math.max(4, barArea * (vs[i] / best)),
                                decoration: BoxDecoration(
                                  color: fatigueColor(
                                    c.levelFor(
                                      velocityLossPercent(
                                        runningBest[start + i],
                                        vs[i],
                                      ),
                                    ),
                                  ),
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(6),
                                  ),
                                ),
                              ),
                              SizedBox(
                                height: indexH,
                                child: Text(
                                  '${start + i + 1}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.white54,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              if (barArea > 40 && c.settings.fatigueEnabled)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: limitY,
                  child: const _DashedLine(),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _DashedLine extends StatelessWidget {
  const _DashedLine();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final n = (box.maxWidth / 12).floor();
      return Row(
        children: [
          for (var i = 0; i < n; i++)
            Container(
              width: 6,
              height: 2,
              margin: const EdgeInsets.only(right: 6),
              color: Colors.white38,
            ),
        ],
      );
    },
  );
}

class _LoadControl extends StatelessWidget {
  final AppController c;
  const _LoadControl({required this.c});

  @override
  Widget build(BuildContext context) {
    final step = c.settings.loadStep;
    Widget btn(String t, double d) => SizedBox(
      width: 54,
      height: 48,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
        onPressed: () => c.setLoad(c.loadKg + d),
        child: Text(t),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: LayoutBuilder(
        builder: (context, box) {
          // En anchos estrechos solo caben los botones de un salto.
          final wide = box.maxWidth >= 330;
          return Row(
            children: [
              if (wide) ...[
                btn('−${kg(step * 2)}', -step * 2),
                const SizedBox(width: 4),
              ],
              btn('−${kg(step)}', -step),
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () async {
                    final v = await showLoadPicker(context, initial: c.loadKg);
                    if (v != null) c.setLoad(v);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '${kg(c.loadKg)} kg',
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const Text(
                          'carga',
                          style: TextStyle(fontSize: 11, color: Colors.white54),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              btn('+${kg(step)}', step),
              if (wide) ...[
                const SizedBox(width: 4),
                btn('+${kg(step * 2)}', step * 2),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Fila de deportistas. Toque = deportista activo (las siguientes repeticiones
/// son suyas). Si justo antes hubo repeticiones, se ofrece pasárselas
/// (corrección a posteriori).
class _PlayerStrip extends StatelessWidget {
  final AppController c;

  /// true = cuadrícula de botones grandes que llena el espacio disponible.
  final bool large;
  const _PlayerStrip({required this.c, this.large = false});

  void _select(BuildContext context, String? id) {
    final pending = c.setActive(id);
    ScaffoldMessenger.of(context).clearSnackBars();
    if (pending == null) return;
    final n = pending.repIds.length;
    final to = c.playerById(id)?.name;
    showAppSnack(
      context,
      switchQuestion(n, to),
      actionLabel: to == null
          ? 'Sí'
          : (n == 1 ? 'Sí, es suya' : 'Sí, son suyas'),
      onAction: () => c.applyPending(pending),
    );
  }

  Future<void> _confirmRemove(
    BuildContext context,
    String id,
    String name,
  ) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(name, style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 4),
              const Text(
                'Se quita solo de esta sesión: sus datos se conservan.',
                style: TextStyle(color: Colors.white60),
              ),
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.person_remove_outlined),
                label: const Text('Quitar de la sesión'),
                onPressed: () => Navigator.pop(ctx, true),
              ),
            ],
          ),
        ),
      ),
    );
    if (ok == true) await c.removeFromSession(id);
  }

  @override
  Widget build(BuildContext context) {
    final players = c.sessionPlayers;
    final entries = <(String?, String)>[
      (null, 'Sin asignar'),
      for (final p in players) (p.id, p.name),
    ];
    void openPlus() => showConvokeSheet(context, c);

    if (large) {
      return LayoutBuilder(
        builder: (context, box) {
          const gap = 10.0;
          final cols = box.maxWidth >= 520 ? 3 : 2;
          final w = (box.maxWidth - 24 - gap * (cols - 1)) / cols;
          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final (id, label) in entries)
                  SizedBox(
                    width: w,
                    height: 64,
                    child: _PlayerButton(
                      label: label,
                      selected: c.activePlayerId == id,
                      unassigned: id == null,
                      onTap: () => _select(context, id),
                      onLongPress: id == null
                          ? null
                          : () => _confirmRemove(context, id, label),
                    ),
                  ),
                SizedBox(
                  width: w,
                  height: 64,
                  child: _PlusButton(onTap: openPlus, empty: players.isEmpty),
                ),
              ],
            ),
          );
        },
      );
    }
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final (id, label) in entries)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onLongPress: id == null
                    ? null
                    : () => _confirmRemove(context, id, label),
                child: ChoiceChip(
                  label: Text(label, style: const TextStyle(fontSize: 16)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  selected: c.activePlayerId == id,
                  onSelected: (_) => _select(context, id),
                ),
              ),
            ),
          ActionChip(
            key: const Key('convoke-plus'),
            avatar: const Icon(Icons.add, size: 20),
            label: Text(
              players.isEmpty ? 'Añadir deportistas' : 'Añadir',
              style: const TextStyle(fontSize: 16),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            onPressed: openPlus,
          ),
        ],
      ),
    );
  }
}

class _PlusButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool empty;
  const _PlusButton({required this.onTap, required this.empty});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return OutlinedButton.icon(
      key: const Key('convoke-plus'),
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        side: BorderSide(
          color: scheme.primary.withValues(alpha: 0.6),
          width: 1.5,
        ),
      ),
      icon: const Icon(Icons.add, size: 26),
      label: Text(
        empty ? 'Añadir deportistas' : 'Añadir',
        style: const TextStyle(fontSize: 17),
      ),
    );
  }
}

class _ActionsRow extends StatelessWidget {
  final AppController c;
  const _ActionsRow({required this.c});

  @override
  Widget build(BuildContext context) {
    final recent = c.recentSets(limit: 1).firstOrNull;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.tonalIcon(
              onPressed: c.forceNewSet,
              icon: const Icon(Icons.add),
              label: const Text('Nueva serie'),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.outlined(
            tooltip: 'Borrar última repetición',
            onPressed: c.reps.isEmpty ? null : c.undoLastRep,
            icon: const Icon(Icons.undo),
          ),
          const SizedBox(width: 8),
          IconButton.outlined(
            tooltip: 'Series recientes',
            onPressed: recent == null
                ? null
                : () => showModalBottomSheet(
                    context: context,
                    showDragHandle: true,
                    isScrollControlled: true,
                    builder: (_) => DraggableScrollableSheet(
                      expand: false,
                      initialChildSize: 0.6,
                      builder: (_, sc) => sheetWithMessenger(
                        ListenableBuilder(
                          listenable: c,
                          builder: (_, _) => ListView(
                            controller: sc,
                            children: [
                              const Padding(
                                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                                child: Text(
                                  'Toca una serie para ver sus reps · '
                                  'desliza a la izquierda para borrarla',
                                  style: TextStyle(
                                    color: Colors.white38,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              for (final s in c.recentSets(limit: 15))
                                SetTile(c: c, set: s),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
            icon: const Icon(Icons.history),
          ),
        ],
      ),
    );
  }
}

/// Panel de una repetición tocada en la gráfica: ver datos, eliminarla
/// (con "Deshacer") o moverla a otro deportista.
Future<void> showRepActions(
  BuildContext context,
  AppController c,
  Rep r,
  int number,
) {
  final messenger = ScaffoldMessenger.of(context);
  final theme = Theme.of(context);
  final m = c.settings.metric;
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Repetición $number · ${DateFormat('HH:mm:ss').format(r.time)}',
              style: Theme.of(ctx).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '${v2(r.velocity(m))} ${m.label} m/s · ROM ${r.romCm.toStringAsFixed(0)} cm'
              '${r.vmax == null ? '' : ' · VMAX ${r.vmax!.toStringAsFixed(2)}'}',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.swap_horiz),
                    label: const Text('Mover a…'),
                    onPressed: () async {
                      final set = c.setById(r.setId);
                      final p = await pickPlayer(
                        ctx,
                        c,
                        current: set?.playerId,
                        title: 'Mover la repetición $number a…',
                      );
                      if (p == null) return;
                      await c.moveRep(r.id, p.id);
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.red.shade700,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Eliminar'),
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await deleteRepWithUndo(messenger, theme, c, r, number);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

/// Botón grande de deportista (cuadrícula en horizontal / tablet).
class _PlayerButton extends StatelessWidget {
  final String label;
  final bool selected;
  final bool unassigned;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  const _PlayerButton({
    required this.label,
    required this.selected,
    required this.unassigned,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.primary : scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              Icon(
                unassigned ? Icons.person_off_outlined : Icons.person,
                size: 26,
                color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? scheme.onPrimary : scheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pantalla estrecha (móvil en vertical): cabecera en dos líneas.
bool _narrow(BuildContext context) => MediaQuery.sizeOf(context).width < 600;

/// Selector de sesión junto al ejercicio.
class _SessionPicker extends StatelessWidget {
  final AppController c;
  final bool compact;
  const _SessionPicker({required this.c, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final name = c.activeSession?.name ?? 'Sin sesión';
    final style = compact
        ? const TextStyle(fontSize: 13, color: Colors.white70)
        : Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(color: Colors.white70);
    return InkWell(
      key: const Key('session-picker'),
      borderRadius: BorderRadius.circular(8),
      onTap: () => showSessionSheet(context, c),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: compact ? 2 : 8, horizontal: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.event_note,
              size: compact ? 15 : 20,
              color: Colors.white70,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(name, overflow: TextOverflow.ellipsis, style: style),
            ),
            Icon(
              Icons.arrow_drop_down,
              size: compact ? 18 : 24,
              color: Colors.white70,
            ),
          ],
        ),
      ),
    );
  }
}
