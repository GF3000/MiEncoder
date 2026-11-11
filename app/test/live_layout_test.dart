import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:miencoder/app_controller.dart';
import 'package:miencoder/core/frame_parser.dart';
import 'package:miencoder/main.dart';
import 'package:miencoder/services/encoder.dart';
import 'package:miencoder/services/repository.dart';

import 'controller_test.dart' show SilentFeedback;

void main() {
  late AppController c;

  setUp(() async {
    await initializeDateFormatting('es');
    final db = await newDatabaseFactoryMemory().openDatabase('ui.db');
    c = AppController(
      repo: Repository(db),
      feedback: SilentFeedback(),
      encoder: SimulatedEncoderSource(),
    );
    await c.init();
    for (final n in ['Ana', 'Ben', 'Carla', 'Dani', 'Eva', 'Fran']) {
      await c.createAndAddToSession(n);
    }
  });

  // Tamaños lógicos reales: el móvil del usuario (2400x1080 a densidad 2.75)
  // y uno pequeño. Se simula la barra de estado (24 dp).
  for (final (name, size) in [
    ('vertical', const Size(393, 873)),
    ('horizontal', const Size(873, 393)),
    ('horizontal pequeño', const Size(640, 320)),
    ('vertical pequeño', const Size(320, 568)),
    ('tablet horizontal', const Size(1280, 854)),
  ]) {
    testWidgets('app completa: En vivo cabe entera en $name', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 24);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MiEncoderApp(controller: c));
      await tester.pump();
      expect(tester.takeException(), isNull);

      c.setActive(c.activePlayers.first.id);
      for (final t in [
        '55.20 0.95 1.01 1.60',
        '54.80 0.90 0.94 1.50',
        '142.88 1.12 1.28 2.0',
      ]) {
        c.onFrame(parseFrameText(t, byteLength: t.length)!);
      }
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);

      // Oráculo del fallo visto en el móvil: la tarjeta no puede salirse por
      // abajo (las etiquetas quedaban cortadas) y las barras deben verse.
      final screenH = size.height;
      final rom = tester.getRect(find.text('ROM'));
      expect(
        rom.bottom,
        lessThanOrEqualTo(screenH),
        reason: 'etiqueta ROM fuera de pantalla',
      );
      // Barra de la rep 3: su índice "3" debajo de la barra, visible.
      final idx = find.text('3');
      expect(idx, findsWidgets);
      final barLabel = tester.getRect(idx.last);
      expect(
        barLabel.bottom,
        lessThanOrEqualTo(screenH),
        reason: 'barras fuera de pantalla',
      );
      expect(
        barLabel.top,
        greaterThan(rom.bottom - 1),
        reason: 'barras solapadas con la tarjeta',
      );
      // En horizontal las barras deben llenar el espacio (sin hueco abajo).
      if (size.width > size.height) {
        expect(
          barLabel.bottom,
          greaterThan(screenH - 60),
          reason: 'hueco vacío bajo las barras',
        );
      }
      expect(find.text('1.28'), findsWidgets);
      expect(find.text('Sin asignar'), findsWidgets);
    });
  }
}
