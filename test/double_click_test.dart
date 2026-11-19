import 'package:flutter_test/flutter_test.dart';
import 'package:telegrive/core/platform/desktop_input.dart';

void main() {
  test('a second click on the same item soon after is a double-click, and a third starts over', () {
    var now = DateTime(2026, 11, 19, 3);
    final clicks = DoubleClick(clock: () => now);
    expect(clicks.on('a'), isFalse);
    now = now.add(const Duration(milliseconds: 200));
    expect(clicks.on('a'), isTrue);
    now = now.add(const Duration(milliseconds: 200));
    expect(clicks.on('a'), isFalse);
  });

  test('clicks on two items, or too far apart, are two clicks', () {
    var now = DateTime(2026, 11, 19, 3);
    final clicks = DoubleClick(clock: () => now);
    expect(clicks.on('a'), isFalse);
    expect(clicks.on('b'), isFalse);
    now = now.add(const Duration(milliseconds: 600));
    expect(clicks.on('b'), isFalse);
  });
}
