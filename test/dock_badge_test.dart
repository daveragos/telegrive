import 'package:flutter_test/flutter_test.dart';
import 'package:telegrive/features/transfers/data/desktop_dock_badge.dart';

void main() {
  test('the Dock badge counts transfers under way, and shows nothing for none', () {
    expect(DockBadge.label(0), isNull);
    expect(DockBadge.label(3), '3');
  });

  test('the taskbar shows progress in whole percent while something runs', () {
    expect(DockBadge.progress(0, 0.5), isNull);
    expect(DockBadge.progress(2, 0.4567), 0.45);
    expect(DockBadge.progress(1, 1.2), 1);
  });
}
