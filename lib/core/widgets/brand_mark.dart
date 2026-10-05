import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';

/// The Telegrive mark: a paper plane folded into a drive, its facets in the
/// app's blue and green and a yellow. The picture is rendered from
/// tool/icon/source/telegrive.png, as every icon is.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 56});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/brand/mark.png',
      width: size,
      height: size,
      filterQuality: FilterQuality.medium,
      excludeFromSemantics: true,
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
