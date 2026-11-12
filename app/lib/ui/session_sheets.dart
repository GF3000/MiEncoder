import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_controller.dart';
import '../core/models.dart';
import 'common.dart';
import 'value_sheets.dart';

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
                    // El panel sigue abierto para poder fijar el objetivo.
                    await c.newSession(copyPlayers: copy);
                  },
                ),
              ),
              if (s != null) ...[
                ListTile(
                  key: const Key('session-loss'),
                  leading: const Icon(Icons.trending_down),
                  title: const Text('Pérdida de velocidad'),
                  subtitle: const Text(
                    'Para todos los ejercicios de la sesión salvo los que la cambien',
                  ),
                  trailing: Text(
                    lossLimitText(s.lossGeneral),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onTap: () async {
                    final v = await askSessionLoss(ctx, s.lossGeneral);
                    if (v != null) await c.setSessionLoss(v);
                  },
                ),
                const _Section('Objetivo por ejercicio'),
                for (final e in c.exercises)
                  Builder(
                    builder: (_) {
                      final rm = s.rmTargets[e.id];
                      // Solo se muestra la pérdida si el ejercicio la cambia.
                      final loss = s.lossTargets[e.id];
                      final has = rm != null || loss != null;
                      return ListTile(
                        key: Key('rm-target-${e.id}'),
                        dense: true,
                        leading: Icon(
                          Icons.speed,
                          color: has
                              ? Theme.of(ctx).colorScheme.primary
                              : Colors.white38,
                        ),
                        title: Text(e.name),
                        trailing: Text(
                          has ? sessionTargetText(rm, loss) : 'Sin objetivo',
                          style: TextStyle(
                            fontSize: 16,
                            color: has ? null : Colors.white54,
                          ),
                        ),
                        onTap: () => editExerciseTarget(ctx, c, e),
                      );
                    },
                  ),
              ],
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

/// Abre el panel de objetivo de [e] en la sesión activa y guarda lo
/// elegido («Guardar» solo en [e], «Guardar en todos» en todos).
Future<void> editExerciseTarget(
  BuildContext context,
  AppController c,
  Exercise e,
) async {
  final s = c.activeSession;
  if (s == null) return;
  final r = await askSessionTarget(
    context,
    exerciseName: e.name,
    rm: s.rmTargets[e.id],
    loss: s.lossTargets[e.id],
    sessionLoss: s.lossGeneral,
  );
  if (r == null) return;
  if (r.applyToAll) {
    await c.applyTargetToAll(rm: r.rm, loss: r.loss);
  } else {
    await c.setSessionTarget([e.id], rm: r.rm, loss: r.loss);
  }
}

/// Resultado del panel de objetivo. [rm] null = sin objetivo; [loss]: un
/// valor, [kNoLossLimit] (sin límite) o null (heredar la de la sesión).
typedef SessionTargetChoice = ({RmTarget? rm, double? loss, bool applyToAll});

/// Rangos de intensidad habituales en VBT (null = sin objetivo).
const List<(String, RmTarget?)> kRmPresets = [
  ('Potencia', RmTarget(50, 65)),
  ('Hipertrofia', RmTarget(65, 75)),
  ('Fuerza-hip.', RmTarget(75, 85)),
  ('Fuerza', RmTarget(85, 95)),
  ('Sin objetivo', null),
];

/// Pérdidas de velocidad máximas de un toque.
const List<double> kLossPresets = [10, 15, 20, 25, 30, 40];

/// Límites del deslizador de %1RM.
const double _rmMin = 30, _rmMax = 100;

/// Panel (sin teclado) con el objetivo de un ejercicio en la sesión: rango
/// de %1RM y pérdida de velocidad máxima. null = cancelar.
Future<SessionTargetChoice?> askSessionTarget(
  BuildContext context, {
  required String exerciseName,
  RmTarget? rm,
  double? loss,
  required double sessionLoss,
}) {
  return showModalBottomSheet<SessionTargetChoice>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => _TargetSheet(
      exerciseName: exerciseName,
      rm: rm,
      loss: loss,
      sessionLoss: sessionLoss,
    ),
  );
}

class _TargetSheet extends StatefulWidget {
  final String exerciseName;
  final RmTarget? rm;
  final double? loss;

  /// Pérdida general de la sesión ([kNoLossLimit] = sin límite).
  final double sessionLoss;

  const _TargetSheet({
    required this.exerciseName,
    this.rm,
    this.loss,
    required this.sessionLoss,
  });

  @override
  State<_TargetSheet> createState() => _TargetSheetState();
}

class _TargetSheetState extends State<_TargetSheet> {
  late RmTarget? rm = widget.rm == null
      ? null
      : RmTarget(
          widget.rm!.min.clamp(_rmMin, _rmMax).toDouble(),
          widget.rm!.max.clamp(_rmMin, _rmMax).toDouble(),
        );
  late double? loss = widget.loss;

  /// Último rango usado, para que el deslizador no salte al quitar el
  /// objetivo y volver a ponerlo.
  late RmTarget lastRm = rm ?? const RmTarget(70, 80);

  void _done(bool all) =>
      Navigator.pop(context, (rm: rm, loss: loss, applyToAll: all));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final custom = loss;
    final losses = {
      ...kLossPresets,
      if (custom != null && custom.isFinite) custom,
    }.toList()..sort();

    Widget header(String title, String value, {bool dim = false}) => Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: dim ? Colors.white54 : primary,
          ),
        ),
      ],
    );

    final slider = rm ?? lastRm;
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Objetivo · ${widget.exerciseName}',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  header(
                    'Intensidad (%1RM)',
                    rm == null ? 'Sin objetivo' : rmTargetText(rm!),
                    dim: rm == null,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final (i, (label, t)) in kRmPresets.indexed)
                        ChoiceChip(
                          key: Key('rm-preset-$i'),
                          label: Text(
                            t == null ? label : '$label ${rmTargetText(t)}',
                          ),
                          selected: rm == t,
                          onSelected: (_) => setState(() {
                            rm = t;
                            if (t != null) lastRm = t;
                          }),
                        ),
                    ],
                  ),
                  RangeSlider(
                    key: const Key('rm-slider'),
                    min: _rmMin,
                    max: _rmMax,
                    divisions: ((_rmMax - _rmMin) / 5).round(),
                    values: RangeValues(slider.min, slider.max),
                    labels: RangeLabels(
                      '${kg(slider.min)} %',
                      '${kg(slider.max)} %',
                    ),
                    activeColor: rm == null ? Colors.white24 : null,
                    onChanged: (v) => setState(() {
                      rm = lastRm = RmTarget(
                        v.start.roundToDouble(),
                        v.end.roundToDouble(),
                      );
                    }),
                  ),
                  const SizedBox(height: 12),
                  header(
                    'Pérdida de velocidad máxima',
                    loss == null
                        ? 'Sesión · ${lossLimitText(widget.sessionLoss)}'
                        : lossLimitText(loss!),
                    dim: loss == null,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final l in losses)
                        ChoiceChip(
                          key: Key('loss-${kg(l)}'),
                          label: Text('${kg(l)} %'),
                          selected: loss == l,
                          onSelected: (_) => setState(() => loss = l),
                        ),
                      ChoiceChip(
                        key: const Key('loss-off'),
                        label: const Text('Sin límite'),
                        selected: loss == kNoLossLimit,
                        onSelected: (_) => setState(() => loss = kNoLossLimit),
                      ),
                      ChoiceChip(
                        key: const Key('loss-default'),
                        label: Text(
                          'Sesión (${lossLimitText(widget.sessionLoss)})',
                        ),
                        selected: loss == null,
                        onSelected: (_) => setState(() => loss = null),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                const Spacer(),
                OutlinedButton(
                  key: const Key('rm-target-save-all'),
                  onPressed: () => _done(true),
                  child: const Text('Guardar en todos'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const Key('rm-target-save'),
                  onPressed: () => _done(false),
                  child: const Text('Guardar'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Pérdida de velocidad general de la sesión, con botones de un toque.
/// Devuelve el valor ([kNoLossLimit] = sin límite) o null si se cancela.
Future<double?> askSessionLoss(BuildContext context, double current) {
  return showModalBottomSheet<double>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SheetScaffold(
      title: 'Pérdida de velocidad de la sesión',
      content: [
        ValueHeader('Actual', lossLimitText(current)),
        const SizedBox(height: 4),
        const Text(
          'Se aplica a todos los ejercicios salvo los que la cambien en su '
          'objetivo. La sesión siguiente empieza con esta.',
          style: TextStyle(fontSize: 13, color: Colors.white60),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final l in [...kLossPresets, kNoLossLimit])
              ChoiceChip(
                key: Key(
                  l.isInfinite ? 'session-loss-off' : 'session-loss-${kg(l)}',
                ),
                label: Text(lossLimitText(l)),
                selected: l == current,
                onSelected: (_) => Navigator.pop(ctx, l),
              ),
          ],
        ),
      ],
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancelar'),
        ),
      ],
    ),
  );
}
