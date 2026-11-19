import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../../core/platform/app_platform.dart';
import 'transfer_queue.dart';

/// On a computer, the app's icon says what's under way, as a computer's
/// own apps do: on a Mac the Dock icon carries the number of transfers in
/// progress, as Mail's carries unread mail, and on Windows the taskbar
/// button fills with how far they've got. Paused ones don't count. Linux
/// has no such place.
final desktopDockBadgeProvider = Provider<void>((ref) {
  if (!AppPlatform.isDesktop) return;
  if (Platform.isMacOS) {
    ref.listen<int>(
      transferQueueProvider.select((s) => s.pending.length - s.pausedCount),
      (_, count) => unawaited(windowManager.setBadgeLabel(DockBadge.label(count))),
      fireImmediately: true,
    );
    ref.onDispose(() => unawaited(windowManager.setBadgeLabel()));
  } else if (Platform.isWindows) {
    ref.listen<double?>(
      transferQueueProvider.select((s) => DockBadge.progress(s.activeCount, s.activeProgress)),
      (_, progress) => unawaited(windowManager.setProgressBar(progress ?? -1)),
      fireImmediately: true,
    );
    ref.onDispose(() => unawaited(windowManager.setProgressBar(-1)));
  }
});

abstract final class DockBadge {
  /// The Dock icon's badge for [count] transfers, none for none.
  static String? label(int count) => count > 0 ? '$count' : null;

  /// The taskbar button's progress, in whole percent so it moves only when
  /// it shows, or null with nothing running.
  static double? progress(int running, double done) =>
      running == 0 ? null : (done.clamp(0, 1) * 100).floor() / 100;
}
