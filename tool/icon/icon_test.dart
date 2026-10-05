// Renders every picture of the mark from source/telegrive.png: the app's
// own copy of it, the launcher icons, the notification icon and the channel
// photo:
//
//   flutter test tool/icon/icon_test.dart --update-goldens
//   dart run flutter_launcher_icons
//   tool/icon/install.sh
//
// mark.png is the mark alone, filling its square, for BrandMark in the app.
// icon.png is the full-bleed square (iOS, legacy Android); foreground.png is
// the plane alone for Android's adaptive icon, and doubles as the themed
// (monochrome) icon.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _size = 1024.0;

/// White, so the blue of the plane reads as Telegram's.
const _tile = Colors.white;

/// The share of a launcher icon the mark spans, across its longer side.
const _iconScale = 0.64;

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

  Future<void> renderMark(
    WidgetTester tester,
    String name, {
    required double scale,
    Color? tile,
    Color? silhouette,
    double size = _size,
  }) async {
    final (image, box) = await loadMark(tester);
    await render(
      tester,
      _MarkPainter(image, box, scale: scale, tile: tile, silhouette: silhouette),
      name,
      size: size,
    );
  }

  testWidgets('mark', (tester) async {
    await renderMark(tester, 'mark', scale: 1, size: 512);
  });

  testWidgets('full icon', (tester) async {
    await renderMark(tester, 'icon', scale: _iconScale, tile: _tile);
  });

  testWidgets('adaptive foreground', (tester) async {
    // flutter_launcher_icons insets the foreground by 16% on each side,
    // which is already Android's visible area, so the mark is drawn at the
    // same size as on the full icon, inside the 66 dp safe circle.
    await renderMark(tester, 'foreground', scale: _iconScale);
  });

  testWidgets('adaptive background', (tester) async {
    await render(tester, const _Tile(_tile), 'background');
  });

  testWidgets('notification icon', (tester) async {
    // Status-bar icons are white silhouettes; the gaps between the facets
    // stay open.
    await renderMark(tester, 'notification', scale: 0.86, silhouette: Colors.white);
  });

  testWidgets('channel photo', (tester) async {
    // Telegram crops chat photos to a circle and shows them on white, so
    // the mark sits well inside it on a faint blue.
    await renderMark(
      tester,
      'channel_photo',
      scale: 0.54,
      tile: const Color(0xFFEAF1FF),
      size: 640,
    );
  });
}

/// A square of one colour.
class _Tile extends CustomPainter {
  const _Tile(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) =>
      canvas.drawRect(Offset.zero & size, Paint()..color = color);

  @override
  bool shouldRepaint(_Tile old) => old.color != color;
}

/// [image]'s mark, the part of it inside [box], centred on a square and
/// scaled so its longer side spans [scale] of it, on [tile] when given, and
/// in one colour when [silhouette] is.
class _MarkPainter extends CustomPainter {
  const _MarkPainter(this.image, this.box, {required this.scale, this.tile, this.silhouette});

  final ui.Image image;
  final Rect box;
  final double scale;
  final Color? tile;
  final Color? silhouette;

  @override
  void paint(Canvas canvas, Size size) {
    if (tile != null) canvas.drawRect(Offset.zero & size, Paint()..color = tile!);
    final factor = size.shortestSide * scale / box.longestSide;
    final drawn = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: box.width * factor,
      height: box.height * factor,
    );
    canvas.drawImageRect(
      image,
      box,
      drawn,
      Paint()
        ..filterQuality = FilterQuality.high
        ..isAntiAlias = true
        ..colorFilter = silhouette == null
            ? null
            : ColorFilter.mode(silhouette!, BlendMode.srcIn),
    );
  }

  @override
  bool shouldRepaint(_MarkPainter old) =>
      old.image != image ||
      old.box != box ||
      old.scale != scale ||
      old.tile != tile ||
      old.silhouette != silhouette;
}
