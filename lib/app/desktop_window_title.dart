import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../core/config/app_config.dart';
import '../core/platform/app_platform.dart';
import '../features/drive/domain/drive_models.dart';
import '../features/files/presentation/file_location.dart';
import 'desktop_sidebar.dart';
import 'router.dart';

/// On a computer, the window is named for where it is, as a file manager's
/// is: the folder open in Files, or the place, Photos or Trash say. The
/// Window menu, Mission Control and the taskbar show it.
final desktopWindowTitleProvider = Provider<void>((ref) {
  if (!AppPlatform.isDesktop) return;
  final router = ref.watch(routerProvider);
  var folders = const <String, DriveFolder>{};
  String? shown;
  void follow() {
    final title = WindowTitle.at(DesktopNavigation.location(router), folders);
    if (title == shown) return;
    shown = title;
    unawaited(windowManager.setTitle(title));
  }

  ref.listen(folderIndexProvider, (_, next) {
    folders = next.value ?? folders;
    follow();
  }, fireImmediately: true);
  router.routerDelegate.addListener(follow);
  ref.onDispose(() => router.routerDelegate.removeListener(follow));
});

abstract final class WindowTitle {
  static const _pages = {
    '/search': 'Search',
    '/private': 'Private',
    '/checkup': 'Check my drive',
    '/changes': 'Changes',
    '/space': 'Stored in Telegram',
    '/category': 'Files',
  };

  /// The window's name at [location]: a folder in Files by its name, a
  /// place by the sidebar's name for it, and the app's own name on Home
  /// and the pages that show one file.
  static String at(String location, Map<String, DriveFolder> folders) {
    final segments = Uri.parse(location).pathSegments;
    if (segments.length == 2 && segments.first == 'files') {
      return folders[segments[1]]?.name ?? 'Files';
    }
    for (final place in [
      ...DesktopNavigation.places,
      ...DesktopNavigation.morePlaces,
      DesktopNavigation.transfers,
      DesktopNavigation.settings,
    ]) {
      if (place.path != '/home' && place.isCurrentAt(location)) return place.label;
    }
    for (final MapEntry(key: path, value: name) in _pages.entries) {
      if (location == path || location.startsWith('$path/')) return name;
    }
    return AppConfig.appName;
  }
}
