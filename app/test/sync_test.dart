import 'package:flutter_test/flutter_test.dart';
import 'package:miencoder/core/models.dart';
import 'package:miencoder/services/repository.dart';
import 'package:miencoder/services/sync.dart';
import 'package:sembast/sembast_memory.dart';

/// Nube en memoria con reloj de servidor propio.
class FakeRemote implements SyncRemote {
  final data = <String, Map<String, Map<String, Object?>>>{};
  int serverTime = 0;
  bool offline = false;
  int pushedDocs = 0;

  static Object? _copy(Object? v) => switch (v) {
    Map m => {for (final e in m.entries) e.key as String: _copy(e.value)},
    List l => [for (final x in l) _copy(x)],
    _ => v,
  };

  @override
  Future<List<Map<String, Object?>>> pull(
    String uid,
    String collection,
    int? sinceMillis,
  ) async {
    if (offline) throw StateError('offline');
    final docs = (data['$uid/$collection'] ?? {}).values
        .where(
          (d) => sinceMillis == null || (d['syncedAt'] as int) >= sinceMillis,
        )
        .map((d) => _copy(d) as Map<String, Object?>)
        .toList();
    docs.sort((a, b) => (a['syncedAt'] as int).compareTo(b['syncedAt'] as int));
    return docs;
  }

  @override
  Future<void> push(
    String uid,
    String collection,
    List<Map<String, Object?>> docs,
  ) async {
    if (offline) throw StateError('offline');
    final col = data.putIfAbsent('$uid/$collection', () => {});
    serverTime++;
    for (final d in docs) {
      col[d['id'] as String] = {
        ...(_copy(d) as Map<String, Object?>),
        'syncedAt': serverTime,
      };
      pushedDocs++;
    }
  }
}

/// Una tablet: base de datos propia y reloj propio.
class Device {
  final Repository repo;
  final SyncEngine engine;
  int now;
  Device._(this.repo, this.engine, this.now);

  static Future<Device> create(String name, FakeRemote remote) async {
    late Device d;
    final db = await newDatabaseFactoryMemory().openDatabase('$name.db');
    final repo = Repository(db, clock: () => d.now);
    d = Device._(repo, SyncEngine(repo, remote), 1000);
    await repo.migrate();
    return d;
  }

  Future<SyncResult> sync() => engine.run('uid');
}

const uid = 'uid';

Rep rep(String id, String setId, {double mpv = 0.9}) => Rep(
  id: id,
  setId: setId,
  time: DateTime(2026, 11, 11, 10),
  romCm: 50,
  mv: 0.8,
  mpv: mpv,
  loadKg: 60,
  exerciseId: 'squat',
);

WorkSet set(String id, {String? playerId}) => WorkSet(
  id: id,
  start: DateTime(2026, 11, 11, 10),
  exerciseId: 'squat',
  playerId: playerId,
);

void main() {
  late FakeRemote remote;
  late Device a;
  late Device b;

  setUp(() async {
    remote = FakeRemote();
    a = await Device.create('a', remote);
    b = await Device.create('b', remote);
  });

  test('lo creado en A llega a B, con las reps dentro de su serie', () async {
    await a.repo.savePlayer(const Player(id: 'p1', name: 'Ana'));
    await a.repo.saveSet(set('s1', playerId: 'p1'));
    await a.repo.saveRep(rep('r1', 's1'));
    await a.repo.saveRep(rep('r2', 's1'));
    await a.sync();

    // En la nube no hay colección de reps: viajan dentro de la serie.
    expect(remote.data.keys, isNot(contains('$uid/reps')));
    final s1 = remote.data['$uid/sets']!['s1']!;
    expect((s1['reps'] as List).length, 2);

    final r = await b.sync();
    expect(r.changedLocal, isTrue);
    expect((await b.repo.players()).single.name, 'Ana');
    expect((await b.repo.sets()).single.playerId, 'p1');
    expect((await b.repo.reps()).map((r) => r.id).toSet(), {'r1', 'r2'});
    expect(await b.repo.pendingCount(), 0);
  });

  test('un borrado en B desaparece también en A', () async {
    await a.repo.saveSet(set('s1'));
    await a.repo.saveRep(rep('r1', 's1'));
    await a.repo.savePlayer(const Player(id: 'p1', name: 'Ana'));
    await a.sync();
    await b.sync();

    b.now = 2000;
    await b.repo.deleteSet('s1');
    await b.repo.deletePlayer('p1');
    await b.sync();
    await a.sync();

    expect(await a.repo.sets(), isEmpty);
    expect(await a.repo.reps(), isEmpty);
    expect(await a.repo.players(), isEmpty);
  });

  test('borrar una sola rep en B la quita en A', () async {
    await a.repo.saveSet(set('s1'));
    await a.repo.saveRep(rep('r1', 's1'));
    await a.repo.saveRep(rep('r2', 's1'));
    await a.sync();
    await b.sync();

    b.now = 2000;
    await b.repo.deleteRep('r1');
    await b.sync();
    await a.sync();
    expect((await a.repo.reps()).map((r) => r.id), ['r2']);
  });

  test('misma edición sin conexión en las dos: gana la más reciente', () async {
    await a.repo.savePlayer(const Player(id: 'p1', name: 'Ana'));
    await a.sync();
    await b.sync();

    a.now = 3000;
    await a.repo.savePlayer(const Player(id: 'p1', name: 'Ana (A)'));
    b.now = 2000; // B la editó antes, pero sincroniza después
    await b.repo.savePlayer(const Player(id: 'p1', name: 'Ana (B)'));

    await a.sync();
    await b.sync(); // B baja primero: la versión de A es más nueva
    await a.sync();

    expect((await a.repo.players()).single.name, 'Ana (A)');
    expect((await b.repo.players()).single.name, 'Ana (A)');
    expect(remote.data['$uid/players']!['p1']!['name'], 'Ana (A)');
  });

  test('una edición antigua hecha sin conexión no pisa la nube', () async {
    await a.repo.savePlayer(const Player(id: 'p1', name: 'Ana'));
    await a.sync();
    await b.sync();

    b.now = 1500;
    await b.repo.savePlayer(const Player(id: 'p1', name: 'Vieja'));
    a.now = 5000;
    await a.repo.savePlayer(const Player(id: 'p1', name: 'Nueva'));
    await a.sync();
    await b.sync();

    expect((await b.repo.players()).single.name, 'Nueva');
    expect(await b.repo.pendingCount(), 0);
  });

  test('datos de antes de tener cuenta se suben la primera vez', () async {
    // Simula datos guardados por la versión anterior (sin campos de control).
    final db = await newDatabaseFactoryMemory().openDatabase('old.db');
    final store = stringMapStoreFactory.store;
    await store('players').record('p1').put(db, {'id': 'p1', 'name': 'Vieja'});
    await store('sets').record('s1').put(db, set('s1').toJson());
    await store('reps').record('r1').put(db, rep('r1', 's1').toJson());
    final old = Repository(db, clock: () => 1000);
    await old.migrate();
    expect(await old.pendingCount(), 0); // nada marcado como pendiente…

    await SyncEngine(old, remote).run(uid); // …pero la primera vez sube todo
    await b.sync();
    expect((await b.repo.players()).single.name, 'Vieja');
    expect((await b.repo.reps()).single.id, 'r1');

    // La segunda vez solo sube lo pendiente.
    final before = remote.pushedDocs;
    await SyncEngine(old, remote).run(uid);
    expect(remote.pushedDocs, before);
  });

  test('mover una rep a otra serie se refleja en la otra tablet', () async {
    await a.repo.saveSet(set('s1', playerId: 'p1'));
    await a.repo.saveSet(set('s2', playerId: 'p2'));
    await a.repo.saveRep(rep('r1', 's1'));
    await a.repo.saveRep(rep('r2', 's1'));
    await a.sync();
    await b.sync();

    a.now = 2000;
    await a.repo.saveRep(rep('r2', 's2')); // "se me olvidó cambiar"
    await a.sync();
    await b.sync();

    final reps = {for (final r in await b.repo.reps()) r.id: r.setId};
    expect(reps, {'r1': 's1', 'r2': 's2'});
  });

  test('sin conexión no se pierde nada: queda pendiente', () async {
    await a.repo.savePlayer(const Player(id: 'p1', name: 'Ana'));
    await a.sync(); // primera subida
    a.now = 2000;
    await a.repo.savePlayer(const Player(id: 'p2', name: 'Luis'));
    remote.offline = true;
    await expectLater(a.sync(), throwsStateError);
    expect(await a.repo.pendingCount(), 1);

    remote.offline = false;
    await a.sync();
    expect(await a.repo.pendingCount(), 0);
    await b.sync();
    expect((await b.repo.players()).map((p) => p.name).toSet(), {
      'Ana',
      'Luis',
    });
  });

  test('un cambio durante la subida sigue pendiente', () async {
    await a.repo.savePlayer(const Player(id: 'p1', name: 'Ana'));
    final docs = await a.repo.outgoing('players');
    a.now = 2000;
    await a.repo.savePlayer(const Player(id: 'p1', name: 'Ana 2'));
    await a.repo.markSynced('players', docs);
    expect(await a.repo.pendingCount(), 1);
  });

  test('los ejercicios de serie no se duplican ni pisan ediciones', () async {
    await a.repo.exercises();
    await b.repo.exercises();
    a.now = 2000;
    await a.repo.saveExercise(
      const Exercise(id: 'squat', name: 'Sentadilla', mvt: 0.33),
    );
    await a.sync();
    await b.sync();
    final list = await b.repo.exercises();
    expect(list.length, kDefaultExercises.length);
    expect(list.firstWhere((e) => e.id == 'squat').mvt, 0.33);
  });

  test('cada repetición nueva marca su serie como pendiente', () async {
    await a.repo.saveSet(set('s1'));
    await a.sync();
    expect(await a.repo.pendingCount(), 0);
    a.now = 2000;
    await a.repo.saveRep(rep('r1', 's1'));
    expect(await a.repo.pendingCount(), 1);
    final out = await a.repo.outgoing('sets');
    expect((out.single['reps'] as List).single, containsPair('id', 'r1'));
  });
}
