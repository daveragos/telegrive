import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegrive/core/widgets/common.dart';

/// How long snacks stay, with and without a screen reader.
void main() {
  /// An empty screen, with TalkBack on when [screenReader].
  Future<BuildContext> pumpScreen(WidgetTester tester, {bool screenReader = false}) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue = FakeAccessibilityFeatures(
      accessibleNavigation: screenReader,
    );
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (screen) {
              context = screen;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
    return context;
  }

  testWidgets('an Undo leaves when its time is up', (tester) async {
    final context = await pumpScreen(tester);
    showUndoSnack(context, 'Moved to Work', onUndo: () {});
    await tester.pumpAndSettle();
    expect(find.text('Undo'), findsOneWidget);

    await tester.pump(undoWindow);
    await tester.pumpAndSettle();
    expect(find.text('Moved to Work'), findsNothing);
  });

  testWidgets('with a screen reader on, an Undo stays until it is used', (tester) async {
    final context = await pumpScreen(tester, screenReader: true);
    var undone = false;
    showUndoSnack(context, 'Moved to Work', onUndo: () => undone = true);
    await tester.pumpAndSettle();

    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();
    expect(find.text('Moved to Work'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(undone, isTrue);
    expect(find.text('Moved to Work'), findsNothing);
  });

  testWidgets('with a screen reader on, a sentence alone still leaves', (tester) async {
    final context = await pumpScreen(tester, screenReader: true);
    showSnack(context, 'Kept');
    await tester.pumpAndSettle();
    expect(find.text('Kept'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text('Kept'), findsNothing);
  });

  testWidgets('a queued sentence waits for the Undo on screen', (tester) async {
    final context = await pumpScreen(tester);
    showUndoSnack(context, 'Added 3 items to "Trip"', onUndo: () {});
    showSnack(context, 'Couldn\'t move "Trip" to the top of Albums', queue: true);
    await tester.pumpAndSettle();
    expect(find.text('Added 3 items to "Trip"'), findsOneWidget);
    expect(find.text('Couldn\'t move "Trip" to the top of Albums'), findsNothing);

    await tester.pump(undoWindow);
    await tester.pumpAndSettle();
    expect(find.text('Couldn\'t move "Trip" to the top of Albums'), findsOneWidget);
  });
}
