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
