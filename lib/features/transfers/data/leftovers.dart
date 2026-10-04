import 'dart:io';

import 'package:path/path.dart' as p;

/// The folders in the app's cache where copies made for an upload wait:
/// staged picks, split parts, thumbnails, the file picker's copies, shares
/// and captures. Anything in them that no transfer or share still needs is
/// a leftover.
const leftoverDirs = [
  'telegrive-staging',
  'telegrive-parts',
  'telegrive-thumbs',
  'file_picker',
  'shared',
  'captured',
];

/// Deletes what sits directly in [roots] that nothing needs, and returns
/// the bytes it freed. An entry stays when it is one of the [keep] paths
/// or a folder holding one, and when anything in it changed less than
/// [minAge] before [now], since a pick or a share may still be being
/// copied into it.
Future<int> sweepLeftovers({
  required List<Directory> roots,
  required Set<String> keep,
  Duration minAge = const Duration(minutes: 10),
  DateTime? now,
}) async {
  final cutoff = (now ?? DateTime.now()).subtract(minAge);
  final kept = {for (final path in keep) p.normalize(path)};
  bool needed(String path) => kept.any((k) => k == path || p.isWithin(path, k));
  var freed = 0;
  for (final root in roots) {
    if (!await root.exists()) continue;
    await for (final entry in root.list(followLinks: false)) {
      if (needed(p.normalize(entry.path))) continue;
      try {
        final (bytes, changed) = await _measure(entry);
        if (changed.isAfter(cutoff)) continue;
        await entry.delete(recursive: true);
        freed += bytes;
      } on FileSystemException catch (_) {
        // Gone already, or not ours to delete; the next sweep looks again.
      }
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
