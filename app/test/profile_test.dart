import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:miencoder/app_controller.dart';
import 'package:miencoder/core/analysis.dart';
import 'package:miencoder/core/models.dart';
import 'package:miencoder/services/encoder.dart';
import 'package:miencoder/services/repository.dart';
import 'package:miencoder/ui/common.dart';
import 'package:miencoder/ui/player_picker.dart';
import 'package:miencoder/ui/profile_screen.dart';
import 'package:sembast/sembast_memory.dart' show newDatabaseFactoryMemory;

import 'controller_test.dart' show SilentFeedback;

Player pl(String id) => Player(id: id, name: id);

var _n = 0;
Rep rep(DateTime t, double load, double v) => Rep(
  id: 'r${_n++}',
  setId: 's$_n',
  time: t,
  romCm: 50,
  mv: v,
  mpv: v,
  loadKg: load,
  exerciseId: 'squat',
);

void main() {
  group('Carrusel de deportistas', () {
    final all = [for (var i = 0; i < 20; i++) pl('p$i')];
    List<String> ids(List<Player> ps) => [for (final p in ps) p.id];

    test('primero la sesión, luego los recientes, luego el resto', () {
      final r = carouselPlayers(
        all: all,
        session: ['p5', 'p6'],
        recent: ['p9', 'p5'],
        selected: 'p5',
        max: 5,
      );
      expect(ids(r), ['p5', 'p6', 'p9', 'p0', 'p1']);
    });

    test('el elegido siempre está, aunque no quepa', () {
      final r = carouselPlayers(
        all: all,
        session: const [],
        recent: const [],
        selected: 'p19',
        max: 4,
      );
      expect(ids(r), ['p19', 'p0', 'p1', 'p2']);
    });

    test('ignora ids que ya no existen', () {
      final r = carouselPlayers(
        all: all.take(3).toList(),
        session: ['borrado'],
        recent: const [],
        selected: 'p0',
      );
      expect(ids(r), ['p0', 'p1', 'p2']);
    });
  });

  test('periodo anterior', () {
    final now = DateTime(2026, 11, 17, 10);
    expect(previousPeriod('Todo', now: now), isNull);
    expect(previousPeriod('30 días', now: now), (
      now.subtract(const Duration(days: 60)),
      now.subtract(const Duration(days: 30)),
    ));
    expect(previousPeriod('Hoy', now: now), (
      DateTime(2026, 11, 16),
      DateTime(2026, 11, 17),
    ));
    expect(previousPeriodLabel('Hoy'), 'vs ayer');
  });

  test('buscar sin tildes ni mayúsculas', () {
    expect(searchKey('Gonzalo Fernández'), 'gonzalo fernandez');
    expect(searchKey('ÁNGEL Muñoz'), 'angel munoz');
  });

  group('Cuándo mostrar evolución y cambios', () {
    TrendPoint tp(int day, double rm) =>
        TrendPoint(DateTime(2026, 9, 7).add(Duration(days: day)), rm);

    test('evolución: 4 semanas o más, repartidas en 5 semanas o más', () {
      expect(trendIsMeaningful([tp(0, 100), tp(7, 101)]), isFalse);
      expect(
        trendIsMeaningful([tp(0, 100), tp(7, 101), tp(14, 102), tp(21, 103)]),
        isFalse, // solo 3 semanas de distancia
      );
      expect(
        trendIsMeaningful([tp(0, 100), tp(14, 101), tp(28, 102), tp(35, 103)]),
        isTrue,
      );
    });

    test('cambio: solo cuenta si supera el rango normal', () {
      expect(rmChangePercent(104, 100), closeTo(4, 1e-9));
      expect(rmChangeIsReal(103, 100, 4), isFalse);
      expect(rmChangeIsReal(96, 100, 4), isTrue);
      expect(rmChangeIsReal(110, 100, 8), isTrue);
    });
  });

  group('Evolución del 1RM', () {
    test('un punto por semana con 3 cargas o más', () {
      final w1 = DateTime(2026, 10, 5, 12); // lunes
      final w2 = DateTime(2026, 10, 12, 12);
      final reps = [
        for (final l in <double>[40, 60, 80]) rep(w1, l, 1.4 - 0.01 * l),
        for (final l in <double>[40, 60, 80]) rep(w2, l, 1.5 - 0.01 * l),
      ];
      final t = oneRmTrend(reps, VelocityMetric.mpv, 0.3);
      expect(t, hasLength(2));
      expect(t.first.oneRm, closeTo(110, 1e-9));
      // La segunda semana junta los datos de las dos (ventana de 90 días).
      expect(t.last.oneRm, greaterThan(t.first.oneRm));
      expect(t.first.end, DateTime(2026, 10, 12));
    });

    test('semanas sin perfil suficiente no salen', () {
      final w = DateTime(2026, 10, 5, 12);
      final reps = [rep(w, 40, 1.1), rep(w, 80, 0.7)];
      expect(oneRmTrend(reps, VelocityMetric.mpv, 0.3), isEmpty);
    });
  });

  group('Pantalla de perfil', () {
    late AppController c;
    late String anaId, gonzaloId;

    setUp(() async {
      await initializeDateFormatting('es');
      final db = await newDatabaseFactoryMemory().openDatabase('p.db');
      c = AppController(
        repo: Repository(db),
        feedback: SilentFeedback(),
        encoder: SimulatedEncoderSource(),
      );
      await c.init();
      final now = DateTime.now();
      Future<String> add(String name, {double v0 = 1.5, DateTime? at}) async {
        final p = await c.addPlayer(name);
        for (final l in <double>[40, 60, 80, 100]) {
          await c.addManualPoint(
            playerId: p.id,
            exerciseId: c.exerciseId,
            loadKg: l,
            velocity: v0 - 0.01 * l,
            date: at ?? now,
          );
        }
        return p.id;
      }

      anaId = await add('Ana');
      // Ana, 40 días antes, 10 kg menos de 1RM: periodo anterior.
      for (final l in <double>[40, 60, 80, 100]) {
        await c.addManualPoint(
          playerId: anaId,
          exerciseId: c.exerciseId,
          loadKg: l,
          velocity: 1.4 - 0.01 * l,
          date: now.subtract(const Duration(days: 40)),
        );
      }
      for (var i = 1; i < 20; i++) {
        await add('Jugador ${i.toString().padLeft(2, '0')}');
      }
      gonzaloId = await add('Gonzalo Fernández');
    });

    Future<void> open(WidgetTester tester, Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: ProfileScreen(c: c),
        ),
      );
      await tester.pumpAndSettle();
    }

    final carousel = find.descendant(
      of: find.byKey(const Key('player-carousel')),
      matching: find.byType(Scrollable),
    );

    final list = find
        .descendant(
          of: find.byKey(const Key('profile-list')),
          matching: find.byType(Scrollable),
        )
        .first;

    /// La pastilla de [id] está elegida (vuelve al principio del carrusel).
    Future<bool> selected(WidgetTester tester, String id) async {
      await tester.scrollUntilVisible(
        find.byKey(ValueKey('player-$id')),
        -200,
        scrollable: carousel,
      );
      return tester.widget<Pill>(find.byKey(ValueKey('player-$id'))).selected;
    }

    /// Lleva [key] del carrusel a la vista.
    Future<void> reveal(WidgetTester tester, Key key) async {
      await tester.scrollUntilVisible(
        find.byKey(key),
        200,
        scrollable: carousel,
      );
      await tester.ensureVisible(find.byKey(key));
      await tester.pumpAndSettle();
    }

    for (final size in [const Size(393, 873), const Size(1280, 854)]) {
      testWidgets('cifras, carrusel y buscador (${size.width.toInt()} px)', (
        tester,
      ) async {
        await open(tester, size);
        final mvt = c.exerciseById(c.exerciseId).mvt;
        final rm = (1.5 - mvt) / 0.01;

        // Cifra principal y cambio respecto al periodo anterior.
        expect(
          tester.widget<Text>(find.byKey(const Key('hero-1rm'))).data,
          kg(rm.roundToDouble()),
        );
        expect(find.text('+10 kg vs los 30 días anteriores'), findsOneWidget);
        // Solo 2 semanas con datos: sin evolución.
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is Tooltip && (w.message ?? '').startsWith('1RM por semana'),
          ),
          findsNothing,
        );
        expect(find.text('Periodo anterior'), findsOneWidget);

        // Carrusel corto: 21 deportistas, como mucho 8 pastillas.
        final pills = find.byWidgetPredicate(
          (w) =>
              w is Pill &&
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('player-p') ==
                  false &&
              (w.key! as ValueKey<String>).value.startsWith('player-'),
        );
        expect(pills.evaluate().length, lessThanOrEqualTo(8));
        await reveal(tester, const Key('player-all'));
        expect(find.text('Todos (21)'), findsOneWidget);

        // Buscar a Gonzalo sin tilde.
        await tester.tap(find.byKey(const Key('player-all')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('player-search')),
          'fernan',
        );
        await tester.pumpAndSettle();
        expect(find.text('Gonzalo Fernández'), findsOneWidget);
        expect(find.text('Jugador 01'), findsNothing);
        await tester.tap(find.text('Gonzalo Fernández'));
        await tester.pumpAndSettle();
        expect(await selected(tester, gonzaloId), isTrue);
        // Sin datos del periodo anterior: no hay comparación.
        expect(find.byKey(const Key('hero-delta')), findsNothing);

        // Deslizar pasa al siguiente en orden alfabético.
        await tester.fling(
          find.byKey(const Key('profile-hero')),
          const Offset(-300, 0),
          1000,
        );
        await tester.pumpAndSettle();
        final order = [for (final p in c.activePlayers) p.id];
        final next = order[(order.indexOf(gonzaloId) + 1) % order.length];
        expect(await selected(tester, next), isTrue);

        // Lista de cargas plegada; se despliega.
        expect(find.textContaining('40 kg →'), findsNothing);
        await tester.scrollUntilVisible(
          find.byKey(const Key('points-tile')),
          200,
          scrollable: list,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('points-tile')));
        await tester.pumpAndSettle();
        expect(find.textContaining('40 kg →'), findsOneWidget);

        // Comparar (barra superior) y volver.
        Finder mode(IconData i) => find.descendant(
          of: find.byKey(const Key('profile-mode')),
          matching: find.byIcon(i),
        );
        await tester.tap(mode(Icons.groups));
        await tester.pumpAndSettle();
        expect(find.text('Comparar'), findsOneWidget);
        await tester.tap(mode(Icons.person));
        await tester.pumpAndSettle();
        expect(find.text('Perfil'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
