import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:miencoder/app_controller.dart';
import 'package:miencoder/core/analysis.dart';
import 'package:miencoder/core/models.dart';
import 'package:miencoder/services/encoder.dart';
import 'package:miencoder/services/repository.dart';
import 'package:miencoder/ui/compare_view.dart';
import 'package:miencoder/ui/player_picker.dart';
import 'package:miencoder/ui/profile_screen.dart';
import 'package:sembast/sembast_memory.dart' show newDatabaseFactoryMemory;

import 'controller_test.dart' show SilentFeedback;

var _n = 0;
Rep rep(double load, double v) => Rep(
  id: 'r${_n++}',
  setId: 's$_n',
  time: DateTime(2026, 11, 1),
  romCm: 50,
  mv: v,
  mpv: v,
  loadKg: load,
  exerciseId: 'squat',
);

/// V = 1.5 − 0.01·carga.
List<Rep> line(List<double> loads) => [
  for (final l in loads) rep(l, 1.5 - 0.01 * l),
];

MetricValue m(
  CompareMetric metric,
  List<Rep> reps, {
  RomReference? rom,
  bool everDone = true,
}) => compareMetricValue(
  metric,
  analysis: analyzeLoadVelocity(reps, VelocityMetric.mpv),
  rom: rom,
  mvt: 0.3,
  everDone: everDone,
);

void main() {
  group('Métricas del perfil', () {
    final reps = line([40, 60, 80, 100]);

    test('1RM, V0, L0, Pmax y carga de Pmax', () {
      expect(m(CompareMetric.oneRm, reps).value, closeTo(120, 1e-9));
      expect(m(CompareMetric.v0, reps).value, closeTo(1.5, 1e-9));
      expect(m(CompareMetric.l0, reps).value, closeTo(150, 1e-9));
      expect(
        m(CompareMetric.pmax, reps).value,
        closeTo(kGravity * 1.5 * 150 / 4, 1e-9),
      );
      expect(m(CompareMetric.optimalLoad, reps).value, closeTo(75, 1e-9));
      expect(m(CompareMetric.oneRm, reps).weak, isFalse);
    });

    test('Pmax es de verdad el máximo de carga × g × velocidad', () {
      final pmax = m(CompareMetric.pmax, reps).value!;
      for (var l = 0.0; l <= 150; l += 5) {
        expect(kGravity * l * (1.5 - 0.01 * l), lessThanOrEqualTo(pmax + 1e-9));
      }
    });

    test('con 2 cargas hay valor, pero poco fiable', () {
      final v = m(CompareMetric.oneRm, line([40, 100]));
      expect(v.value, closeTo(120, 1e-9));
      expect(v.weak, isTrue);
      expect(v.weakReason, 'Solo 2 cargas');
    });

    test('R² bajo: poco fiable', () {
      final noisy = [rep(40, 1.1), rep(60, 0.75), rep(80, 0.85), rep(100, 0.5)];
      final v = m(CompareMetric.v0, noisy);
      expect(v.value, isNotNull);
      expect(v.weakReason, startsWith('R²'));
    });
  });

  group('Métrica que falta', () {
    test('nunca ha hecho el ejercicio', () {
      for (final metric in CompareMetric.values) {
        final v = m(metric, const [], everDone: false);
        expect(v.value, isNull);
        expect(v.gap, MetricGap.neverDone);
      }
    });

    test('sin datos en el periodo', () {
      expect(m(CompareMetric.oneRm, const []).gap, MetricGap.noDataInPeriod);
    });

    test('una sola carga', () {
      expect(m(CompareMetric.l0, line([60])).gap, MetricGap.fewLoads);
    });

    test('la velocidad sube con la carga', () {
      final up = [rep(40, 0.5), rep(80, 0.9)];
      expect(m(CompareMetric.pmax, up).gap, MetricGap.noSlope);
    });

    test('1RM sin sentido (V0 por debajo de la VMT)', () {
      final slow = [rep(40, 0.22), rep(80, 0.2)];
      expect(m(CompareMetric.oneRm, slow).gap, MetricGap.noSlope);
      expect(m(CompareMetric.v0, slow).value, isNotNull);
    });

    test('ROM: referencia o motivo', () {
      expect(m(CompareMetric.rom, const []).gap, MetricGap.fewRomReps);
      expect(
        m(CompareMetric.rom, const [], rom: const RomReference(52, 3)).value,
        52,
      );
    });
  });

  test('los que faltan van al final en ambos sentidos', () {
    final xs = <double?>[3, null, 1, 2];
    expect(List.of(xs)..sort((a, b) => compareNullableLast(a, b)), [
      1,
      2,
      3,
      null,
    ]);
    expect(
      List.of(xs)..sort((a, b) => compareNullableLast(a, b, ascending: false)),
      [3, 2, 1, null],
    );
  });

  group('Pantalla Comparar', () {
    late AppController c;
    late String anaId;
    final ids = <String, String>{};
    setUp(() async {
      await initializeDateFormatting('es');
      final db = await newDatabaseFactoryMemory().openDatabase('c.db');
      c = AppController(
        repo: Repository(db),
        feedback: SilentFeedback(),
        encoder: SimulatedEncoderSource(),
      );
      await c.init();
      final today = DateTime.now();
      Future<void> points(String name, List<double> loads) async {
        final p = await c.addPlayer(name);
        if (name == 'Ana') anaId = p.id;
        for (final l in loads) {
          await c.addManualPoint(
            playerId: p.id,
            exerciseId: c.exerciseId,
            loadKg: l,
            velocity: 1.5 - 0.01 * l,
            date: today,
          );
        }
      }

      await points('Ana', [40, 60, 80, 100]);
      await points('Ben', [40, 100]); // poco fiable
      await points('Carla', [60]); // sin perfil
      for (final p in c.activePlayers) {
        ids[p.name] = p.id;
      }
    });

    for (final size in [const Size(393, 873), const Size(1280, 854)]) {
      final wide = size.width >= kCompareSideBySide;
      testWidgets('tabla y dispersión (${size.width.toInt()} px)', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: ProfileScreen(c: c),
          ),
        );
        await tester.tap(
          find.descendant(
            of: find.byKey(const Key('profile-mode')),
            matching: find.byIcon(Icons.groups),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Comparar'), findsOneWidget);
        expect(find.text('Todos · 3'), findsOneWidget);

        final list = find
            .descendant(
              of: find.byKey(const Key('compare-list')),
              matching: find.byType(Scrollable),
            )
            .first;
        Future<void> reveal(Finder f, {bool up = false}) async {
          await tester.scrollUntilVisible(f, up ? -200 : 200, scrollable: list);
          await tester.pumpAndSettle();
        }

        double dy(String name) => tester
            .getTopLeft(find.byKey(ValueKey('compare-row-${ids[name]}')))
            .dy;

        // Tabla: ordenada por 1RM; Carla (1 carga) al final con su motivo.
        expect(find.text('1.50'), findsOneWidget); // V0 de Ana
        expect(find.text('≈1.50'), findsOneWidget); // Ben: 2 cargas
        expect(find.text('1 carga'), findsOneWidget);
        expect(dy('Carla'), greaterThan(dy('Ana')));
        expect(dy('Carla'), greaterThan(dy('Ben')));

        // Ordenar por V0 en los dos sentidos: Carla sigue al final.
        for (var i = 0; i < 2; i++) {
          await tester.tap(find.byKey(const ValueKey('compare-col-v0')));
          await tester.pumpAndSettle();
          expect(dy('Carla'), greaterThan(dy('Ana')));
        }

        // Dispersión.
        if (!wide) {
          await tester.tap(find.text('Dispersión'));
          await tester.pumpAndSettle();
        }
        await reveal(find.byKey(const Key('compare-missing')));
        expect(
          tester.widget<Text>(find.byKey(const Key('compare-missing'))).data,
          'Fuera del gráfico: Carla (1 carga)',
        );
        // 1RM frente a V0: cuadrantes con nombre.
        expect(find.text('Fuerte y rápido'), findsOneWidget);
        expect(find.text('A desarrollar'), findsOneWidget);
        await reveal(find.byKey(const Key('compare-quadrants')), up: true);
        await tester.tap(find.byKey(const Key('compare-quadrants')));
        await tester.pumpAndSettle();
        expect(find.text('Fuerte y rápido'), findsNothing);

        // Intercambiar ejes.
        await tester.tap(find.byKey(const Key('compare-swap')));
        await tester.pumpAndSettle();
        expect(find.text('X · V0'), findsOneWidget);
        expect(find.text('Y · 1RM'), findsOneWidget);

        // Elegir a nadie: aviso.
        await reveal(find.byKey(const Key('compare-players')), up: true);
        await tester.tap(find.byKey(const Key('compare-players')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Ninguno'));
        await tester.pumpAndSettle();
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
        expect(find.text('Elige al menos un deportista.'), findsOneWidget);
        expect(find.text('Elegidos · 0'), findsOneWidget);

        // Volver a todos y abrir el perfil de Ana desde la tabla.
        await tester.tap(find.byKey(const Key('compare-group-all')));
        await tester.pumpAndSettle();
        if (!wide) {
          await tester.tap(find.text('Tabla'));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.byKey(ValueKey('compare-row-$anaId')));
        await tester.pumpAndSettle();
        if (wide) {
          // En ancho, la fila resalta su punto y abre la ficha.
          expect(find.byKey(const Key('compare-focus')), findsOneWidget);
          await tester.tap(find.byKey(const Key('compare-open-profile')));
          await tester.pumpAndSettle();
        }
        expect(find.text('Perfil'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.byKey(ValueKey('player-$anaId')),
          -200,
          scrollable: find.descendant(
            of: find.byKey(const Key('player-carousel')),
            matching: find.byType(Scrollable),
          ),
        );
        expect(
          tester.widget<Pill>(find.byKey(ValueKey('player-$anaId'))).selected,
          isTrue,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  test('nombre de los cuadrantes fuerza-velocidad', () {
    const f = CompareMetric.oneRm, v = CompareMetric.v0;
    expect(quadrantName(f, v, true, true), 'Fuerte y rápido');
    expect(quadrantName(f, v, false, true), 'Rápido, poca fuerza');
    expect(quadrantName(v, f, false, true), 'Fuerte, lento');
    expect(quadrantName(f, v, false, false), 'A desarrollar');
    expect(quadrantName(f, CompareMetric.pmax, true, true), isNull);
    expect(CompareMetric.rom.higherIsBetter, isFalse);
  });

  test('dispersión con muchos: solo se rotulan los extremos', () {
    final few = [for (var i = 0; i < 5; i++) (i.toDouble(), i.toDouble())];
    expect(labelledIndexes(few), {0, 1, 2, 3, 4});
    final many = [
      for (var i = 0; i < 20; i++) (i.toDouble(), (19 - i).toDouble()),
    ];
    // Extremos de x e y coinciden aquí: 0, 1, 18, 19.
    expect(labelledIndexes(many), {0, 1, 18, 19});
  });
}
