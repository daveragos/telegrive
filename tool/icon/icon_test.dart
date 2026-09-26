// Renders the launcher icons, the notification icon and the channel photo
// from the same drawing as BrandMark:
//
//   flutter test tool/icon/icon_test.dart --update-goldens
//   dart run flutter_launcher_icons
//   tool/icon/install.sh
//
// icon.png is the full-bleed square (iOS, legacy Android); foreground.png is
// the plane alone for Android's adaptive icon, and doubles as the themed
// (monochrome) icon.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegrive/core/widgets/brand_mark.dart';

const _size = 1024.0;

/// White, so the blue plane reads as Telegram's.
const _tile = Colors.white;

void main() {
  Future<void> render(
    WidgetTester tester,
    BrandPainter painter,
    String name, {
    double size = _size,
  }) async {
    tester.view.physicalSize = Size(size, size);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RepaintBoundary(
        child: SizedBox.square(
          dimension: size,
          child: CustomPaint(painter: painter),
        ),
      ),
    );
    await expectLater(
      find.byType(RepaintBoundary).first,
      matchesGoldenFile('out/$name.png'),
    );
  }

  testWidgets('full icon', (tester) async {
    await render(tester, const BrandPainter(scale: 0.64, tile: _tile), 'icon');
  });

  testWidgets('adaptive foreground', (tester) async {
    // flutter_launcher_icons insets the foreground by 16% on each side,
    // which is already Android's visible area, so the plane is drawn at the
    // same size as on the full icon. Its nose stays inside the 66 dp safe
    // circle.
    await render(tester, const BrandPainter(scale: 0.64), 'foreground');
  });

  testWidgets('adaptive background', (tester) async {
    await render(
      tester,
      const BrandPainter(scale: 0, tile: _tile),
      'background',
    );
  });

  testWidgets('notification icon', (tester) async {
    // Status-bar icons are white silhouettes; the creases stay open.
    await render(
      tester,
      const BrandPainter(scale: 0.86, silhouette: Colors.white),
      'notification',
    );
  });

  testWidgets('channel photo', (tester) async {
    // Telegram crops chat photos to a circle and shows them on white, so
    // the plane sits well inside it on a faint blue.
    await render(
      tester,
      const BrandPainter(scale: 0.54, tile: Color(0xFFEAF1FF)),
      'channel_photo',
      size: 640,
    );
  });
}
