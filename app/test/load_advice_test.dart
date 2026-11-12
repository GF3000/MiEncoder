import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:miencoder/app_controller.dart';
import 'package:miencoder/core/analysis.dart';
import 'package:miencoder/core/frame_parser.dart';
import 'package:miencoder/core/models.dart';
import 'package:miencoder/services/encoder.dart';
import 'package:miencoder/services/repository.dart';

import 'controller_test.dart' show SilentFeedback;

/// Perfil de ejemplo: 1RM 120 kg a 0,30 m/s.
double v(double load) => 1.40 - 1.10 / 120 * load;

EncoderFrame f(double mpv) => parseFrameText(
  '50.00 ${(mpv * 0.95).toStringAsFixed(2)} ${mpv.toStringAsFixed(2)} ${(mpv * 1.6).toStringAsFixed(2)}',
)!;

void main() {
  const t = RmTarget(75, 80);

  group('RmTarget', () {
    test('JSON de ida y vuelta, y JSON inválido = null', () {
      expect(RmTarget.fromJson(t.toJson()), t);
      expect(RmTarget.fromJson('x'), isNull);
      expect(RmTarget.fromJson([75]), isNull);
    });

    test('la sesión guarda y quita objetivos por ejercicio', () {
      final s = TrainingSession(
        id: 's',
        name: 'S',
        start: DateTime(2026),
      ).withRmTarget('squat', t).withRmTarget('bench', const RmTarget(60, 70));
      final back = TrainingSession.fromJson(s.toJson());
      expect(back.rmTargets, {'squat': t, 'bench': const RmTarget(60, 70)});
      expect(back.withRmTarget('squat', null).rmTargets.keys, ['bench']);
      // Sesiones antiguas sin el campo.
      expect(
        TrainingSession.fromJson({
          'id': 'x',
          'name': 'X',
          'start': 0,
        }).rmTargets,
        isEmpty,
      );
    });
  });

  group('loadAdvice', () {
    LoadAdvice a(double load, double rm, {double step = 2.5}) =>
        loadAdvice(load: load, dayRm: rm, target: t, step: step)!;

    test('dentro del rango: mantener', () {
      final r = a(95, 122); // 77,9 %
      expect(r.kind, LoadAdviceKind.keep);
      expect(r.targetLoad, 95);
      expect(r.percent, closeTo(77.9, 0.1));
    });

    test('ligero: sube hacia el centro del rango, redondeado al paso', () {
      final r = a(100, 140); // 71 % → 77,5 % = 108,5 → 107,5
      expect(r.kind, LoadAdviceKind.up);
      expect(r.targetLoad, 107.5);
      expect(r.delta, 7.5);
    });

    test('pesado: baja', () {
      final r = a(100, 115); // 87 % → 77,5 % = 89,1 → tope −10 % = 90
      expect(r.kind, LoadAdviceKind.down);
      expect(r.targetLoad, 90);
    });

    test('no cambia más de un 10 % de golpe', () {
      final r = a(60, 120); // 50 % → ideal 93 kg, tope 66
      expect(r.targetLoad, 65);
    });

    test('fuera del rango siempre cambia al menos un paso', () {
      // 74,6 %: el centro (77,5 %) redondea a la misma carga.
      final r = a(50, 67, step: 5);
      expect(r.kind, LoadAdviceKind.up);
      expect(r.targetLoad, 55);
    });

    test('sin datos válidos no hay consejo', () {
      expect(loadAdvice(load: 0, dayRm: 100, target: t, step: 2.5), isNull);
      expect(
        loadAdvice(load: 80, dayRm: double.nan, target: t, step: 2.5),
        isNull,
      );
    });
  });

  group('zona de velocidad', () {
    const metric = VelocityMetric.mpv;
    var n = 0;
    Rep rep(String setId, double load, double mpv) => Rep(
      id: 'r${n++}',
      setId: setId,
      time: DateTime(2026, 11, 1),
      romCm: 50,
      mv: mpv,
      mpv: mpv,
      loadKg: load,
      exerciseId: 'squat',
    );
    List<Rep> set(String id, double load) => [
      rep(id, load, v(load)),
      rep(id, load, v(load) - 0.01),
      rep(id, load, v(load) - 0.04),
    ];
    final ref = dayRmReference(
      [...set('a', 60), ...set('b', 80), ...set('c', 100)],
      metric,
      0.30,
    )!;

    test('es coherente con el consejo: en los bordes da el % del rango', () {
      final (slow, fast) = ref.velocityZone(90, t)!;
      expect(slow, lessThan(fast));
      expect(90 / ref.e1RmFor(90, slow) * 100, closeTo(80, 1e-6));
      expect(90 / ref.e1RmFor(90, fast) * 100, closeTo(75, 1e-6));
    });

    test('con cargas muy ligeras no hay zona', () {
      expect(ref.velocityZone(30, t), isNull);
    });
  });

  group('controlador', () {
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
      repo = Repository(await newDatabaseFactoryMemory().openDatabase('a.db'));
      now = DateTime(2026, 11, 10, 10);
      c = await build();
    });

    late String lastSetId;

    Future<void> doSet(double load, double mpv) async {
      c.setLoad(load);
      for (final d in [0.0, -0.01, -0.03]) {
        now = now.add(const Duration(seconds: 3));
        c.onFrame(f(mpv + d));
      }
      lastSetId = c.lastLive!.rep.setId;
      c.forceNewSet(); // misma carga = serie nueva
      now = now.add(const Duration(minutes: 3));
    }

    /// Perfil de Ana el día anterior (1RM ≈ 120 kg) y hoy con objetivo.
    Future<void> anaWithProfile(RmTarget target) async {
      final ana = await c.createAndAddToSession('Ana');
      c.setActive(ana.id);
      c.setExercise('squat');
      for (final load in [60.0, 80.0, 100.0]) {
        await doSet(load, v(load));
      }
      now = DateTime(2026, 11, 11, 10);
      await c.setRmTarget('squat', target);
    }

    test('el objetivo se guarda en la sesión activa', () async {
      await c.setRmTarget('squat', t);
      final again = await build();
      expect(again.activeSession!.rmTargets, {'squat': t});
      await c.setRmTarget('squat', null);
      expect(c.activeSession!.rmTargets, isEmpty);
    });

    test('tras una serie ligera recomienda subir', () async {
      final ana = await c.createAndAddToSession('Ana');
      c.setActive(ana.id);
      c.setExercise('squat');
      // Día anterior: perfil con 1RM ≈ 120 kg.
      for (final load in [60.0, 80.0, 100.0]) {
        await doSet(load, v(load));
      }
      now = DateTime(2026, 11, 11, 10);
      await c.setRmTarget('squat', t);
      // La serie del día anterior no tiene perfil previo: consejo genérico.
      expect(c.loadAdviceFor(lastSetId)!.generic, isTrue);

      await doSet(80, v(80)); // 67 % del 1RM del día
      final setId = lastSetId;
      final a = c.loadAdviceFor(setId)!;
      expect(a.generic, isFalse);
      expect(a.kind, LoadAdviceKind.up);
      expect(a.percent, closeTo(66.7, 1.5));
      expect(a.targetLoad, 87.5); // tope +10 %
      final (slow, fast) = c.velocityZoneFor(setId)!;
      expect(v(80), greaterThan(fast)); // demasiado rápido para el objetivo
      expect(slow, lessThan(fast));
    });

    test('sin asignar: consejo y zona con la relación genérica', () async {
      c.setActive(null);
      c.setExercise('squat'); // VMP a 1RM 0,30
      await c.setRmTarget('squat', t);
      // 0,90 m/s en sentadilla ≈ 62 % según la relación genérica.
      await doSet(100, 0.90);
      final setId = lastSetId;
      final a = c.loadAdviceFor(setId)!;
      expect(a.generic, isTrue);
      expect(a.kind, LoadAdviceKind.up);
      expect(a.percent, closeTo(genericPercentRm(0.895, 0.30), 0.5));
      final (slow, fast) = c.velocityZoneFor(setId)!;
      expect(genericPercentRm(slow, 0.30), closeTo(80, 1e-9));
      expect(genericPercentRm(fast, 0.30), closeTo(75, 1e-9));
    });

    test(
      'la pérdida máxima del ejercicio en la sesión manda sobre la global',
      () async {
        c.setExercise('squat');
        await c.setSessionTarget(['squat'], loss: 10.0);
        await doSet(100, 0.60);
        final setId = lastSetId;
        expect(c.lossThresholdForSet(setId), 10);
        // Última rep: 0,57 frente a 0,60 → 5 %; con 0,53 → 11,7 % ≥ 10 %.
        expect(c.levelFor(11.7, setId: setId), FatigueLevel.stop);
        await c.setSessionTarget(['squat'], loss: null);
        expect(c.lossThresholdForSet(setId), c.settings.velocityLossThreshold);
      },
    );

    test('aplicar a todos fija el objetivo en todos los ejercicios', () async {
      await c.setSessionTarget(
        [for (final e in c.exercises) e.id],
        rm: t,
        loss: 15.0,
      );
      final s = c.activeSession!;
      for (final e in c.exercises) {
        expect(s.rmTargets[e.id], t);
        expect(s.lossTargets[e.id], 15);
      }
      final back = TrainingSession.fromJson(s.toJson());
      expect(back.lossTargets, s.lossTargets);
    });

    test(
      'el 1RM del día queda fijado: la fatiga entre series no lo baja',
      () async {
        const tgt = RmTarget(75, 85);
        await anaWithProfile(tgt);
        await doSet(95, v(95)); // 1RM del día ≈ 120 → 79 %
        final a1 = c.loadAdviceFor(lastSetId)!;
        expect(a1.kind, LoadAdviceKind.keep);

        await doSet(95, v(95) - 0.10); // cansado: por sí sola, 1RM ≈ 109 → 87 %
        final tired = lastSetId;
        expect(
          c.dayRmFor(tired)!.e1Rm,
          lessThan(112),
        ); // la comparación sí baja
        final a2 = c.loadAdviceFor(tired)!;
        expect(a2.kind, LoadAdviceKind.keep); // ...pero no dice «Baja»
        expect(a2.percent, closeTo(a1.percent, 0.5));

        await doSet(95, v(95) + 0.08); // más rápida: el 1RM del día sube
        final a3 = c.loadAdviceFor(lastSetId)!;
        expect(a3.percent, lessThan(a1.percent));
        expect(a3.kind, LoadAdviceKind.up);
      },
    );

    test('genérico: también con el máximo de las series del día', () async {
      c.setActive(null);
      c.setExercise('squat');
      await c.setRmTarget('squat', const RmTarget(60, 70));
      await doSet(100, 0.90); // ≈ 62 %
      final first = c.loadAdviceFor(lastSetId)!;
      await doSet(100, 0.70); // cansado
      final second = c.loadAdviceFor(lastSetId)!;
      expect(second.generic, isTrue);
      expect(second.percent, closeTo(first.percent, 0.5));
    });

    test('interruptores: sin consejo y sin genérico', () async {
      c.setActive(null);
      c.setExercise('squat');
      await c.setRmTarget('squat', t);
      await doSet(100, 0.90);
      final setId = lastSetId;
      expect(c.loadAdviceFor(setId), isNotNull);

      await c.updateSettings(c.settings.copyWith(loadAdvice: false));
      expect(c.loadAdviceFor(setId), isNull);
      expect(c.velocityZoneFor(setId), isNotNull); // el objetivo sí se ve

      await c.updateSettings(
        c.settings.copyWith(loadAdvice: true, genericWithoutProfile: false),
      );
      expect(c.loadAdviceFor(setId), isNull);
      expect(c.velocityZoneFor(setId), isNull);
    });
  });

  group('Ajustes de análisis en vivo', () {
    test('activados por defecto y tolerantes a JSON antiguo', () {
      const d = Settings();
      expect(
        d.compareProfileRm && d.loadAdvice && d.genericWithoutProfile,
        isTrue,
      );
      final old = Settings.fromJson({'loss': 20});
      expect(
        old.compareProfileRm && old.loadAdvice && old.genericWithoutProfile,
        isTrue,
      );
      final off = Settings.fromJson(
        d
            .copyWith(
              compareProfileRm: false,
              loadAdvice: false,
              genericWithoutProfile: false,
            )
            .toJson(),
      );
      expect(
        off.compareProfileRm || off.loadAdvice || off.genericWithoutProfile,
        isFalse,
      );
    });
  });
}
