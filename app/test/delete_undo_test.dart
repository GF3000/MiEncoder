import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:miencoder/app_controller.dart';
import 'package:miencoder/core/frame_parser.dart';
import 'package:miencoder/main.dart';
import 'package:miencoder/services/encoder.dart';
import 'package:miencoder/services/repository.dart';
import 'package:miencoder/ui/common.dart';
import 'package:miencoder/ui/set_tile.dart';

import 'controller_test.dart' show SilentFeedback;

EncoderFrame f(double mpv) => parseFrameText(
  '50.00 ${(mpv * 0.95).toStringAsFixed(2)} ${mpv.toStringAsFixed(2)} ${(mpv * 1.6).toStringAsFixed(2)}',
)!;

void main() {
  late AppController c;
  late Repository repo;
  late DateTime now;

  Future<AppController> build() async {
    final ctrl = AppController(
      repo: repo,
      feedback: SilentFeedback(),
      encoder: SimulatedEncoderSource(),
      clock: () => now,
    );
    await ctrl.init();
    return ctrl;
  }

  setUp(() async {
    await initializeDateFormatting('es');
    repo = Repository(await newDatabaseFactoryMemory().openDatabase('d.db'));
    now = DateTime(2026, 11, 11, 10);
    c = await build();
  });

  group('Borrar una repetición', () {
    test('la fatiga se recalcula sin la rep borrada', () async {
      c.onFrame(f(1.00));
      c.onFrame(f(1.50)); // rep mal anotada (pico falso)
      c.onFrame(f(0.95));
      expect(c.lastLive!.lossPercent, closeTo(36.7, 0.1)); // vs 1.50
      await c.deleteRep(c.reps[1].id);
      expect(c.currentSetReps.length, 2);
      expect(c.lastLive!.lossPercent, closeTo(5, 0.01)); // vs 1.00
      expect(c.lastLive!.indexInSet, 2);
    });

    test('deshacer la devuelve a su sitio y persiste', () async {
      c.onFrame(f(1.0));
      now = now.add(const Duration(seconds: 3));
      c.onFrame(f(0.9));
      final id = c.reps[0].id;
      final d = await c.deleteRep(id);
      await c.restore(d!);
      expect(c.reps.map((r) => r.id).first, id);
      expect(c.currentSetReps.length, 2);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect((await build()).reps.length, 2);
    });

    test('si era la única, se borra la serie y deshacer la recupera', () async {
      c.onFrame(f(1.0));
      final setId = c.sets.single.id;
      final d = await c.deleteRep(c.reps.single.id);
      expect(c.sets, isEmpty);
      await c.restore(d!);
      expect(c.sets.single.id, setId);
      expect(c.reps.single.setId, setId);
    });

    test('borrar no deja rastro en disco', () async {
      c.onFrame(f(1.0));
      c.onFrame(f(0.9));
      await c.deleteRep(c.reps.last.id);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect((await build()).reps.length, 1);
    });
  });

  group('Borrar una serie', () {
    test('deshacer recupera serie y repeticiones', () async {
      final ana = await c.addPlayer('Ana');
      c.setActive(ana.id);
      c.onFrame(f(1.0));
      c.onFrame(f(0.9));
      final d = await c.deleteSet(c.sets.single.id);
      expect(c.reps, isEmpty);
      await c.restore(d!);
      expect(c.reps.length, 2);
      expect(c.sets.single.playerId, ana.id);
    });
  });

  group('Pregunta al cambiar de deportista', () {
    test('solo si las reps son recientes (< 2 min)', () async {
      final ana = await c.addPlayer('Ana');
      final ben = await c.addPlayer('Ben');
      c.setActive(ana.id);
      c.onFrame(f(1.0));
      now = now.add(const Duration(minutes: 3));
      expect(c.setActive(ben.id), isNull);
    });

    test('dentro del margen sí se pregunta', () async {
      final ana = await c.addPlayer('Ana');
      final ben = await c.addPlayer('Ben');
      c.setActive(ana.id);
      c.onFrame(f(1.0));
      now = now.add(const Duration(seconds: 90));
      expect(c.setActive(ben.id)!.repIds.length, 1);
    });

    test('texto con concordancia correcta', () {
      expect(switchQuestion(1, 'Ana'), '¿La última rep era de Ana?');
      expect(switchQuestion(3, 'Ana'), '¿Las 3 últimas reps eran de Ana?');
      expect(switchQuestion(1, null), '¿Dejar la última rep sin asignar?');
      expect(switchQuestion(2, null), '¿Dejar las 2 últimas reps sin asignar?');
    });
  });

  group('Interfaz', () {
    Future<void> pumpApp(WidgetTester tester, Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MiEncoderApp(controller: c));
      await tester.pump();
    }

    testWidgets('el chip dice "Sin asignar"', (tester) async {
      await tester.runAsync(() => c.addPlayer('Ana'));
      await pumpApp(tester, const Size(393, 873));
      await tester.pump();
      expect(find.widgetWithText(ChoiceChip, 'Sin asignar'), findsOneWidget);
      expect(find.text('Ninguno'), findsNothing);
    });

    testWidgets('tocar una barra → Eliminar → Deshacer', (tester) async {
      await pumpApp(tester, const Size(393, 873));
      c.onFrame(f(1.0));
      c.onFrame(f(0.9));
      c.onFrame(f(0.8));
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.byKey(const Key('bar-2')));
      await tester.pumpAndSettle();
      expect(find.text('Eliminar'), findsOneWidget);
      await tester.tap(find.text('Eliminar'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      await tester.pumpAndSettle();
      expect(c.reps.length, 2);
      expect(find.text('Deshacer'), findsOneWidget);

      await tester.tap(find.text('Deshacer'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      await tester.pumpAndSettle();
      expect(c.reps.length, 3);
      await tester.pump(const Duration(seconds: 5)); // deja expirar el aviso
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('deslizar una serie en "Series recientes" la borra', (
      tester,
    ) async {
      await pumpApp(tester, const Size(393, 873));
      c.onFrame(f(1.0));
      c.forceNewSet();
      c.onFrame(f(0.9));
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.byTooltip('Series recientes'));
      await tester.pumpAndSettle();
      expect(find.byType(Dismissible), findsNWidgets(2));
      await tester.runAsync(() async {
        await tester.drag(
          find.byType(Dismissible).first,
          const Offset(-500, 0),
        );
        await tester.pumpAndSettle();
      });
      // El aviso sale tras una escritura en la BD que, según cuándo termine la
      // animación, corre con reloj real o con el simulado: alternar ambos hasta
      // que aparezca (antes había un retardo fijo y el test era intermitente).
      for (var i = 0; i < 40 && find.text('Deshacer').evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pump(const Duration(milliseconds: 300));
      expect(c.recentSets().length, 1);
      expect(
        find.text('Deshacer'),
        findsOneWidget,
      ); // visible dentro de la hoja
      await tester.pump(const Duration(seconds: 5)); // deja expirar el aviso
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('mantener pulsada una serie → Eliminar serie', (tester) async {
      await pumpApp(tester, const Size(393, 873));
      c.onFrame(f(1.0));
      c.forceNewSet();
      c.onFrame(f(0.9));
      c.onFrame(f(0.85));
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.byTooltip('Series recientes'));
      await tester.pumpAndSettle();
      await tester.longPress(
        find
            .descendant(
              of: find.byType(SetTile),
              matching: find.byType(ListTile),
            )
            .first,
      );
      await tester.pumpAndSettle();
      final item = find.textContaining('Eliminar serie (');
      expect(item, findsOneWidget);
      await tester.tap(item);
      for (var i = 0; i < 40 && c.recentSets().length != 1; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(c.recentSets().length, 1);
      expect(c.reps.length, lessThan(3));
      await tester.pump(const Duration(seconds: 5)); // deja expirar el aviso
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'selector de peso en horizontal: Aceptar a la vista y funciona',
      (tester) async {
        const size = Size(873, 393); // el móvil del usuario en horizontal
        c.setLoad(45);
        await pumpApp(tester, size);
        await tester.tap(find.text('45 kg'));
        await tester.pumpAndSettle();
        expect(find.byType(CupertinoPicker), findsNWidgets(4));
        final accept = tester.getRect(find.text('Aceptar'));
        final cancel = tester.getRect(find.text('Cancelar'));
        expect(accept.bottom, lessThanOrEqualTo(size.height));
        expect(cancel.bottom, lessThanOrEqualTo(size.height));
        await tester.drag(
          find.byType(CupertinoPicker).at(2),
          const Offset(0, -52),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Aceptar'));
        await tester.pumpAndSettle();
        expect(c.loadKg, 46);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
