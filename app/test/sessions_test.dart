import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:miencoder/app_controller.dart';
import 'package:miencoder/core/frame_parser.dart';
import 'package:miencoder/core/models.dart';
import 'package:miencoder/main.dart';
import 'package:miencoder/services/encoder.dart';
import 'package:miencoder/services/repository.dart';

import 'controller_test.dart' show SilentFeedback;

EncoderFrame f(double mpv) => parseFrameText(
  '50.00 ${(mpv * 0.95).toStringAsFixed(2)} ${mpv.toStringAsFixed(2)} ${(mpv * 1.6).toStringAsFixed(2)}',
)!;

void main() {
  late AppController c;
  late Repository repo;
  late DateTime now;

  Future<AppController> build() async {
    final ctrl = AppController(
      repo: repo,
      feedback: SilentFeedback(),
      encoder: SimulatedEncoderSource(),
      clock: () => now,
    );
    await ctrl.init();
    return ctrl;
  }

  setUp(() async {
    repo = Repository(await newDatabaseFactoryMemory().openDatabase('s.db'));
    now = DateTime(2026, 11, 11, 10);
    c = await build();
  });

  group('Sesión', () {
    test('al empezar hay una sesión activa con nombre de la fecha', () {
      expect(c.activeSession, isNotNull);
      expect(c.activeSession!.name, 'Mié 11 nov');
      expect(c.sessionPlayers, isEmpty);
    });

    test(
      'la cuadrícula solo muestra convocados, en orden de convocatoria',
      () async {
        final ana = await c.addPlayer('Ana');
        final ben = await c.addPlayer('Ben');
        await c.addPlayer('Carla'); // existe pero no está convocada
        await c.addToSession(ben.id);
        await c.addToSession(ana.id);
        expect(c.sessionPlayers.map((p) => p.name), ['Ben', 'Ana']);
      },
    );

    test('crear desde el "+" lo crea y lo convoca', () async {
      final p = await c.createAndAddToSession('Pablo');
      expect(c.players.single.id, p.id);
      expect(c.isInSession(p.id), isTrue);
    });

    test(
      'quitar de la sesión no borra al deportista y suelta al activo',
      () async {
        final ana = await c.createAndAddToSession('Ana');
        c.setActive(ana.id);
        await c.removeFromSession(ana.id);
        expect(c.players.single.name, 'Ana');
        expect(c.isInSession(ana.id), isFalse);
        expect(c.activePlayerId, isNull);
      },
    );

    test('las series quedan marcadas con su sesión', () async {
      final s1 = c.activeSessionId;
      c.onFrame(f(1.0));
      await c.newSession(copyPlayers: false);
      c.onFrame(f(0.9));
      final bySession = c.sets.map((s) => s.sessionId).toList();
      expect(bySession, [s1, c.activeSessionId]);
      expect(c.setsInSession(s1!), 1);
    });

    test(
      'una serie no continúa en otra sesión aunque nada más cambie',
      () async {
        final ana = await c.createAndAddToSession('Ana');
        c.setActive(ana.id);
        c.onFrame(f(1.0));
        await c.newSession(copyPlayers: true);
        c.setActive(ana.id);
        c.onFrame(f(0.9));
        expect(c.recentSets().length, 2);
      },
    );

    test('nueva sesión copiando convocados / vacía', () async {
      final ana = await c.createAndAddToSession('Ana');
      await c.newSession(copyPlayers: true);
      expect(c.sessionPlayers.single.id, ana.id);
      await c.newSession(copyPlayers: false);
      expect(c.sessionPlayers, isEmpty);
    });

    test('retomar una sesión anterior recupera sus convocados', () async {
      await c.createAndAddToSession('Ana');
      final morning = c.activeSessionId!;
      await c.newSession(copyPlayers: false);
      await c.createAndAddToSession('Ben');
      c.resumeSession(morning);
      expect(c.sessionPlayers.map((p) => p.name), ['Ana']);
    });

    test('renombrar', () async {
      await c.renameSession(c.activeSessionId!, '  Fuerza 1.º equipo ');
      expect(c.activeSession!.name, 'Fuerza 1.º equipo');
    });

    test('borrar un deportista lo quita de todas las sesiones', () async {
      final ana = await c.createAndAddToSession('Ana');
      await c.newSession(copyPlayers: true);
      await c.deletePlayer(ana.id, deleteData: false);
      expect(c.sessions.every((s) => !s.playerIds.contains(ana.id)), isTrue);
    });

    test(
      'todo persiste al reabrir: sesión activa, convocados y nombre',
      () async {
        await c.createAndAddToSession('Ana');
        await c.renameSession(c.activeSessionId!, 'Martes');
        await Future<void>.delayed(const Duration(milliseconds: 50));
        final c2 = await build();
        expect(c2.activeSession!.name, 'Martes');
        expect(c2.sessionPlayers.single.name, 'Ana');
      },
    );

    test('otro día: se detecta para preguntar; mismo día no', () async {
      expect(c.activeSessionIsFromAnotherDay, isFalse);
      now = now.add(const Duration(days: 1));
      final c2 = await build();
      expect(c2.activeSessionIsFromAnotherDay, isTrue);
    });
  });

  group('Migración de datos antiguos', () {
    test('series sin sesión se agrupan en una sesión por día', () async {
      final ana = await c.addPlayer('Ana');
      Future<void> oldSet(DateTime t, String? player) async {
        final s = WorkSet(
          id: 'set$t',
          start: t,
          exerciseId: 'squat',
          playerId: player,
        );
        await repo.saveSet(s);
        await repo.saveRep(
          Rep(
            id: 'rep$t',
            setId: s.id,
            time: t,
            romCm: 50,
            mv: 0.9,
            mpv: 0.95,
            loadKg: 60,
            exerciseId: 'squat',
          ),
        );
      }

      await oldSet(DateTime(2026, 11, 9, 10), ana.id);
      await oldSet(DateTime(2026, 11, 9, 11), null);
      await oldSet(DateTime(2026, 11, 10, 10), ana.id);
      final c2 = await build();
      final migrated = c2.sessions
          .where((s) => s.name == 'Lun 9 nov' || s.name == 'Mar 10 nov')
          .toList();
      expect(migrated.length, 2);
      expect(c2.sets.every((s) => s.sessionId != null), isTrue);
      final monday = c2.sessions.firstWhere((s) => s.name == 'Lun 9 nov');
      expect(monday.playerIds, [ana.id]);
      expect(c2.setsInSession(monday.id), 2);
    });
  });

  group('Pantalla', () {
    Future<void> pumpApp(WidgetTester tester, Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MiEncoderApp(controller: c));
      await tester.pump();
    }

    for (final (name, size) in [
      ('móvil vertical', const Size(393, 873)),
      ('móvil horizontal', const Size(873, 393)),
      ('tablet', const Size(1280, 854)),
    ]) {
      testWidgets('cabecera con ejercicio + sesión sin desbordes ($name)', (
        tester,
      ) async {
        await tester.runAsync(
          () => c.renameSession(
            c.activeSessionId!,
            'Fuerza – 1.º equipo – mañana',
          ),
        );
        await pumpApp(tester, size);
        expect(find.byKey(const Key('session-picker')), findsOneWidget);
        expect(find.text('Sentadilla'), findsOneWidget);
        final picker = tester.getRect(find.byKey(const Key('session-picker')));
        final conn = tester.getRect(find.byKey(const Key('connection-chip')));
        expect(
          picker.right,
          lessThanOrEqualTo(conn.left),
          reason: 'la sesión pisa el chip de conexión',
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('"+" → buscar → crear y convocar → marcar existente', (
      tester,
    ) async {
      await tester.runAsync(() => c.addPlayer('María López'));
      await pumpApp(tester, const Size(873, 393));
      await tester.tap(find.byKey(const Key('convoke-plus')));
      await tester.pumpAndSettle();

      // Buscar sin tildes encuentra "María López"; marcarla la convoca.
      await tester.enterText(find.byKey(const Key('convoke-search')), 'maria');
      await tester.pumpAndSettle();
      expect(find.text('María López'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.text('María López'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(c.sessionPlayers.single.name, 'María López');

      // Nombre nuevo → "Crear «Pablo» y añadirlo".
      await tester.enterText(find.byKey(const Key('convoke-search')), 'Pablo');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('convoke-create')), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('convoke-create')));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(c.sessionPlayers.map((p) => p.name), ['María López', 'Pablo']);

      await tester.tap(find.text('Listo'));
      await tester.pumpAndSettle();
      expect(find.text('Pablo'), findsOneWidget); // ya en la cuadrícula
      expect(tester.takeException(), isNull);
    });

    testWidgets('mantener pulsado → Quitar de la sesión', (tester) async {
      await tester.runAsync(() => c.createAndAddToSession('Ana'));
      await pumpApp(tester, const Size(1280, 854));
      await tester.longPress(find.text('Ana'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Quitar de la sesión'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(c.sessionPlayers, isEmpty);
      expect(c.players.single.name, 'Ana');
      expect(tester.takeException(), isNull);
    });

    testWidgets('al abrir otro día pregunta continuar o nueva', (tester) async {
      await tester.runAsync(() async {
        await c.createAndAddToSession('Ana');
        now = now.add(const Duration(days: 1));
        c = await build();
      });
      await pumpApp(tester, const Size(393, 873));
      await tester.pumpAndSettle();
      expect(find.text('¿Nueva sesión?'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.text('Nueva con los 1'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(c.activeSession!.name, 'Jue 12 nov');
      expect(c.sessionPlayers.single.name, 'Ana');
      expect(tester.takeException(), isNull);
    });
  });
}
