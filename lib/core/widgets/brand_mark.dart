import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The Telegrive mark: a paper plane carried on a drive-blue tile.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 64});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.3),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3B82F6), Color(0xFF2F6FED), Color(0xFF22B8E6)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2F6FED).withValues(alpha: 0.35),
            blurRadius: size * 0.35,
            offset: Offset(0, size * 0.12),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            bottom: size * 0.2,
            child: Container(
              width: size * 0.5,
              height: size * 0.08,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(size),
              ),
            ),
          ),
          Transform.translate(
            offset: Offset(size * 0.02, -size * 0.05),
            child: Transform.rotate(
              angle: -math.pi / 7,
              child: Icon(Icons.send_rounded, size: size * 0.5, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

/// Mark plus name, for the welcome and splash screens.
class BrandLockup extends StatelessWidget {
  const BrandLockup({super.key, this.markSize = 88});

  final double markSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        BrandMark(size: markSize),
        SizedBox(height: markSize * 0.28),
        Text(
          'telegrive',
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -1,
          ),
        ),
      ],
    );
  }
}
