import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:miencoder/app_controller.dart';
import 'package:miencoder/core/models.dart';
import 'package:miencoder/main.dart';
import 'package:miencoder/services/encoder.dart';
import 'package:miencoder/services/repository.dart';
import 'package:miencoder/ui/load_picker.dart';

import 'controller_test.dart' show SilentFeedback;

void main() {
  group('Descomponer y recomponer la carga', () {
    test('valores habituales', () {
      expect(splitLoad(0), (0, 0, 0, 0));
      expect(splitLoad(45), (0, 4, 5, 0));
      expect(splitLoad(62.5), (0, 6, 2, 2));
      expect(splitLoad(107.25), (1, 0, 7, 1));
      expect(splitLoad(499.75), (4, 9, 9, 3));
    });

    test('ida y vuelta para todas las cargas de 0 a 499.75', () {
      for (var q = 0; q < 2000; q++) {
        final kg = q / 4;
        final (h, t, u, d) = splitLoad(kg);
        expect(joinLoad(h, t, u, d), kg);
      }
    });

    test('decimales raros se redondean al cuarto de kilo', () {
      expect(splitLoad(42.6), (0, 4, 2, 2)); // 42.5
      expect(splitLoad(42.9), (0, 4, 3, 0)); // 43.0
    });

    test('fuera de rango se acota', () {
      expect(splitLoad(-5), (0, 0, 0, 0));
      expect(splitLoad(900), (4, 9, 9, 3));
    });
  });

  group('En la app', () {
    late AppController c;

    setUp(() async {
      await initializeDateFormatting('es');
      final db = await newDatabaseFactoryMemory().openDatabase('pk.db');
      c = AppController(
        repo: Repository(db),
        feedback: SilentFeedback(),
        encoder: SimulatedEncoderSource(),
      );
      await c.init();
    });

    /// Abre el menú tocando el nombre del ejercicio (el objetivo de al
    /// lado abre su panel).
    Future<void> openExerciseMenu(WidgetTester tester) => tester.tap(
      find.descendant(
        of: find.byKey(const Key('exercise-picker')),
        matching: find.text(c.exercise.name),
      ),
    );

    Future<void> pumpApp(WidgetTester tester, Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MiEncoderApp(controller: c));
      await tester.pump();
    }

    testWidgets('tocar el peso abre las ruedas; girar unidades y aceptar', (
      tester,
    ) async {
      c.setLoad(45);
      await pumpApp(tester, const Size(393, 873));
      await tester.tap(find.text('45 kg'));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoPicker), findsNWidgets(4));
      expect(find.byKey(const Key('load-picker-value')), findsOneWidget);

      // Rueda de unidades (3.ª): subir dos posiciones → 47.
      final units = find.byType(CupertinoPicker).at(2);
      await tester.drag(units, const Offset(0, -104));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('load-picker-value'))).data,
        '47 kg',
      );
      // Rueda de decenas (2.ª): bajar una posición → 37.
      await tester.drag(
        find.byType(CupertinoPicker).at(1),
        const Offset(0, 52),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('load-picker-value'))).data,
        '37 kg',
      );
      await tester.tap(find.text('Aceptar'));
      await tester.pumpAndSettle();
      expect(c.loadKg, 37);
      expect(tester.takeException(), isNull);
    });

    testWidgets('cancelar no cambia la carga', (tester) async {
      c.setLoad(45);
      await pumpApp(tester, const Size(393, 873));
      await tester.tap(find.text('45 kg'));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byType(CupertinoPicker).at(2),
        const Offset(0, -52),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(c.loadKg, 45);
    });

    for (final (name, size) in [
      ('vertical', const Size(393, 873)),
      ('horizontal', const Size(873, 393)),
    ]) {
      testWidgets('el menú de ejercicio no ocupa todo el ancho ($name)', (
        tester,
      ) async {
        await pumpApp(tester, size);
        await openExerciseMenu(tester);
        await tester.pumpAndSettle();
        final item = find.text('Press banca').last;
        final menu = tester.getRect(
          find.ancestor(of: item, matching: find.byType(Material)).first,
        );
        expect(menu.width, lessThanOrEqualTo(360));
        expect(menu.width, lessThan(size.width - 40)); // no ocupa todo el ancho
        await tester.tap(item);
        await tester.pumpAndSettle();
        expect(c.exerciseId, 'bench');
        expect(find.text('Press banca'), findsOneWidget); // ya en la cabecera
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('el icono del menú edita el objetivo sin cambiar de ejercicio', (
      tester,
    ) async {
      await pumpApp(tester, const Size(1280, 800));
      final before = c.exerciseId;
      final headerW = tester
          .getSize(find.byKey(const Key('exercise-picker')))
          .width;
      await openExerciseMenu(tester);
      await tester.pumpAndSettle();
      // Sin objetivo: icono +.
      expect(
        find.descendant(
          of: find.byKey(const Key('exercise-target-edit-bench')),
          matching: find.byIcon(Icons.add),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('exercise-target-edit-bench')));
      await tester.pumpAndSettle();
      expect(find.text('Objetivo · Press banca'), findsOneWidget);
      await tester.tap(find.byKey(const Key('rm-preset-1'))); // 65–75
      await tester.tap(find.byKey(const Key('loss-15')));
      await tester.tap(find.byKey(const Key('rm-target-save')));
      await tester.pumpAndSettle();
      expect(c.exerciseId, before); // no ha cambiado de ejercicio
      final s = c.activeSession!;
      expect(s.rmTargets['bench'], const RmTarget(65, 75));
      expect(s.lossTargets['bench'], 15);
      expect(s.rmTargets[before], isNull);
      // El botón plegado no cambia de ancho (el objetivo es de otro ejercicio).
      expect(
        tester.getSize(find.byKey(const Key('exercise-picker'))).width,
        headerW,
      );

      // En el menú se ve el objetivo y el icono pasa a ⚙.
      await openExerciseMenu(tester);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const Key('exercise-item-target-bench')))
            .data,
        '65–75 % · pérdida ≤ 15 %',
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('exercise-target-edit-bench')),
          matching: find.byIcon(Icons.settings),
        ),
        findsOneWidget,
      );
      // Y el panel de la sesión muestra lo mismo.
      await tester.tapAt(const Offset(5, 790)); // cerrar el menú
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('session-picker')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const Key('rm-target-bench')),
          matching: find.text('65–75 % · pérdida ≤ 15 %'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('tocar el objetivo de la cabecera abre su panel', (
      tester,
    ) async {
      await pumpApp(tester, const Size(1280, 800));
      final ex = c.exercise.name;
      await tester.tap(find.byKey(const Key('exercise-target')));
      await tester.pumpAndSettle();
      expect(find.text('Objetivo · $ex'), findsOneWidget);
      expect(find.byKey(const Key('rm-target-save')), findsOneWidget);
    });

    group('con objetivo', () {
      // E/S real de la base de datos: en setUp, fuera del reloj simulado de
      // testWidgets (dentro se queda esperando para siempre).
      setUp(
        () => c.setSessionTarget(
          [c.exerciseId],
          rm: const RmTarget(65, 75),
          loss: 25.0,
        ),
      );

      testWidgets(
        'tablet: el objetivo de la cabecera se ve entero y es pulsable',
        (tester) async {
          // Tablet en horizontal (1600 × 1000 dp).
          await pumpApp(tester, const Size(1600, 1000));
          final pill = find.byKey(const Key('exercise-target'));
          final text = find.descendant(
            of: pill,
            matching: find.text('65–75 % · pérdida ≤ 25 %'),
          );
          expect(text, findsOneWidget);
          final para = tester.renderObject<RenderParagraph>(text);
          expect(para.didExceedMaxLines, isFalse); // sin «…»
          expect(tester.getSize(pill).height, greaterThanOrEqualTo(40));
          expect(tester.takeException(), isNull);
        },
      );
    });
  });
}
