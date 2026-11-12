import 'package:flutter_test/flutter_test.dart';
import 'package:miencoder/core/analysis.dart';
import 'package:miencoder/core/models.dart';

var _n = 0;
Rep rep(double rom, {String set = 's', double load = 80, double mpv = 0.6}) =>
    Rep(
      id: 'r${_n++}',
      setId: set,
      time: DateTime(2026, 11, 1),
      romCm: rom,
      mv: mpv,
      mpv: mpv,
      loadKg: load,
      exerciseId: 'squat',
    );

void main() {
  final history = [
    for (final r in <double>[54, 55, 56, 55, 53, 57, 55, 54, 56, 55, 55, 54])
      rep(r),
  ];

  group('ROM de referencia', () {
    test('mediana y rango mínimo de ±3 cm', () {
      final ref = romReference(history)!;
      expect(ref.target, 55);
      expect(ref.band, kRomMinBandCm);
      expect(ref.manual, isFalse);
    });

    test('con pocas repeticiones no hay referencia automática', () {
      expect(romReference(history.take(5).toList()), isNull);
    });

    test('el rango no pasa del 8 % aunque haya mucha dispersión', () {
      final noisy = [for (var i = 0; i < 12; i++) rep(i.isEven ? 45.0 : 65.0)];
      final ref = romReference(noisy)!;
      expect(ref.band, closeTo(55 * kRomMaxBandFraction, 1e-9));
    });

    test('objetivo manual: centro fijado, rango del historial', () {
      final ref = romReference(history, manualTarget: 60)!;
      expect(ref.target, 60);
      expect(ref.manual, isTrue);
      expect(romReference(const [], manualTarget: 60)!.band, kRomMinBandCm);
    });

    test('corta, normal y larga', () {
      final ref = romReference(history)!;
      expect(ref.statusOf(50), RomStatus.short);
      expect(ref.statusOf(53), RomStatus.ok);
      expect(ref.statusOf(59), RomStatus.long);
      expect(ref.accepts(0), isTrue); // punto manual sin ROM
    });
  });

  group('ROM de la serie', () {
    final ref = romReference(history)!;

    test('serie normal: sin texto', () {
      final s = summarizeSetRom([rep(55), rep(54), rep(56), rep(55)], ref)!;
      expect(s.status, RomStatus.ok);
      expect(s.dropsAtEnd, isFalse);
      expect(s.outOfRange, 0);
    });

    test('serie corta de media', () {
      final s = summarizeSetRom([rep(48), rep(49), rep(47)], ref)!;
      expect(s.status, RomStatus.short);
      expect(s.meanDelta, closeTo(-7, 1e-9));
    });

    test('pérdida de ROM al final de la serie', () {
      final s = summarizeSetRom([
        rep(57),
        rep(57),
        rep(55),
        rep(52),
        rep(51),
      ], ref)!;
      expect(s.drift, closeTo(-5.5, 1e-9));
      expect(s.dropsAtEnd, isTrue);
    });
  });

  group('Las repeticiones cortas no cuentan', () {
    test('1RM del día ignora una repetición corta y rápida', () {
      double v(double load) => 1.40 - 1.10 / 120 * load;
      final prior = [
        for (final l in [60.0, 80.0, 100.0]) ...[
          rep(55, set: 'p$l', load: l, mpv: v(l)),
          rep(55, set: 'p$l', load: l, mpv: v(l) - 0.01),
        ],
      ];
      final rom = romReference(history);
      final ref = dayRmReference(prior, VelocityMetric.mpv, 0.30, rom: rom);
      // Serie a 90 kg normal, más una repetición corta (40 cm) muy rápida.
      final set = [
        rep(55, set: 'x', load: 90, mpv: v(90)),
        rep(55, set: 'x', load: 90, mpv: v(90) - 0.01),
        rep(40, set: 'x', load: 90, mpv: v(90) + 0.08),
      ];
      final withRom = estimateDayRm(set, ref, VelocityMetric.mpv, rom: rom)!;
      final without = estimateDayRm(set, ref, VelocityMetric.mpv)!;
      expect(withRom.level, DayRmLevel.normal);
      expect(without.e1Rm, greaterThan(withRom.e1Rm));
    });
  });
}
