import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitType;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../core/platform/app_platform.dart';
import '../features/backup/data/watched_folders.dart';
import '../infrastructure/storage/preferences.dart';

/// Telegrive in a Mac's menu bar, Windows' notification area or a Linux
/// tray, while Keep running in the background is on. Closing the window
/// then hides it, and the app goes on syncing folders and finishing
/// transfers until Quit in the icon's menu, which also opens the window
/// and pauses or resumes folder sync. A Mac drops the app from the Dock
/// while its window is hidden, as a menu bar app does.
///
/// With it off there is no icon, and closing the window quits, closing
/// TDLib on the way out as quitting from the menu does.
final desktopTrayProvider = Provider<void>((ref) {
  if (!AppPlatform.isDesktop) return;
  final keepRunning = ref.watch(preferencesProvider.select((p) => p.keepRunning));
  final tray = DesktopTray._(ref, keepRunning: keepRunning);
  ref.onDispose(tray._stop);
  ref.listen<bool>(watchedFoldersProvider.select((s) => s.paused), (_, _) => unawaited(tray._setMenu()));
  unawaited(tray._start());
});

class DesktopTray with TrayListener, WindowListener {
  DesktopTray._(this._ref, {required this.keepRunning});

  final Ref _ref;
  final bool keepRunning;
  bool _iconUp = false;
  bool _stopped = false;

  /// Where the icon is among the app's assets: a black template a Mac tints
  /// to suit its menu bar, an .ico for Windows, a PNG for Linux.
  static String get _icon {
    if (Platform.isMacOS) return 'assets/brand/tray_template.png';
    if (Platform.isWindows) return 'assets/brand/tray.ico';
    return 'assets/brand/tray.png';
  }

  Future<void> _start() async {
    windowManager.addListener(this);
    // Closing is always held, so either way it goes through [onWindowClose].
    await windowManager.setPreventClose(true);
    if (!keepRunning || _stopped) return;
    trayManager.addListener(this);
    try {
      await trayManager.setIcon(_icon, isTemplate: Platform.isMacOS);
      if (!Platform.isLinux) await trayManager.setToolTip('Telegrive');
      _iconUp = true;
      await _setMenu();
    } catch (e) {
      // A Linux desktop without a tray: closing then quits, so the app
      // can't be left running out of reach.
      debugPrint('[Tray] $e');
      _iconUp = false;
    }
  }

  void _stop() {
    _stopped = true;
    windowManager.removeListener(this);
    trayManager.removeListener(this);
    if (_iconUp) unawaited(trayManager.destroy());
    _iconUp = false;
  }

  Future<void> _setMenu() async {
    if (!_iconUp || _stopped) return;
    final paused = _ref.read(watchedFoldersProvider).paused;
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'open', label: 'Open Telegrive'),
          MenuItem.separator(),
          MenuItem(key: 'pause', label: paused ? 'Resume folder sync' : 'Pause folder sync'),
          MenuItem.separator(),
          MenuItem(key: 'quit', label: 'Quit Telegrive'),
        ],
      ),
    );
  }

  /// Brings the window back, with the app in the Dock again on a Mac.
  static Future<void> show() async {
    if (Platform.isMacOS) await windowManager.setSkipTaskbar(false);
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _hide() async {
    await windowManager.hide();
    if (Platform.isMacOS) await windowManager.setSkipTaskbar(true);
  }

  /// Quits the way the system's own Quit does, so TDLib closes first.
  static Future<void> quit() async {
    await windowManager.setPreventClose(false);
    await ServicesBinding.instance.exitApplication(AppExitType.cancelable);
  }

  @override
  void onWindowClose() => unawaited(keepRunning && _iconUp ? _hide() : quit());

  @override
  void onTrayIconMouseDown() {
    // A Mac opens a menu bar icon's menu on a click; Windows opens the app.
    if (Platform.isMacOS) {
      unawaited(trayManager.popUpContextMenu());
    } else {
      unawaited(show());
    }
  }

  @override
  void onTrayIconRightMouseDown() => unawaited(trayManager.popUpContextMenu());

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    final folders = _ref.read(watchedFoldersProvider.notifier);
    switch (menuItem.key) {
      case 'open':
        unawaited(show());
      case 'pause':
        unawaited(_ref.read(watchedFoldersProvider).paused ? folders.resume() : folders.pause());
      case 'quit':
        unawaited(quit());
    }
  }
}
