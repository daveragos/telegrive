import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'desktop_folders.dart';

/// Tells when something changes in a folder on this computer, so a watched
/// folder is checked moments after a file lands in it rather than at the
/// next rescan. It only says that something changed; the check that
/// follows lists the folder and works out what.
///
/// macOS and Windows watch a folder and everything below it at once. Linux
/// watches each folder on its own, as inotify does, the ones made later
/// included, up to [maxFolders]. A watch the system drops, when Windows'
/// buffer overflows or the folder is renamed or deleted, is taken up again
/// after [retryAfter]. Changes to hidden files, inside hidden folders or
/// packages, and the clutter [DesktopFolders.isClutter] names say nothing.
class FolderWatcher {
  FolderWatcher(
    this.root, {
    required this.recursive,
    required this.onChange,
    @visibleForTesting bool? perFolder,
  }) : _perFolder = perFolder ?? Platform.isLinux;

  final String root;
  final bool recursive;
  final void Function() onChange;
  final bool _perFolder;

  /// The most folders watched one by one, well within Linux's default
  /// inotify watches per person.
  static const int maxFolders = 2000;

  /// How long a dropped watch waits before it is taken up again.
  static const Duration retryAfter = Duration(seconds: 30);

  final Map<String, StreamSubscription<FileSystemEvent>> _watching = {};
  Timer? _retry;
  bool _stopped = false;

  /// Starts watching. Nothing happens where the system can't watch.
  Future<void> start() async {
    if (_stopped || !FileSystemEntity.isWatchSupported) return;
    if (!_perFolder) {
      _watch(root, recursive: recursive);
      return;
    }
    _watch(root, recursive: false);
    if (recursive) await _watchBelow(root);
  }

  /// Stops watching for good.
  void stop() {
    _stopped = true;
    _retry?.cancel();
    for (final subscription in _watching.values) {
      unawaited(subscription.cancel());
    }
    _watching.clear();
  }

  Future<void> _watchBelow(String folder) async {
    for (final below in await DesktopFolders.folders(folder, limit: maxFolders)) {
      _watch(below, recursive: false);
    }
  }

  void _watch(String folder, {required bool recursive}) {
    if (_stopped || _watching.containsKey(folder) || _watching.length >= maxFolders) return;
    try {
      _watching[folder] = Directory(folder)
          .watch(recursive: recursive)
          .listen(_seen, onError: (Object e) => _lost(folder, e), onDone: () => _lost(folder, null));
    } on FileSystemException catch (e) {
      _lost(folder, e);
    }
  }

  void _seen(FileSystemEvent event) {
    if (_stopped) return;
    final relative = p.relative(event.path, from: root);
    if (relative == '.' || DesktopFolders.ignored(relative)) return;
    // A folder made, or moved in, is watched too, with what is inside it.
    if (_perFolder && recursive && event is FileSystemCreateEvent && event.isDirectory) {
      _watch(event.path, recursive: false);
      unawaited(_watchBelow(event.path));
    }
    onChange();
  }

  void _lost(String folder, Object? error) {
    unawaited(_watching.remove(folder)?.cancel());
    if (error != null) debugPrint('[Watch] $folder: $error');
    if (_stopped || folder != root) return;
    _retry?.cancel();
    _retry = Timer(retryAfter, () {
      if (_stopped) return;
      for (final subscription in _watching.values) {
        unawaited(subscription.cancel());
      }
      _watching.clear();
      unawaited(start());
      onChange();
    });
  }
}
