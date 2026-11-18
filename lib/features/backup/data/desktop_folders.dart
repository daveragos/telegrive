import 'dart:io';

import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;

import 'phone_folders.dart';

/// Folders on this computer, read where they are. What [list] gives looks
/// as a phone folder's listing does, so uploading a folder and watching
/// one plan from it the same way: each file's [PhoneDocument.uri] is its
/// path, and its id the path inside the folder, which stays while the file
/// keeps its name and place.
abstract final class DesktopFolders {
  /// Files the system or another app leaves in folders, which are nobody's
  /// to upload: Finder's and Explorer's notes on a folder, Office's lock
  /// files, and downloads still on their way.
  static bool isClutter(String name) {
    final lower = name.toLowerCase();
    return lower == '.ds_store' ||
        lower == 'thumbs.db' ||
        lower == 'desktop.ini' ||
        lower.startsWith('~\$') ||
        lower.startsWith('._') ||
        lower.endsWith('.part') ||
        lower.endsWith('.crdownload') ||
        lower.endsWith('.download') ||
        lower.endsWith('.tmp');
  }

  /// The files under [root], every folder down when [recursive], at most
  /// [limit] of them, with `truncated` set when there were more. Links are
  /// not followed, so a link to a folder above can't loop, and a folder
  /// that can't be read is passed over with what is in it.
  static Future<({List<PhoneDocument> files, bool truncated})> list(
    String root, {
    bool recursive = true,
    int limit = PhoneFolders.listLimit,
  }) async {
    final files = <PhoneDocument>[];
    final entries = Directory(root)
        .list(recursive: recursive, followLinks: false)
        .handleError((_) {}, test: (e) => e is FileSystemException);
    await for (final entry in entries) {
      if (entry is! File) continue;
      final relative = p.relative(entry.path, from: root);
      final name = p.basename(relative);
      if (isClutter(name)) continue;
      if (files.length == limit) return (files: files, truncated: true);
      final FileStat stat;
      try {
        stat = await entry.stat();
      } on FileSystemException {
        continue;
      }
      final dir = p.dirname(relative);
      files.add(
        PhoneDocument(
          id: p.split(relative).join('/'),
          name: name,
          mimeType: lookupMimeType(name) ?? '',
          size: stat.size,
          modifiedAt: stat.modified,
          dir: dir == '.' ? '' : p.split(dir).join('/'),
          uri: entry.path,
        ),
      );
    }
    return (files: files, truncated: false);
  }
}
