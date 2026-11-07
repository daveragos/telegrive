import 'package:flutter/foundation.dart';

import '../../backup/data/phone_folders.dart';

/// One folder of a phone folder going up: where it sits below the picked
/// folder, empty for the picked folder itself, and the files that go in it.
typedef FolderUploadGroup = ({List<String> path, List<PhoneDocument> files});

/// The files of a phone folder picked to upload, grouped by the drive
/// folder each goes into, parents before the folders inside them. Hidden
/// files and folders, whose names start with a dot, and empty files are
/// left out: Android names files still being written or in its trash that
/// way, and Telegram takes no empty file.
@immutable
class FolderUploadPlan {
  const FolderUploadPlan._({
    required this.name,
    required this.groups,
    required this.skipped,
  });

  factory FolderUploadPlan.of(String name, List<PhoneDocument> documents) {
    final byDir = <String, List<PhoneDocument>>{};
    var skipped = 0;
    for (final doc in documents) {
      final path = _segments(doc.dir);
      final hidden =
          doc.name.startsWith('.') || path.any((part) => part.startsWith('.'));
      if (hidden || doc.size <= 0 || doc.uri == null) {
        skipped++;
        continue;
      }
      (byDir[path.join('/')] ??= []).add(doc);
    }
    final groups = [
      for (final MapEntry(key: dir, value: files) in byDir.entries)
        (path: _segments(dir), files: files),
    ]..sort(_parentsFirst);
    return FolderUploadPlan._(name: name, groups: groups, skipped: skipped);
  }

  /// The picked folder's name, which its drive folder takes.
  final String name;
  final List<FolderUploadGroup> groups;

  /// Files left out as hidden or empty.
  final int skipped;

  int get fileCount => groups.fold(0, (sum, g) => sum + g.files.length);

  int get bytes => groups.fold(
    0,
    (sum, g) => g.files.fold(sum, (total, file) => total + file.size),
  );

  /// The folders inside the picked one that get files.
  int get subfolderCount => {
    for (final group in groups)
      for (var depth = 1; depth <= group.path.length; depth++)
        group.path.take(depth).join('/'),
  }.length;

  static List<String> _segments(String dir) => [
    for (final part in dir.split('/'))
      if (part.isNotEmpty) part,
  ];

  /// Shallower folders first, then by path, so each folder is made before
  /// the ones inside it and the order stays the same from one try to the
  /// next.
  static int _parentsFirst(FolderUploadGroup a, FolderUploadGroup b) {
    final depth = a.path.length.compareTo(b.path.length);
    return depth != 0 ? depth : a.path.join('/').compareTo(b.path.join('/'));
  }
}
