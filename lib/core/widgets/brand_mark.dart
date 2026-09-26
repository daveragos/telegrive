import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';

/// The Telegrive mark: a paper plane, the way Telegram sends, folded from
/// three facets into one rounded triangle. A green
/// wing, a yellow body and a blue keel, with thin creases between them.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 56});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: const CustomPaint(painter: BrandPainter()),
    );
  }
}

/// Draws the mark into a square. The app draws it bare; tool/icon renders
/// the launcher icons, the notification icon and the channel photo with it.
class BrandPainter extends CustomPainter {
  const BrandPainter({
    this.scale = 0.92,
    this.tile,
    this.tileRadius = 0,
    this.silhouette,
  });

  /// Share of the square the plane spans.
  final double scale;

  /// Background filling the square, if any.
  final Color? tile;

  /// Corner radius of [tile], as a share of the side.
  final double tileRadius;

  /// One colour for every facet (notification and themed icons).
  final Color? silhouette;

  static const Color green = Color(0xFF0EBC5F);
  static const Color sky = Color(0xFF78C9FF);
  static const Color yellow = Color(0xFFFECA03);
  static const Color lightYellow = Color(0xFFFFE21A);
  static const Color blue = Color(0xFF3186FF);
  static const Color lavender = Color(0xFFA9A8FF);

  static const Offset _nose = Offset(0.86, 0.17);
  static const Offset _tail = Offset(0.13, 0.47);
  static const Offset _keel = Offset(0.47, 0.86);
  static const Rect _bounds = Rect.fromLTRB(0.13, 0.17, 0.86, 0.86);

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    if (tile != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(side * tileRadius)),
        Paint()..color = tile!,
      );
    }
    if (scale <= 0) return;

    final unit = side * scale / _bounds.longestSide;
    canvas
      ..save()
      ..translate(size.width / 2, size.height / 2)
      ..scale(unit)
      ..translate(-_bounds.center.dx, -_bounds.center.dy);

    // The crease meets the back edge a little past halfway; the keel takes
    // the lower part of the leading edge.
    final fold = Offset.lerp(_tail, _keel, 0.52)!;
    final keelTop = Offset.lerp(_nose, _keel, 0.56)!;

    canvas
      ..saveLayer(_bounds.inflate(0.1), Paint())
      ..clipPath(_rounded([_nose, _tail, _keel], 0.06));
    // Each facet shades the way light falls across a fold: the wing cools
    // to sky at its tail, the body brightens outward, the keel fades to
    // lavender at its tip.
    final outer = Offset.lerp(_nose, keelTop, 0.5)! + const Offset(0.08, 0.05);
    final facets = [
      (
        [_nose, _tail, fold],
        ui.Gradient.linear(_tail, Offset.lerp(_tail, _nose, 0.42)!, [sky, green], [0.12, 1]),
      ),
      (
        [_nose, fold, keelTop],
        ui.Gradient.linear(fold, outer, [yellow, lightYellow], [0.35, 1]),
      ),
      (
        [fold, _keel, keelTop],
        ui.Gradient.linear(fold, Offset.lerp(_keel, keelTop, 0.3)!, [blue, lavender], [0.55, 1]),
      ),
    ];
    for (final (points, shader) in facets) {
      final paint = Paint();
      silhouette == null ? paint.shader = shader : paint.color = silhouette!;
      canvas.drawPath(Path()..addPolygon(points, true), paint);
    }
    // Creases cut through to whatever is behind, so the mark works on any
    // background and as a one-colour silhouette.
    final crease = Paint()
      ..blendMode = BlendMode.clear
      ..strokeWidth = math.max(0.022, 1 / unit)
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawLine(_nose, fold, crease)
      ..drawLine(fold, keelTop, crease)
      ..restore()
      ..restore();
  }

  /// [points] with each corner cut [r] back along its edges and curved.
  static Path _rounded(List<Offset> points, double r) {
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final previous = points[(i - 1 + points.length) % points.length];
      final corner = points[i];
      final next = points[(i + 1) % points.length];
      final from = corner + (previous - corner) / (previous - corner).distance * r;
      final to = corner + (next - corner) / (next - corner).distance * r;
      i == 0 ? path.moveTo(from.dx, from.dy) : path.lineTo(from.dx, from.dy);
      path.quadraticBezierTo(corner.dx, corner.dy, to.dx, to.dy);
    }
    return path..close();
  }

  @override
  bool shouldRepaint(BrandPainter old) =>
      old.scale != scale ||
      old.tile != tile ||
      old.tileRadius != tileRadius ||
      old.silhouette != silhouette;
}

/// Mark and name side by side.
class BrandLockup extends StatelessWidget {
  const BrandLockup({super.key, this.markSize = 40});

  final double markSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        BrandMark(size: markSize),
        SizedBox(width: markSize * 0.3),
        Text(
          'Telegrive',
          style: context.text.titleLarge?.copyWith(fontSize: markSize * 0.5),
        ),
      ],
    );
  }
}
