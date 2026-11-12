import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miencoder/core/models.dart';
import 'package:miencoder/ui/session_sheets.dart';

void main() {
  testWidgets('cabe en tablet horizontal y los chips actualizan el valor', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2000, 1335);
    tester.view.devicePixelRatio = 1.6;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Builder(
          builder: (ctx) => TextButton(
            onPressed: () => askSessionTarget(
              ctx,
              exerciseName: 'Sentadilla',
              sessionLoss: 20,
            ),
            child: const Text('abrir'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull); // sin overflow
    expect(find.byType(TextField), findsNothing); // sin teclado
    await tester.tap(find.byKey(const Key('rm-preset-2'))); // 75–85
    await tester.tap(find.byKey(const Key('loss-25')));
    await tester.pump();
    expect(find.text('75–85 %'), findsOneWidget);
    expect(find.text('25 %'), findsWidgets);
    expect(
      find.byKey(const Key('rm-target-save-all')).hitTestable(),
      findsOneWidget,
    );
  });

  testWidgets('devuelve lo elegido y «Guardar en todos»', (tester) async {
    SessionTargetChoice? result;
    tester.view.physicalSize = const Size(2000, 1335);
    tester.view.devicePixelRatio = 1.6;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (ctx) => TextButton(
            onPressed: () async => result = await askSessionTarget(
              ctx,
              exerciseName: 'Sentadilla',
              rm: const RmTarget(70, 80),
              loss: 22,
              sessionLoss: 20,
            ),
            child: const Text('abrir'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    // Una pérdida que no está entre los presets aparece igualmente.
    expect(find.byKey(const Key('loss-22')), findsOneWidget);
    await tester.tap(find.byKey(const Key('rm-preset-3'))); // Fuerza 85–95
    await tester.tap(find.byKey(const Key('loss-default')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('rm-target-save-all')));
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.rm, const RmTarget(85, 95));
    expect(result!.loss, isNull);
    expect(result!.applyToAll, isTrue);
  });

  testWidgets('«Sin objetivo» quita el rango; Cancelar devuelve null', (
    tester,
  ) async {
    SessionTargetChoice? result = (rm: null, loss: null, applyToAll: false);
    tester.view.physicalSize = const Size(2000, 1335);
    tester.view.devicePixelRatio = 1.6;
    addTearDown(tester.view.reset);
    Future<void> openWith() async {
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (ctx) => TextButton(
            onPressed: () async => result = await askSessionTarget(
              ctx,
              exerciseName: 'Sentadilla',
              rm: const RmTarget(70, 80),
              sessionLoss: 20,
            ),
            child: const Text('abrir'),
          ),
        ),
      ),
    );
    await openWith();
    await tester.tap(find.byKey(const Key('rm-preset-4')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('rm-target-save')));
    await tester.pumpAndSettle();
    expect(result!.rm, kNoRmTarget); // «Sin objetivo» explícito, no heredar
    expect(result!.applyToAll, isFalse);

    await openWith();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });
}
