import 'dart:async';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'core/analysis.dart';
import 'core/frame_parser.dart';
import 'core/models.dart';
import 'services/encoder.dart';
import 'services/feedback.dart';
import 'services/repository.dart';

final _idRandom = math.Random.secure();

/// Identificador único también entre tablets: instante en microsegundos
/// (ordena por creación) + 32 bits aleatorios de longitud fija (evita que dos
/// dispositivos generen el mismo id en el mismo instante).
String newId() =>
    '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
    '${_idRandom.nextInt(0x100000000).toRadixString(36).padLeft(7, '0')}';

/// Clave interna para "ningún deportista".
const String kNone = '_none';
String _key(String? playerId) => playerId ?? kNone;

/// Última repetición procesada, con lo necesario para pintarla.
class LiveRep {
  final Rep rep;
  final int indexInSet;
  final double lossPercent;
  final FatigueLevel level;
  const LiveRep(this.rep, this.indexInSet, this.lossPercent, this.level);
}

/// Repeticiones hechas con el deportista activo anterior, que el entrenador
/// puede pasar al nuevo de un toque ("se me olvidó cambiar").
class PendingReassign {
  final List<String> repIds;
  final String? fromPlayerId;
  final String? toPlayerId;
  const PendingReassign(this.repIds, this.fromPlayerId, this.toPlayerId);
}

/// Días de historial con los que se calcula la referencia del 1RM del día.
const int kDayRmWindowDays = 90;

/// Solo se ofrece reasignar si la última rep fue hace menos de esto.
const kPendingWindow = Duration(minutes: 2);

/// Lo que se borró, para poder deshacerlo.
class DeletedData {
  final List<WorkSet> sets;
  final List<Rep> reps;
  const DeletedData(this.sets, this.reps);
}

class AppController extends ChangeNotifier {
  final Repository repo;
  final FeedbackService feedback;
  final DateTime Function() clock;

  AppController({
    required this.repo,
    required this.feedback,
    EncoderSource? encoder,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now,
       _encoder = encoder ?? BleEncoderSource();

  EncoderSource _encoder;
  EncoderSource get encoder => _encoder;
  StreamSubscription<EncoderFrame>? _frameSub;
  bool get simulated => _encoder is SimulatedEncoderSource;

  Settings settings = const Settings();
  List<Player> players = [];
  List<Exercise> exercises = [];
  final List<WorkSet> sets = [];
  final List<Rep> reps = [];

  String exerciseId = kDefaultExercises.first.id;
  double loadKg = 40;

  /// Sesiones (la activa decide qué deportistas salen en la cuadrícula).
  final List<TrainingSession> sessions = [];
  String? activeSessionId;

  /// Deportista que está levantando ahora. null = "Ninguno".
  String? activePlayerId;

  /// Última carga usada por cada deportista (para rotaciones con cargas distintas).
  final Map<String, double> _loadByPlayer = {};

  /// Serie abierta de cada deportista (clave: id o [kNone]). Solo en memoria:
  /// al reabrir la app todas las series empiezan de cero.
  final Map<String, String> _openSet = {};

  /// Repeticiones registradas desde el último cambio de deportista activo.
  final List<String> _streak = [];

  String? _currentSetId;
  LiveRep? lastLive;

  // ------------------------------------------------------------ arranque

  Future<void> init() async {
    await initializeDateFormatting('es');
    await repo.migrate();
    settings = await repo.settings();
    players = await repo.players();
    exercises = await repo.exercises();
    sets
      ..clear()
      ..addAll(await repo.sets());
    reps
      ..clear()
      ..addAll(await repo.reps());
    sets.sort((a, b) => a.start.compareTo(b.start));
    reps.sort((a, b) => a.time.compareTo(b.time));

    final s = await repo.session();
    exerciseId = (s['exerciseId'] as String?) ?? exerciseId;
    if (!exercises.any((e) => e.id == exerciseId))
      exerciseId = exercises.first.id;
    loadKg = (s['load'] as num?)?.toDouble() ?? loadKg;
    activePlayerId = s['active'] as String?;
    if (playerById(activePlayerId)?.archived ?? true) activePlayerId = null;
    final lb = s['loadByPlayer'];
    if (lb is Map) {
      lb.forEach((k, v) => _loadByPlayer[k as String] = (v as num).toDouble());
    }

    sessions
      ..clear()
      ..addAll(await repo.sessions(legacyLoss: settings.legacyLossThreshold));
    sessions.sort((a, b) => a.start.compareTo(b.start));
    await _migrateSetsWithoutSession();
    activeSessionId = s['activeSession'] as String?;
    if (activeSession == null) {
      // Primera vez (o datos antiguos): seguir con la de hoy si existe.
      final today = sessions
          .where((x) => _sameDay(x.start, clock()))
          .lastOrNull;
      activeSessionId = today?.id ?? (await _createSession([])).id;
    }
    if (activePlayerId != null &&
        !activeSession!.playerIds.contains(activePlayerId)) {
      activePlayerId = null;
    }
    _saveSession(); // la sesión activa debe sobrevivir a un reinicio

    await feedback.init();
    _attachEncoder();
    notifyListeners();
  }

  /// Vuelve a leer los datos tras recibir cambios de otra tablet. Mantiene lo
  /// que se está haciendo ahora (deportista activo, serie abierta, carga).
  Future<void> reloadData() async {
    // Si se guarda algo mientras se lee, se vuelve a leer para no perderlo.
    for (var attempt = 0; attempt < 5; attempt++) {
      final v = repo.writeCount;
      final p = await repo.players();
      final e = await repo.exercises();
      final st = await repo.sets();
      final r = await repo.reps();
      final ss = await repo.sessions(legacyLoss: settings.legacyLossThreshold);
      if (repo.writeCount != v) continue;
      players = p;
      exercises = e;
      sets
        ..clear()
        ..addAll(st..sort((a, b) => a.start.compareTo(b.start)));
      reps
        ..clear()
        ..addAll(r..sort((a, b) => a.time.compareTo(b.time)));
      sessions
        ..clear()
        ..addAll(ss..sort((a, b) => a.start.compareTo(b.start)));
      break;
    }
    if (exercises.isNotEmpty && !exercises.any((e) => e.id == exerciseId)) {
      exerciseId = exercises.first.id;
    }
    if (activePlayerId != null && playerById(activePlayerId) == null) {
      activePlayerId = null;
    }
    _openSet.removeWhere((_, setId) => setById(setId) == null);
    if (setById(_currentSetId) == null) {
      _currentSetId = null;
      lastLive = null;
    }
    if (activeSession == null) {
      final today = sessions
          .where((x) => _sameDay(x.start, clock()))
          .lastOrNull;
      activeSessionId = today?.id ?? (await _createSession([])).id;
      _saveSession();
    }
    _refreshLive();
    notifyListeners();
  }

  void _attachEncoder() {
    _frameSub?.cancel();
    _frameSub = _encoder.frames.listen(onFrame);
    _encoder.status.addListener(_onStatus);
  }

  void _onStatus() {
    final connected =
        _encoder.status.value == EncoderStatus.connected ||
        _encoder.status.value == EncoderStatus.reconnecting;
    WakelockPlus.toggle(enable: connected).catchError((_) {});
    notifyListeners();
  }

  Future<void> useSimulator(bool on) async {
    if (on == simulated) return;
    await _encoder.disconnect();
    _encoder.status.removeListener(_onStatus);
    _encoder.dispose();
    _encoder = on ? SimulatedEncoderSource() : BleEncoderSource();
    _attachEncoder();
    notifyListeners();
  }

  void _saveSession() => repo.saveSession({
    'exerciseId': exerciseId,
    'load': loadKg,
    'active': activePlayerId,
    'loadByPlayer': Map<String, Object?>.from(_loadByPlayer),
    'activeSession': activeSessionId,
  });

  // ------------------------------------------------------------ consultas

  Player? playerById(String? id) =>
      id == null ? null : players.firstWhereOrNull((p) => p.id == id);
  Exercise exerciseById(String id) =>
      exercises.firstWhereOrNull((e) => e.id == id) ?? exercises.first;
  Exercise get exercise => exerciseById(exerciseId);
  List<Player> get activePlayers =>
      players.where((p) => !p.archived).toList()
        ..sort((a, b) => a.name.compareTo(b.name));

  WorkSet? setById(String? id) =>
      id == null ? null : sets.firstWhereOrNull((s) => s.id == id);
  List<Rep> repsOfSet(String setId) =>
      reps.where((r) => r.setId == setId).toList();
  Rep? repById(String id) => reps.firstWhereOrNull((r) => r.id == id);

  /// Serie que se está mostrando (la última en recibir una repetición).
  WorkSet? get currentSet => setById(_currentSetId);
  List<Rep> get currentSetReps =>
      _currentSetId == null ? const [] : repsOfSet(_currentSetId!);

  /// Series más recientes primero (por su última repetición).
  List<WorkSet> recentSets({int limit = 1 << 30}) {
    final lastTime = <String, DateTime>{};
    for (final r in reps) {
      lastTime[r.setId] = r.time;
    }
    final list = sets.where((s) => lastTime.containsKey(s.id)).toList()
      ..sort((a, b) => lastTime[b.id]!.compareTo(lastTime[a.id]!));
    return list.take(limit).toList();
  }

  double _setLoad(WorkSet s) => repsOfSet(s.id).firstOrNull?.loadKg ?? loadKg;

  /// Serie abierta válida para [playerId] con la carga y ejercicio dados.
  WorkSet? _openSetFor(String? playerId, double load, String exId) {
    final s = setById(_openSet[_key(playerId)]);
    if (s == null) return null;
    if (s.playerId != playerId) return null;
    if (!sameOpenSet(
      openLoad: _setLoad(s),
      openExerciseId: s.exerciseId,
      load: load,
      exerciseId: exId,
    )) {
      return null;
    }
    return s;
  }

  WorkSet _newSet(
    String? playerId,
    String exId,
    DateTime start, {
    bool open = true,
    bool inActiveSession = true,
    String? sessionId,
  }) {
    final s = WorkSet(
      id: newId(),
      start: start,
      exerciseId: exId,
      playerId: playerId,
      sessionId: inActiveSession ? activeSessionId : sessionId,
    );
    sets.add(s);
    repo.saveSet(s);
    if (open) _openSet[_key(playerId)] = s.id;
    return s;
  }

  // ------------------------------------------------------------ flujo en vivo

  void onFrame(EncoderFrame f) {
    final now = clock();
    final set =
        _openSetFor(activePlayerId, loadKg, exerciseId) ??
        _newSet(activePlayerId, exerciseId, now);
    _currentSetId = set.id;

    final rep = Rep(
      id: newId(),
      setId: set.id,
      time: now,
      romCm: f.romCm,
      mv: f.meanVelocity,
      mpv: f.meanPropulsiveVelocity,
      vmax: f.peakVelocity,
      vmaxTruncated: f.peakTruncated,
      loadKg: loadKg,
      exerciseId: exerciseId,
    );
    reps.add(rep);
    repo.saveRep(rep);
    _streak.add(rep.id);

    lastLive = _liveFor(rep);
    final rom = romRefForSet(set.id);
    feedback.onRep(
      level: lastLive!.level,
      beepEachRep: settings.beepEachRep,
      speak: settings.speakVelocity,
      velocity: rep.velocity(settings.metric),
      romShort:
          settings.romAlerts &&
          rom != null &&
          rom.statusOf(rep.romCm) == RomStatus.short,
    );
    notifyListeners();
  }

  /// Fatiga = pérdida respecto a la mejor repetición de la serie hasta ese
  /// momento (incluye las pausas de un cluster: la serie no se corta por tiempo).
  LiveRep _liveFor(Rep rep) {
    final setReps = repsOfSet(
      rep.setId,
    ).where((r) => !r.time.isAfter(rep.time)).toList();
    final best = setReps
        .map((r) => r.velocity(settings.metric))
        .reduce(math.max);
    final loss = velocityLossPercent(best, rep.velocity(settings.metric));
    return LiveRep(rep, setReps.length, loss, levelFor(loss, setId: rep.setId));
  }

  /// Cierra todas las series abiertas: la próxima repetición empieza serie.
  void forceNewSet() {
    _openSet.clear();
    _currentSetId = null;
    lastLive = null;
    notifyListeners();
  }

  /// Cambia el deportista activo (a priori). Devuelve las repeticiones hechas
  /// desde el último cambio, por si en realidad eran del nuevo (a posteriori).
  PendingReassign? setActive(String? playerId) {
    if (playerId == activePlayerId) return null;
    // Activar a alguien lo convoca si no lo estaba: nunca hay un deportista
    // activo fuera de la sesión.
    if (playerId != null && !isInSession(playerId)) {
      final s = activeSession;
      if (s != null) {
        final updated = s.copyWith(playerIds: [...s.playerIds, playerId]);
        sessions[sessions.indexWhere((x) => x.id == s.id)] = updated;
        repo.saveTrainingSession(updated);
      }
    }
    final lastTime = _streak.isEmpty ? null : repById(_streak.last)?.time;
    final recent =
        lastTime != null && clock().difference(lastTime) <= kPendingWindow;
    final pending = recent
        ? PendingReassign(List.of(_streak), activePlayerId, playerId)
        : null;
    _streak.clear();
    _loadByPlayer[_key(activePlayerId)] = loadKg;
    activePlayerId = playerId;
    loadKg = _loadByPlayer[_key(playerId)] ?? loadKg;
    final open = _openSetFor(playerId, loadKg, exerciseId);
    _currentSetId = open?.id;
    lastLive = null;
    _saveSession();
    notifyListeners();
    return pending;
  }

  /// "Se me olvidó cambiar": pasa esas repeticiones al deportista activo.
  Future<void> applyPending(PendingReassign p) async {
    for (final id in p.repIds) {
      await moveRep(id, p.toPlayerId, live: true);
    }
    // Siguen siendo "las recientes" del deportista activo.
    _streak
      ..clear()
      ..addAll(p.repIds.where((id) => repById(id) != null));
    final last = p.repIds.map(repById).whereType<Rep>().lastOrNull;
    if (last != null) {
      _currentSetId = last.setId;
      lastLive = _liveFor(last);
    }
    notifyListeners();
  }

  /// Mueve una repetición a otro deportista (o a ninguno).
  /// Se une a una serie de ese deportista con la misma carga y ejercicio si
  /// la hay cerca en el tiempo; si no, crea una.
  Future<void> moveRep(
    String repId,
    String? playerId, {
    bool live = false,
  }) async {
    final r = repById(repId);
    if (r == null) return;
    final source = setById(r.setId);
    if (source?.playerId == playerId) return;

    WorkSet? target = live
        ? _openSetFor(playerId, r.loadKg, r.exerciseId)
        : null;
    target ??= sets.firstWhereOrNull((s) {
      if (s.playerId != playerId ||
          s.exerciseId != r.exerciseId ||
          s.id == r.setId)
        return false;
      final rs = repsOfSet(s.id);
      if (rs.isEmpty || rs.first.loadKg != r.loadKg) return false;
      return rs.any(
        (x) => x.time.difference(r.time).abs() <= const Duration(minutes: 15),
      );
    });
    target ??= _newSet(
      playerId,
      r.exerciseId,
      r.time,
      open: live,
      inActiveSession: false,
      sessionId: source?.sessionId,
    );
    if (live) _openSet[_key(playerId)] = target.id;

    final moved = r.inSet(target.id);
    reps[reps.indexOf(r)] = moved;
    await repo.saveRep(moved);
    if (source != null && repsOfSet(source.id).isEmpty) {
      await _removeSet(source.id);
    }
    notifyListeners();
  }

  /// Reasigna una serie entera.
  void reassign(String setId, String? playerId) {
    final i = sets.indexWhere((s) => s.id == setId);
    if (i < 0) return;
    final old = sets[i];
    sets[i] = old.withPlayer(playerId);
    repo.saveSet(sets[i]);
    if (_openSet[_key(old.playerId)] == setId) {
      _openSet.remove(_key(old.playerId));
      _openSet.putIfAbsent(_key(playerId), () => setId);
    }
    notifyListeners();
  }

  Future<void> _removeSet(String setId) async {
    sets.removeWhere((s) => s.id == setId);
    reps.removeWhere((r) => r.setId == setId);
    _openSet.removeWhere((_, v) => v == setId);
    if (_currentSetId == setId) {
      _currentSetId = null;
      lastLive = null;
    }
    await repo.deleteSet(setId);
  }

  /// Borra una serie. Devuelve lo borrado para poder deshacer con [restore].
  Future<DeletedData?> deleteSet(String setId) async {
    final s = setById(setId);
    if (s == null) return null;
    final snapshot = DeletedData([s], repsOfSet(setId));
    await _removeSet(setId);
    notifyListeners();
    return snapshot;
  }

  /// Borra una repetición suelta (p. ej. mal anotada). Si la serie queda
  /// vacía, se borra también. Devuelve lo borrado para poder deshacer.
  Future<DeletedData?> deleteRep(String repId) async {
    final r = repById(repId);
    if (r == null) return null;
    final s = setById(r.setId);
    reps.remove(r);
    _streak.remove(r.id);
    await repo.deleteRep(r.id);
    var setGone = false;
    if (s != null && repsOfSet(s.id).isEmpty) {
      await _removeSet(s.id);
      setGone = true;
    }
    _refreshLive();
    notifyListeners();
    return DeletedData(setGone && s != null ? [s] : const [], [r]);
  }

  /// Borra la última repetición registrada.
  Future<DeletedData?> undoLastRep() async {
    final last = reps.lastOrNull;
    return last == null ? null : deleteRep(last.id);
  }

  /// Deshace un borrado.
  Future<void> restore(DeletedData d) async {
    for (final s in d.sets) {
      if (setById(s.id) == null) {
        sets.add(s);
        await repo.saveSet(s);
      }
    }
    for (final r in d.reps) {
      if (repById(r.id) == null && setById(r.setId) != null) {
        reps.add(r);
        await repo.saveRep(r);
      }
    }
    sets.sort((a, b) => a.start.compareTo(b.start));
    reps.sort((a, b) => a.time.compareTo(b.time));
    _refreshLive();
    notifyListeners();
  }

  /// Recalcula la tarjeta en vivo con la última rep de la serie mostrada.
  void _refreshLive() {
    final last = currentSetReps.lastOrNull;
    lastLive = last == null ? null : _liveFor(last);
  }

  void setLoad(double kg) {
    loadKg = (kg.clamp(0, 999) * 10).round() / 10;
    _loadByPlayer[_key(activePlayerId)] = loadKg;
    _saveSession();
    notifyListeners();
  }

  void setExercise(String id) {
    exerciseId = id;
    _saveSession();
    notifyListeners();
  }

  // ------------------------------------------------------------ sesiones

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Nombre por defecto: "Mié 11 nov".
  static String defaultSessionName(DateTime d) {
    final s = DateFormat('EEE d MMM', 'es').format(d).replaceAll('.', '');
    return s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
  }

  TrainingSession? get activeSession =>
      sessions.firstWhereOrNull((s) => s.id == activeSessionId);

  TrainingSession? sessionById(String? id) =>
      id == null ? null : sessions.firstWhereOrNull((s) => s.id == id);

  /// Deportistas convocados en la sesión activa (en orden de convocatoria).
  List<Player> get sessionPlayers => [
    for (final id in activeSession?.playerIds ?? const <String>[])
      if (playerById(id) case final p? when !p.archived) p,
  ];

  bool isInSession(String playerId) =>
      activeSession?.playerIds.contains(playerId) ?? false;

  /// Sesiones más recientes primero.
  List<TrainingSession> get recentSessions =>
      sessions.reversed.toList(growable: false);

  int setsInSession(String sessionId) => sets
      .where((s) => s.sessionId == sessionId && repsOfSet(s.id).isNotEmpty)
      .length;

  /// La sesión activa empezó otro día (para preguntar al abrir la app).
  bool get activeSessionIsFromAnotherDay {
    final s = activeSession;
    return s != null && !_sameDay(s.start, clock());
  }

  /// Crea una sesión. La pérdida de velocidad general se copia de la sesión
  /// activa (o la última); los objetivos por ejercicio no se copian.
  Future<TrainingSession> _createSession(
    List<String> playerIds, {
    String? name,
  }) async {
    final now = clock();
    final s = TrainingSession(
      id: newId(),
      name: name ?? defaultSessionName(now),
      start: now,
      playerIds: playerIds,
      lossGeneral:
          (activeSession ?? sessions.lastOrNull)?.lossGeneral ??
          kDefaultSessionLoss,
    );
    sessions.add(s);
    await repo.saveTrainingSession(s);
    return s;
  }

  Future<void> _replaceSession(TrainingSession s) async {
    final i = sessions.indexWhere((x) => x.id == s.id);
    if (i >= 0) sessions[i] = s;
    await repo.saveTrainingSession(s);
  }

  /// Empieza una sesión nueva (opcionalmente con los convocados de la actual).
  Future<TrainingSession> newSession({
    bool copyPlayers = true,
    String? name,
  }) async {
    final players = copyPlayers
        ? List.of(activeSession?.playerIds ?? const <String>[])
        : <String>[];
    final s = await _createSession(players, name: name);
    _switchTo(s.id);
    return s;
  }

  /// Retoma una sesión anterior con sus convocados.
  void resumeSession(String id) {
    if (sessionById(id) == null || id == activeSessionId) return;
    _switchTo(id);
  }

  void _switchTo(String id) {
    activeSessionId = id;
    _openSet.clear(); // las series no cruzan sesiones
    _streak.clear();
    _currentSetId = null;
    lastLive = null;
    if (activePlayerId != null && !isInSession(activePlayerId!)) {
      activePlayerId = null;
    }
    _saveSession();
    notifyListeners();
  }

  Future<void> renameSession(String id, String name) async {
    final s = sessionById(id);
    if (s == null || name.trim().isEmpty) return;
    await _replaceSession(s.copyWith(name: name.trim()));
    notifyListeners();
  }

  /// Convoca a un deportista en la sesión activa.
  Future<void> addToSession(String playerId) async {
    final s = activeSession;
    if (s == null || s.playerIds.contains(playerId)) return;
    await _replaceSession(s.copyWith(playerIds: [...s.playerIds, playerId]));
    notifyListeners();
  }

  /// Quita a un deportista de la sesión activa (no lo borra).
  Future<void> removeFromSession(String playerId) async {
    final s = activeSession;
    if (s == null || !s.playerIds.contains(playerId)) return;
    if (activePlayerId == playerId) setActive(null);
    await _replaceSession(
      s.copyWith(playerIds: s.playerIds.where((x) => x != playerId).toList()),
    );
    notifyListeners();
  }

  /// Crea un deportista y lo convoca en un solo paso.
  Future<Player> createAndAddToSession(String name) async {
    final p = await addPlayer(name);
    await addToSession(p.id);
    return p;
  }

  /// Series antiguas sin sesión: una sesión "histórica" por día, con sus
  /// deportistas. Los puntos manuales (sin repeticiones con ROM) se dejan fuera.
  Future<void> _migrateSetsWithoutSession() async {
    final orphan = sets.where((s) => s.sessionId == null).toList();
    if (orphan.isEmpty) return;
    final byDay = <DateTime, List<WorkSet>>{};
    for (final s in orphan) {
      final rs = repsOfSet(s.id);
      final manual = rs.isNotEmpty && rs.every((r) => r.romCm == 0);
      if (manual) continue;
      final d = DateTime(s.start.year, s.start.month, s.start.day);
      byDay.putIfAbsent(d, () => []).add(s);
    }
    for (final entry in byDay.entries) {
      final playerIds = <String>[];
      for (final s in entry.value) {
        if (s.playerId != null && !playerIds.contains(s.playerId)) {
          playerIds.add(s.playerId!);
        }
      }
      final session = TrainingSession(
        id: newId(),
        name: defaultSessionName(entry.key),
        start: entry.value
            .map((s) => s.start)
            .reduce((a, b) => a.isBefore(b) ? a : b),
        playerIds: playerIds,
        lossGeneral: settings.legacyLossThreshold,
      );
      sessions.add(session);
      await repo.saveTrainingSession(session);
      for (final s in entry.value) {
        final i = sets.indexWhere((x) => x.id == s.id);
        sets[i] = s.withSession(session.id);
        await repo.saveSet(sets[i]);
      }
    }
    sessions.sort((a, b) => a.start.compareTo(b.start));
  }

  // ------------------------------------------------------------ jugadores / ejercicios / ajustes

  Future<Player> addPlayer(String name) async {
    final p = Player(id: newId(), name: name.trim());
    players.add(p);
    await repo.savePlayer(p);
    notifyListeners();
    return p;
  }

  Future<void> updatePlayer(Player p) async {
    final i = players.indexWhere((x) => x.id == p.id);
    if (i >= 0) players[i] = p;
    if (p.archived && activePlayerId == p.id) setActive(null);
    await repo.savePlayer(p);
    notifyListeners();
  }

  Future<Exercise> addExercise(String name, double mvt) async {
    final e = Exercise(id: newId(), name: name.trim(), mvt: mvt);
    exercises.add(e);
    await repo.saveExercise(e);
    notifyListeners();
    return e;
  }

  Future<void> updateExercise(Exercise e) async {
    final i = exercises.indexWhere((x) => x.id == e.id);
    if (i >= 0) exercises[i] = e;
    await repo.saveExercise(e);
    notifyListeners();
  }

  Future<void> updateSettings(Settings s) async {
    settings = s;
    await repo.saveSettings(s);
    notifyListeners();
  }

  /// Nivel de fatiga con el umbral de la serie [setId] (ver
  /// [lossThresholdForSet]). [FatigueLevel.off] si está apagada en los
  /// ajustes o no hay límite.
  FatigueLevel levelFor(double lossPercent, {String? setId}) {
    final t = settings.fatigueEnabled ? lossThresholdForSet(setId) : null;
    return t == null ? FatigueLevel.off : fatigueLevel(lossPercent, t);
  }

  /// Pérdida de velocidad máxima (%) para la serie [setId]: la del
  /// ejercicio en su sesión si la sobrescribe, si no la general de la
  /// sesión. Sin serie, la del ejercicio actual en la sesión activa. null =
  /// sin límite.
  double? lossThresholdForSet(String? setId) {
    final s = setId == null ? null : setById(setId);
    final session = s == null ? activeSession : sessionById(s.sessionId);
    final loss =
        session?.lossFor(s?.exerciseId ?? exerciseId) ?? kDefaultSessionLoss;
    return loss.isInfinite ? null : loss;
  }

  int setsOfPlayer(String playerId) =>
      sets.where((s) => s.playerId == playerId).length;
  int setsOfExercise(String exerciseId) =>
      sets.where((s) => s.exerciseId == exerciseId).length;

  /// Borra un deportista. Con [deleteData] borra también sus series; si no,
  /// sus series quedan como "Ninguno" (no se pierde ninguna repetición).
  Future<void> deletePlayer(String playerId, {required bool deleteData}) async {
    if (activePlayerId == playerId) setActive(null);
    final own = sets.where((s) => s.playerId == playerId).toList();
    for (final s in own) {
      if (deleteData) {
        await _removeSet(s.id);
      } else {
        reassign(s.id, null);
      }
    }
    _openSet.remove(playerId);
    _loadByPlayer.remove(playerId);
    for (var i = 0; i < sessions.length; i++) {
      if (sessions[i].playerIds.contains(playerId)) {
        sessions[i] = sessions[i].copyWith(
          playerIds: sessions[i].playerIds.where((x) => x != playerId).toList(),
        );
        await repo.saveTrainingSession(sessions[i]);
      }
    }
    players.removeWhere((p) => p.id == playerId);
    await repo.deletePlayer(playerId);
    _saveSession();
    notifyListeners();
  }

  /// Borra un ejercicio y todas sus series. Siempre queda al menos uno.
  Future<bool> deleteExercise(String id) async {
    if (exercises.length <= 1) return false;
    for (final s in sets.where((s) => s.exerciseId == id).toList()) {
      await _removeSet(s.id);
    }
    exercises.removeWhere((e) => e.id == id);
    await repo.deleteExercise(id);
    if (exerciseId == id) exerciseId = exercises.first.id;
    _saveSession();
    notifyListeners();
    return true;
  }

  // ------------------------------------------------------------ perfil

  List<Rep> repsFor({
    required String playerId,
    required String exerciseId,
    DateTime? since,
  }) {
    final setIds = sets
        .where((s) => s.playerId == playerId && s.exerciseId == exerciseId)
        .map((s) => s.id)
        .toSet();
    return reps
        .where(
          (r) =>
              setIds.contains(r.setId) &&
              (since == null || !r.time.isBefore(since)),
        )
        .toList();
  }

  /// Para cada jugador, los ejercicios en los que tiene al menos una
  /// repetición registrada (medida del encoder o punto manual).
  Map<String, Set<String>> exercisesWithRepsByPlayer() {
    final setById = {for (final s in sets) s.id: s};
    final out = <String, Set<String>>{};
    for (final r in reps) {
      final s = setById[r.setId];
      final pid = s?.playerId;
      if (pid == null) continue; // serie sin asignar
      (out[pid] ??= <String>{}).add(s!.exerciseId);
    }
    return out;
  }

  /// Perfil carga-velocidad de un deportista en un ejercicio, con los datos
  /// raros descartados y las marcas manuales aplicadas.
  LvAnalysis profileFor({
    required String playerId,
    required String exerciseId,
    DateTime? since,
  }) => analyzeLoadVelocity(
    withValidRom(
      repsFor(playerId: playerId, exerciseId: exerciseId, since: since),
      romRefFor(playerId, exerciseId),
    ),
    settings.metric,
    marks: _profileMarks,
  );

  Map<String, ProfileMark> get _profileMarks => {
    for (final s in sets)
      if (s.profileMark != null) s.id: s.profileMark!,
  };

  /// Referencias del 1RM del día, por (deportista, ejercicio, día). Se
  /// vacían en cada cambio de datos (ver [notifyListeners]).
  final Map<(String, String, DateTime), DayRmReference?> _dayRmRefs = {};

  /// Referencias de ROM, por (deportista, ejercicio, día o null = todo).
  final Map<(String, String, DateTime?), RomReference?> _romRefs = {};

  @override
  void notifyListeners() {
    _dayRmRefs.clear();
    _romRefs.clear();
    super.notifyListeners();
  }

  /// ROM de referencia de [playerId] en [exerciseId]: el objetivo manual si
  /// lo hay; si no, la mediana de los [kDayRmWindowDays] días ANTERIORES a
  /// [day] (con [day] null, de todos los datos: para el perfil).
  RomReference? romRefFor(String playerId, String exerciseId, [DateTime? day]) {
    final key = (playerId, exerciseId, day);
    if (_romRefs.containsKey(key)) return _romRefs[key];
    var history = repsFor(
      playerId: playerId,
      exerciseId: exerciseId,
      since: day?.subtract(const Duration(days: kDayRmWindowDays)),
    );
    if (day != null) {
      history = history.where((r) => r.time.isBefore(day)).toList();
    }
    return _romRefs[key] = romReference(
      history,
      manualTarget: playerById(playerId)?.romTargets[exerciseId],
    );
  }

  /// ROM de referencia con el que se juzga la serie [setId] (la de su día).
  RomReference? romRefForSet(String setId) {
    final s = setById(setId);
    final playerId = s?.playerId;
    if (s == null || playerId == null) return null;
    final t = repsOfSet(setId).firstOrNull?.time ?? s.start;
    return romRefFor(playerId, s.exerciseId, DateTime(t.year, t.month, t.day));
  }

  /// Fija (cm) o quita (null = automático) el ROM objetivo de un deportista.
  Future<void> setRomTarget(
    String playerId,
    String exerciseId,
    double? cm,
  ) async {
    final p = playerById(playerId);
    if (p == null) return;
    await updatePlayer(p.withRomTarget(exerciseId, cm));
  }

  /// Referencia del 1RM del día para la serie [setId]: el perfil del
  /// deportista con los datos de los [kDayRmWindowDays] días ANTERIORES a
  /// ese día (las series del propio día no cuentan: si no, un día malo
  /// bajaría la referencia y dejaría de verse).
  DayRmReference? _dayRmRefForSet(String setId) {
    final s = setById(setId);
    final playerId = s?.playerId;
    if (s == null || playerId == null) return null;
    final t = repsOfSet(setId).firstOrNull?.time ?? s.start;
    final day = DateTime(t.year, t.month, t.day);
    final key = (playerId, s.exerciseId, day);
    if (_dayRmRefs.containsKey(key)) return _dayRmRefs[key];
    return _dayRmRefs[key] = dayRmReference(
      repsFor(
        playerId: playerId,
        exerciseId: s.exerciseId,
        since: day.subtract(const Duration(days: kDayRmWindowDays)),
      ).where((r) => r.time.isBefore(day)).toList(),
      settings.metric,
      exerciseById(s.exerciseId).mvt,
      marks: _profileMarks,
      rom: romRefFor(playerId, s.exerciseId, day),
    );
  }

  /// 1RM del día que indica la serie [setId], comparado con el perfil del
  /// deportista (ver [_dayRmRefForSet]). null si no se puede estimar.
  DayRmEstimate? dayRmFor(String setId) {
    final setReps = repsOfSet(setId);
    if (setReps.isEmpty) return null;
    final ref = _dayRmRefForSet(setId);
    if (ref == null) return null;
    return estimateDayRm(
      setReps,
      ref,
      settings.metric,
      rom: romRefForSet(setId),
    );
  }

  // ------------------------------------------------------------ %1RM objetivo

  /// Objetivo de intensidad de la sesión de la serie [setId] para su
  /// ejercicio, o null si no hay.
  RmTarget? rmTargetForSet(String setId) {
    final s = setById(setId);
    if (s == null) return null;
    return sessionById(s.sessionId)?.rmTargets[s.exerciseId];
  }

  /// Fija (o quita, con null) el %1RM objetivo de [exerciseId] en la sesión
  /// activa.
  Future<void> setRmTarget(String exerciseId, RmTarget? target) =>
      setSessionTarget([exerciseId], rm: target, loss: _keep);

  /// Fija el objetivo de la sesión activa para [exerciseIds]: rango de %1RM
  /// ([rm], null = sin objetivo) y pérdida de velocidad máxima ([loss]: un
  /// valor, [kNoLossLimit], o null = heredar la de la sesión).
  Future<void> setSessionTarget(
    List<String> exerciseIds, {
    Object? rm = _keep,
    Object? loss = _keep,
  }) async {
    var s = activeSession;
    if (s == null) return;
    for (final id in exerciseIds) {
      if (rm != _keep) s = s!.withRmTarget(id, rm as RmTarget?);
      if (loss != _keep) s = s!.withLossTarget(id, loss as double?);
    }
    await _replaceSession(s!);
    notifyListeners();
  }

  static const _keep = Object();

  /// Cambia la pérdida de velocidad general de la sesión activa
  /// ([kNoLossLimit] = sin límite).
  Future<void> setSessionLoss(double loss) async {
    final s = activeSession;
    if (s == null || s.lossGeneral == loss) return;
    await _replaceSession(s.copyWith(lossGeneral: loss));
    notifyListeners();
  }

  /// «Guardar en todos»: copia [rm] a todos los ejercicios y, para la
  /// pérdida, la pone como general de la sesión ([loss] null = dejar la
  /// general como está) y quita las sobrescrituras por ejercicio.
  Future<void> applyTargetToAll({RmTarget? rm, double? loss}) async {
    var s = activeSession;
    if (s == null) return;
    for (final e in exercises) {
      s = s!.withRmTarget(e.id, rm);
    }
    s = s!.copyWith(lossGeneral: loss ?? s.lossGeneral, lossTargets: const {});
    await _replaceSession(s);
    notifyListeners();
  }

  /// Series del mismo deportista (o sin asignar), ejercicio, sesión y día
  /// que [setId], hasta ella incluida.
  Iterable<String> _daySetsUpTo(String setId) {
    final s = setById(setId);
    final t = repsOfSet(setId).firstOrNull?.time;
    if (s == null || t == null) return const [];
    return [
      for (final x in sets)
        if (x.playerId == s.playerId &&
            x.exerciseId == s.exerciseId &&
            x.sessionId == s.sessionId)
          if (repsOfSet(x.id).firstOrNull?.time case final u?
              when _sameDay(u, t) && !u.isAfter(t))
            x.id,
    ];
  }

  /// 1RM del día FIJADO para la serie [setId]: el máximo de los 1RM que
  /// indican las series válidas de ese día hasta ella. La fatiga entre
  /// series no lo baja (sí lo sube una serie más rápida). Con perfil propio
  /// sale de [dayRmFor]; sin él, de la relación genérica ([generic] true).
  /// null si aún no hay ninguna serie válida.
  ({double rm, bool generic})? fixedDayRmFor(String setId) {
    final s = setById(setId);
    if (s == null) return null;
    final withProfile = _dayRmRefForSet(setId) != null;
    if (!withProfile && !settings.genericWithoutProfile) return null;
    final mvt = exerciseById(s.exerciseId).mvt;
    double? best;
    for (final id in _daySetsUpTo(setId)) {
      final e1 = withProfile ? dayRmFor(id)?.e1Rm : _genericE1Rm(id, mvt);
      if (e1 != null && e1.isFinite && (best == null || e1 > best)) best = e1;
    }
    return best == null ? null : (rm: best, generic: !withProfile);
  }

  double? _genericE1Rm(String setId, double mvt) {
    final reps = repsOfSet(setId);
    final valid = withValidRom(reps, romRefForSet(setId));
    return genericE1Rm(valid.length >= 2 ? valid : reps, settings.metric, mvt);
  }

  /// Consejo de carga tras la serie [setId] según el objetivo de su sesión,
  /// sobre el 1RM del día fijado ([fixedDayRmFor]). null si está apagado en
  /// los ajustes, sin objetivo o sin dato.
  LoadAdvice? loadAdviceFor(String setId) {
    if (!settings.loadAdvice) return null;
    final target = rmTargetForSet(setId);
    if (target == null) return null;
    final load = repsOfSet(setId).firstOrNull?.loadKg ?? 0;
    if (load <= 0) return null;
    final day = fixedDayRmFor(setId);
    if (day == null) return null;
    return loadAdvice(
      load: load,
      dayRm: day.rm,
      target: target,
      step: settings.loadStep,
      generic: day.generic,
    );
  }

  /// Velocidades de serie (lenta, rápida) que corresponden al objetivo con
  /// la carga de [setId]: con el perfil del deportista o, si no tiene (y
  /// está activado en los ajustes), con la relación genérica. null sin
  /// objetivo.
  (double, double)? velocityZoneFor(String setId) {
    final target = rmTargetForSet(setId);
    final s = setById(setId);
    final load = repsOfSet(setId).firstOrNull?.loadKg;
    if (target == null || s == null || load == null || load <= 0) return null;
    final ref = _dayRmRefForSet(setId);
    if (ref != null) return ref.velocityZone(load, target);
    if (!settings.genericWithoutProfile) return null;
    final mvt = exerciseById(s.exerciseId).mvt;
    return (
      genericVelocityAt(target.max, mvt),
      genericVelocityAt(target.min, mvt),
    );
  }

  /// Incluye o excluye a mano una serie del perfil (null = que decida la app).
  void setProfileMark(String setId, ProfileMark? mark) {
    final i = sets.indexWhere((s) => s.id == setId);
    if (i < 0 || sets[i].profileMark == mark) return;
    sets[i] = sets[i].withProfileMark(mark);
    repo.saveSet(sets[i]);
    notifyListeners();
  }

  /// Punto añadido a mano (p. ej. una medición hecha en otro sitio).
  Future<void> addManualPoint({
    required String playerId,
    required String exerciseId,
    required double loadKg,
    required double velocity,
    required DateTime date,
  }) async {
    final s = _newSet(
      playerId,
      exerciseId,
      date,
      open: false,
      inActiveSession: false,
    );
    final r = Rep(
      id: newId(),
      setId: s.id,
      time: date,
      romCm: 0,
      mv: velocity,
      mpv: velocity,
      loadKg: loadKg,
      exerciseId: exerciseId,
    );
    reps.add(r);
    sets.sort((a, b) => a.start.compareTo(b.start));
    reps.sort((a, b) => a.time.compareTo(b.time));
    await repo.saveRep(r);
    notifyListeners();
  }

  // ------------------------------------------------------------ exportar

  String exportCsv() {
    final b = StringBuffer(
      'fecha;jugador;ejercicio;serie;rep;carga_kg;rom_cm;vm;vmp;vmax;vmax_truncada;potencia_w\n',
    );
    for (final s in sets) {
      final rs = repsOfSet(s.id);
      for (var i = 0; i < rs.length; i++) {
        final r = rs[i];
        b.writeln(
          [
            r.time.toIso8601String(),
            playerById(s.playerId)?.name ?? '',
            exerciseById(s.exerciseId).name,
            s.id,
            i + 1,
            r.loadKg,
            r.romCm,
            r.mv,
            r.mpv,
            r.vmax ?? '',
            r.vmaxTruncated ? 'si' : 'no',
            r.meanPowerW.round(),
          ].join(';'),
        );
      }
    }
    return b.toString();
  }

  @override
  void dispose() {
    _frameSub?.cancel();
    _encoder.dispose();
    feedback.dispose();
    super.dispose();
  }
}
