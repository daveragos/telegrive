import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegrive/app/theme/app_theme.dart';
import 'package:telegrive/core/platform/app_platform.dart';
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

  group('the Undo key', () {
    /// A screen whose root answers Cmd-Z or Ctrl-Z as the app's does, with
    /// a text field to type in.
    Future<BuildContext> pumpWithKeys(WidgetTester tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => Actions(actions: {UndoTextIntent: PendingUndo.action}, child: child!),
          home: Scaffold(
            body: Builder(
              builder: (screen) {
                context = screen;
                return const Column(children: [Focus(autofocus: true, child: SizedBox(height: 40)), TextField()]);
              },
            ),
          ),
        ),
      );
      return context;
    }

    Future<void> pressUndo(WidgetTester tester) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pumpAndSettle();
    }

    testWidgets('takes back what the snack offers to undo', (tester) async {
      final context = await pumpWithKeys(tester);
      var undone = 0;
      showUndoSnack(context, 'Moved to Trash', onUndo: () => undone++);
      await tester.pumpAndSettle();

      await pressUndo(tester);
      expect(undone, 1);
      expect(find.text('Moved to Trash'), findsNothing);

      await pressUndo(tester);
      expect(undone, 1, reason: 'the change was taken back once');
    });

    testWidgets('does nothing once the snack has gone', (tester) async {
      final context = await pumpWithKeys(tester);
      var undone = false;
      showUndoSnack(context, 'Moved to Trash', onUndo: () => undone = true);
      await tester.pumpAndSettle();
      await tester.pump(undoWindow);
      await tester.pumpAndSettle();

      await pressUndo(tester);
      expect(undone, isFalse);
    });

    testWidgets('undoes the typing while a text field has the keys', (tester) async {
      final context = await pumpWithKeys(tester);
      var undone = false;
      showUndoSnack(context, 'Moved to Trash', onUndo: () => undone = true);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'name');
      await tester.pumpAndSettle();

      await pressUndo(tester);
      expect(undone, isFalse);
      expect(find.text('Moved to Trash'), findsOneWidget);
    });
  });

  testWidgets('on a computer a snack sits at the foot of the window, not across the sidebar', (tester) async {
    AppPlatform.debugDesktop = true;
    addTearDown(() => AppPlatform.debugDesktop = false);
    tester.view.physicalSize = const Size(1280, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
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
    showSnack(context, 'Moved to Trash');
    await tester.pumpAndSettle();
    final snack = tester.getRect(find.descendant(of: find.byType(SnackBar), matching: find.byType(Material)).first);
    expect(snack.width, 520);
    expect(snack.center.dx, 640);
  });
}
