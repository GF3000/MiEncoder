import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miencoder/ui/common.dart';

void main() {
  Future<BuildContext> pump(WidgetTester t) async {
    late BuildContext ctx;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    return ctx;
  }

  testWidgets('aviso con acción se cierra solo', (t) async {
    final ctx = await pump(t);
    showAppSnack(
      ctx,
      'Serie borrada',
      actionLabel: 'Deshacer',
      onAction: () {},
    );
    await t.pumpAndSettle();
    expect(find.text('Serie borrada'), findsOneWidget);
    await t.pump(kSnackActionDuration);
    await t.pumpAndSettle();
    expect(find.text('Serie borrada'), findsNothing);
  });

  testWidgets('aviso sin acción se cierra solo', (t) async {
    final ctx = await pump(t);
    showAppSnack(ctx, 'Hecho');
    await t.pumpAndSettle();
    expect(find.text('Hecho'), findsOneWidget);
    await t.pump(kSnackDuration);
    await t.pumpAndSettle();
    expect(find.text('Hecho'), findsNothing);
  });

  testWidgets('la X cierra el aviso sin ejecutar la acción', (t) async {
    final ctx = await pump(t);
    var done = false;
    showAppSnack(
      ctx,
      '¿Son suyas?',
      actionLabel: 'Sí',
      onAction: () => done = true,
    );
    await t.pumpAndSettle();
    await t.tap(find.byIcon(Icons.close));
    await t.pumpAndSettle();
    expect(find.text('¿Son suyas?'), findsNothing);
    expect(done, isFalse);
  });

  testWidgets('aviso sin acción no lleva X', (t) async {
    final ctx = await pump(t);
    showAppSnack(ctx, 'Hecho');
    await t.pumpAndSettle();
    expect(find.byIcon(Icons.close), findsNothing);
  });
}
