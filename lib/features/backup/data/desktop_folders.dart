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

  /// Folders a Mac shows as one file, an app or a library, whose insides
  /// are the app's own business: a Photos library in Pictures holds every
  /// photo again, in pieces no one could put back together.
  static bool isPackage(String name) => _packages.contains(p.extension(name).toLowerCase());

  static const Set<String> _packages = {
    '.app',
    '.photoslibrary',
    '.photolibrary',
    '.musiclibrary',
    '.tvlibrary',
    '.imovielibrary',
    '.fcpbundle',
    '.lrdata',
  };

  /// Whether a change at [relative], a path inside a watched folder, is one
  /// a check would pass over anyway: inside a hidden folder or a package,
  /// or to a hidden or cluttering file.
  static bool ignored(String relative) {
    final parts = p.split(relative);
    if (parts.isEmpty || parts.first == '..') return true;
    return parts.any((part) => part.startsWith('.') || isPackage(part)) || isClutter(parts.last);
  }

  /// The files under [root], every folder down when [recursive], at most
  /// [limit] of them, with `truncated` set when there were more. Links are
  /// not followed, so a link to a folder above can't loop, a folder that
  /// can't be read is passed over with what is in it, and packages aren't
  /// gone into. With [skipHidden] hidden folders aren't either; without,
  /// their files are listed for the caller to count.
  static Future<({List<PhoneDocument> files, bool truncated})> list(
    String root, {
    bool recursive = true,
    bool skipHidden = false,
    int limit = PhoneFolders.listLimit,
  }) async {
    final files = <PhoneDocument>[];
    final folders = [Directory(root)];
    while (folders.isNotEmpty) {
      final folder = folders.removeAt(0);
      final List<FileSystemEntity> entries;
      try {
        entries = await folder.list(followLinks: false).toList();
      } on FileSystemException {
        continue;
      }
      entries.sort((a, b) => a.path.compareTo(b.path));
      for (final entry in entries) {
        final name = p.basename(entry.path);
        if (entry is Directory) {
          if (recursive && !isPackage(name) && !(skipHidden && name.startsWith('.'))) {
            folders.add(entry);
          }
          continue;
        }
        if (entry is! File || isClutter(name)) continue;
        if (files.length == limit) return (files: files, truncated: true);
        final FileStat stat;
        try {
          stat = await entry.stat();
        } on FileSystemException {
          continue;
        }
        final relative = p.relative(entry.path, from: root);
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
    }
    return (files: files, truncated: false);
  }

  /// The folders under [root], every one down, leaving out hidden folders
  /// and packages, at most [limit] of them.
  static Future<List<String>> folders(String root, {int limit = 2000}) async {
    final found = <String>[];
    final pending = [Directory(root)];
    while (pending.isNotEmpty && found.length < limit) {
      final List<FileSystemEntity> entries;
      try {
        entries = await pending.removeAt(0).list(followLinks: false).toList();
      } on FileSystemException {
        continue;
      }
      for (final entry in entries) {
        final name = p.basename(entry.path);
        if (entry is! Directory || name.startsWith('.') || isPackage(name)) continue;
        if (found.length == limit) break;
        found.add(entry.path);
        pending.add(entry);
      }
    }
    return found;
  }
}
