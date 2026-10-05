// Renders the launcher icons from the mark in source/telegrive.png, and the
// notification icon and the channel photo from the same drawing as
// BrandMark:
//
//   flutter test tool/icon/icon_test.dart --update-goldens
//   dart run flutter_launcher_icons
//   tool/icon/install.sh
//
// icon.png is the full-bleed square (iOS, legacy Android); foreground.png is
// the plane alone for Android's adaptive icon, and doubles as the themed
// (monochrome) icon.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegrive/core/widgets/brand_mark.dart';

const _size = 1024.0;

/// White, so the blue of the plane reads as Telegram's.
const _tile = Colors.white;

/// The share of the icon the mark spans, across its longer side.
const _markScale = 0.64;

void main() {
  Future<void> render(
    WidgetTester tester,
    CustomPainter painter,
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

  /// The launcher mark, read from its source image, with the box its
  /// visible pixels take up.
  Future<(ui.Image, Rect)> loadMark(WidgetTester tester) async {
    final bytes = File('tool/icon/source/telegrive.png').readAsBytesSync();
    final (image, pixels) = (await tester.runAsync(() async {
      final frame = await (await ui.instantiateImageCodec(bytes)).getNextFrame();
      final data = await frame.image.toByteData();
      return (frame.image, data!.buffer.asUint8List());
    }))!;
    var (left, top, right, bottom) = (image.width, image.height, 0, 0);
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        if (pixels[(y * image.width + x) * 4 + 3] <= 8) continue;
        if (x < left) left = x;
        if (x > right) right = x;
        if (y < top) top = y;
        if (y > bottom) bottom = y;
      }
    }
    return (
      image,
      Rect.fromLTRB(left.toDouble(), top.toDouble(), right + 1.0, bottom + 1.0),
    );
  }

  Future<void> renderMark(WidgetTester tester, String name, {Color? tile}) async {
    final (image, box) = await loadMark(tester);
    await render(tester, _MarkPainter(image, box, tile: tile), name);
  }

  testWidgets('full icon', (tester) async {
    await renderMark(tester, 'icon', tile: _tile);
  });

  testWidgets('adaptive foreground', (tester) async {
    // flutter_launcher_icons insets the foreground by 16% on each side,
    // which is already Android's visible area, so the mark is drawn at the
    // same size as on the full icon, inside the 66 dp safe circle.
    await renderMark(tester, 'foreground');
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

/// [image]'s mark, the part of it inside [box], centred on a square and
/// scaled so its longer side spans [_markScale] of it, on [tile] when given.
class _MarkPainter extends CustomPainter {
  const _MarkPainter(this.image, this.box, {this.tile});

  final ui.Image image;
  final Rect box;
  final Color? tile;

  @override
  void paint(Canvas canvas, Size size) {
    if (tile != null) canvas.drawRect(Offset.zero & size, Paint()..color = tile!);
    final scale = size.shortestSide * _markScale / box.longestSide;
    final drawn = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: box.width * scale,
      height: box.height * scale,
    );
    canvas.drawImageRect(
      image,
      box,
      drawn,
      Paint()
        ..filterQuality = FilterQuality.high
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(_MarkPainter old) =>
      old.image != image || old.box != box || old.tile != tile;
}
