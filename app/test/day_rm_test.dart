import 'package:flutter_test/flutter_test.dart';
import 'package:miencoder/core/analysis.dart';
import 'package:miencoder/core/models.dart';

var _n = 0;
Rep rep(String setId, double load, double mpv, {DateTime? t}) => Rep(
  id: 'r${_n++}',
  setId: setId,
  time: t ?? DateTime(2026, 11, 1),
  romCm: 50,
  mv: mpv,
  mpv: mpv,
  loadKg: load,
  exerciseId: 'squat',
);

/// Perfil de ejemplo: 1RM 120 kg a 0,30 m/s.
double v(double load) => 1.40 - 1.10 / 120 * load;

/// Una serie de 3 repeticiones a [load], [d] m/s por encima o debajo del perfil.
List<Rep> set(String id, double load, {double d = 0}) => [
  rep(id, load, v(load) + d),
  rep(id, load, v(load) + d - 0.01),
  rep(id, load, v(load) + d - 0.04),
];

void main() {
  const m = VelocityMetric.mpv;

  group('setVelocity', () {
    test('media de las 2 más rápidas', () {
      expect(
        setVelocity([
          rep('s', 80, 0.60),
          rep('s', 80, 0.70),
          rep('s', 80, 0.66),
        ], m),
        closeTo(0.68, 1e-9),
      );
    });

    test('quita un pico de fallo de lectura', () {
      expect(
        setVelocity([
          rep('s', 80, 1.10),
          rep('s', 80, 0.70),
          rep('s', 80, 0.66),
        ], m),
        closeTo(0.68, 1e-9),
      );
    });

    test('con una sola repetición no hay dato', () {
      expect(setVelocity([rep('s', 80, 0.70)], m), isNull);
    });
  });

  group('1RM del día', () {
    final history = [...set('a', 60), ...set('b', 80), ...set('c', 100)];

    test('la referencia reproduce el 1RM del perfil', () {
      final ref = dayRmReference(history, m, 0.30)!;
      expect(ref.oneRm, closeTo(120, 0.5));
      expect(ref.band, kDayRmDefaultBand); // pocas series: rango por defecto
    });

    test('sin 3 cargas no hay referencia', () {
      expect(
        dayRmReference([...set('a', 60), ...set('b', 80)], m, 0.30),
        isNull,
      );
    });

    test('serie normal → normal', () {
      final ref = dayRmReference(history, m, 0.30);
      final e = estimateDayRm(set('x', 90), ref, m)!;
      expect(e.percent.abs(), lessThan(1));
      expect(e.level, DayRmLevel.normal);
    });

    test('día cansado a 70 kg: el 1RM del día baja, la referencia no', () {
      final ref = dayRmReference(history, m, 0.30)!;
      final e = estimateDayRm(set('x', 70, d: -0.10), ref, m)!;
      expect(e.referenceRm, closeTo(120, 0.5));
      // −0,10 m/s con pendiente 1,10/120 → unos 11 kg menos (≈ −9 %).
      expect(e.e1Rm, closeTo(109, 1));
      expect(e.level, DayRmLevel.veryLow);
    });

    test('por encima del perfil → above', () {
      final ref = dayRmReference(history, m, 0.30);
      final e = estimateDayRm(set('x', 90, d: 0.07), ref, m)!;
      expect(e.percent, greaterThan(4));
      expect(e.level, DayRmLevel.above);
    });

    test('carga demasiado ligera (< 40 % del 1RM) → sin dato', () {
      final ref = dayRmReference(history, m, 0.30);
      expect(estimateDayRm(set('x', 40), ref, m), isNull);
    });

    test('el rango normal sale de la dispersión de la persona', () {
      final noisy = [
        for (var i = 0; i < 8; i++)
          ...set('n$i', 60.0 + 5 * i, d: i.isEven ? 0.06 : -0.06),
      ];
      final ref = dayRmReference(noisy, m, 0.30)!;
      expect(ref.band, greaterThan(kDayRmDefaultBand));
      expect(ref.band, lessThanOrEqualTo(kDayRmMaxBand));
    });

    test('series excluidas a mano no cuentan', () {
      final ref = dayRmReference(
        [...history, ...set('bad', 90, d: -0.3)],
        m,
        0.30,
        marks: {'bad': ProfileMark.exclude},
      )!;
      expect(ref.oneRm, closeTo(120, 0.5));
    });

    test('ROM corto en casi toda la serie: estima igual y lo marca', () {
      final ref = dayRmReference(history, m, 0.30);
      const rom = RomReference(50, 3);
      final short = [
        for (final r in set('x', 90))
          Rep(
            id: r.id,
            setId: r.setId,
            time: r.time,
            romCm: 42,
            mv: r.mv,
            mpv: r.mpv,
            loadKg: r.loadKg,
            exerciseId: r.exerciseId,
          ),
      ];
      final e = estimateDayRm(short, ref, m, rom: rom)!;
      expect(e.romOutOfRange, isTrue);
      expect(e.percent.abs(), lessThan(1));
      // Con ROM válido no se marca.
      expect(
        estimateDayRm(set('y', 90), ref, m, rom: rom)!.romOutOfRange,
        isFalse,
      );
    });
  });
}
