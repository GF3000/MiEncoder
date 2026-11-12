import 'dart:math' as math;

import 'models.dart';

/// Clave de "serie abierta": un deportista (o ninguno) solo tiene una serie
/// abierta a la vez. Si cambia la carga o el ejercicio, esa serie se cierra.
/// No hay corte por tiempo: las pausas de un cluster siguen en la misma serie.
bool sameOpenSet({
  required double openLoad,
  required String openExerciseId,
  required double load,
  required String exerciseId,
}) => openLoad == load && openExerciseId == exerciseId;

/// Pérdida de velocidad (%) de [current] respecto a la mejor velocidad de la
/// serie [best]. 0 si current >= best.
double velocityLossPercent(double best, double current) {
  if (best <= 0) return 0;
  final loss = (best - current) / best * 100;
  return loss < 0 ? 0 : loss;
}

/// Estado de fatiga de una repetición. [off] = avisos desactivados.
enum FatigueLevel { off, fresh, warning, stop }

FatigueLevel fatigueLevel(double lossPercent, double threshold) {
  if (lossPercent >= threshold) return FatigueLevel.stop;
  if (lossPercent >= threshold * 0.5) return FatigueLevel.warning;
  return FatigueLevel.fresh;
}

/// Resumen de una serie.
class SetSummary {
  final int reps;
  final double best;
  final double last;
  final double lossPercent;
  final double avg;

  const SetSummary({
    required this.reps,
    required this.best,
    required this.last,
    required this.lossPercent,
    required this.avg,
  });
}

SetSummary? summarizeSet(List<Rep> reps, VelocityMetric metric) {
  if (reps.isEmpty) return null;
  final v = reps.map((r) => r.velocity(metric)).toList();
  final best = v.reduce(math.max);
  final last = v.last;
  return SetSummary(
    reps: reps.length,
    best: best,
    last: last,
    lossPercent: velocityLossPercent(best, last),
    avg: v.reduce((a, b) => a + b) / v.length,
  );
}

/// Cómo cuenta un punto en el perfil carga-velocidad.
enum LvPointStatus {
  /// Entra en el ajuste (decisión automática).
  used,

  /// Se aleja demasiado de la recta: descartado automáticamente.
  outlier,

  /// El entrenador lo excluyó a mano.
  excluded,

  /// El entrenador lo incluyó a mano (aunque parezca atípico).
  forced,
}

extension LvPointStatusX on LvPointStatus {
  bool get counts => this == LvPointStatus.used || this == LvPointStatus.forced;
}

/// Un punto del perfil carga-velocidad.
class LvPoint {
  final double loadKg;
  final double velocity;
  final DateTime time;

  /// Serie de la que sale el punto (la marca manual se guarda en la serie).
  final String? setId;
  final LvPointStatus status;

  /// Distancia (m/s) a la recta robusta; null si no se calculó.
  final double? residual;

  const LvPoint(
    this.loadKg,
    this.velocity,
    this.time, {
    this.setId,
    this.status = LvPointStatus.used,
    this.residual,
  });

  LvPoint withStatus(LvPointStatus status, {double? residual}) => LvPoint(
    loadKg,
    velocity,
    time,
    setId: setId,
    status: status,
    residual: residual ?? this.residual,
  );
}

/// Resultado del ajuste lineal velocidad = a + b * carga.
class LvProfile {
  final List<LvPoint> points;
  final double intercept; // a
  final double slope; // b (negativa)
  final double r2;

  const LvProfile({
    required this.points,
    required this.intercept,
    required this.slope,
    required this.r2,
  });

  double velocityAt(double load) => intercept + slope * load;

  /// Carga a la que la velocidad sería [v].
  double loadAt(double v) => (v - intercept) / slope;

  /// 1RM estimado con la velocidad mínima umbral [mvt].
  double estimated1Rm(double mvt) => loadAt(mvt);

  /// Carga (kg) que corresponde a un % del 1RM estimado.
  double loadForPercent(double percent, double mvt) =>
      estimated1Rm(mvt) * percent / 100;
}

double _loadKey(double kg) => (kg * 2).round() / 2;

/// Una repetición se considera un fallo de lectura si, dentro de su serie y
/// carga, supera a la segunda mejor en más de un 20 % y más de 0.10 m/s.
/// En ese caso la serie cuenta con su segunda mejor repetición.
const double kGlitchRatio = 1.20;
const double kGlitchMinDiff = 0.10;

/// Mejor repetición de cada (serie, carga), descartando un pico aislado que
/// parezca un fallo del encoder.
List<LvPoint> _bestPerSet(List<Rep> reps, VelocityMetric metric) {
  final groups = <(String, double), List<Rep>>{};
  for (final r in reps) {
    if (r.loadKg <= 0) continue;
    (groups[(r.setId, _loadKey(r.loadKg))] ??= []).add(r);
  }
  final out = <LvPoint>[];
  for (final MapEntry(key: (setId, load), value: rs) in groups.entries) {
    rs.sort((a, b) => b.velocity(metric).compareTo(a.velocity(metric)));
    var top = rs.first;
    if (rs.length >= 2) {
      final v1 = top.velocity(metric), v2 = rs[1].velocity(metric);
      if (v1 > v2 * kGlitchRatio && v1 - v2 > kGlitchMinDiff) top = rs[1];
    }
    out.add(LvPoint(load, top.velocity(metric), top.time, setId: setId));
  }
  return out;
}

/// Se queda con la repetición más rápida de cada carga (las cargas se
/// agrupan redondeando a 0.5 kg), ignorando picos aislados por fallo de
/// lectura (ver [kGlitchRatio]).
List<LvPoint> bestRepPerLoad(List<Rep> reps, VelocityMetric metric) {
  final best = <double, LvPoint>{};
  for (final p in _bestPerSet(reps, metric)) {
    final current = best[p.loadKg];
    if (current == null || p.velocity > current.velocity) best[p.loadKg] = p;
  }
  return best.values.toList()..sort((a, b) => a.loadKg.compareTo(b.loadKg));
}

/// Ajuste por mínimos cuadrados. Necesita al menos 2 cargas distintas y una
/// pendiente negativa (más carga = menos velocidad); si no, null.
LvProfile? fitLoadVelocity(List<LvPoint> points) {
  if (points.length < 2) return null;
  final n = points.length;
  final mx = points.map((p) => p.loadKg).reduce((a, b) => a + b) / n;
  final my = points.map((p) => p.velocity).reduce((a, b) => a + b) / n;
  var sxx = 0.0, sxy = 0.0, syy = 0.0;
  for (final p in points) {
    final dx = p.loadKg - mx, dy = p.velocity - my;
    sxx += dx * dx;
    sxy += dx * dy;
    syy += dy * dy;
  }
  if (sxx == 0) return null;
  final slope = sxy / sxx;
  if (slope >= 0) return null;
  final intercept = my - slope * mx;
  final r2 = syy == 0 ? 1.0 : (sxy * sxy) / (sxx * syy);
  return LvProfile(points: points, intercept: intercept, slope: slope, r2: r2);
}

double _median(List<double> xs) {
  final s = List.of(xs)..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

/// Recta de Theil–Sen: pendiente = mediana de las pendientes entre cada par
/// de puntos. Un punto raro apenas la mueve. Devuelve (a, b) o null.
(double, double)? theilSen(List<LvPoint> points) {
  final slopes = <double>[];
  for (var i = 0; i < points.length; i++) {
    for (var j = i + 1; j < points.length; j++) {
      final dx = points[j].loadKg - points[i].loadKg;
      if (dx == 0) continue;
      slopes.add((points[j].velocity - points[i].velocity) / dx);
    }
  }
  if (slopes.isEmpty) return null;
  final b = _median(slopes);
  final a = _median([for (final p in points) p.velocity - b * p.loadKg]);
  return (a, b);
}

/// Mínimo de cargas para descartar puntos automáticamente: con 3 no se
/// puede saber cuál de ellas es la errónea.
const int kMinPointsForOutliers = 4;

/// Distancia mínima (m/s) a la recta para considerar un punto atípico. Está
/// por encima de la variación normal entre días (~0.03-0.06 m/s).
const double kOutlierMinResidual = 0.08;

/// Perfil con los puntos y cómo ha contado cada uno.
class LvAnalysis {
  /// Todos los puntos, incluidos los descartados, ordenados por carga.
  final List<LvPoint> points;
  final LvProfile? profile;

  const LvAnalysis(this.points, this.profile);

  List<LvPoint> get used => [
    for (final p in points)
      if (p.status.counts) p,
  ];
}

/// Perfil carga-velocidad resistente a datos raros:
///
/// 1. Se apartan las series que el entrenador excluyó ([marks]). Si todas
///    las series de una carga están excluidas, la carga aparece en gris.
/// 2. Un punto por carga: la mejor repetición (sin picos de fallo).
/// 3. Con 4 o más cargas se ajusta una recta robusta (Theil–Sen) y se
///    descartan los puntos demasiado lejos de ella (como mucho 1 de cada 4 y
///    dejando al menos 3). Los incluidos a mano nunca se descartan.
/// 4. Con los puntos que quedan, mínimos cuadrados normales.
LvAnalysis analyzeLoadVelocity(
  List<Rep> reps,
  VelocityMetric metric, {
  Map<String, ProfileMark> marks = const {},
}) {
  final active = <double, LvPoint>{};
  final excluded = <double, LvPoint>{};
  for (final p in _bestPerSet(reps, metric)) {
    final target = marks[p.setId] == ProfileMark.exclude ? excluded : active;
    final current = target[p.loadKg];
    if (current == null || p.velocity > current.velocity) target[p.loadKg] = p;
  }

  var candidates = [
    for (final p in active.values)
      p.withStatus(
        marks[p.setId] == ProfileMark.include
            ? LvPointStatus.forced
            : LvPointStatus.used,
      ),
  ];

  if (candidates.length >= kMinPointsForOutliers) {
    final line = theilSen(candidates);
    if (line != null) {
      final (a, b) = line;
      final res = [for (final p in candidates) p.velocity - (a + b * p.loadKg)];
      final mad = _median([for (final r in res) r.abs()]);
      final threshold = math.max(kOutlierMinResidual, 3 * 1.4826 * mad);
      final maxOut = math.min(candidates.length ~/ 4, candidates.length - 3);
      final ranked = [
        for (var i = 0; i < candidates.length; i++)
          if (candidates[i].status != LvPointStatus.forced &&
              res[i].abs() > threshold)
            i,
      ]..sort((x, y) => res[y].abs().compareTo(res[x].abs()));
      final out = ranked.take(maxOut).toSet();
      candidates = [
        for (var i = 0; i < candidates.length; i++)
          candidates[i].withStatus(
            out.contains(i) ? LvPointStatus.outlier : candidates[i].status,
            residual: res[i],
          ),
      ];
    }
  }

  final points = [
    ...candidates,
    for (final e in excluded.entries)
      if (!active.containsKey(e.key))
        e.value.withStatus(LvPointStatus.excluded),
  ]..sort((a, b) => a.loadKg.compareTo(b.loadKg));

  final analysis = LvAnalysis(points, null);
  return LvAnalysis(points, fitLoadVelocity(analysis.used));
}

// ------------------------------------------------------------ ROM

/// Repeticiones de días anteriores necesarias para calcular el ROM de
/// referencia automático.
const int kRomMinReps = 10;

/// Rango normal del ROM: al menos ±3 cm (lo que el encoder distingue de
/// verdad) y como mucho ±8 % del ROM de referencia.
const double kRomMinBandCm = 3;
const double kRomMaxBandFraction = 0.08;

enum RomStatus { ok, short, long }

/// ROM de referencia de un deportista en un ejercicio y su rango normal.
class RomReference {
  /// cm.
  final double target;

  /// ± cm.
  final double band;

  /// true si el entrenador fijó el ROM objetivo a mano.
  final bool manual;

  const RomReference(this.target, this.band, {this.manual = false});

  RomStatus statusOf(double romCm) {
    if (romCm < target - band) return RomStatus.short;
    if (romCm > target + band) return RomStatus.long;
    return RomStatus.ok;
  }

  /// ROM ≤ 0 = sin medir (p. ej. un punto manual): se acepta siempre.
  bool accepts(double romCm) => romCm <= 0 || statusOf(romCm) == RomStatus.ok;
}

/// ROM de referencia a partir de [history] (repeticiones de días
/// anteriores): mediana y rango con la dispersión robusta (MAD). Con
/// [manualTarget] el centro es ese valor y el historial solo da el rango.
/// null si no hay objetivo manual ni [kRomMinReps] repeticiones.
RomReference? romReference(List<Rep> history, {double? manualTarget}) {
  final roms = [
    for (final r in history)
      if (r.romCm > 0) r.romCm,
  ];
  if (manualTarget == null && roms.length < kRomMinReps) return null;
  final target = manualTarget ?? _median(roms);
  double band;
  if (roms.length >= kRomMinReps) {
    final med = _median(roms);
    final sd = 1.4826 * _median([for (final r in roms) (r - med).abs()]);
    band = 2 * sd;
  } else {
    band = kRomMinBandCm;
  }
  final maxBand = math.max(kRomMinBandCm, target * kRomMaxBandFraction);
  band = band.clamp(kRomMinBandCm, maxBand).toDouble();
  return RomReference(target, band, manual: manualTarget != null);
}

/// Repeticiones de [reps] con el ROM dentro del rango de [rom] (todas si
/// no hay referencia).
List<Rep> withValidRom(List<Rep> reps, RomReference? rom) => rom == null
    ? reps
    : [
        for (final r in reps)
          if (rom.accepts(r.romCm)) r,
      ];

/// Cómo fue el ROM de una serie respecto a la referencia.
class SetRomSummary {
  /// ROM medio de la serie menos el de referencia (cm).
  final double meanDelta;

  /// Repeticiones fuera de rango (cortas o largas).
  final int outOfRange;

  /// ROM de las 2 últimas menos el de las 2 primeras (cm); null con menos
  /// de 4 repeticiones.
  final double? drift;

  final RomReference ref;

  const SetRomSummary(this.meanDelta, this.outOfRange, this.drift, this.ref);

  RomStatus get status => ref.statusOf(ref.target + meanDelta);

  /// El ROM cae al final de la serie más que el rango normal.
  bool get dropsAtEnd => drift != null && drift! < -ref.band;
}

SetRomSummary? summarizeSetRom(List<Rep> reps, RomReference? ref) {
  if (ref == null || reps.isEmpty) return null;
  final roms = [for (final r in reps) r.romCm];
  final mean = roms.reduce((a, b) => a + b) / roms.length;
  final out = roms.where((r) => !ref.accepts(r)).length;
  double? drift;
  if (roms.length >= 4) {
    final first = (roms[0] + roms[1]) / 2;
    final last = (roms[roms.length - 1] + roms[roms.length - 2]) / 2;
    drift = last - first;
  }
  return SetRomSummary(mean - ref.target, out, drift, ref);
}

// ------------------------------------------------------------ 1RM del día

/// Velocidad que representa una serie: media de sus 2 repeticiones más
/// rápidas, quitando antes un pico aislado que parezca fallo de lectura
/// (ver [kGlitchRatio]). null si no quedan al menos 2 repeticiones.
double? setVelocity(List<Rep> reps, VelocityMetric metric) {
  final v = [for (final r in reps) r.velocity(metric)]
    ..sort((a, b) => b.compareTo(a));
  if (v.length >= 2 &&
      v[0] > v[1] * kGlitchRatio &&
      v[0] - v[1] > kGlitchMinDiff) {
    v.removeAt(0);
  }
  if (v.length < 2) return null;
  return (v[0] + v[1]) / 2;
}

/// Por debajo de este % del 1RM la estimación es poco fiable: no se muestra.
const double kDayRmMinPercentLoad = 40;

/// Mínimo de cargas en el perfil de referencia para estimar el 1RM del día.
const int kDayRmMinLoads = 3;

/// Rango normal (±%) cuando aún no hay series suficientes para calcular el
/// de la persona, y límites para el calculado.
const double kDayRmDefaultBand = 4;
const double kDayRmMinBand = 3;
const double kDayRmMaxBand = 8;
const int kDayRmMinSetsForBand = 6;

/// Cómo está el 1RM del día respecto al de referencia.
enum DayRmLevel { above, normal, low, veryLow }

/// Referencia con la que se comparan las series de un día: el perfil
/// carga-velocidad con los datos ANTERIORES a ese día y el rango normal de
/// la persona (±%).
class DayRmReference {
  final LvProfile profile;
  final double mvt;
  final double band;

  const DayRmReference(this.profile, this.mvt, this.band);

  double get oneRm => profile.estimated1Rm(mvt);

  /// 1RM que indica una serie con carga [load] y velocidad [v]: la recta del
  /// perfil desplazada en paralelo hasta pasar por ese punto.
  double e1RmFor(double load, double v) => load + (mvt - v) / profile.slope;

  /// Inversa de [e1RmFor]: velocidad de una serie con [load] que indicaría
  /// un 1RM del día de [e1Rm].
  double velocityFor(double load, double e1Rm) =>
      mvt - profile.slope * (e1Rm - load);

  /// Velocidades de serie (lenta, rápida) con las que [load] queda dentro de
  /// [target] respecto al 1RM del día. null si la carga es demasiado ligera
  /// respecto al perfil para juzgarla.
  (double, double)? velocityZone(double load, RmTarget target) {
    if (load <= 0 || target.min <= 0 || target.max < target.min) return null;
    if (load / oneRm * 100 < kDayRmMinPercentLoad) return null;
    return (
      velocityFor(load, load * 100 / target.max),
      velocityFor(load, load * 100 / target.min),
    );
  }
}

/// 1RM que indica una serie, comparado con el de referencia.
class DayRmEstimate {
  final double e1Rm;
  final double referenceRm;
  final double band;

  /// true si casi todas las repeticiones tenían el ROM fuera de rango y se
  /// estimó con todas igualmente (menos fiable: se avisa en pantalla).
  final bool romOutOfRange;

  const DayRmEstimate(
    this.e1Rm,
    this.referenceRm,
    this.band, {
    this.romOutOfRange = false,
  });

  /// Diferencia en % respecto al 1RM de referencia (negativo = por debajo).
  double get percent => (e1Rm / referenceRm - 1) * 100;

  DayRmLevel get level {
    final p = percent;
    if (p <= -2 * band) return DayRmLevel.veryLow;
    if (p < -band) return DayRmLevel.low;
    if (p >= band) return DayRmLevel.above;
    return DayRmLevel.normal;
  }
}

/// Referencia para estimar el 1RM del día a partir de [history] (las
/// repeticiones de ese deportista y ejercicio ANTES del día). null si el
/// perfil no tiene al menos [kDayRmMinLoads] cargas.
///
/// El rango normal sale de cuánto se desvían de la referencia las series del
/// propio historial (raíz del error cuadrático medio, en %).
DayRmReference? dayRmReference(
  List<Rep> history,
  VelocityMetric metric,
  double mvt, {
  Map<String, ProfileMark> marks = const {},
  RomReference? rom,
}) {
  history = withValidRom(history, rom);
  final analysis = analyzeLoadVelocity(history, metric, marks: marks);
  final profile = analysis.profile;
  if (profile == null || analysis.used.length < kDayRmMinLoads) return null;
  final draft = DayRmReference(profile, mvt, kDayRmDefaultBand);
  final rm = draft.oneRm;
  if (!rm.isFinite || rm <= 0) return null;

  final bySet = <String, List<Rep>>{};
  for (final r in history) {
    if (r.loadKg <= 0 || marks[r.setId] == ProfileMark.exclude) continue;
    (bySet[r.setId] ??= []).add(r);
  }
  final devs = <double>[];
  for (final rs in bySet.values) {
    final v = setVelocity(rs, metric);
    final load = rs.first.loadKg;
    if (v == null || load / rm * 100 < kDayRmMinPercentLoad) continue;
    devs.add((draft.e1RmFor(load, v) / rm - 1) * 100);
  }
  var band = kDayRmDefaultBand;
  if (devs.length >= kDayRmMinSetsForBand) {
    final rms = math.sqrt(
      devs.map((d) => d * d).reduce((a, b) => a + b) / devs.length,
    );
    band = rms.clamp(kDayRmMinBand, kDayRmMaxBand).toDouble();
  }
  return DayRmReference(profile, mvt, band);
}

/// 1RM del día que indica una serie ([setReps], todas con la misma carga).
/// Se usan las repeticiones con ROM válido; si quedan menos de 2, todas
/// (marcado con [DayRmEstimate.romOutOfRange]): mejor un dato con aviso que
/// ninguno. null si no hay referencia, la serie tiene menos de 2
/// repeticiones o la carga es demasiado ligera para estimar con fiabilidad.
DayRmEstimate? estimateDayRm(
  List<Rep> setReps,
  DayRmReference? ref,
  VelocityMetric metric, {
  RomReference? rom,
}) {
  if (ref == null || setReps.isEmpty) return null;
  final load = setReps.first.loadKg;
  final rm = ref.oneRm;
  if (load <= 0 || load / rm * 100 < kDayRmMinPercentLoad) return null;
  var v = setVelocity(withValidRom(setReps, rom), metric);
  var romOut = false;
  if (v == null) {
    v = setVelocity(setReps, metric);
    romOut = v != null && rom != null;
  }
  if (v == null) return null;
  return DayRmEstimate(
    ref.e1RmFor(load, v),
    rm,
    ref.band,
    romOutOfRange: romOut,
  );
}

/// Máximo acumulado: [3, 5, 4] → [3, 5, 5]. Sirve para colorear cada
/// repetición respecto a la mejor HASTA ese momento.
List<double> runningMax(List<double> values) {
  final out = <double>[];
  var m = double.negativeInfinity;
  for (final v in values) {
    if (v > m) m = v;
    out.add(m);
  }
  return out;
}

// ------------------------------------------------------------ consejo de carga

/// Cambio máximo (%) que se recomienda de una serie a la siguiente: si el
/// objetivo queda lejos, se llega en varios pasos y se re-evalúa cada serie.
const double kAdviceMaxChangePercent = 10;

enum LoadAdviceKind { up, keep, down }

/// Qué hacer con la carga tras una serie para quedar en el %1RM objetivo.
class LoadAdvice {
  final LoadAdviceKind kind;

  /// Carga de la serie que se juzga.
  final double load;

  /// Carga recomendada para la siguiente (igual a [load] si [kind] es keep).
  final double targetLoad;

  /// % del 1RM del día que ha supuesto la serie.
  final double percent;
  final RmTarget target;

  /// true si se calculó con la relación genérica velocidad-%1RM (sin
  /// perfil propio del deportista): menos precisa.
  final bool generic;

  const LoadAdvice(
    this.kind,
    this.load,
    this.targetLoad,
    this.percent,
    this.target, {
    this.generic = false,
  });

  double get delta => targetLoad - load;
}

/// Consejo de carga: si [load] es el [LoadAdvice.percent] % de [dayRm] y
/// está dentro de [target], mantener; si no, ir hacia el centro del rango,
/// redondeando a [step] y sin cambiar más de [kAdviceMaxChangePercent] %
/// (siempre al menos un [step]).
LoadAdvice? loadAdvice({
  required double load,
  required double dayRm,
  required RmTarget target,
  required double step,
  bool generic = false,
}) {
  if (load <= 0 || !dayRm.isFinite || dayRm <= 0) return null;
  final pct = load / dayRm * 100;
  if (target.contains(pct)) {
    return LoadAdvice(
      LoadAdviceKind.keep,
      load,
      load,
      pct,
      target,
      generic: generic,
    );
  }
  final s = step > 0 ? step : 2.5;
  final cap = load * kAdviceMaxChangePercent / 100;
  final ideal = (target.mid / 100 * dayRm).clamp(load - cap, load + cap);
  var next = (ideal / s).round() * s;
  final up = pct < target.min;
  if (up ? next <= load : next >= load) next = up ? load + s : load - s;
  if (next <= 0) return null;
  return LoadAdvice(
    up ? LoadAdviceKind.up : LoadAdviceKind.down,
    load,
    next,
    pct,
    target,
    generic: generic,
  );
}

// ------------------------------------------------------------ relación genérica

/// Diferencia de velocidad media propulsiva entre el 100 % y el 40 % del
/// 1RM, típica en la literatura de VBT para sentadilla y press banca
/// (≈ 0,95 m/s). Con la velocidad a 1RM de cada ejercicio da una recta
/// velocidad-%1RM genérica para quien no tiene perfil propio.
const double kGenericVelocitySpan = 0.95;

/// %1RM que indica la velocidad [v] según la relación genérica.
double genericPercentRm(double v, double mvt) =>
    100 - 60 * (v - mvt) / kGenericVelocitySpan;

/// Velocidad que corresponde a [percent] %1RM según la relación genérica.
double genericVelocityAt(double percent, double mvt) =>
    mvt + kGenericVelocitySpan * (100 - percent) / 60;

/// Consejo de carga sin perfil propio: el %1RM sale de la velocidad de la
/// serie con la relación genérica. null si la serie no tiene 2
/// repeticiones o la velocidad cae fuera de 40–105 %.
LoadAdvice? genericLoadAdvice(
  List<Rep> setReps,
  VelocityMetric metric, {
  required double mvt,
  required RmTarget target,
  required double step,
}) {
  if (setReps.isEmpty) return null;
  final v = setVelocity(setReps, metric);
  if (v == null) return null;
  final pct = genericPercentRm(v, mvt);
  if (pct < kDayRmMinPercentLoad || pct > 105) return null;
  final load = setReps.first.loadKg;
  return loadAdvice(
    load: load,
    dayRm: load * 100 / pct,
    target: target,
    step: step,
    generic: true,
  );
}
