import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegrive/app/theme/app_theme.dart';
import 'package:telegrive/features/files/presentation/trash_sheet.dart';

void main() {
  /// Opens the sheet from a button and returns what it answers, once it
  /// has closed.
  Future<List<bool?>> openSheet(
    WidgetTester tester, {
    String what = '5 items',
    int count = 5,
    int onPhone = 5,
    bool initialAlsoPhone = false,
  }) async {
    final answers = <bool?>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => answers.add(
                await showTrashSheet(
                  context,
                  what: what,
                  count: count,
                  onPhone: onPhone,
                  initialAlsoPhone: initialAlsoPhone,
                ),
              ),
              child: const Text('Trash'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Trash'));
    await tester.pumpAndSettle();
    return answers;
  }

  bool ticked(WidgetTester tester) =>
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value!;

  testWidgets('asks about several items and starts from the last answer', (tester) async {
    await openSheet(tester, initialAlsoPhone: true);

    expect(find.text('Move 5 items to Trash?'), findsOneWidget);
    expect(
      find.text('They stay in the Trash for 30 days, where you can restore them.'),
      findsOneWidget,
    );
    expect(find.text('Also delete from this phone'), findsOneWidget);
    expect(ticked(tester), isTrue);
  });

  testWidgets('one file reads in the singular', (tester) async {
    await openSheet(tester, what: '"IMG_1.jpg"', count: 1, onPhone: 1);

    expect(find.text('Move "IMG_1.jpg" to Trash?'), findsOneWidget);
    expect(
      find.text('It stays in the Trash for 30 days, where you can restore it.'),
      findsOneWidget,
    );
    expect(ticked(tester), isFalse);
  });

  testWidgets('says how many are on the phone only when not all of them are', (
    tester,
  ) async {
    Future<void> close() async {
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    }

    await openSheet(tester, onPhone: 3);
    expect(find.text('3 of these are on this phone'), findsOneWidget);
    await close();

    await openSheet(tester, onPhone: 1);
    expect(find.text('1 of these is on this phone'), findsOneWidget);
    await close();

    await openSheet(tester);
    expect(find.textContaining('of these'), findsNothing);
  });

  testWidgets('over 100 it says Undo takes a while, as the confirm would', (tester) async {
    await openSheet(tester, what: '101 items', count: 101, onPhone: 101);
    expect(
      find.text(
        'They stay in the Trash for 30 days, where you can restore them. '
        'Undo takes a while for this many, one edit per file.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await openSheet(tester, what: '100 items', count: 100, onPhone: 100);
    expect(find.textContaining('Undo takes a while'), findsNothing);
  });

  testWidgets('Move to Trash answers with the box as it was left', (tester) async {
    var answers = await openSheet(tester);
    await tester.tap(find.text('Also delete from this phone'));
    await tester.pump();
    await tester.tap(find.text('Move to Trash'));
    await tester.pumpAndSettle();
    expect(answers, [true]);

    answers = await openSheet(tester);
    await tester.tap(find.text('Move to Trash'));
    await tester.pumpAndSettle();
    expect(answers, [false]);

    answers = await openSheet(tester, initialAlsoPhone: true);
    await tester.tap(find.text('Also delete from this phone'));
    await tester.pump();
    await tester.tap(find.text('Move to Trash'));
    await tester.pumpAndSettle();
    expect(answers, [false]);
  });

  testWidgets('Cancel answers nothing', (tester) async {
    final answers = await openSheet(tester, initialAlsoPhone: true);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(answers, [null]);
    expect(find.byType(TrashSheet), findsNothing);
  });

  test('the phone copies go unless Undo closed the snack', () {
    for (final reason in [
      SnackBarClosedReason.timeout,
      SnackBarClosedReason.hide,
      SnackBarClosedReason.swipe,
      SnackBarClosedReason.dismiss,
      SnackBarClosedReason.remove,
    ]) {
      expect(shouldDeletePhoneCopy(reason, alsoPhone: true), isTrue, reason: '$reason');
    }
    expect(shouldDeletePhoneCopy(SnackBarClosedReason.action, alsoPhone: true), isFalse);
    for (final reason in SnackBarClosedReason.values) {
      expect(shouldDeletePhoneCopy(reason, alsoPhone: false), isFalse, reason: '$reason');
    }
  });
}
