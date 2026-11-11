import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:miencoder/app_controller.dart';
import 'package:miencoder/core/analysis.dart';
import 'package:miencoder/core/frame_parser.dart';
import 'package:miencoder/main.dart';
import 'package:miencoder/services/encoder.dart';
import 'package:miencoder/services/repository.dart';

import 'controller_test.dart' show SilentFeedback;

EncoderFrame f(double mpv) => parseFrameText(
  '50.00 ${(mpv * 0.95).toStringAsFixed(2)} ${mpv.toStringAsFixed(2)} ${(mpv * 1.6).toStringAsFixed(2)}',
)!;

void main() {
  test('máximo acumulado', () {
    expect(runningMax([0.55, 0.61, 0.73, 0.64, 0.56]), [
      0.55,
      0.61,
      0.73,
      0.73,
      0.73,
    ]);
    expect(runningMax([]), isEmpty);
  });

  test('color de cada rep = pérdida vs la mejor HASTA ella', () {
    // Serie real de la tablet: la rep 1 (0.55) era la mejor en su momento.
    final v = [0.55, 0.61, 0.73, 0.64, 0.60, 0.64, 0.56];
    final rb = runningMax(v);
    final levels = [
      for (var i = 0; i < v.length; i++)
        fatigueLevel(velocityLossPercent(rb[i], v[i]), 20),
    ];
    expect(levels.first, FatigueLevel.fresh); // antes salía en rojo
    expect(levels.last, FatigueLevel.stop); // 0.56 vs 0.73 = −23 %
  });

  group('Tablet', () {
    late AppController c;
    setUp(() async {
      await initializeDateFormatting('es');
      final db = await newDatabaseFactoryMemory().openDatabase('t.db');
      c = AppController(
        repo: Repository(db),
        feedback: SilentFeedback(),
        encoder: SimulatedEncoderSource(),
      );
      await c.init();
      for (final n in [
        'Ana',
        'Ben',
        'Carla',
        'Dani',
        'Eva',
        'Fran',
        'Gonzalo Fernández',
      ]) {
        await c.createAndAddToSession(n);
      }
    });

    testWidgets('cuadrícula de deportistas grande y funcional', (tester) async {
      const size = Size(1280, 854);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MiEncoderApp(controller: c));
      await tester.pump();

      final ben = tester.getRect(find.text('Ben'));
      final benButton = tester.getRect(
        find
            .ancestor(of: find.text('Ben'), matching: find.byType(SizedBox))
            .first,
      );
      expect(benButton.height, greaterThanOrEqualTo(60));
      expect(benButton.width, greaterThanOrEqualTo(120));
      expect(ben.bottom, lessThan(size.height));

      await tester.tap(find.text('Ben'));
      await tester.pump();
      expect(c.playerById(c.activePlayerId)!.name, 'Ben');
      await tester.tap(find.text('Sin asignar'));
      await tester.pump();
      expect(c.activePlayerId, isNull);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    });
  });
}
