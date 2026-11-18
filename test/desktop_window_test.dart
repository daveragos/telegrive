import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:telegrive/app/desktop_window.dart';

void main() {
  test('a kept place reads back as it was written', () {
    const rect = Rect.fromLTWH(120, 80, 1300, 840);
    expect(DesktopWindow.readBounds(DesktopWindow.writeBounds(rect)), rect);
  });

  test('nothing kept, a smaller window than allowed, or a damaged entry opens at the first size', () {
    expect(DesktopWindow.readBounds(null), isNull);
    expect(DesktopWindow.readBounds(DesktopWindow.writeBounds(const Rect.fromLTWH(0, 0, 400, 300))), isNull);
    expect(DesktopWindow.readBounds('{"x": 1}'), isNull);
    expect(DesktopWindow.readBounds('not json'), isNull);
  });
}
