import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegrive/app/theme/app_theme.dart';
import 'package:telegrive/core/widgets/common.dart';

void main() {
  /// Opens the dialog from a button and says what it popped with, once it
  /// has.
  Future<({String? value, bool closed}) Function()> pumpOpener(
    WidgetTester tester, {
    required bool dismissible,
  }) async {
    String? value;
    var closed = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  value = await showTextInputDialog(
                    context,
                    title: 'Name this scan',
                    initialValue: 'Scan 2026-09-26 14.03.pdf',
                    selectStem: true,
                    confirmLabel: 'Upload',
                    cancelLabel: 'Discard',
                    dismissible: dismissible,
                  );
                  closed = true;
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    return () => (value: value, closed: closed);
  }

  testWidgets('a dialog that is not dismissible closes only through its buttons', (
    tester,
  ) async {
    final outcome = await pumpOpener(tester, dismissible: false);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(
      field.controller!.selection,
      TextSelection(baseOffset: 0, extentOffset: 'Scan 2026-09-26 14.03'.length),
    );

    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(find.text('Name this scan'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Name this scan'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '  ');
    await tester.pump();
    expect(
      tester.widget<TextButton>(find.widgetWithText(TextButton, 'Upload')).onPressed,
      isNull,
    );

    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('Name this scan'), findsNothing);
    expect(outcome(), (value: null, closed: true));
  });

  testWidgets('a dismissible one still closes on Back', (tester) async {
    final outcome = await pumpOpener(tester, dismissible: true);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Name this scan'), findsNothing);
    expect(outcome(), (value: null, closed: true));
  });
}
