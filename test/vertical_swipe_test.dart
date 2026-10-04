import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegrive/features/viewer/presentation/vertical_swipe.dart';

void main() {
  late int dismissed;
  late int swipedUp;
  late List<bool> dragging;
  late Completer<void> sheet;

  final page = find.byType(ColoredBox);

  Future<void> pumpSwipe(WidgetTester tester, {bool enabled = true}) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    dismissed = 0;
    swipedUp = 0;
    dragging = [];
    sheet = Completer<void>();
    await tester.pumpWidget(
      VerticalSwipe(
        enabled: enabled,
        onDismiss: () => dismissed++,
        onSwipeUp: () {
          swipedUp++;
          return sheet.future;
        },
        onDragging: dragging.add,
        child: const ColoredBox(color: Color(0xFF2E3A59)),
      ),
    );
  }

  double offset(WidgetTester tester) {
    final transform = tester.widget<Transform>(
      find.descendant(of: find.byType(VerticalSwipe), matching: find.byType(Transform)),
    );
    return MatrixUtils.getAsTranslation(transform.transform)!.dy;
  }

  double opacity(WidgetTester tester) => tester.widget<Opacity>(find.byType(Opacity)).opacity;

  testWidgets('a long drag down closes the page and leaves it where it was let go', (
    tester,
  ) async {
    await pumpSwipe(tester);
    await tester.drag(page, const Offset(0, 150));
    await tester.pumpAndSettle();
    expect(dismissed, 1);
    expect(swipedUp, 0);
    expect(offset(tester), greaterThan(VerticalSwipe.dismissDistance));
    // The bars stay hidden while the page fades out.
    expect(dragging, [true]);

    await tester.drag(page, const Offset(0, -150));
    await tester.pumpAndSettle();
    expect(swipedUp, 0);
  });

  testWidgets('a short drag slides back in 150 ms without overshooting', (tester) async {
    await pumpSwipe(tester);
    final gesture = await tester.startGesture(tester.getCenter(page));
    await gesture.moveBy(const Offset(0, 40));
    await gesture.moveBy(const Offset(0, 40));
    await tester.pump();
    expect(offset(tester), 80);
    expect(opacity(tester), closeTo(1 - 80 / 300 * 0.6, 0.001));
    await gesture.up();
    expect(dismissed, 0);
    expect(swipedUp, 0);

    var last = offset(tester);
    for (var elapsed = 0; elapsed < 150; elapsed += 10) {
      await tester.pump(const Duration(milliseconds: 10));
      final now = offset(tester);
      expect(now, lessThanOrEqualTo(last));
      expect(now, greaterThanOrEqualTo(0));
      last = now;
    }
    await tester.pump(const Duration(milliseconds: 10));
    expect(offset(tester), 0);
    expect(opacity(tester), 1);
    expect(dragging, [true, false]);
  });

  testWidgets('the page fades to 40 % and no further', (tester) async {
    await pumpSwipe(tester);
    final gesture = await tester.startGesture(tester.getCenter(page));
    await gesture.moveBy(const Offset(0, 100));
    await gesture.moveBy(const Offset(0, 200));
    await tester.pump();
    expect(opacity(tester), closeTo(0.4, 0.001));
    await gesture.moveBy(const Offset(0, 100));
    await tester.pump();
    expect(opacity(tester), closeTo(0.4, 0.001));
    await gesture.up();
    await tester.pumpAndSettle();
  });

  // A flick sampled finely enough that all of it counts towards its speed,
  // about 900 px/s, as a phone samples a real one.
  Future<void> flick(WidgetTester tester, double dy) => tester.timedDrag(
    page,
    Offset(0, dy),
    Duration(microseconds: (dy.abs() / 900 * 1e6).round()),
    frequency: 240,
  );

  testWidgets('a short fast flick down closes the page', (tester) async {
    await pumpSwipe(tester);
    await flick(tester, 40);
    await tester.pumpAndSettle();
    expect(dismissed, 1);
    expect(swipedUp, 0);
  });

  testWidgets('a drag up opens the details once and the page slides back', (tester) async {
    await pumpSwipe(tester);
    await tester.drag(page, const Offset(0, -90));
    await tester.pumpAndSettle();
    expect(swipedUp, 1);
    expect(dismissed, 0);
    expect(offset(tester), 0);
    expect(dragging, [true, false]);
  });

  testWidgets('a short fast flick up opens the details too', (tester) async {
    await pumpSwipe(tester);
    await flick(tester, -30);
    await tester.pumpAndSettle();
    expect(swipedUp, 1);
    expect(dismissed, 0);
  });

  testWidgets('an upward drag stops following at 80 px', (tester) async {
    await pumpSwipe(tester);
    final gesture = await tester.startGesture(tester.getCenter(page));
    await gesture.moveBy(const Offset(0, -100));
    await gesture.moveBy(const Offset(0, -100));
    await tester.pump();
    expect(offset(tester), -VerticalSwipe.upLimit);
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('drags wait until the details have closed', (tester) async {
    await pumpSwipe(tester);
    await tester.drag(page, const Offset(0, -90));
    await tester.pumpAndSettle();
    expect(swipedUp, 1);

    await tester.drag(page, const Offset(0, 150));
    await tester.pumpAndSettle();
    expect(dismissed, 0);
    expect(offset(tester), 0);

    sheet.complete();
    await tester.pumpAndSettle();
    await tester.drag(page, const Offset(0, 150));
    await tester.pumpAndSettle();
    expect(dismissed, 1);
  });

  testWidgets('switched off, drags neither move the page nor call back', (tester) async {
    await pumpSwipe(tester, enabled: false);
    final gesture = await tester.startGesture(tester.getCenter(page));
    await gesture.moveBy(const Offset(0, 100));
    await gesture.moveBy(const Offset(0, 100));
    await tester.pump();
    expect(offset(tester), 0);
    await gesture.up();
    await tester.drag(page, const Offset(0, -90));
    await tester.pumpAndSettle();
    expect(dismissed, 0);
    expect(swipedUp, 0);
    expect(dragging, isEmpty);
  });

  testWidgets('a tap goes through to what is around it', (tester) async {
    var taps = 0;
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      GestureDetector(
        onTap: () => taps++,
        child: VerticalSwipe(
          onDismiss: () {},
          onSwipeUp: () async {},
          child: const ColoredBox(color: Color(0xFF2E3A59)),
        ),
      ),
    );
    await tester.tap(page);
    expect(taps, 1);
  });
}
