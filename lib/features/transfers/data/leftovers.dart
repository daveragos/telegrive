import 'dart:io';

import 'package:path/path.dart' as p;

/// The folders in the app's cache where copies made for an upload wait:
/// staged picks, split parts, thumbnails, small copies of photos, the file
/// picker's copies, shares, captures and files from the watched phone
/// folders. Anything in them that no transfer or share still needs is a
/// leftover.
const leftoverDirs = [
  'telegrive-staging',
  'telegrive-parts',
  'telegrive-thumbs',
  'telegrive-small',
  'file_picker',
  'shared',
  'captured',
  'watched',
  'takeout',
];

/// Files in the app's cache that only setting up the drive needs: the
/// channel photo handed to Telegram.
const leftoverFiles = ['telegrive-channel-photo.jpg'];

/// A copy nothing needs, and the bytes in it.
typedef Leftover = ({FileSystemEntity entry, int bytes});

/// What sits directly in [roots], and each of [files] that is there, that
/// nothing needs. An entry is needed when it is one of the [keep] paths or
/// a folder holding one, and when anything in it changed less than
/// [minAge] before [now], since a pick or a share may still be being copied
/// into it. Nothing is deleted.
Future<List<Leftover>> findLeftovers({
  required List<Directory> roots,
  List<File> files = const [],
  required Set<String> keep,
  Duration minAge = const Duration(minutes: 10),
  DateTime? now,
}) async {
  final cutoff = (now ?? DateTime.now()).subtract(minAge);
  final kept = {for (final path in keep) p.normalize(path)};
  bool needed(String path) => kept.any((k) => k == path || p.isWithin(path, k));
  final found = <Leftover>[];
  Future<void> consider(FileSystemEntity entry) async {
    if (needed(p.normalize(entry.path))) return;
    try {
      final (bytes, changed) = await _measure(entry);
      if (!changed.isAfter(cutoff)) found.add((entry: entry, bytes: bytes));
    } on FileSystemException catch (_) {
      // Gone already; the next look passes it over.
    }
  }

  for (final root in roots) {
    if (!await root.exists()) continue;
    await for (final entry in root.list(followLinks: false)) {
      await consider(entry);
    }
  }
  for (final file in files) {
    if (await file.exists()) await consider(file);
  }
  return found;
}

/// Deletes what [findLeftovers] finds, and returns the bytes it freed.
Future<int> sweepLeftovers({
  required List<Directory> roots,
  List<File> files = const [],
  required Set<String> keep,
  Duration minAge = const Duration(minutes: 10),
  DateTime? now,
}) async {
  final found = await findLeftovers(
    roots: roots,
    files: files,
    keep: keep,
    minAge: minAge,
    now: now,
  );
  var freed = 0;
  for (final leftover in found) {
    try {
      await leftover.entry.delete(recursive: true);
      freed += leftover.bytes;
    } on FileSystemException catch (_) {
      // Gone already, or not ours to delete; the next sweep looks again.
    }
  }
  return freed;
}

/// The bytes in [entry] and when anything in it last changed. A folder's
/// own time only moves when an entry is added or removed, so a file still
/// being written inside it is looked at too.
Future<(int bytes, DateTime changed)> _measure(FileSystemEntity entry) async {
  final stat = await entry.stat();
  var bytes = stat.type == FileSystemEntityType.directory ? 0 : stat.size;
  var changed = stat.modified;
  if (stat.type == FileSystemEntityType.directory) {
    await for (final child in Directory(entry.path).list(recursive: true, followLinks: false)) {
      final childStat = await child.stat();
      if (childStat.type == FileSystemEntityType.file) bytes += childStat.size;
      if (childStat.modified.isAfter(changed)) changed = childStat.modified;
    }
  }
  return (bytes, changed);
}
