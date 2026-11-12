import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:miencoder/ui/value_sheets.dart';

/// Abre el panel que devuelve [open] en una tablet en horizontal y guarda
/// el resultado en [out].
Future<void> pumpSheet<T>(
  WidgetTester tester,
  Future<T?> Function(BuildContext) open,
  void Function(T?) out,
) async {
  tester.view.physicalSize = const Size(2000, 1335);
  tester.view.devicePixelRatio = 1.6;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: Builder(
        builder: (ctx) => TextButton(
          onPressed: () async => out(await open(ctx)),
          child: const Text('abrir'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull); // sin overflow
}

String textOf(WidgetTester tester, String key) =>
    (tester.widget(find.byKey(Key(key))) as Text).data!;

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  group('Punto manual', () {
    testWidgets('sugiere la velocidad del perfil y la sigue con la carga', (
      tester,
    ) async {
      ManualPoint? r;
      await pumpSheet<ManualPoint>(
        tester,
        (ctx) => showManualPointSheet(
          ctx,
          initialLoad: 80,
          metricLabel: 'VMP',
          velocityAt: (l) => 1.40 - 0.01 * l,
          today: DateTime(2026, 11, 12),
        ),
        (v) => r = v,
      );
      expect(find.byType(TextField), findsNothing);
      expect(textOf(tester, 'manual-velocity'), '0.60 m/s');
      expect(textOf(tester, 'manual-date'), 'Hoy');

      await tester.tap(find.byKey(const Key('manual-load+5')));
      await tester.pump();
      expect(textOf(tester, 'manual-load'), '85 kg');
      expect(textOf(tester, 'manual-velocity'), '0.55 m/s');

      // Al tocar la velocidad deja de seguir a la carga.
      await tester.tap(find.byKey(const Key('manual-vel+0.01')));
      await tester.tap(find.byKey(const Key('manual-load-2.5')));
      await tester.pump();
      expect(textOf(tester, 'manual-velocity'), '0.56 m/s');

      await tester.tap(find.byKey(const Key('manual-save')));
      await tester.pumpAndSettle();
      expect(r!.load, 82.5);
      expect(r!.velocity, closeTo(0.56, 1e-9));
      expect(r!.date, DateTime(2026, 11, 12));
    });
  });

  group('Ejercicio', () {
    testWidgets('nuevo: nombre + preset de VMT en un solo panel', (
      tester,
    ) async {
      ExerciseEdit? r;
      await pumpSheet<ExerciseEdit>(
        tester,
        (ctx) => showExerciseSheet(ctx, title: 'Nuevo ejercicio'),
        (v) => r = v,
      );
      final save = find.byKey(const Key('exercise-save'));
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      await tester.enterText(find.byKey(const Key('exercise-name')), 'Zancada');
      await tester.tap(find.byKey(const Key('mvt-preset-3'))); // 0,17
      await tester.pump();
      await tester.tap(find.byKey(const Key('mvt+0.01')));
      await tester.pump();
      expect(textOf(tester, 'exercise-mvt'), '0.18 m/s');
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(r!.name, 'Zancada');
      expect(r!.mvt, closeTo(0.18, 1e-9));
    });

    testWidgets('cambiar VMT: sin campo de nombre', (tester) async {
      ExerciseEdit? r;
      await pumpSheet<ExerciseEdit>(
        tester,
        (ctx) => showExerciseSheet(
          ctx,
          title: 'VMT de Remo',
          name: 'Remo',
          mvt: 0.50,
          askName: false,
        ),
        (v) => r = v,
      );
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.byKey(const Key('mvt-0.05')));
      await tester.tap(find.byKey(const Key('exercise-save')));
      await tester.pumpAndSettle();
      expect(r!.name, 'Remo');
      expect(r!.mvt, closeTo(0.45, 1e-9));
    });

    testWidgets('cancelar no crea nada', (tester) async {
      ExerciseEdit? r = (name: 'x', mvt: 1);
      await pumpSheet<ExerciseEdit>(
        tester,
        (ctx) => showExerciseSheet(ctx, title: 'Nuevo ejercicio'),
        (v) => r = v,
      );
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(r, isNull);
    });
  });

  group('ROM objetivo', () {
    testWidgets('pasos desde el ROM actual y Fijar', (tester) async {
      RomTargetChoice? r;
      await pumpSheet<RomTargetChoice>(
        tester,
        (ctx) => showRomTargetSheet(ctx, initial: 47.6, canReset: false),
        (v) => r = v,
      );
      expect(find.byType(TextField), findsNothing);
      expect(find.byKey(const Key('rom-auto')), findsNothing);
      expect(textOf(tester, 'rom-value'), '48 cm');
      await tester.tap(find.byKey(const Key('rom-5')));
      await tester.tap(find.byKey(const Key('rom+1')));
      await tester.pump();
      expect(textOf(tester, 'rom-value'), '44 cm');
      await tester.tap(find.byKey(const Key('rom-save')));
      await tester.pumpAndSettle();
      expect(r!.cm, 44);
    });

    testWidgets('con objetivo manual: «Automático» lo quita', (tester) async {
      RomTargetChoice? r;
      await pumpSheet<RomTargetChoice>(
        tester,
        (ctx) => showRomTargetSheet(ctx, initial: 40, canReset: true),
        (v) => r = v,
      );
      await tester.tap(find.byKey(const Key('rom-auto')));
      await tester.pumpAndSettle();
      expect(r, isNotNull);
      expect(r!.cm, isNull);
    });
  });
}
