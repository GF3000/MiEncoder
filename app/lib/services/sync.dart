import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import 'auth.dart';
import 'repository.dart';

/// La nube, vista desde la sincronización. Abstracta para poder probar la
/// mezcla de datos sin Firestore.
abstract class SyncRemote {
  /// Documentos de [collection] modificados en el servidor desde
  /// [sinceMillis] (incluido; null = todos). Cada documento trae
  /// `syncedAt` en milisegundos de servidor.
  Future<List<Map<String, Object?>>> pull(
    String uid,
    String collection,
    int? sinceMillis,
  );

  /// Sube (sobrescribe) [docs]. El servidor les pone `syncedAt`.
  Future<void> push(
    String uid,
    String collection,
    List<Map<String, Object?>> docs,
  );
}

/// Resultado de una pasada de sincronización.
class SyncResult {
  final int pulled;
  final int pushed;
  const SyncResult(this.pulled, this.pushed);
  bool get changedLocal => pulled > 0;
}

/// Lógica de sincronización, sin temporizadores ni red.
///
/// Cada pasada: primero baja lo que cambió en la nube desde la última vez y
/// lo mezcla (gana el `updatedAt` más reciente); después sube lo pendiente.
/// Bajar antes evita sobrescribir en la nube una versión más nueva con un
/// cambio antiguo hecho sin conexión.
///
/// La primera vez que una cuenta sincroniza en esta tablet se sube todo lo
/// que había guardado (incluidos los datos de antes de tener cuenta).
class SyncEngine {
  final Repository repo;
  final SyncRemote remote;
  SyncEngine(this.repo, this.remote);

  Future<SyncResult> run(String uid) async {
    final log = <String>[];
    final state = Map<String, Object?>.of(await repo.syncState(uid));
    final cursors = Map<String, Object?>.of(
      (state['cursors'] as Map?)?.cast<String, Object?>() ?? const {},
    );

    var pulled = 0;
    for (final c in Repository.syncCollections) {
      final docs = await remote.pull(uid, c, cursors[c] as int?);
      log.add('$c↓${docs.length}');
      var cursor = cursors[c] as int?;
      for (final d in docs) {
        if (await repo.applyRemote(c, d)) pulled++;
        final at = d['syncedAt'] as int?;
        if (at != null && (cursor == null || at > cursor)) cursor = at;
      }
      cursors[c] = cursor;
      state['cursors'] = cursors;
      await repo.saveSyncState(uid, state);
    }

    final all = state['initialPushDone'] != true;
    log.add(all ? 'primera subida' : 'solo pendientes');
    var pushed = 0;
    for (final c in Repository.syncCollections) {
      final docs = await repo.outgoing(c, all: all);
      if (docs.isEmpty) continue;
      await remote.push(uid, c, docs);
      await repo.markSynced(c, docs);
      pushed += docs.length;
      log.add('$c↑${docs.length}');
    }
    state['initialPushDone'] = true;
    state['lastSync'] = DateTime.now().millisecondsSinceEpoch;
    await repo.saveSyncState(uid, state);
    debugPrint(
      'Sync ${uid.substring(0, math.min(6, uid.length))}:${log.join(' ')} · aplicados $pulled',
    );
    return SyncResult(pulled, pushed);
  }
}

/// Firestore: `users/{uid}/{collection}/{id}`.
class FirestoreRemote implements SyncRemote {
  final FirebaseFirestore db;
  FirestoreRemote(this.db);

  static const _page = 300;
  static const _batch = 400; // máximo de Firestore: 500 operaciones
  static const _timeout = Duration(seconds: 45);

  CollectionReference<Map<String, dynamic>> _col(String uid, String c) =>
      db.collection('users').doc(uid).collection(c);

  @override
  Future<List<Map<String, Object?>>> pull(
    String uid,
    String collection,
    int? sinceMillis,
  ) async {
    Query<Map<String, dynamic>> q = _col(uid, collection).orderBy('syncedAt');
    if (sinceMillis != null) {
      q = q.where(
        'syncedAt',
        isGreaterThanOrEqualTo: Timestamp.fromMillisecondsSinceEpoch(
          sinceMillis,
        ),
      );
    }
    final out = <Map<String, Object?>>[];
    DocumentSnapshot<Map<String, dynamic>>? last;
    while (true) {
      var page = q.limit(_page);
      if (last != null) page = page.startAfterDocument(last);
      final snap = await page
          .get(const GetOptions(source: Source.server))
          .timeout(_timeout);
      for (final d in snap.docs) {
        final m = _toLocal(d.data());
        m['id'] ??= d.id;
        out.add(m);
      }
      if (snap.docs.length < _page) break;
      last = snap.docs.last;
    }
    return out;
  }

  @override
  Future<void> push(
    String uid,
    String collection,
    List<Map<String, Object?>> docs,
  ) async {
    final col = _col(uid, collection);
    for (var i = 0; i < docs.length; i += _batch) {
      final batch = db.batch();
      for (final d in docs.skip(i).take(_batch)) {
        batch.set(col.doc(d['id'] as String), {
          ...d,
          'syncedAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit().timeout(_timeout);
    }
  }

  /// Convierte lo que devuelve Firestore a valores que sembast acepta.
  static Map<String, Object?> _toLocal(Map<String, dynamic> m) => {
    for (final e in m.entries) e.key: _value(e.value),
  };

  static Object? _value(Object? v) => switch (v) {
    Timestamp t => t.millisecondsSinceEpoch,
    Map m => {for (final e in m.entries) e.key as String: _value(e.value)},
    List l => [for (final x in l) _value(x)],
    _ => v,
  };
}

enum SyncPhase { off, idle, syncing, offline, error }

/// Decide cuándo sincronizar y publica el estado para la interfaz.
///
/// Sincroniza al iniciar sesión, al arrancar, al recuperar la conexión, al
/// volver a la app, un rato después de cada cambio local y cada pocos
/// minutos. Nunca bloquea: si no hay red, lo deja para la próxima.
class SyncService extends ChangeNotifier {
  final Repository repo;
  final AuthService auth;
  final SyncEngine engine;

  /// Se llama cuando han llegado cambios de la nube (recargar pantallas).
  final Future<void> Function() onRemoteChanges;

  final Duration debounce;
  final Duration period;

  SyncService({
    required this.repo,
    required this.auth,
    required SyncRemote remote,
    required this.onRemoteChanges,
    Stream<bool>? online,
    this.debounce = const Duration(seconds: 30),
    this.period = const Duration(minutes: 10),
  }) : engine = SyncEngine(repo, remote) {
    auth.addListener(_onAuth);
    _localSub = repo.localChanges.listen((_) => _onLocalChange());
    _onlineSub = (online ?? _connectivity()).listen((up) {
      if (up) syncSoon(const Duration(seconds: 2));
    });
    _timer = Timer.periodic(period, (_) => syncNow());
    _onAuth();
  }

  StreamSubscription<void>? _localSub;
  StreamSubscription<bool>? _onlineSub;
  Timer? _timer;
  Timer? _soon;
  String? _uid;
  bool _running = false;
  bool _again = false;

  SyncPhase phase = SyncPhase.off;
  DateTime? lastSync;
  int pending = 0;
  String? lastError;

  static Stream<bool> _connectivity() => Connectivity().onConnectivityChanged
      .map((r) => r.any((x) => x != ConnectivityResult.none));

  void _onAuth() {
    final uid = auth.user?.uid;
    if (uid == _uid) return;
    _uid = uid;
    if (uid == null) {
      phase = SyncPhase.off;
      lastSync = null;
      notifyListeners();
      return;
    }
    phase = SyncPhase.idle;
    repo.syncState(uid).then((s) {
      final t = s['lastSync'] as int?;
      lastSync = t == null ? null : DateTime.fromMillisecondsSinceEpoch(t);
      notifyListeners();
    });
    syncNow();
  }

  Timer? _countTimer;
  void _onLocalChange() {
    if (_uid == null) return;
    syncSoon(debounce);
    // Contar pendientes sin recalcular en cada repetición.
    _countTimer ??= Timer(const Duration(seconds: 1), () async {
      _countTimer = null;
      pending = await repo.pendingCount();
      notifyListeners();
    });
  }

  /// Sincroniza dentro de [delay] (reinicia la espera si ya había una).
  void syncSoon([Duration delay = const Duration(seconds: 2)]) {
    if (_uid == null) return;
    _soon?.cancel();
    _soon = Timer(delay, syncNow);
  }

  Future<void> syncNow() async {
    final uid = _uid;
    if (uid == null) return;
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    _soon?.cancel();
    phase = SyncPhase.syncing;
    notifyListeners();
    try {
      final r = await engine.run(uid);
      if (_uid != uid) return; // cerró sesión mientras tanto
      lastSync = DateTime.now();
      lastError = null;
      phase = SyncPhase.idle;
      if (r.changedLocal) await onRemoteChanges();
    } on FirebaseException catch (e) {
      final offline = e.code == 'unavailable' || e.code == 'deadline-exceeded';
      phase = offline ? SyncPhase.offline : SyncPhase.error;
      lastError = offline ? null : '${e.code}: ${e.message}';
      debugPrint('Sync: $e');
    } on TimeoutException {
      phase = SyncPhase.offline;
    } catch (e) {
      phase = SyncPhase.error;
      lastError = '$e';
      debugPrint('Sync: $e');
    } finally {
      _running = false;
      pending = await repo.pendingCount();
      notifyListeners();
      if (_again) {
        _again = false;
        syncSoon();
      }
    }
  }

  @override
  void dispose() {
    auth.removeListener(_onAuth);
    _localSub?.cancel();
    _onlineSub?.cancel();
    _timer?.cancel();
    _soon?.cancel();
    _countTimer?.cancel();
    super.dispose();
  }
}
