// Modelos de datos. Se guardan como mapas JSON en sembast.

enum VelocityMetric { mpv, mv }

extension VelocityMetricLabel on VelocityMetric {
  String get label => this == VelocityMetric.mpv ? 'VMP' : 'VM';
}

class Player {
  final String id;
  final String name;
  final bool archived;

  /// ROM objetivo (cm) fijado a mano por ejercicio. Sin entrada = automático.
  final Map<String, double> romTargets;

  const Player({
    required this.id,
    required this.name,
    this.archived = false,
    this.romTargets = const {},
  });

  Player copyWith({
    String? name,
    bool? archived,
    Map<String, double>? romTargets,
  }) => Player(
    id: id,
    name: name ?? this.name,
    archived: archived ?? this.archived,
    romTargets: romTargets ?? this.romTargets,
  );

  /// Copia con el ROM objetivo de [exerciseId] fijado ([cm]) o quitado (null).
  Player withRomTarget(String exerciseId, double? cm) => copyWith(
    romTargets: {
      for (final e in romTargets.entries)
        if (e.key != exerciseId) e.key: e.value,
      exerciseId: ?cm,
    },
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'archived': archived,
    if (romTargets.isNotEmpty) 'romTargets': romTargets,
  };

  factory Player.fromJson(Map<String, Object?> j) => Player(
    id: j['id'] as String,
    name: j['name'] as String,
    archived: (j['archived'] as bool?) ?? false,
    romTargets: {
      for (final e in ((j['romTargets'] as Map?) ?? const {}).entries)
        e.key as String: (e.value as num).toDouble(),
    },
  );
}

class Exercise {
  final String id;
  final String name;

  /// Velocidad (VMP) a la que se estima el 1RM: "velocidad mínima umbral".
  final double mvt;

  const Exercise({required this.id, required this.name, required this.mvt});

  Exercise copyWith({String? name, double? mvt}) =>
      Exercise(id: id, name: name ?? this.name, mvt: mvt ?? this.mvt);

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'mvt': mvt};

  factory Exercise.fromJson(Map<String, Object?> j) => Exercise(
    id: j['id'] as String,
    name: j['name'] as String,
    mvt: (j['mvt'] as num).toDouble(),
  );
}

/// Ejercicios iniciales. Las velocidades a 1RM son valores de referencia
/// habituales en la literatura de VBT; el entrenador puede cambiarlas.
const List<Exercise> kDefaultExercises = [
  Exercise(id: 'squat', name: 'Sentadilla', mvt: 0.30),
  Exercise(id: 'bench', name: 'Press banca', mvt: 0.17),
  Exercise(id: 'deadlift', name: 'Peso muerto', mvt: 0.15),
  Exercise(id: 'hipthrust', name: 'Hip thrust', mvt: 0.25),
  Exercise(id: 'row', name: 'Remo', mvt: 0.50),
  Exercise(id: 'ohp', name: 'Press militar', mvt: 0.20),
];

class Rep {
  final String id;
  final String setId;
  final DateTime time;
  final double romCm;
  final double mv;
  final double mpv;
  final double? vmax;
  final bool vmaxTruncated;
  final double loadKg;
  final String exerciseId;

  const Rep({
    required this.id,
    required this.setId,
    required this.time,
    required this.romCm,
    required this.mv,
    required this.mpv,
    this.vmax,
    this.vmaxTruncated = false,
    required this.loadKg,
    required this.exerciseId,
  });

  double velocity(VelocityMetric m) => m == VelocityMetric.mpv ? mpv : mv;

  Rep inSet(String newSetId) => Rep(
    id: id,
    setId: newSetId,
    time: time,
    romCm: romCm,
    mv: mv,
    mpv: mpv,
    vmax: vmax,
    vmaxTruncated: vmaxTruncated,
    loadKg: loadKg,
    exerciseId: exerciseId,
  );

  /// Potencia media aproximada (W) = masa * g * velocidad media.
  double get meanPowerW => loadKg * 9.81 * mv;

  Map<String, Object?> toJson() => {
    'id': id,
    'setId': setId,
    'time': time.millisecondsSinceEpoch,
    'rom': romCm,
    'mv': mv,
    'mpv': mpv,
    'vmax': vmax,
    'vmaxTruncated': vmaxTruncated,
    'load': loadKg,
    'exerciseId': exerciseId,
  };

  factory Rep.fromJson(Map<String, Object?> j) => Rep(
    id: j['id'] as String,
    setId: j['setId'] as String,
    time: DateTime.fromMillisecondsSinceEpoch(j['time'] as int),
    romCm: (j['rom'] as num).toDouble(),
    mv: (j['mv'] as num).toDouble(),
    mpv: (j['mpv'] as num).toDouble(),
    vmax: (j['vmax'] as num?)?.toDouble(),
    vmaxTruncated: (j['vmaxTruncated'] as bool?) ?? false,
    loadKg: (j['load'] as num).toDouble(),
    exerciseId: j['exerciseId'] as String,
  );
}

/// Decisión manual del entrenador sobre si una serie cuenta en el perfil
/// carga-velocidad. Sin marca (null) decide la app.
enum ProfileMark { include, exclude }

/// Una serie: grupo de repeticiones seguidas. Puede no tener jugador.
class WorkSet {
  final String id;
  final DateTime start;
  final String exerciseId;
  final String? playerId;

  /// Sesión a la que pertenece (null = punto manual, fuera de sesión).
  final String? sessionId;

  /// Marca manual para el perfil carga-velocidad (null = automático).
  final ProfileMark? profileMark;

  const WorkSet({
    required this.id,
    required this.start,
    required this.exerciseId,
    this.playerId,
    this.sessionId,
    this.profileMark,
  });

  WorkSet _copy({
    String? Function()? playerId,
    String? Function()? sessionId,
    ProfileMark? Function()? profileMark,
  }) => WorkSet(
    id: id,
    start: start,
    exerciseId: exerciseId,
    playerId: playerId != null ? playerId() : this.playerId,
    sessionId: sessionId != null ? sessionId() : this.sessionId,
    profileMark: profileMark != null ? profileMark() : this.profileMark,
  );

  WorkSet withPlayer(String? playerId) => _copy(playerId: () => playerId);

  WorkSet withSession(String? sessionId) => _copy(sessionId: () => sessionId);

  WorkSet withProfileMark(ProfileMark? mark) => _copy(profileMark: () => mark);

  Map<String, Object?> toJson() => {
    'id': id,
    'start': start.millisecondsSinceEpoch,
    'exerciseId': exerciseId,
    'playerId': playerId,
    'sessionId': sessionId,
    'profileMark': profileMark?.name,
  };

  factory WorkSet.fromJson(Map<String, Object?> j) => WorkSet(
    id: j['id'] as String,
    start: DateTime.fromMillisecondsSinceEpoch(j['start'] as int),
    exerciseId: j['exerciseId'] as String,
    playerId: j['playerId'] as String?,
    sessionId: j['sessionId'] as String?,
    profileMark: ProfileMark.values.asNameMap()[j['profileMark']],
  );
}

/// Rango objetivo de intensidad, en % del 1RM (p. ej. 75–80 %).
class RmTarget {
  final double min;
  final double max;

  const RmTarget(this.min, this.max);

  double get mid => (min + max) / 2;

  bool contains(double percent) => percent >= min && percent <= max;

  List<double> toJson() => [min, max];

  /// null si el JSON no es un rango válido.
  static RmTarget? fromJson(Object? j) {
    if (j is! List || j.length != 2) return null;
    final [a, b] = j;
    if (a is! num || b is! num) return null;
    return RmTarget(a.toDouble(), b.toDouble());
  }

  @override
  bool operator ==(Object other) =>
      other is RmTarget && other.min == min && other.max == max;

  @override
  int get hashCode => Object.hash(min, max);
}

/// Pérdida de velocidad "sin límite": sin avisos de fatiga (la pérdida se
/// sigue mostrando como dato).
const double kNoLossLimit = double.infinity;

/// Pérdida de velocidad general de una sesión nueva sin sesión anterior.
const double kDefaultSessionLoss = 20;

Object _lossToJson(double v) => v.isInfinite ? 'off' : v;

double? _lossFromJson(Object? j) => switch (j) {
  'off' => kNoLossLimit,
  num n => n.toDouble(),
  _ => null,
};

/// Una sesión: "la convocatoria del día". Decide qué deportistas aparecen en
/// la cuadrícula y agrupa las series que se registran mientras está activa.
class TrainingSession {
  final String id;
  final String name;
  final DateTime start;

  /// Deportistas convocados, en el orden en que se añadieron.
  final List<String> playerIds;

  /// Intensidad objetivo por ejercicio (id → rango de %1RM).
  final Map<String, RmTarget> rmTargets;

  /// Pérdida de velocidad máxima (%) de toda la sesión; [kNoLossLimit] =
  /// sin límite.
  final double lossGeneral;

  /// Pérdida por ejercicio que sobrescribe [lossGeneral]: un valor o
  /// [kNoLossLimit]. Sin entrada, el ejercicio hereda la de la sesión.
  final Map<String, double> lossTargets;

  const TrainingSession({
    required this.id,
    required this.name,
    required this.start,
    this.playerIds = const [],
    this.rmTargets = const {},
    this.lossGeneral = kDefaultSessionLoss,
    this.lossTargets = const {},
  });

  TrainingSession copyWith({
    String? name,
    List<String>? playerIds,
    Map<String, RmTarget>? rmTargets,
    double? lossGeneral,
    Map<String, double>? lossTargets,
  }) => TrainingSession(
    id: id,
    name: name ?? this.name,
    start: start,
    playerIds: playerIds ?? this.playerIds,
    rmTargets: rmTargets ?? this.rmTargets,
    lossGeneral: lossGeneral ?? this.lossGeneral,
    lossTargets: lossTargets ?? this.lossTargets,
  );

  /// Pérdida que se aplica a [exerciseId] ([kNoLossLimit] = sin límite).
  double lossFor(String exerciseId) => lossTargets[exerciseId] ?? lossGeneral;

  /// Fija (o quita, con null) el objetivo de un ejercicio.
  TrainingSession withRmTarget(String exerciseId, RmTarget? t) => copyWith(
    rmTargets: {
      for (final e in rmTargets.entries)
        if (e.key != exerciseId) e.key: e.value,
      exerciseId: ?t,
    },
  );

  /// Sobrescribe la pérdida de un ejercicio (un valor o [kNoLossLimit]);
  /// null = heredar la de la sesión.
  TrainingSession withLossTarget(String exerciseId, double? loss) => copyWith(
    lossTargets: {
      for (final e in lossTargets.entries)
        if (e.key != exerciseId) e.key: e.value,
      exerciseId: ?loss,
    },
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'start': start.millisecondsSinceEpoch,
    'players': playerIds,
    if (rmTargets.isNotEmpty)
      'rmTargets': {for (final e in rmTargets.entries) e.key: e.value.toJson()},
    'lossGeneral': _lossToJson(lossGeneral),
    if (lossTargets.isNotEmpty)
      'lossTargets': {
        for (final e in lossTargets.entries) e.key: _lossToJson(e.value),
      },
  };

  /// [legacyLoss]: pérdida general para sesiones guardadas antes de que la
  /// tuvieran (la que había en los ajustes), para que su historial se siga
  /// coloreando igual.
  factory TrainingSession.fromJson(
    Map<String, Object?> j, {
    double legacyLoss = kDefaultSessionLoss,
  }) => TrainingSession(
    id: j['id'] as String,
    name: j['name'] as String,
    start: DateTime.fromMillisecondsSinceEpoch(j['start'] as int),
    playerIds: [
      for (final p in (j['players'] as List? ?? const [])) p as String,
    ],
    rmTargets: {
      for (final e in ((j['rmTargets'] as Map?) ?? const {}).entries)
        e.key as String: ?RmTarget.fromJson(e.value),
    },
    lossGeneral: _lossFromJson(j['lossGeneral']) ?? legacyLoss,
    lossTargets: {
      for (final e in ((j['lossTargets'] as Map?) ?? const {}).entries)
        e.key as String: ?_lossFromJson(e.value),
    },
  );
}

class Settings {
  /// Pérdida de velocidad que había en los ajustes antes de que viviera en
  /// la sesión. Solo sirve para migrar sesiones antiguas.
  final double legacyLossThreshold;

  /// Apagado general: si es false, sin colores de fatiga, sin aviso ni
  /// bocinazo en ninguna sesión.
  final bool fatigueEnabled;
  final VelocityMetric metric;
  final bool beepEachRep;
  final bool speakVelocity;
  final double loadStep;

  /// Avisar (voz o pitido) cuando una repetición tiene el ROM corto.
  final bool romAlerts;

  /// Análisis en vivo: comparar el 1RM del día con el del perfil.
  final bool compareProfileRm;

  /// Análisis en vivo: consejo de subir / mantener / bajar la carga.
  final bool loadAdvice;

  /// Análisis en vivo: consejo y zona con la relación genérica cuando el
  /// deportista no tiene perfil propio (o la serie no tiene deportista).
  final bool genericWithoutProfile;

  const Settings({
    this.legacyLossThreshold = 20,
    this.fatigueEnabled = true,
    this.metric = VelocityMetric.mpv,
    this.beepEachRep = true,
    this.speakVelocity = false,
    this.loadStep = 2.5,
    this.romAlerts = true,
    this.compareProfileRm = true,
    this.loadAdvice = true,
    this.genericWithoutProfile = true,
  });

  Settings copyWith({
    double? legacyLossThreshold,
    bool? fatigueEnabled,
    VelocityMetric? metric,
    bool? beepEachRep,
    bool? speakVelocity,
    double? loadStep,
    bool? romAlerts,
    bool? compareProfileRm,
    bool? loadAdvice,
    bool? genericWithoutProfile,
  }) => Settings(
    legacyLossThreshold: legacyLossThreshold ?? this.legacyLossThreshold,
    fatigueEnabled: fatigueEnabled ?? this.fatigueEnabled,
    metric: metric ?? this.metric,
    beepEachRep: beepEachRep ?? this.beepEachRep,
    speakVelocity: speakVelocity ?? this.speakVelocity,
    loadStep: loadStep ?? this.loadStep,
    romAlerts: romAlerts ?? this.romAlerts,
    compareProfileRm: compareProfileRm ?? this.compareProfileRm,
    loadAdvice: loadAdvice ?? this.loadAdvice,
    genericWithoutProfile: genericWithoutProfile ?? this.genericWithoutProfile,
  );

  Map<String, Object?> toJson() => {
    'loss': legacyLossThreshold,
    'fatigue': fatigueEnabled,
    'metric': metric.name,
    'beep': beepEachRep,
    'speak': speakVelocity,
    'loadStep': loadStep,
    'romAlerts': romAlerts,
    'compareRm': compareProfileRm,
    'advice': loadAdvice,
    'generic': genericWithoutProfile,
  };

  factory Settings.fromJson(Map<String, Object?> j) => Settings(
    legacyLossThreshold: (j['loss'] as num?)?.toDouble() ?? 20,
    fatigueEnabled: (j['fatigue'] as bool?) ?? true,
    metric: VelocityMetric.values.firstWhere(
      (m) => m.name == j['metric'],
      orElse: () => VelocityMetric.mpv,
    ),
    beepEachRep: (j['beep'] as bool?) ?? true,
    speakVelocity: (j['speak'] as bool?) ?? false,
    loadStep: (j['loadStep'] as num?)?.toDouble() ?? 2.5,
    romAlerts: (j['romAlerts'] as bool?) ?? true,
    compareProfileRm: (j['compareRm'] as bool?) ?? true,
    loadAdvice: (j['advice'] as bool?) ?? true,
    genericWithoutProfile: (j['generic'] as bool?) ?? true,
  );
}
