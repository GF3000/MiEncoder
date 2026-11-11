import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:miencoder/app_controller.dart';
import 'package:miencoder/core/frame_parser.dart';
import 'package:miencoder/services/encoder.dart';
import 'package:miencoder/services/repository.dart';
import 'package:miencoder/core/analysis.dart';
import 'package:miencoder/ui/common.dart';
import 'package:miencoder/ui/history_screen.dart';
import 'package:miencoder/ui/player_detail_screen.dart';

import 'controller_test.dart' show SilentFeedback;

EncoderFrame f(double mpv) => parseFrameText(
  '50.00 ${(mpv * 0.95).toStringAsFixed(2)} ${mpv.toStringAsFixed(2)} ${(mpv * 1.6).toStringAsFixed(2)}',
)!;

void main() {
  late AppController c;
  late Repository repo;

  Future<AppController> build() async {
    final ctrl = AppController(
      repo: repo,
      feedback: SilentFeedback(),
      encoder: SimulatedEncoderSource(),
    );
    await ctrl.init();
    return ctrl;
  }

  setUp(() async {
    await initializeDateFormatting('es');
    repo = Repository(await newDatabaseFactoryMemory().openDatabase('p.db'));
    c = await build();
  });

  group('Borrar deportista', () {
    test('conservando sus series: pasan a Ninguno', () async {
      final ana = await c.addPlayer('Ana');
      c.setActive(ana.id);
      c.onFrame(f(1.0));
      c.onFrame(f(0.9));
      await c.deletePlayer(ana.id, deleteData: false);
      expect(c.players, isEmpty);
      expect(c.reps.length, 2);
      expect(c.sets.single.playerId, isNull);
      expect(c.activePlayerId, isNull);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final c2 = await build();
      expect(c2.players, isEmpty);
      expect(c2.reps.length, 2);
      expect(c2.sets.single.playerId, isNull);
    });

    test(
      'borrando sus series: desaparecen sus reps, no las de otros',
      () async {
        final ana = await c.addPlayer('Ana');
        final ben = await c.addPlayer('Ben');
        c.setActive(ana.id);
        c.onFrame(f(1.0));
        c.setActive(ben.id);
        c.onFrame(f(0.9));
        await c.deletePlayer(ana.id, deleteData: true);
        expect(c.reps.length, 1);
        expect(c.sets.single.playerId, ben.id);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect((await build()).reps.length, 1);
      },
    );

    test('tras borrar, las nuevas reps no van al borrado', () async {
      final ana = await c.addPlayer('Ana');
      c.setActive(ana.id);
      await c.deletePlayer(ana.id, deleteData: false);
      c.onFrame(f(1.0));
      expect(c.sets.single.playerId, isNull);
    });
  });

  group('Borrar ejercicio', () {
    test('borra sus series y cambia el ejercicio actual', () async {
      final e = await c.addExercise('Zancada', 0.4);
      c.setExercise(e.id);
      c.onFrame(f(1.0));
      c.setExercise('squat');
      c.onFrame(f(0.9));
      c.setExercise(e.id);
      expect(await c.deleteExercise(e.id), isTrue);
      expect(c.exercises.any((x) => x.id == e.id), isFalse);
      expect(c.reps.length, 1);
      expect(c.exerciseId, isNot(e.id));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final c2 = await build();
      expect(c2.exercises.any((x) => x.id == e.id), isFalse);
      expect(c2.reps.length, 1);
    });

    test('no se puede borrar el último ejercicio', () async {
      for (final e in List.of(c.exercises).skip(1)) {
        await c.deleteExercise(e.id);
      }
      expect(c.exercises.length, 1);
      expect(await c.deleteExercise(c.exercises.single.id), isFalse);
      expect(c.exercises.length, 1);
    });
  });

  group('Periodo', () {
    test('"Hoy" empieza a las 00:00 del día', () {
      final now = DateTime(2026, 11, 11, 16, 30);
      expect(sinceForPeriod('Hoy', now: now), DateTime(2026, 11, 11));
      expect(sinceForPeriod('7 días', now: now), DateTime(2026, 11, 4, 16, 30));
      expect(sinceForPeriod('Todo', now: now), isNull);
    });
  });

  group('Avisos de fatiga apagados', () {
    test('nivel off en todas las reps, aunque la pérdida sea enorme', () async {
      final fb = c.feedback as SilentFeedback;
      await c.updateSettings(c.settings.copyWith(fatigueEnabled: false));
      c.onFrame(f(1.0));
      c.onFrame(f(0.5)); // −50 %
      expect(c.lastLive!.level, FatigueLevel.off);
      expect(fb.levels, [FatigueLevel.off, FatigueLevel.off]);
      expect(
        c.lastLive!.lossPercent,
        closeTo(50, 0.01),
      ); // el dato se sigue calculando
    });

    test('al volver a activarlos, vuelven los avisos', () async {
      final fb = c.feedback as SilentFeedback;
      await c.updateSettings(c.settings.copyWith(fatigueEnabled: false));
      await c.updateSettings(c.settings.copyWith(fatigueEnabled: true));
      c.onFrame(f(1.0));
      c.onFrame(f(0.5));
      expect(fb.levels.last, FatigueLevel.stop);
    });

    test('el ajuste persiste', () async {
      await c.updateSettings(c.settings.copyWith(fatigueEnabled: false));
      expect((await build()).settings.fatigueEnabled, isFalse);
    });
  });

  group('Filtro del historial', () {
    test('Todos / Sin asignar / un deportista', () async {
      final ana = await c.addPlayer('Ana');
      c.onFrame(f(1.0)); // sin asignar
      c.setActive(ana.id);
      c.onFrame(f(0.9));
      final sets = c.recentSets();
      int count(String flt) =>
          sets.where((s) => setMatchesPlayerFilter(s, flt)).length;
      expect(count(kFilterAll), 2);
      expect(count(kFilterNone), 1);
      expect(count(ana.id), 1);
      expect(count('otro'), 0);
    });
  });

  group('Ficha del deportista', () {
    test('1RM solo donde hay al menos 2 cargas', () async {
      final ana = await c.addPlayer('Ana');
      final now = DateTime.now();
      for (final (l, v) in [(40.0, 1.10), (60.0, 0.90), (80.0, 0.70)]) {
        await c.addManualPoint(
          playerId: ana.id,
          exerciseId: 'squat',
          loadKg: l,
          velocity: v,
          date: now,
        );
      }
      await c.addManualPoint(
        playerId: ana.id,
        exerciseId: 'bench',
        loadKg: 40,
        velocity: 0.8,
        date: now,
      );
      final est = estimatesFor(c, ana.id);
      final squat = est.firstWhere((e) => e.exercise.id == 'squat');
      final bench = est.firstWhere((e) => e.exercise.id == 'bench');
      expect(squat.profile!.estimated1Rm(0.30), closeTo(120, 1e-6));
      expect(bench.profile, isNull);
      expect(bench.loads, 1);
      expect(est.any((e) => e.exercise.id == 'deadlift'), isFalse);
    });

    test('el filtro de periodo excluye datos antiguos', () async {
      final ana = await c.addPlayer('Ana');
      final now = DateTime.now();
      await c.addManualPoint(
        playerId: ana.id,
        exerciseId: 'squat',
        loadKg: 40,
        velocity: 1.1,
        date: now.subtract(const Duration(days: 40)),
      );
      await c.addManualPoint(
        playerId: ana.id,
        exerciseId: 'squat',
        loadKg: 80,
        velocity: 0.7,
        date: now,
      );
      expect(estimatesFor(c, ana.id).single.loads, 2);
      expect(
        estimatesFor(c, ana.id, since: sinceForPeriod('30 días')).single.loads,
        1,
      );
    });

    testWidgets('la ficha se pinta con datos y sin desbordes', (tester) async {
      tester.view.physicalSize = const Size(393, 873);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      late final String anaId;
      await tester.runAsync(() async {
        anaId = (await c.addPlayer('Ana')).id;
        c.setActive(anaId);
        c.onFrame(f(1.0));
        c.onFrame(f(0.9));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: PlayerDetailScreen(c: c, playerId: anaId),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Ana'), findsWidgets);
      expect(find.text('1RM estimado'), findsOneWidget);
      expect(find.text('Series medidas'), findsOneWidget);
    });
  });
}
