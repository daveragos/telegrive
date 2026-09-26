// Renders the launcher icon sources from the same drawing as BrandMark:
//
//   flutter test tool/icon/icon_test.dart --update-goldens
//   dart run flutter_launcher_icons
//
// icon.png is the full-bleed square (iOS, legacy Android); foreground.png is
// the glyph alone inside Android's adaptive-icon safe zone.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';

const _size = 1024.0;

class _Glyph extends StatelessWidget {
  const _Glyph({required this.scale, this.showBar = true});

  final double scale;
  final bool showBar;

  @override
  Widget build(BuildContext context) {
    final size = _size * scale;
    return SizedBox.square(
      dimension: _size,
      child: Center(
        child: SizedBox.square(
          dimension: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (showBar)
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
                  child: Icon(
                    Icons.send_rounded,
                    size: size * 0.5,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const _gradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF3B82F6), Color(0xFF2F6FED), Color(0xFF22B8E6)],
);

void main() {
  setUpAll(() async {
    final root =
        '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
    final bytes = await File('$root/MaterialIcons-Regular.otf').readAsBytes();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
  });

  Future<void> render(WidgetTester tester, Widget child, String name) async {
    tester.view.physicalSize = const Size(_size, _size);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(child: child),
      ),
    );
    await expectLater(
      find.byType(RepaintBoundary).first,
      matchesGoldenFile('out/$name.png'),
    );
  }

  testWidgets('full icon', (tester) async {
    await render(
      tester,
      const DecoratedBox(
        decoration: BoxDecoration(gradient: _gradient),
        child: _Glyph(scale: 1),
      ),
      'icon',
    );
  });

  testWidgets('adaptive foreground', (tester) async {
    // Android crops adaptive icons to the middle ~61%; keep the glyph inside.
    await render(tester, const _Glyph(scale: 0.62), 'foreground');
  });

  testWidgets('notification icon', (tester) async {
    // Status-bar icons are white silhouettes; the plane alone reads best.
    await render(
      tester,
      const _Glyph(scale: 1.25, showBar: false),
      'notification',
    );
  });

  testWidgets('adaptive background', (tester) async {
    await render(
      tester,
      const SizedBox.square(
        dimension: _size,
        child: DecoratedBox(decoration: BoxDecoration(gradient: _gradient)),
      ),
      'background',
    );
  });
}
