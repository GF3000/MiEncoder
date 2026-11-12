import 'dart:async';

import 'package:sembast/sembast.dart';

import '../core/models.dart';

typedef _Store = StoreRef<String, Map<String, Object?>>;

/// Persistencia local. Todo vive en el dispositivo; es la fuente de verdad.
///
/// Preparado para sincronizar con la nube: cada registro sincronizable lleva
/// campos de control que añade este repositorio (los modelos no los ven):
///
/// - `updatedAt`: milisegundos de la última modificación. Al mezclar datos de
///   otra tablet gana la versión más reciente.
/// - `deleted`: los borrados no eliminan el registro, lo sustituyen por una
///   "lápida" (`{id, deleted: true, updatedAt}`) para que el borrado también
///   llegue a los demás dispositivos. Las lecturas las ignoran.
/// - `dirty`: cambiado en esta tablet y aún no subido a la nube.
///
/// Las repeticiones no se suben sueltas: viajan dentro de su serie. Por eso
/// cambiar o borrar una repetición marca su serie como pendiente.
///
/// La tienda `meta` (ajustes, sesión en curso, estado de sincronización) es
/// propia de cada tablet y no lleva estos campos.
class Repository {
  final Database db;

  /// Reloj en milisegundos. Inyectable para los tests.
  final int Function() clock;

  Repository(this.db, {int Function()? clock})
    : clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  static final _players = stringMapStoreFactory.store('players');
  static final _exercises = stringMapStoreFactory.store('exercises');
  static final _sets = stringMapStoreFactory.store('sets');
  static final _reps = stringMapStoreFactory.store('reps');
  static final _meta = stringMapStoreFactory.store('meta');
  static final _sessions = stringMapStoreFactory.store('sessions');

  /// Tiendas con campos de control.
  static final _controlled = [_players, _exercises, _sets, _reps, _sessions];

  /// Colecciones que se suben a la nube (las repeticiones van en `sets`).
  static const syncCollections = ['players', 'exercises', 'sessions', 'sets'];

  static const kUpdatedAt = 'updatedAt';
  static const kDeleted = 'deleted';
  static const kDirty = 'dirty';

  /// Versión del formato de datos guardada en `meta/schema`.
  /// 1 = original (sin campos de control). 2 = con `updatedAt` y `deleted`.
  static const schemaVersion = 2;

  // ------------------------------------------------------- avisos de cambios

  final _changes = StreamController<void>.broadcast();

  /// Emite cada vez que se guarda o borra algo desde esta tablet (no cuando
  /// llegan datos de la nube).
  Stream<void> get localChanges => _changes.stream;

  /// Número de escrituras locales. Sirve para detectar si hubo cambios
  /// mientras se recargaban los datos.
  int writeCount = 0;

  void _changed() {
    writeCount++;
    _changes.add(null);
  }

  // ---------------------------------------------------------------- migración

  /// Pone al día los datos guardados con versiones anteriores de la app.
  /// Es idempotente: se puede llamar en cada arranque.
  Future<void> migrate() async {
    final current =
        ((await _meta.record('schema').get(db))?['version'] as int?) ?? 1;
    if (current >= schemaVersion) return;
    final now = clock();
    await db.transaction((tx) async {
      for (final store in _controlled) {
        for (final r in await store.find(tx)) {
          if (r.value[kUpdatedAt] is int) continue;
          await store.record(r.key).put(tx, {
            ...r.value,
            kUpdatedAt: now,
            kDeleted: false,
          });
        }
      }
      await _meta.record('schema').put(tx, {'version': schemaVersion});
    });
  }

  // ----------------------------------------------------------------- internos

  Future<void> _put(
    _Store store,
    String id,
    Map<String, Object?> json, {
    DatabaseClient? client,
    int? updatedAt,
    bool dirty = true,
  }) async {
    await store.record(id).put(client ?? db, {
      ...json,
      kUpdatedAt: updatedAt ?? clock(),
      kDeleted: false,
      kDirty: dirty,
    });
    _changed();
  }

  Future<void> _tombstone(
    _Store store,
    String id, {
    DatabaseClient? client,
    bool dirty = true,
  }) async {
    await store.record(id).put(client ?? db, {
      'id': id,
      kUpdatedAt: clock(),
      kDeleted: true,
      kDirty: dirty,
    });
    _changed();
  }

  /// Marca una serie como modificada (cambió alguna de sus repeticiones).
  Future<void> _touchSet(DatabaseClient client, String? setId) async {
    if (setId == null) return;
    final rec = await _sets.record(setId).get(client);
    if (rec == null || rec[kDeleted] == true) return;
    await _sets.record(setId).put(client, {
      ...rec,
      kUpdatedAt: clock(),
      kDirty: true,
    });
  }

  Future<List<Map<String, Object?>>> _live(_Store store) async => [
    for (final r in await store.find(db))
      if (r.value[kDeleted] != true) r.value,
  ];

  // ------------------------------------------------------------- deportistas

  Future<List<Player>> players() async =>
      (await _live(_players)).map(Player.fromJson).toList();

  Future<void> savePlayer(Player p) => _put(_players, p.id, p.toJson());

  Future<void> deletePlayer(String id) => _tombstone(_players, id);

  // --------------------------------------------------------------- ejercicios

  Future<List<Exercise>> exercises() async {
    // Solo se siembran los de serie si la tienda está vacía del todo: si el
    // entrenador los borró, sus lápidas siguen ahí y no deben resucitar.
    if (await _exercises.count(db) == 0) {
      for (final e in kDefaultExercises) {
        // updatedAt 0: cualquier edición posterior (de esta u otra tablet)
        // gana a la versión sembrada.
        await _put(_exercises, e.id, e.toJson(), updatedAt: 0);
      }
      return List.of(kDefaultExercises);
    }
    return (await _live(_exercises)).map(Exercise.fromJson).toList();
  }

  Future<void> saveExercise(Exercise e) => _put(_exercises, e.id, e.toJson());

  Future<void> deleteExercise(String id) => _tombstone(_exercises, id);

  // ------------------------------------------------------ series y repeticiones

  Future<List<WorkSet>> sets() async =>
      (await _live(_sets)).map(WorkSet.fromJson).toList();

  Future<void> saveSet(WorkSet s) => _put(_sets, s.id, s.toJson());

  Future<void> deleteSet(String setId) async {
    await db.transaction((tx) async {
      await _tombstone(_sets, setId, client: tx);
      final reps = await _reps.find(
        tx,
        finder: Finder(filter: Filter.equals('setId', setId)),
      );
      for (final r in reps) {
        if (r.value[kDeleted] == true) continue;
        await _tombstone(_reps, r.key, client: tx, dirty: false);
      }
    });
  }

  Future<List<Rep>> reps() async =>
      (await _live(_reps)).map(Rep.fromJson).toList();

  Future<void> saveRep(Rep r) => db.transaction((tx) async {
    final old = await _reps.record(r.id).get(tx);
    await _put(_reps, r.id, r.toJson(), client: tx, dirty: false);
    await _touchSet(tx, r.setId);
    final oldSet = old?['setId'] as String?;
    if (oldSet != r.setId) await _touchSet(tx, oldSet);
  });

  Future<void> deleteRep(String id) => db.transaction((tx) async {
    final old = await _reps.record(id).get(tx);
    await _tombstone(_reps, id, client: tx, dirty: false);
    await _touchSet(tx, old?['setId'] as String?);
  });

  // ------------------------------------------------------------------ sesiones

  /// [legacyLoss]: pérdida general para sesiones antiguas sin ella.
  Future<List<TrainingSession>> sessions({
    double legacyLoss = kDefaultSessionLoss,
  }) async => [
    for (final j in await _live(_sessions))
      TrainingSession.fromJson(j, legacyLoss: legacyLoss),
  ];

  Future<void> saveTrainingSession(TrainingSession s) =>
      _put(_sessions, s.id, s.toJson());

  // ------------------------------------------- propio de la tablet (no se sincroniza)

  Future<Settings> settings() async {
    final v = await _meta.record('settings').get(db);
    return v == null ? const Settings() : Settings.fromJson(v);
  }

  Future<void> saveSettings(Settings s) =>
      _meta.record('settings').put(db, s.toJson());

  Future<Map<String, Object?>> session() async =>
      (await _meta.record('session').get(db)) ?? const {};

  Future<void> saveSession(Map<String, Object?> s) =>
      _meta.record('session').put(db, s);

  // ----------------------------------------------------------- sincronización

  static _Store _store(String collection) =>
      stringMapStoreFactory.store(collection);

  static Map<String, Object?> _clean(Map<String, Object?> m) =>
      Map.of(m)..remove(kDirty);

  /// Documentos a subir de [collection]: los pendientes o, con [all], todos.
  /// Las series llevan dentro la lista `reps` con sus repeticiones vivas.
  Future<List<Map<String, Object?>>> outgoing(
    String collection, {
    bool all = false,
  }) async {
    final recs = await _store(collection).find(
      db,
      finder: all ? null : Finder(filter: Filter.equals(kDirty, true)),
    );
    if (recs.isEmpty) return const [];
    Map<String, List<Map<String, Object?>>>? repsBySet;
    if (collection == 'sets') {
      repsBySet = {};
      for (final r in await _reps.find(db)) {
        if (r.value[kDeleted] == true) continue;
        final setId = r.value['setId'] as String?;
        if (setId == null) continue;
        (repsBySet[setId] ??= []).add(_clean(r.value));
      }
    }
    return [
      for (final r in recs)
        {
          ..._clean(r.value),
          if (repsBySet != null && r.value[kDeleted] != true)
            'reps': repsBySet[r.key] ?? const [],
        },
    ];
  }

  /// Quita la marca de pendiente de lo que se acaba de subir, salvo que haya
  /// cambiado otra vez mientras se subía.
  Future<void> markSynced(
    String collection,
    List<Map<String, Object?>> docs,
  ) async {
    final store = _store(collection);
    await db.transaction((tx) async {
      for (final d in docs) {
        final id = d['id'] as String;
        final rec = await store.record(id).get(tx);
        if (rec == null || rec[kDirty] != true) continue;
        if (rec[kUpdatedAt] != d[kUpdatedAt]) continue;
        await store.record(id).put(tx, {...rec, kDirty: false});
      }
    });
  }

  /// Mezcla un documento llegado de la nube. Gana la versión con `updatedAt`
  /// más reciente. Devuelve true si cambió algo local.
  Future<bool> applyRemote(
    String collection,
    Map<String, Object?> remote,
  ) async {
    final store = _store(collection);
    final id = remote['id'] as String;
    return db.transaction((tx) async {
      final local = await store.record(id).get(tx);
      final remoteAt = (remote[kUpdatedAt] as num?)?.toInt() ?? 0;
      final localAt = (local?[kUpdatedAt] as num?)?.toInt() ?? -1;
      if (local != null && remoteAt <= localAt) return false;

      final doc = Map<String, Object?>.of(remote)
        ..remove('syncedAt')
        ..remove('reps');
      await store.record(id).put(tx, {
        ...doc,
        kUpdatedAt: remoteAt,
        kDeleted: remote[kDeleted] == true,
        kDirty: false,
      });
      if (collection == 'sets') {
        await _applyRemoteReps(tx, id, remote['reps'] as List? ?? const []);
      }
      return true;
    });
  }

  /// Deja las repeticiones locales de la serie [setId] como dice la nube.
  Future<void> _applyRemoteReps(
    Transaction tx,
    String setId,
    List<Object?> remoteReps,
  ) async {
    final remoteIds = <String>{};
    for (final raw in remoteReps) {
      final r = Map<String, Object?>.from(raw as Map);
      final id = r['id'] as String;
      remoteIds.add(id);
      final local = await _reps.record(id).get(tx);
      final remoteAt = (r[kUpdatedAt] as num?)?.toInt() ?? 0;
      final localAt = (local?[kUpdatedAt] as num?)?.toInt() ?? -1;
      // Si la tablet tiene una versión más nueva (p. ej. la movió a otra
      // serie), se respeta: esa otra serie ya traerá el cambio.
      if (local != null && remoteAt < localAt) continue;
      await _reps.record(id).put(tx, {
        ...r,
        'setId': setId,
        kUpdatedAt: remoteAt,
        kDeleted: false,
        kDirty: false,
      });
    }
    final locals = await _reps.find(
      tx,
      finder: Finder(filter: Filter.equals('setId', setId)),
    );
    for (final l in locals) {
      if (l.value[kDeleted] == true || remoteIds.contains(l.key)) continue;
      // Ya no está en la serie (borrada o movida en otra tablet). Se conserva
      // su updatedAt para que, si se movió, la versión movida gane.
      await _reps.record(l.key).put(tx, {
        'id': l.key,
        kUpdatedAt: l.value[kUpdatedAt],
        kDeleted: true,
        kDirty: false,
      });
    }
  }

  /// Registros cambiados en esta tablet y aún no subidos.
  Future<int> pendingCount() async {
    var n = 0;
    for (final c in syncCollections) {
      n += await _store(c).count(db, filter: Filter.equals(kDirty, true));
    }
    return n;
  }

  /// Estado de sincronización de una cuenta en esta tablet.
  Future<Map<String, Object?>> syncState(String uid) async =>
      (await _meta.record('sync_$uid').get(db)) ?? const {};

  Future<void> saveSyncState(String uid, Map<String, Object?> s) =>
      _meta.record('sync_$uid').put(db, s);
}
