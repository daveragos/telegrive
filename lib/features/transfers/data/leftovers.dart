import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../infrastructure/storage/app_dirs.dart';

/// The folders in the app's cache where copies made for an upload wait:
/// staged picks, split parts, thumbnails, those of a gallery album's photos,
/// small copies of photos, the file picker's copies, shares, captures, files
/// from the watched phone folders, and files fetched to make a preview of.
/// Anything in them that no transfer or share still needs is a leftover.
const leftoverDirs = [
  'telegrive-staging',
  'telegrive-parts',
  'telegrive-thumbs',
  'telegrive-album-thumbs',
  'telegrive-small',
  'file_picker',
  'shared',
  'captured',
  'watched',
  'takeout',
  'previews',
];

/// Files in the app's cache that only setting up the drive needs: the
/// channel photo handed to Telegram.
const leftoverFiles = ['telegrive-channel-photo.jpg'];

/// Where the app's own copies of files are: its scratch folder (see
/// [scratchDirectory]), where it makes them itself, and on iOS its
/// temporary folder, where the photo library and the file picker put the
/// copies they hand over. iOS gives an app no path into the photo library
/// or into another app's files, so everything they hand over there is a
/// copy. Android 11 and later hand over the photo itself, where it lies,
/// and a computer's file picker the file itself, wherever it is.
class CopyFolders {
  const CopyFolders({required this.cache, this.iosTemp});

  /// This device's.
  static Future<CopyFolders> find() async {
    final cache = (await scratchDirectory()).path;
    return CopyFolders(
      cache: cache,
      iosTemp: Platform.isIOS ? iosTempBeside(cache) : null,
    );
  }

  /// The app's scratch folder, which the [leftoverDirs] are in.
  final String cache;

  /// The app's temporary folder on iOS; null elsewhere.
  final String? iosTemp;

  /// Whether [path], a file the gallery or the file picker handed over, is
  /// a copy the app deletes once it is sent, rather than the original.
  bool holds(String path) =>
      p.isWithin(cache, path) || (iosTemp != null && p.isWithin(iosTemp!, path));
}

/// The temporary folder of an iOS app whose cache is [cache]: `tmp`, beside
/// the `Library` that holds `Caches`. Null when [cache] isn't laid out as an
/// iOS app's is.
String? iosTempBeside(String cache) {
  final library = p.dirname(cache);
  if (p.basename(cache) != 'Caches' || p.basename(library) != 'Library') return null;
  return p.join(p.dirname(library), 'tmp');
}

/// Where [findLeftovers] looks in [folders]: the [leftoverDirs] and the
/// [leftoverFiles] in the cache, and on iOS every file in the temporary
/// folder, each a copy the photo library or the file picker made.
({List<Directory> roots, List<Directory> fileRoots, List<File> files}) leftoverPlaces(
  CopyFolders folders,
) => (
  roots: [for (final dir in leftoverDirs) Directory(p.join(folders.cache, dir))],
  fileRoots: [if (folders.iosTemp case final temp?) Directory(temp)],
  files: [for (final name in leftoverFiles) File(p.join(folders.cache, name))],
);

/// A copy nothing needs, and the bytes in it.
typedef Leftover = ({FileSystemEntity entry, int bytes});

/// What sits directly in [roots], each file at any depth in [fileRoots],
/// and each of [files] that is there, that nothing needs. An entry is
/// needed when it is one of the [keep] paths or a folder holding one, and
/// when anything in it changed less than [minAge] before [now], since a
/// pick or a share may still be being copied into it. The files in
/// [fileRoots] are looked at one by one, since the folders there are the
/// plugins' own and hold copies made for many uploads. Nothing is deleted.
Future<List<Leftover>> findLeftovers({
  required List<Directory> roots,
  List<Directory> fileRoots = const [],
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
  for (final root in fileRoots) {
    if (!await root.exists()) continue;
    final entries = root
        .list(recursive: true, followLinks: false)
        // A folder that can't be read is passed over with what is in it.
        .handleError((_) {}, test: (e) => e is FileSystemException);
    await for (final entry in entries) {
      if (entry is File) await consider(entry);
    }
  }
  for (final file in files) {
    if (await file.exists()) await consider(file);
  }
  return found;
}

/// Deletes what [findLeftovers] finds, and returns the bytes it freed. The
/// folders in [fileRoots] stay, as the plugins write into them again.
Future<int> sweepLeftovers({
  required List<Directory> roots,
  List<Directory> fileRoots = const [],
  List<File> files = const [],
  required Set<String> keep,
  Duration minAge = const Duration(minutes: 10),
  DateTime? now,
}) async {
  final found = await findLeftovers(
    roots: roots,
    fileRoots: fileRoots,
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
