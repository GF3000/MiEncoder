import 'package:flutter/material.dart';

import '../core/analysis.dart';

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

String v2(double v) => v.toStringAsFixed(2);

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

/// Aviso flotante breve con el estilo de la app. Sustituye al que hubiera.
void showAppSnack(
  BuildContext context,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
  Duration duration = const Duration(seconds: 3),
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
  Duration duration = const Duration(seconds: 3),
}) {
  messenger
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: duration,
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
