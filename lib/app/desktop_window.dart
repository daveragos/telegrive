import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import '../core/platform/app_platform.dart';

/// The app's window on a computer: the smallest it gets, its size the first
/// time, and where it was left, which it opens at again.
abstract final class DesktopWindow {
  /// Wide enough for the sidebar beside a list with its columns.
  static const Size minimumSize = Size(900, 600);
  static const Size firstSize = Size(1280, 820);

  static const String _boundsKey = 'window_bounds';

  /// Sets the window up and shows it, where it was left when that place is
  /// still on a screen. Nothing on a phone.
  static Future<void> open(SharedPreferences prefs) async {
    if (!AppPlatform.isDesktop) return;
    await windowManager.ensureInitialized();
    final saved = readBounds(prefs.getString(_boundsKey));
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(title: 'Telegrive', minimumSize: minimumSize, size: firstSize, center: true),
      () async {
        try {
          if (saved != null && await _onAScreen(saved)) await windowManager.setBounds(saved);
        } catch (e) {
          debugPrint('[Window] $e');
        } finally {
          await windowManager.show();
          await windowManager.focus();
        }
      },
    );
    windowManager.addListener(_BoundsKeeper(prefs));
  }

  /// Whether most of [bounds] is on one of the screens there are now; one
  /// left on a display since unplugged isn't.
  static Future<bool> _onAScreen(Rect bounds) async {
    for (final display in await screenRetriever.getAllDisplays()) {
      final origin = display.visiblePosition ?? Offset.zero;
      final area = origin & (display.visibleSize ?? display.size);
      final shared = area.intersect(bounds);
      if (shared.width >= bounds.width / 2 && shared.height >= bounds.height / 2) return true;
    }
    return false;
  }

  /// The bounds kept in [json], or null when there are none or they don't
  /// read as a window at least [minimumSize].
  @visibleForTesting
  static Rect? readBounds(String? json) {
    if (json == null) return null;
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      final rect = Rect.fromLTWH(
        (map['x'] as num).toDouble(),
        (map['y'] as num).toDouble(),
        (map['w'] as num).toDouble(),
        (map['h'] as num).toDouble(),
      );
      if (rect.width < minimumSize.width || rect.height < minimumSize.height) return null;
      return rect;
    } catch (_) {
      return null;
    }
  }

  @visibleForTesting
  static String writeBounds(Rect rect) =>
      jsonEncode({'x': rect.left, 'y': rect.top, 'w': rect.width, 'h': rect.height});
}

/// Keeps the window's place as it is moved and resized, a moment after it
/// settles. A maximised or full-screen window keeps the place it had before.
class _BoundsKeeper with WindowListener {
  _BoundsKeeper(this._prefs);

  final SharedPreferences _prefs;
  Timer? _settle;

  void _keep() {
    _settle?.cancel();
    _settle = Timer(const Duration(milliseconds: 500), () async {
      try {
        if (await windowManager.isMaximized() || await windowManager.isFullScreen()) return;
        await _prefs.setString(DesktopWindow._boundsKey, DesktopWindow.writeBounds(await windowManager.getBounds()));
      } catch (e) {
        debugPrint('[Window] Could not keep its place: $e');
      }
    });
  }

  @override
  void onWindowResized() => _keep();

  @override
  void onWindowMoved() => _keep();
}
