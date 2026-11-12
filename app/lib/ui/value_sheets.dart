import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'common.dart';
import 'load_picker.dart';

// Paneles inferiores para ajustar números sin teclado: valor grande y
// botones de paso. Pensados para la tablet en horizontal en el gimnasio.

/// Esqueleto común: título, contenido desplazable y botones fijos abajo
/// (nunca quedan tapados por el teclado ni se montan sobre el contenido).
class SheetScaffold extends StatelessWidget {
  final String title;
  final List<Widget> content;
  final List<Widget> actions;

  const SheetScaffold({
    super.key,
    required this.title,
    required this.content,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
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
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 16),
                    ...content,
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(children: actions),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fila "Título ........ valor" con el valor grande.
class ValueHeader extends StatelessWidget {
  final String title;
  final String value;
  final bool dim;
  final VoidCallback? onTapValue;
  final Key? valueKey;

  const ValueHeader(
    this.title,
    this.value, {
    super.key,
    this.dim = false,
    this.onTapValue,
    this.valueKey,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = Text(
      value,
      key: valueKey,
      style: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: dim ? Colors.white54 : theme.colorScheme.primary,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
    return Row(
      children: [
        Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
        if (onTapValue == null)
          text
        else
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTapValue,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  text,
                  const SizedBox(width: 4),
                  const Icon(Icons.edit_outlined, size: 18),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Botones −/+ con varios pasos: [−5] [−1] [+1] [+5].
class StepButtons extends StatelessWidget {
  final List<double> steps;
  final String Function(double) label;
  final ValueChanged<double> onStep;
  final String keyPrefix;

  const StepButtons({
    super.key,
    required this.steps,
    required this.label,
    required this.onStep,
    required this.keyPrefix,
  });

  @override
  Widget build(BuildContext context) {
    final all = [for (final s in steps.reversed) -s, ...steps];
    return Row(
      children: [
        for (final s in all)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: OutlinedButton(
                key: Key('$keyPrefix${s > 0 ? '+' : ''}${label(s)}'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 52),
                  padding: EdgeInsets.zero,
                ),
                onPressed: () => onStep(s),
                child: Text(
                  '${s > 0 ? '+' : '−'}${label(s.abs())}',
                  style: const TextStyle(fontSize: 18),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

double _round(double v, double to) => (v / to).round() * to;

// ------------------------------------------------------------ punto manual

typedef ManualPoint = ({double load, double velocity, DateTime date});

/// Punto manual del perfil en un solo panel: carga, velocidad y fecha.
/// [velocityAt] sugiere la velocidad para una carga (el perfil actual) hasta
/// que se toca la velocidad. null = cancelar.
Future<ManualPoint?> showManualPointSheet(
  BuildContext context, {
  required double initialLoad,
  required String metricLabel,
  double? Function(double load)? velocityAt,
  DateTime? today,
}) {
  return showModalBottomSheet<ManualPoint>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _ManualPointSheet(
      initialLoad: initialLoad,
      metricLabel: metricLabel,
      velocityAt: velocityAt,
      today: today ?? DateTime.now(),
    ),
  );
}

class _ManualPointSheet extends StatefulWidget {
  final double initialLoad;
  final String metricLabel;
  final double? Function(double load)? velocityAt;
  final DateTime today;

  const _ManualPointSheet({
    required this.initialLoad,
    required this.metricLabel,
    this.velocityAt,
    required this.today,
  });

  @override
  State<_ManualPointSheet> createState() => _ManualPointSheetState();
}

class _ManualPointSheetState extends State<_ManualPointSheet> {
  late double load = widget.initialLoad;
  late double velocity = _suggest(load) ?? 0.50;
  bool velocityTouched = false;
  late DateTime date = DateUtils.dateOnly(widget.today);

  double? _suggest(double l) {
    final v = widget.velocityAt?.call(l);
    if (v == null || !v.isFinite || v <= 0.05) return null;
    return _round(v, 0.01);
  }

  void _setLoad(double l) {
    load = l.clamp(0, 499.75).toDouble();
    if (!velocityTouched) velocity = _suggest(load) ?? velocity;
  }

  @override
  Widget build(BuildContext context) {
    final isToday = DateUtils.isSameDay(date, widget.today);
    return SheetScaffold(
      title: 'Punto manual',
      content: [
        ValueHeader(
          'Carga',
          '${kg(load)} kg',
          valueKey: const Key('manual-load'),
          onTapValue: () async {
            final v = await showLoadPicker(
              context,
              initial: load,
              title: 'Carga del punto manual',
            );
            if (v != null) setState(() => _setLoad(v));
          },
        ),
        StepButtons(
          steps: const [2.5, 5],
          label: kg,
          keyPrefix: 'manual-load',
          onStep: (s) => setState(() => _setLoad(load + s)),
        ),
        const SizedBox(height: 16),
        ValueHeader(
          'Velocidad (${widget.metricLabel})',
          '${v2(velocity)} m/s',
          valueKey: const Key('manual-velocity'),
          dim: !velocityTouched,
        ),
        if (!velocityTouched && widget.velocityAt != null)
          const Text(
            'Sugerida por el perfil actual: ajústala a lo medido.',
            style: TextStyle(fontSize: 13, color: Colors.white60),
          ),
        StepButtons(
          steps: const [0.01, 0.05],
          label: (s) => s.toStringAsFixed(2),
          keyPrefix: 'manual-vel',
          onStep: (s) => setState(() {
            velocityTouched = true;
            velocity = _round(velocity + s, 0.01).clamp(0.05, 3.0).toDouble();
          }),
        ),
        const SizedBox(height: 16),
        ValueHeader(
          'Fecha',
          isToday ? 'Hoy' : DateFormat('d MMM yyyy', 'es').format(date),
          valueKey: const Key('manual-date'),
          onTapValue: () async {
            final d = await showDatePicker(
              context: context,
              initialDate: date,
              firstDate: DateTime(2020),
              lastDate: widget.today,
            );
            if (d != null) setState(() => date = d);
          },
        ),
      ],
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        const Spacer(),
        FilledButton(
          key: const Key('manual-save'),
          onPressed: load > 0
              ? () => Navigator.pop(context, (
                  load: load,
                  velocity: velocity,
                  date: date,
                ))
              : null,
          child: const Text('Añadir punto'),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------ ejercicio

/// Velocidades a 1RM (VMP) habituales por tipo de ejercicio.
const List<(String, double)> kMvtPresets = [
  ('Sentadilla / pierna', 0.30),
  ('Hip thrust', 0.25),
  ('Press militar', 0.20),
  ('Press banca', 0.17),
  ('Peso muerto', 0.15),
  ('Remo / tirón', 0.50),
];

typedef ExerciseEdit = ({String name, double mvt});

/// Nombre (solo si [askName]) y velocidad a 1RM de un ejercicio en un solo
/// panel. null = cancelar.
Future<ExerciseEdit?> showExerciseSheet(
  BuildContext context, {
  required String title,
  String name = '',
  double mvt = 0.30,
  bool askName = true,
}) {
  return showModalBottomSheet<ExerciseEdit>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) =>
        _ExerciseSheet(title: title, name: name, mvt: mvt, askName: askName),
  );
}

class _ExerciseSheet extends StatefulWidget {
  final String title;
  final String name;
  final double mvt;
  final bool askName;

  const _ExerciseSheet({
    required this.title,
    required this.name,
    required this.mvt,
    required this.askName,
  });

  @override
  State<_ExerciseSheet> createState() => _ExerciseSheetState();
}

class _ExerciseSheetState extends State<_ExerciseSheet> {
  late final name = TextEditingController(text: widget.name);
  late double mvt = widget.mvt;

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ok = !widget.askName || name.text.trim().isNotEmpty;
    return SheetScaffold(
      title: widget.title,
      content: [
        if (widget.askName) ...[
          TextField(
            key: const Key('exercise-name'),
            controller: name,
            autofocus: widget.name.isEmpty,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Nombre',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
        ],
        ValueHeader(
          'Velocidad a 1RM (VMT)',
          '${v2(mvt)} m/s',
          valueKey: const Key('exercise-mvt'),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (i, (label, v)) in kMvtPresets.indexed)
              ChoiceChip(
                key: Key('mvt-preset-$i'),
                label: Text('$label ${v2(v)}'),
                selected: (mvt - v).abs() < 1e-6,
                onSelected: (_) => setState(() => mvt = v),
              ),
          ],
        ),
        const SizedBox(height: 4),
        StepButtons(
          steps: const [0.01, 0.05],
          label: (s) => s.toStringAsFixed(2),
          keyPrefix: 'mvt',
          onStep: (s) => setState(
            () => mvt = _round(mvt + s, 0.01).clamp(0.05, 1.5).toDouble(),
          ),
        ),
        const Text(
          'Es la velocidad a la que se estima el 1RM. Los valores son '
          'referencias habituales; ajústala si conoces la del deportista.',
          style: TextStyle(fontSize: 13, color: Colors.white60),
        ),
      ],
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        const Spacer(),
        FilledButton(
          key: const Key('exercise-save'),
          onPressed: ok
              ? () => Navigator.pop(context, (name: name.text.trim(), mvt: mvt))
              : null,
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------ ROM objetivo

/// Resultado: [cm] null = volver al automático.
typedef RomTargetChoice = ({double? cm});

/// ROM objetivo (cm) con botones de paso, partiendo de [initial] (el ROM
/// de referencia actual). [canReset] muestra «Automático». null = cancelar.
Future<RomTargetChoice?> showRomTargetSheet(
  BuildContext context, {
  required double initial,
  required bool canReset,
  String? autoText,
}) {
  return showModalBottomSheet<RomTargetChoice>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _RomTargetSheet(
      initial: initial,
      canReset: canReset,
      autoText: autoText,
    ),
  );
}

class _RomTargetSheet extends StatefulWidget {
  final double initial;
  final bool canReset;
  final String? autoText;

  const _RomTargetSheet({
    required this.initial,
    required this.canReset,
    this.autoText,
  });

  @override
  State<_RomTargetSheet> createState() => _RomTargetSheetState();
}

class _RomTargetSheetState extends State<_RomTargetSheet> {
  late double cm = widget.initial.roundToDouble().clamp(5, 150).toDouble();

  @override
  Widget build(BuildContext context) {
    return SheetScaffold(
      title: 'ROM objetivo',
      content: [
        ValueHeader(
          'Recorrido',
          '${cm.round()} cm',
          valueKey: const Key('rom-value'),
        ),
        const SizedBox(height: 4),
        StepButtons(
          steps: const [1, 5],
          label: (s) => s.toStringAsFixed(0),
          keyPrefix: 'rom',
          onStep: (s) => setState(() => cm = (cm + s).clamp(5, 150).toDouble()),
        ),
        const SizedBox(height: 8),
        Text(
          widget.autoText ??
              'Fíjalo cuando el recorrido sea distinto del habitual '
                  '(p. ej. sentadilla a cajón).',
          style: const TextStyle(fontSize: 13, color: Colors.white60),
        ),
      ],
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        const Spacer(),
        if (widget.canReset) ...[
          OutlinedButton(
            key: const Key('rom-auto'),
            onPressed: () => Navigator.pop(context, (cm: null)),
            child: const Text('Automático'),
          ),
          const SizedBox(width: 8),
        ],
        FilledButton(
          key: const Key('rom-save'),
          onPressed: () => Navigator.pop(context, (cm: cm)),
          child: const Text('Fijar objetivo'),
        ),
      ],
    );
  }
}
