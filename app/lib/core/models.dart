// Modelos de datos. Se guardan como mapas JSON en sembast.

enum VelocityMetric { mpv, mv }

extension VelocityMetricLabel on VelocityMetric {
  String get label => this == VelocityMetric.mpv ? 'VMP' : 'VM';
}

class Player {
  final String id;
  final String name;
  final bool archived;

  const Player({required this.id, required this.name, this.archived = false});

  Player copyWith({String? name, bool? archived}) => Player(
    id: id,
    name: name ?? this.name,
    archived: archived ?? this.archived,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'archived': archived,
  };

  factory Player.fromJson(Map<String, Object?> j) => Player(
    id: j['id'] as String,
    name: j['name'] as String,
    archived: (j['archived'] as bool?) ?? false,
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

/// Una sesión: "la convocatoria del día". Decide qué deportistas aparecen en
/// la cuadrícula y agrupa las series que se registran mientras está activa.
class TrainingSession {
  final String id;
  final String name;
  final DateTime start;

  /// Deportistas convocados, en el orden en que se añadieron.
  final List<String> playerIds;

  const TrainingSession({
    required this.id,
    required this.name,
    required this.start,
    this.playerIds = const [],
  });

  TrainingSession copyWith({String? name, List<String>? playerIds}) =>
      TrainingSession(
        id: id,
        name: name ?? this.name,
        start: start,
        playerIds: playerIds ?? this.playerIds,
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'start': start.millisecondsSinceEpoch,
    'players': playerIds,
  };

  factory TrainingSession.fromJson(Map<String, Object?> j) => TrainingSession(
    id: j['id'] as String,
    name: j['name'] as String,
    start: DateTime.fromMillisecondsSinceEpoch(j['start'] as int),
    playerIds: [
      for (final p in (j['players'] as List? ?? const [])) p as String,
    ],
  );
}

class Settings {
  /// Pérdida de velocidad (%) a partir de la que se avisa.
  final double velocityLossThreshold;

  /// Si es false: sin colores de fatiga, sin aviso ni bocinazo.
  final bool fatigueEnabled;
  final VelocityMetric metric;
  final bool beepEachRep;
  final bool speakVelocity;
  final double loadStep;

  const Settings({
    this.velocityLossThreshold = 20,
    this.fatigueEnabled = true,
    this.metric = VelocityMetric.mpv,
    this.beepEachRep = true,
    this.speakVelocity = false,
    this.loadStep = 2.5,
  });

  Settings copyWith({
    double? velocityLossThreshold,
    bool? fatigueEnabled,
    VelocityMetric? metric,
    bool? beepEachRep,
    bool? speakVelocity,
    double? loadStep,
  }) => Settings(
    velocityLossThreshold: velocityLossThreshold ?? this.velocityLossThreshold,
    fatigueEnabled: fatigueEnabled ?? this.fatigueEnabled,
    metric: metric ?? this.metric,
    beepEachRep: beepEachRep ?? this.beepEachRep,
    speakVelocity: speakVelocity ?? this.speakVelocity,
    loadStep: loadStep ?? this.loadStep,
  );

  Map<String, Object?> toJson() => {
    'loss': velocityLossThreshold,
    'fatigue': fatigueEnabled,
    'metric': metric.name,
    'beep': beepEachRep,
    'speak': speakVelocity,
    'loadStep': loadStep,
  };

  factory Settings.fromJson(Map<String, Object?> j) => Settings(
    velocityLossThreshold: (j['loss'] as num?)?.toDouble() ?? 20,
    fatigueEnabled: (j['fatigue'] as bool?) ?? true,
    metric: VelocityMetric.values.firstWhere(
      (m) => m.name == j['metric'],
      orElse: () => VelocityMetric.mpv,
    ),
    beepEachRep: (j['beep'] as bool?) ?? true,
    speakVelocity: (j['speak'] as bool?) ?? false,
    loadStep: (j['loadStep'] as num?)?.toDouble() ?? 2.5,
  );
}
