import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'app_platform.dart';

/// The computer's own file manager: Finder, File Explorer, or the one a
/// Linux desktop has.
abstract final class FileManager {
  /// "Show in Finder", "Show in File Explorer", "Show in Files".
  static String get showIn => 'Show in ${AppPlatform.fileManager}';

  /// Opens the file manager at [path], with the file selected where it can
  /// do that: Finder and File Explorer always, a Linux file manager through
  /// the FileManager1 interface, or else the folder the file is in.
  static Future<void> reveal(String path) async {
    try {
      if (Platform.isMacOS) {
        await Process.run('open', ['-R', path]);
      } else if (Platform.isWindows) {
        await Process.run('explorer.exe', ['/select,', path]);
      } else if (Platform.isLinux) {
        final shown = await Process.run('dbus-send', [
          '--session',
          '--print-reply',
          '--dest=org.freedesktop.FileManager1',
          '--type=method_call',
          '/org/freedesktop/FileManager1',
          'org.freedesktop.FileManager1.ShowItems',
          'array:string:${Uri.file(path)}',
          'string:',
        ]);
        if (shown.exitCode != 0) await Process.run('xdg-open', [p.dirname(path)]);
      }
    } catch (e) {
      debugPrint('[FileManager] Could not show $path: $e');
    }
  }

  /// Opens the file manager at the folder [path].
  static Future<void> open(String path) async {
    try {
      if (Platform.isMacOS) {
        await Process.run('open', [path]);
      } else if (Platform.isWindows) {
        await Process.run('explorer.exe', [path]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [path]);
      }
    } catch (e) {
      debugPrint('[FileManager] Could not open $path: $e');
    }
  }
}
