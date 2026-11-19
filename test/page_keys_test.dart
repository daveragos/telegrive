import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegrive/core/platform/desktop_input.dart';

/// A page's keys stay with the page, so its shortcuts and the Mac's menu bar
/// reach it.
void main() {
  /// Two pages side by side, one shown, as a shell's tabs are, with a text
  /// field outside both.
  Widget tabs({required bool firstShown}) => MaterialApp(
    home: Scaffold(
      body: Column(
        children: [
          const TextField(),
          TickerMode(
            enabled: firstShown,
            child: const PageKeys(child: SizedBox(key: Key('first'), height: 100, width: 100)),
          ),
          TickerMode(
            enabled: !firstShown,
            child: const PageKeys(child: SizedBox(key: Key('second'), height: 100, width: 100)),
          ),
        ],
      ),
    ),
  );

  bool focused(WidgetTester tester, String page) =>
      Focus.of(tester.element(find.byKey(Key(page)))).hasPrimaryFocus;

  testWidgets('the page shown takes the keys, and another does once it shows', (tester) async {
    await tester.pumpWidget(tabs(firstShown: true));
    await tester.pump();
    expect(focused(tester, 'first'), isTrue);

    await tester.pumpWidget(tabs(firstShown: false));
    await tester.pump();
    expect(focused(tester, 'second'), isTrue);
  });

  testWidgets('a click on a page gives it the keys', (tester) async {
    await tester.pumpWidget(tabs(firstShown: true));
    await tester.pump();
    await tester.tap(find.byKey(const Key('second')));
    await tester.pump();
    expect(focused(tester, 'second'), isTrue);
  });

  testWidgets('a text field being typed in keeps the keys', (tester) async {
    await tester.pumpWidget(tabs(firstShown: true));
    await tester.pump();
    await tester.tap(find.byType(TextField));
    await tester.pump();

    await tester.pumpWidget(tabs(firstShown: false));
    await tester.pump();
    expect(focused(tester, 'second'), isFalse);
    expect(tester.testTextInput.isVisible, isTrue);
  });
}
