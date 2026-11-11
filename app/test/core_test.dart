import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:miencoder/core/analysis.dart';
import 'package:miencoder/core/frame_parser.dart';
import 'package:miencoder/core/models.dart';

List<int> hex(String s) =>
    s.split('-').map((h) => int.parse(h, radix: 16)).toList();

Rep rep(double load, double mpv, {DateTime? t, double? mv}) => Rep(
  id: 'r$load$mpv',
  setId: 's',
  time: t ?? DateTime(2026, 11, 1),
  romCm: 50,
  mv: mv ?? mpv,
  mpv: mpv,
  loadKg: load,
  exerciseId: 'squat',
);

void main() {
  group('Oráculo: tramas reales capturadas del AdrEncoder5.3C', () {
    // Bytes exactos de captura-nrf-2026-11-11.txt
    final captured = <String, List<double?>>{
      '36-31-2E-39-32-20-30-2E-34-38-20-30-2E-34-38-20-30-2E-37-37': [
        61.92,
        0.48,
        0.48,
        0.77,
      ],
      '36-33-2E-37-36-20-31-2E-32-38-20-31-2E-34-36-20-32-2E-33-32': [
        63.76,
        1.28,
        1.46,
        2.32,
      ],
      '32-37-2E-31-32-20-30-2E-33-37-20-30-2E-33-37-20-30-2E-36-32': [
        27.12,
        0.37,
        0.37,
        0.62,
      ],
      '35-39-2E-32-37-20-31-2E-32-30-20-31-2E-32-37-20-31-2E-39-31': [
        59.27,
        1.20,
        1.27,
        1.91,
      ],
    };

    captured.forEach((h, expected) {
      test('decodifica $h', () {
        final f = parseFrameBytes(hex(h))!;
        expect(f.romCm, expected[0]);
        expect(f.meanVelocity, expected[1]);
        expect(f.meanPropulsiveVelocity, expected[2]);
        expect(f.peakVelocity, expected[3]);
        expect(f.peakTruncated, isFalse);
      });
    });

    test('marca la VMAX truncada cuando ROM >= 100 cm (20 bytes)', () {
      final f = parseFrameBytes(
        hex('31-34-32-2E-38-38-20-31-2E-31-32-20-31-2E-32-38-20-32-2E-30'),
      )!;
      expect(f.romCm, 142.88);
      expect(f.meanPropulsiveVelocity, 1.28);
      expect(f.peakVelocity, 2.0);
      expect(f.peakTruncated, isTrue);
    });

    test('segunda trama truncada (MTU 255)', () {
      final f = parseFrameBytes(
        hex('31-35-37-2E-32-31-20-31-2E-31-39-20-31-2E-38-31-20-32-2E-38'),
      )!;
      expect(f.romCm, 157.21);
      expect(f.peakTruncated, isTrue);
    });

    test('acepta trama de 3 campos (sin VMAX)', () {
      final f = parseFrameText('45.10 0.80 0.85')!;
      expect(f.peakVelocity, isNull);
      expect(f.peakTruncated, isFalse);
    });

    test('usa solo la primera repetición si llegan varias con coma', () {
      final f = parseFrameText('45.10 0.80 0.85 1.20,40.00 0.70 0.75 1.10')!;
      expect(f.romCm, 45.10);
    });
  });

  group('Fallos plantados: el parser debe rechazarlos', () {
    for (final bad in [
      '45.10 0.80', // 2 campos
      '45.10 0.80 0.85 1.20 9.99', // 5 campos
      '45.10 abc 0.85 1.20', // texto no numérico
      '45,10 0.80 0.85', // coma decimal → primer bloque de 1 campo
      '-5.00 0.80 0.85 1.20', // negativo
      '45.10 0.00 0.85 1.20', // velocidad 0
      '45.10 25.0 0.85 1.20', // velocidad imposible
      '',
    ]) {
      test('rechaza "$bad"', () => expect(parseFrameText(bad), isNull));
    }

    test('rechaza bytes no ASCII', () {
      expect(parseFrameBytes([0xFF, 0xFE, 0x20]), isNull);
    });

    test('una trama corta con 1 decimal en VMAX NO se marca truncada', () {
      // Sin llegar a 20 bytes no hay truncado, aunque tenga 1 decimal.
      final f = parseFrameBytes(utf8.encode('45.10 0.80 0.85 1.2'))!;
      expect(f.peakTruncated, isFalse);
    });
  });

  group('Serie abierta', () {
    test('misma carga y ejercicio → misma serie', () {
      expect(
        sameOpenSet(
          openLoad: 50,
          openExerciseId: 'squat',
          load: 50,
          exerciseId: 'squat',
        ),
        isTrue,
      );
    });
    test('otra carga → serie nueva', () {
      expect(
        sameOpenSet(
          openLoad: 50,
          openExerciseId: 'squat',
          load: 52.5,
          exerciseId: 'squat',
        ),
        isFalse,
      );
    });
    test('otro ejercicio → serie nueva', () {
      expect(
        sameOpenSet(
          openLoad: 50,
          openExerciseId: 'squat',
          load: 50,
          exerciseId: 'bench',
        ),
        isFalse,
      );
    });
  });

  group('Fatiga', () {
    test('pérdida respecto a la mejor', () {
      expect(velocityLossPercent(1.0, 0.8), closeTo(20, 1e-9));
      expect(velocityLossPercent(1.0, 1.1), 0);
      expect(velocityLossPercent(0, 0.5), 0);
    });

    test('niveles con umbral 20 %', () {
      expect(fatigueLevel(5, 20), FatigueLevel.fresh);
      expect(fatigueLevel(10, 20), FatigueLevel.warning);
      expect(fatigueLevel(19.99, 20), FatigueLevel.warning);
      expect(fatigueLevel(20, 20), FatigueLevel.stop);
    });

    test('resumen de serie usa la mejor, no la primera', () {
      final s = summarizeSet([
        rep(60, 0.90),
        rep(60, 1.00),
        rep(60, 0.85),
      ], VelocityMetric.mpv)!;
      expect(s.best, 1.00);
      expect(s.last, 0.85);
      expect(s.lossPercent, closeTo(15, 1e-9));
      expect(s.reps, 3);
    });

    test('la métrica VM y VMP no se mezclan', () {
      final r = rep(60, 1.27, mv: 1.20);
      expect(r.velocity(VelocityMetric.mpv), 1.27);
      expect(r.velocity(VelocityMetric.mv), 1.20);
    });
  });

  group('Perfil carga-velocidad', () {
    // Recta exacta: v = 1.50 - 0.01 * carga
    final exact = [
      for (final l in [20.0, 40.0, 60.0, 80.0]) rep(l, 1.50 - 0.01 * l),
    ];

    test('recupera una recta exacta', () {
      final p = fitLoadVelocity(bestRepPerLoad(exact, VelocityMetric.mpv))!;
      expect(p.slope, closeTo(-0.01, 1e-9));
      expect(p.intercept, closeTo(1.50, 1e-9));
      expect(p.r2, closeTo(1, 1e-9));
    });

    test('1RM con VMT 0.30 → (1.50-0.30)/0.01 = 120 kg', () {
      final p = fitLoadVelocity(bestRepPerLoad(exact, VelocityMetric.mpv))!;
      expect(p.estimated1Rm(0.30), closeTo(120, 1e-6));
      expect(p.loadForPercent(80, 0.30), closeTo(96, 1e-6));
    });

    test('se queda con la repetición más rápida de cada carga', () {
      final pts = bestRepPerLoad([
        rep(50, 0.90),
        rep(50, 1.05),
        rep(50, 0.70),
        rep(70, 0.60),
      ], VelocityMetric.mpv);
      expect(pts.length, 2);
      expect(pts.first.velocity, 1.05);
    });

    test('agrupa cargas a 0.5 kg', () {
      final pts = bestRepPerLoad([
        rep(50.2, 0.9),
        rep(49.9, 1.0),
      ], VelocityMetric.mpv);
      expect(pts.length, 1);
      expect(pts.single.loadKg, 50.0);
    });

    test('ignora repeticiones sin carga', () {
      expect(bestRepPerLoad([rep(0, 1.5)], VelocityMetric.mpv), isEmpty);
    });

    // Fallos plantados del ajuste
    test('una sola carga no da perfil', () {
      expect(
        fitLoadVelocity(
          bestRepPerLoad([rep(50, 1.0), rep(50, 0.9)], VelocityMetric.mpv),
        ),
        isNull,
      );
    });
    test('pendiente positiva (datos absurdos) no da perfil', () {
      expect(
        fitLoadVelocity(
          bestRepPerLoad([rep(20, 0.5), rep(80, 1.2)], VelocityMetric.mpv),
        ),
        isNull,
      );
    });
    test('constante equivocada en el 1RM sería detectada', () {
      final p = fitLoadVelocity(bestRepPerLoad(exact, VelocityMetric.mpv))!;
      expect(p.estimated1Rm(0.30), isNot(closeTo(p.estimated1Rm(0.17), 1)));
    });
  });

  group('Perfil resistente a datos raros', () {
    // Recta real: v = 1.90 - 0.015 * carga → 60: 1.00, 80: 0.70, 100: 0.40.
    Rep r(double load, double v, String set) => Rep(
      id: 'r$set$load$v',
      setId: set,
      time: DateTime(2026, 11, 1),
      romCm: 50,
      mv: v,
      mpv: v,
      loadKg: load,
      exerciseId: 'squat',
    );
    final good = [r(60, 1.00, 'a'), r(80, 0.70, 'b'), r(100, 0.40, 'c')];
    const m = VelocityMetric.mpv;

    test('un día malo con una carga nueva se descarta solo', () {
      // A 70 kg tocaría 0.85; ese día salió 0.70.
      final a = analyzeLoadVelocity([...good, r(70, 0.70, 'malo')], m);
      final bad = a.points.firstWhere((p) => p.loadKg == 70);
      expect(bad.status, LvPointStatus.outlier);
      expect(bad.residual, closeTo(-0.15, 1e-9));
      expect(a.profile!.slope, closeTo(-0.015, 1e-9));
      expect(a.profile!.estimated1Rm(0.30), closeTo(106.67, 0.01));
    });

    test('un dato falso hacia arriba también se descarta', () {
      final a = analyzeLoadVelocity([...good, r(90, 0.80, 'raro')], m);
      expect(
        a.points.firstWhere((p) => p.loadKg == 90).status,
        LvPointStatus.outlier,
      );
      expect(a.profile!.intercept, closeTo(1.90, 1e-9));
    });

    test('un punto normal (variación de día a día) no se toca', () {
      final a = analyzeLoadVelocity([...good, r(70, 0.80, 'normal')], m);
      expect(a.used.length, 4);
    });

    test('con 3 cargas no se descarta nada (no se sabe cuál falla)', () {
      final a = analyzeLoadVelocity([
        r(60, 1.00, 'a'),
        r(70, 0.70, 'b'),
        r(100, 0.40, 'c'),
      ], m);
      expect(a.used.length, 3);
    });

    test('incluir a mano gana a la decisión automática', () {
      final a = analyzeLoadVelocity(
        [...good, r(70, 0.70, 'malo')],
        m,
        marks: {'malo': ProfileMark.include},
      );
      expect(
        a.points.firstWhere((p) => p.loadKg == 70).status,
        LvPointStatus.forced,
      );
      expect(a.used.length, 4);
      expect(a.profile!.slope, isNot(closeTo(-0.015, 1e-4)));
    });

    test('excluir a mano saca la serie; si queda otra serie, cuenta esa', () {
      final reps = [...good, r(80, 0.75, 'otroDia')];
      var a = analyzeLoadVelocity(reps, m);
      expect(a.points.firstWhere((p) => p.loadKg == 80).velocity, 0.75);

      a = analyzeLoadVelocity(reps, m, marks: {'otroDia': ProfileMark.exclude});
      final p80 = a.points.where((p) => p.loadKg == 80).single;
      expect(p80.velocity, 0.70);
      expect(p80.status, LvPointStatus.used);

      a = analyzeLoadVelocity(
        reps,
        m,
        marks: {'otroDia': ProfileMark.exclude, 'b': ProfileMark.exclude},
      );
      expect(
        a.points.firstWhere((p) => p.loadKg == 80).status,
        LvPointStatus.excluded,
      );
      expect(a.used.length, 2);
    });

    test('un pico aislado dentro de una serie se toma como fallo', () {
      final pts = bestRepPerLoad([
        r(80, 0.70, 's'),
        r(80, 0.68, 's'),
        r(80, 1.10, 's'), // lectura imposible
      ], m);
      expect(pts.single.velocity, 0.70);
    });

    test('la marca manual sobrevive a guardar y cargar la serie', () {
      final s = WorkSet(
        id: 'x',
        start: DateTime(2026),
        exerciseId: 'squat',
      ).withProfileMark(ProfileMark.exclude);
      final back = WorkSet.fromJson(s.toJson());
      expect(back.profileMark, ProfileMark.exclude);
      expect(back.withPlayer('ana').profileMark, ProfileMark.exclude);
      expect(
        WorkSet.fromJson(s.withProfileMark(null).toJson()).profileMark,
        isNull,
      );
    });
  });
}
