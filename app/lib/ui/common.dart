import 'package:flutter/material.dart';

import '../core/analysis.dart';
import '../core/models.dart';

const kFresh = Color(0xFF2ECC71);
const kWarning = Color(0xFFF5A623);
const kStop = Color(0xFFE74C3C);

/// Color único cuando los avisos de fatiga están desactivados.
const kNeutral = Color(0xFF64B5F6);

Color fatigueColor(FatigueLevel l) => switch (l) {
  FatigueLevel.off => kNeutral,
  FatigueLevel.fresh => kFresh,
  FatigueLevel.warning => kWarning,
  FatigueLevel.stop => kStop,
};

Color dayRmColor(DayRmLevel l) => switch (l) {
  DayRmLevel.above || DayRmLevel.normal => kFresh,
  DayRmLevel.low => kWarning,
  DayRmLevel.veryLow => kStop,
};

/// "normal" dentro del rango de la persona; si no, "+5 %" o "−7 %".
String dayRmText(DayRmEstimate e) {
  if (e.level == DayRmLevel.normal) return 'normal';
  final p = e.percent.round();
  return p > 0 ? '+$p %' : '−${-p} %';
}

/// Diferencia de ROM en cm con signo: "+2", "−7", "0".
String cmDelta(double d) {
  final r = d.round();
  return r > 0 ? '+$r' : (r < 0 ? '−${-r}' : '0');
}

/// Texto corto del ROM de una serie para la lista de series, o null si todo
/// está dentro del rango (no se muestra nada para no saturar).
String? setRomText(SetRomSummary s) {
  if (s.status != RomStatus.ok) return 'ROM ${cmDelta(s.meanDelta)} cm';
  if (s.dropsAtEnd) return 'ROM ${cmDelta(s.drift!)} cm al final';
  if (s.outOfRange > 0) {
    return '${s.outOfRange} rep${s.outOfRange == 1 ? '' : 's'} con ROM fuera';
  }
  return null;
}

String v2(double v) => v.toStringAsFixed(2);

/// "75–80 %".
String rmTargetText(RmTarget t) =>
    t.min == t.max ? '${kg(t.min)} %' : '${kg(t.min)}–${kg(t.max)} %';

/// "20 %" o "Sin límite" ([kNoLossLimit]).
String lossLimitText(double loss) =>
    loss.isInfinite ? 'Sin límite' : '${kg(loss)} %';

/// "75–80 % · pérdida ≤ 20 %", "75–80 %", "pérdida ≤ 20 %" o
/// "sin límite de pérdida".
String sessionTargetText(RmTarget? rm, double? loss) => [
  if (rm != null) rm.isNone ? 'sin %1RM' : rmTargetText(rm),
  if (loss != null)
    loss.isInfinite ? 'sin límite de pérdida' : 'pérdida ≤ ${kg(loss)} %',
].join(' · ');

/// Consejo de carga: "↑ Sube a 110 kg (+10)", "✓ Mantén 100 kg"…
String loadAdviceText(LoadAdvice a) => switch (a.kind) {
  LoadAdviceKind.keep => '✓ Mantén ${kg(a.load)} kg',
  LoadAdviceKind.up => '↑ Sube a ${kg(a.targetLoad)} kg (+${kg(a.delta)})',
  LoadAdviceKind.down => '↓ Baja a ${kg(a.targetLoad)} kg (−${kg(-a.delta)})',
};

Color loadAdviceColor(LoadAdviceKind k) =>
    k == LoadAdviceKind.keep ? kFresh : kWarning;

String kg(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

Future<String?> askText(
  BuildContext context, {
  required String title,
  String initial = '',
  String? hint,
  TextInputType? keyboard,
}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        keyboardType: keyboard,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, c.text),
          child: const Text('Aceptar'),
        ),
      ],
    ),
  );
}

double? parseNum(String? s) =>
    s == null ? null : double.tryParse(s.trim().replaceAll(',', '.'));

/// "−12 %", o "0 %" si no hay pérdida (nunca "−0 %").
String lossText(double loss) {
  final r = loss.round();
  return r == 0 ? '0 %' : '−$r %';
}

/// Periodos de filtro. 0 = hoy (desde las 00:00); null = todo.
const kPeriods = <String, int?>{
  'Hoy': 0,
  '7 días': 7,
  '30 días': 30,
  '90 días': 90,
  'Todo': null,
};

DateTime? sinceForPeriod(String period, {DateTime? now}) {
  final days = kPeriods[period];
  final n = now ?? DateTime.now();
  if (days == null) return null;
  if (days == 0) return DateTime(n.year, n.month, n.day);
  return n.subtract(Duration(days: days));
}

/// Duración de un aviso sin acción.
const kSnackDuration = Duration(seconds: 3);

/// Duración de un aviso con acción (p. ej. "Deshacer"): algo más de margen
/// para pulsarla, pero se cierra solo igualmente.
const kSnackActionDuration = Duration(seconds: 5);

/// Aviso flotante breve con el estilo de la app. Sustituye al que hubiera.
/// Siempre se cierra solo, lleve acción o no.
void showAppSnack(
  BuildContext context,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
  Duration? duration,
}) => showAppSnackOn(
  ScaffoldMessenger.of(context),
  Theme.of(context),
  message,
  actionLabel: actionLabel,
  onAction: onAction,
  duration: duration,
);

/// Igual que [showAppSnack], pero con el messenger ya obtenido (útil cuando
/// el widget que lo lanza desaparece, p. ej. tras deslizar para borrar).
void showAppSnackOn(
  ScaffoldMessengerState messenger,
  ThemeData theme,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
  Duration? duration,
}) {
  messenger
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration:
            duration ??
            (actionLabel == null ? kSnackDuration : kSnackActionDuration),
        // Desde Flutter 3.29 un SnackBar con acción no se cierra nunca por
        // defecto (persist = true). Lo forzamos a respetar la duración.
        persist: false,
        // Con acción, una X para descartarla sin aceptarla.
        showCloseIcon: actionLabel != null,
        closeIconColor: theme.colorScheme.onSurfaceVariant,
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        content: Text(
          message,
          style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 15),
        ),
        action: actionLabel == null
            ? null
            : SnackBarAction(
                label: actionLabel,
                textColor: theme.colorScheme.primary,
                onPressed: onAction ?? () {},
              ),
      ),
    );
}

/// Hoja inferior con su propio ScaffoldMessenger, para que los avisos
/// (p. ej. "Deshacer") se vean dentro de la hoja y no detrás.
Widget sheetWithMessenger(Widget child) => ScaffoldMessenger(
  child: Scaffold(backgroundColor: Colors.transparent, body: child),
);

/// Pregunta tras cambiar de deportista: ¿lo recién registrado era suyo?
/// [to] null = se cambió a "Sin asignar".
String switchQuestion(int n, String? to) {
  if (to == null) {
    return n == 1
        ? '¿Dejar la última rep sin asignar?'
        : '¿Dejar las $n últimas reps sin asignar?';
  }
  return n == 1
      ? '¿La última rep era de $to?'
      : '¿Las $n últimas reps eran de $to?';
}
