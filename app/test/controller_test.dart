import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:miencoder/app_controller.dart';
import 'package:miencoder/core/analysis.dart';
import 'package:miencoder/core/frame_parser.dart';
import 'package:miencoder/services/encoder.dart';
import 'package:miencoder/services/feedback.dart';
import 'package:miencoder/services/repository.dart';

class SilentFeedback extends FeedbackService {
  final levels = <FatigueLevel>[];
  @override
  Future<void> init() async {}
  @override
  Future<void> onRep({
    required FatigueLevel level,
    required bool beepEachRep,
    required bool speak,
    required double velocity,
  }) async => levels.add(level);
  @override
  void dispose() {}
}

EncoderFrame f(double mpv) => parseFrameText(
  '50.00 ${(mpv * 0.95).toStringAsFixed(2)} ${mpv.toStringAsFixed(2)} ${(mpv * 1.6).toStringAsFixed(2)}',
)!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppController c;
  late SilentFeedback fb;
  late DateTime now;
  late Repository repo;

  Future<AppController> build() async {
    final ctrl = AppController(
      repo: repo,
      feedback: fb,
      encoder: SimulatedEncoderSource(),
      clock: () => now,
    );
    await ctrl.init();
    return ctrl;
  }

  setUp(() async {
    final db = await newDatabaseFactoryMemory().openDatabase('t.db');
    repo = Repository(db);
    fb = SilentFeedback();
    now = DateTime(2026, 11, 11, 10);
    c = await build();
  });

  void tick(int s) => now = now.add(Duration(seconds: s));
  String? playerOfRep(int i) => c.setById(c.reps[i].setId)!.playerId;

  group('Series sin corte por tiempo', () {
    test('cluster: pausas de 1 minuto siguen en la misma serie', () {
      for (var block = 0; block < 3; block++) {
        c.onFrame(f(1.0 - block * 0.05));
        tick(3);
        c.onFrame(f(0.98 - block * 0.05));
        tick(60);
      }
      expect(c.recentSets().length, 1);
      expect(c.currentSetReps.length, 6);
    });

    test('la fatiga del cluster se acumula entre bloques', () {
      c.onFrame(f(1.00));
      tick(60);
      c.onFrame(f(0.92));
      tick(60);
      c.onFrame(f(0.78)); // −22 % respecto a la primera, aunque hubo pausas
      expect(fb.levels.last, FatigueLevel.stop);
    });

    test('cambiar la carga abre serie nueva al instante', () {
      c.onFrame(f(1.0));
      c.setLoad(60);
      c.onFrame(f(0.8));
      expect(c.recentSets().length, 2);
      expect(c.reps.last.loadKg, 60);
    });

    test('cambiar el ejercicio abre serie nueva', () {
      c.onFrame(f(1.0));
      c.setExercise('bench');
      c.onFrame(f(0.8));
      expect(c.recentSets().length, 2);
    });

    test('"Nueva serie" corta aunque nada haya cambiado', () {
      c.onFrame(f(1.0));
      c.forceNewSet();
      c.onFrame(f(1.0));
      expect(c.recentSets().length, 2);
    });
  });

  group('Deportista activo (a priori)', () {
    test('por defecto Ninguno: las series quedan sin asignar', () {
      c.onFrame(f(1.0));
      expect(c.activePlayerId, isNull);
      expect(playerOfRep(0), isNull);
    });

    test('las reps van al deportista activo hasta que cambie', () async {
      final ana = await c.addPlayer('Ana');
      final ben = await c.addPlayer('Ben');
      c.setActive(ana.id);
      c.onFrame(f(1.0));
      c.onFrame(f(0.9));
      c.setActive(ben.id);
      c.onFrame(f(0.8));
      c.setActive(null);
      c.onFrame(f(0.7));
      expect([0, 1, 2, 3].map(playerOfRep).toList(), [
        ana.id,
        ana.id,
        ben.id,
        null,
      ]);
    });

    test('rotación: cada deportista retoma su serie abierta', () async {
      final ana = await c.addPlayer('Ana');
      final ben = await c.addPlayer('Ben');
      for (var round = 0; round < 3; round++) {
        c.setActive(ana.id);
        c.onFrame(f(1.0 - round * 0.1));
        tick(20);
        c.setActive(ben.id);
        c.onFrame(f(0.9 - round * 0.1));
        tick(20);
      }
      final s = c.recentSets();
      expect(s.length, 2);
      for (final set in s) {
        expect(c.repsOfSet(set.id).length, 3);
      }
      // Fatiga de Ben con sus propias reps: 0.9 → 0.7 = −22 %
      expect(c.lastLive!.lossPercent, closeTo(22.2, 0.1));
      expect(c.lastLive!.indexInSet, 3);
    });

    test('la fatiga no compara a un deportista con otro', () async {
      final ana = await c.addPlayer('Ana');
      final ben = await c.addPlayer('Ben');
      c.setActive(ana.id);
      c.onFrame(f(1.30));
      c.setActive(ben.id);
      c.onFrame(f(0.60)); // primera rep de Ben: 0 % de pérdida
      expect(c.lastLive!.lossPercent, 0);
      expect(fb.levels.last, FatigueLevel.fresh);
    });

    test('cada deportista recuerda su carga', () async {
      final ana = await c.addPlayer('Ana');
      final ben = await c.addPlayer('Ben');
      c.setActive(ana.id);
      c.setLoad(60);
      c.setActive(ben.id);
      c.setLoad(80);
      c.setActive(ana.id);
      expect(c.loadKg, 60);
      c.setActive(ben.id);
      expect(c.loadKg, 80);
    });

    test(
      'si un deportista cambia de carga, su serie anterior se cierra',
      () async {
        final ana = await c.addPlayer('Ana');
        c.setActive(ana.id);
        c.setLoad(60);
        c.onFrame(f(1.0));
        c.setLoad(70);
        c.onFrame(f(0.8));
        c.setLoad(60);
        c.onFrame(f(1.0));
        expect(c.recentSets().length, 3);
      },
    );
  });

  group('Corrección a posteriori', () {
    test(
      '"se me olvidó cambiar": pasar las reps anteriores al nuevo',
      () async {
        final ana = await c.addPlayer('Ana');
        final ben = await c.addPlayer('Ben');
        c.setActive(ana.id);
        c.onFrame(f(1.0)); // de Ana
        c.forceNewSet();
        c.setActive(null);
        c.setActive(ana.id); // reinicia la racha
        c.onFrame(f(0.9)); // en realidad Ben
        c.onFrame(f(0.85)); // en realidad Ben
        final pending = c.setActive(ben.id)!;
        expect(pending.repIds.length, 2);
        await c.applyPending(pending);
        expect(playerOfRep(0), ana.id);
        expect(playerOfRep(1), ben.id);
        expect(playerOfRep(2), ben.id);
        // Y las siguientes de Ben se suman a esa misma serie
        c.onFrame(f(0.8));
        expect(c.reps[3].setId, c.reps[1].setId);
        expect(c.lastLive!.indexInSet, 3);
      },
    );

    test('no se ofrece nada si no hubo reps desde el último cambio', () async {
      final ana = await c.addPlayer('Ana');
      expect(c.setActive(ana.id), isNull);
    });

    test('pasar a Ninguno desasigna', () async {
      final ana = await c.addPlayer('Ana');
      c.setActive(ana.id);
      c.onFrame(f(1.0));
      await c.applyPending(c.setActive(null)!);
      expect(playerOfRep(0), isNull);
    });

    test('mover una rep suelta desde el historial', () async {
      final ana = await c.addPlayer('Ana');
      final ben = await c.addPlayer('Ben');
      c.setActive(ana.id);
      c.onFrame(f(1.0));
      c.onFrame(f(0.95));
      c.onFrame(f(0.90));
      await c.moveRep(c.reps[1].id, ben.id);
      expect([0, 1, 2].map(playerOfRep).toList(), [ana.id, ben.id, ana.id]);
      expect(c.recentSets().length, 2);
    });

    test('mover la única rep de una serie elimina la serie vacía', () async {
      final ben = await c.addPlayer('Ben');
      c.onFrame(f(1.0));
      await c.moveRep(c.reps[0].id, ben.id);
      expect(c.sets.length, 1);
      expect(c.sets.single.playerId, ben.id);
    });

    test('reasignar una serie entera', () async {
      final ana = await c.addPlayer('Ana');
      c.onFrame(f(1.0));
      c.onFrame(f(0.9));
      c.reassign(c.recentSets().single.id, ana.id);
      expect([0, 1].map(playerOfRep).toList(), [ana.id, ana.id]);
    });
  });

  test('deshacer borra la última rep y la serie si queda vacía', () async {
    c.onFrame(f(1.0));
    await c.undoLastRep();
    expect(c.reps, isEmpty);
    expect(c.recentSets(), isEmpty);
  });

  test('todo persiste y se recupera al reabrir', () async {
    final ana = await c.addPlayer('Ana');
    c.setActive(ana.id);
    c.setLoad(72.5);
    c.onFrame(f(0.8));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final c2 = await build();
    expect(c2.reps.length, 1);
    expect(c2.sets.single.playerId, ana.id);
    expect(c2.loadKg, 72.5);
    expect(c2.activePlayerId, ana.id);
    expect(c2.players.single.name, 'Ana');
  });

  test('perfil: junta series de días distintos y respeta el periodo', () async {
    final ana = await c.addPlayer('Ana');
    for (final (load, v, daysAgo) in [
      (40.0, 1.10, 3),
      (60.0, 0.90, 10),
      (80.0, 0.70, 20),
      (100.0, 0.30, 60),
    ]) {
      await c.addManualPoint(
        playerId: ana.id,
        exerciseId: 'squat',
        loadKg: load,
        velocity: v,
        date: now.subtract(Duration(days: daysAgo)),
      );
    }
    final last30 = c.repsFor(
      playerId: ana.id,
      exerciseId: 'squat',
      since: now.subtract(const Duration(days: 30)),
    );
    expect(last30.length, 3);
    final p = fitLoadVelocity(bestRepPerLoad(last30, c.settings.metric))!;
    expect(p.estimated1Rm(0.30), closeTo(120, 1e-6));
    expect(c.repsFor(playerId: ana.id, exerciseId: 'bench'), isEmpty);
  });

  test('las reps sin asignar no entran en ningún perfil', () async {
    final ana = await c.addPlayer('Ana');
    c.onFrame(f(1.0));
    expect(c.repsFor(playerId: ana.id, exerciseId: c.exerciseId), isEmpty);
  });

  test('CSV incluye cabecera, jugador y marca de VMAX truncada', () async {
    final ana = await c.addPlayer('Ana');
    c.setActive(ana.id);
    c.onFrame(parseFrameText('142.88 1.12 1.28 2.0', byteLength: 20)!);
    final csv = c.exportCsv().trim().split('\n');
    expect(csv.length, 2);
    expect(csv[1], contains('Ana'));
    expect(csv[1], contains(';si;'));
  });
}
