import 'package:flutter_test/flutter_test.dart';
import 'package:miencoder/app_controller.dart';
import 'package:miencoder/core/models.dart';
import 'package:miencoder/services/repository.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  late Database db;
  late Repository repo;
  var now = 1000;

  final rawStore = stringMapStoreFactory.store;

  setUp(() async {
    now = 1000;
    db = await newDatabaseFactoryMemory().openDatabase('sync.db');
    repo = Repository(db, clock: () => now);
  });

  Rep rep(String id, String setId) => Rep(
    id: id,
    setId: setId,
    time: DateTime(2026, 11, 11),
    romCm: 50,
    mv: 0.8,
    mpv: 0.9,
    loadKg: 60,
    exerciseId: 'squat',
  );

  group('Campos de control', () {
    test('guardar añade updatedAt y deleted=false', () async {
      await repo.savePlayer(const Player(id: 'p1', name: 'Ana'));
      final raw = await rawStore('players').record('p1').get(db);
      expect(raw!['updatedAt'], 1000);
      expect(raw['deleted'], false);
      expect((await repo.players()).single.name, 'Ana');
    });

    test('volver a guardar actualiza updatedAt', () async {
      await repo.savePlayer(const Player(id: 'p1', name: 'Ana'));
      now = 2000;
      await repo.savePlayer(const Player(id: 'p1', name: 'Ana B.'));
      final raw = await rawStore('players').record('p1').get(db);
      expect(raw!['updatedAt'], 2000);
    });
  });

  group('Borrados lógicos', () {
    test('borrar deja una lápida que las lecturas ignoran', () async {
      await repo.savePlayer(const Player(id: 'p1', name: 'Ana'));
      now = 3000;
      await repo.deletePlayer('p1');
      expect(await repo.players(), isEmpty);
      final raw = await rawStore('players').record('p1').get(db);
      expect(raw, {
        'id': 'p1',
        'updatedAt': 3000,
        'deleted': true,
        'dirty': true,
      });
    });

    test('borrar una serie deja lápidas en la serie y sus reps', () async {
      await repo.saveSet(
        WorkSet(id: 's1', start: DateTime(2026), exerciseId: 'squat'),
      );
      await repo.saveRep(rep('r1', 's1'));
      await repo.saveRep(rep('r2', 's1'));
      await repo.saveRep(rep('r3', 'otra'));
      await repo.deleteSet('s1');
      expect(await repo.sets(), isEmpty);
      expect((await repo.reps()).map((r) => r.id), ['r3']);
      for (final id in ['r1', 'r2']) {
        final raw = await rawStore('reps').record(id).get(db);
        expect(raw!['deleted'], true);
      }
    });

    test('deshacer (volver a guardar) revive el registro', () async {
      await repo.saveRep(rep('r1', 's1'));
      await repo.deleteRep('r1');
      now = 5000;
      await repo.saveRep(rep('r1', 's1'));
      expect((await repo.reps()).single.id, 'r1');
      final raw = await rawStore('reps').record('r1').get(db);
      expect(raw!['deleted'], false);
      expect(raw['updatedAt'], 5000);
    });
  });

  group('Ejercicios de serie', () {
    test('se siembran con updatedAt 0', () async {
      final list = await repo.exercises();
      expect(list.length, kDefaultExercises.length);
      final raw = await rawStore('exercises').record('squat').get(db);
      expect(raw!['updatedAt'], 0);
    });

    test('si se borran todos no resucitan', () async {
      for (final e in await repo.exercises()) {
        await repo.deleteExercise(e.id);
      }
      expect(await repo.exercises(), isEmpty);
    });
  });

  group('Migración', () {
    test('marca los registros antiguos y es idempotente', () async {
      // Datos tal como los guardaba la versión anterior (sin campos de control).
      await rawStore('players').record('p1').put(db, {'id': 'p1', 'name': 'A'});
      await rawStore('reps').record('r1').put(db, rep('r1', 's1').toJson());
      await rawStore('meta').record('settings').put(db, {'loss': 25});

      now = 7000;
      await repo.migrate();
      final p = await rawStore('players').record('p1').get(db);
      expect(p, {'id': 'p1', 'name': 'A', 'updatedAt': 7000, 'deleted': false});
      final r = await rawStore('reps').record('r1').get(db);
      expect(r!['updatedAt'], 7000);
      // meta no se toca.
      expect(await rawStore('meta').record('settings').get(db), {'loss': 25});
      expect((await rawStore('meta').record('schema').get(db))!['version'], 2);

      // Segunda vez: no cambia nada.
      now = 9000;
      await repo.savePlayer(const Player(id: 'p2', name: 'B'));
      await repo.migrate();
      final p1 = await rawStore('players').record('p1').get(db);
      expect(p1!['updatedAt'], 7000);
    });
  });

  group('Identificadores', () {
    test('únicos y con sufijo aleatorio de longitud fija', () {
      final ids = {for (var i = 0; i < 10000; i++) newId()};
      expect(ids.length, 10000);
      final ts = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
      expect(ids.first.length, ts.length + 7);
    });
  });
}
