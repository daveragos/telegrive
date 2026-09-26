import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';

/// The Telegrive mark: a paper plane over a baseline, on a flat accent tile.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 56});

  final double size;

  /// The one fixed brand colour, the light-theme accent.
  static const Color tile = Color(0xFF2356E0);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tile,
        borderRadius: BorderRadius.circular(size * 0.24),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            bottom: size * 0.2,
            child: Container(
              width: size * 0.46,
              height: size * 0.07,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(size),
              ),
            ),
          ),
          Transform.translate(
            offset: Offset(size * 0.02, -size * 0.05),
            child: Transform.rotate(
              angle: -math.pi / 7,
              child: Icon(Icons.send_rounded, size: size * 0.48, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
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
