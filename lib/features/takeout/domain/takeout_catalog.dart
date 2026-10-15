import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/files/file_kind.dart';
import '../../../core/files/zip_reader.dart';

// -----------------------------------------------------------------------------
// What a Takeout export holds
// -----------------------------------------------------------------------------

/// A photo or video in one part of an export.
@immutable
class TakeoutMedia {
  const TakeoutMedia(this.part, this.entry);

  /// The part it is in, by the id the import gives each part.
  final String part;
  final ZipEntry entry;
}

/// What the JSON beside a photo or video says about it. Takeout writes one
/// per file in the same folder, named after the file, with the details
/// Google Photos keeps apart from the file itself.
@immutable
class TakeoutSidecar {
  const TakeoutSidecar({
    required this.folder,
    required this.fileName,
    this.title = '',
    this.takenAt,
    this.favorited = false,
  });

  /// The folder it is in, `/`-separated.
  final String folder;

  /// Its own name, `.json` and all.
  final String fileName;

  /// The name the photo had when it went into Google Photos.
  final String title;
  final DateTime? takenAt;
  final bool favorited;
}

/// An album, as the `metadata.json` in its folder names it.
@immutable
class TakeoutAlbum {
  const TakeoutAlbum({required this.folder, required this.title});

  final String folder;
  final String title;
}

/// Reads a JSON file of an export: a [TakeoutSidecar], a [TakeoutAlbum], or
/// null for anything else, such as the lists of shared albums and prints
/// at the top of the Google Photos folder. Album folders are told by their
/// metadata rather than their names, which Takeout translates.
Object? parseTakeoutJson(String path, List<int> bytes) {
  final Object? json;
  try {
    json = jsonDecode(utf8.decode(bytes, allowMalformed: true));
  } on FormatException {
    return null;
  }
  if (json is! Map<String, dynamic>) return null;
  final slash = path.lastIndexOf('/');
  final folder = slash < 0 ? '' : path.substring(0, slash);
  final fileName = path.substring(slash + 1);

  final taken = _timestamp(json['photoTakenTime']);
  final created = _timestamp(json['creationTime']);
  if (json.containsKey('photoTakenTime') || (created != null && json.containsKey('url'))) {
    final title = json['title'];
    return TakeoutSidecar(
      folder: folder,
      fileName: fileName,
      title: title is String ? title : '',
      takenAt: taken ?? created,
      favorited: json['favorited'] == true,
    );
  }
  final album = json['albumData'] is Map<String, dynamic> ? json['albumData'] as Map<String, dynamic> : json;
  final title = album['title'];
  if (title is String &&
      title.trim().isNotEmpty &&
      (album.containsKey('date') || album.containsKey('access') || identical(album, json['albumData']))) {
    return TakeoutAlbum(folder: folder, title: title.trim());
  }
  return null;
}

/// A Takeout `{"timestamp": "1560601530"}` as a time on this phone, or null
/// when it is missing or zero.
DateTime? _timestamp(Object? field) {
  if (field is! Map) return null;
  final raw = field['timestamp'];
  final seconds = raw is int ? raw : int.tryParse('$raw');
  if (seconds == null || seconds <= 0) return null;
  return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
}

/// Whether a file of an export is one the import reads: a photo or video,
/// or a JSON small enough to be details rather than data.
bool takeoutKeeps(ZipEntry entry) {
  if (!entry.readable || entry.size <= 0) return false;
  final name = entry.name;
  if (name.startsWith('.')) return false;
  if (name.toLowerCase().endsWith('.json')) return entry.size <= _jsonLimit;
  final kind = FileKind.detect(fileName: name);
  return kind == FileKind.image || kind == FileKind.video;
}

bool isTakeoutJson(ZipEntry entry) => entry.name.toLowerCase().endsWith('.json');

/// What tells one file of an export from another: its size and checksum.
/// Takeout gives the copy in an album's folder a name of its own when the
/// album already has one by that name, so the name is left out.
String takeoutKey(ZipEntry entry) => '${entry.size}:${entry.crc.toRadixString(16)}';

/// Bigger JSON files are lists of something else, never one photo's details.
const int _jsonLimit = 256 << 10;

// -----------------------------------------------------------------------------
// Matching each photo with its details
// -----------------------------------------------------------------------------

/// One photo or video to import, found once however many folders and parts
/// of the export hold it: Takeout puts a photo in its year's folder and in
/// the folder of every album it is in.
@immutable
class TakeoutItem {
  const TakeoutItem({
    required this.key,
    required this.name,
    required this.sources,
    this.takenAt,
    this.starred = false,
    this.albums = const [],
    this.described = false,
    this.motionOf,
  });

  /// Its [takeoutKey], the same in every folder and part that holds it,
  /// and in later exports.
  final String key;

  /// The name it goes into the drive with.
  final String name;

  /// Every copy of it, the one in the earliest part first.
  final List<TakeoutMedia> sources;

  /// When it was taken, from its details or else its name.
  final DateTime? takenAt;

  /// Marked as a favourite in Google Photos.
  final bool starred;

  /// The albums it is in, by title.
  final List<String> albums;

  /// Its details were found. One without them may have them in a part not
  /// added yet, so it goes last.
  final bool described;

  /// The photo this video is the moving part of, by key: Google keeps a
  /// Live Photo or motion photo as a photo and a short video, and Takeout
  /// gives the video beside the photo under the photo's name.
  final String? motionOf;

  int get size => sources.first.entry.size;

  TakeoutItem _withMotionOf(String still) => TakeoutItem(
    key: key,
    name: name,
    sources: sources,
    takenAt: takenAt,
    starred: starred,
    albums: albums,
    described: described,
    motionOf: still,
  );

  FileKind get kind => FileKind.detect(fileName: name);
}

/// Everything an export holds once each photo is matched with its details.
@immutable
class TakeoutCatalog {
  const TakeoutCatalog(this.items);

  /// In the order they go up: part by part, as each part lays them out, so
  /// the first parts are done first and can be deleted, with any whose
  /// details weren't found at the end.
  final List<TakeoutItem> items;

  int get photos => items.where((i) => i.kind == FileKind.image).length;
  int get videos => items.where((i) => i.kind == FileKind.video).length;
  int get bytes => items.fold(0, (sum, i) => sum + i.size);
  Set<String> get albums => {for (final item in items) ...item.albums};
}

/// Suffixes Google Photos puts on the saved copy of an edited photo, in
/// the languages Takeout writes them in. Such a copy has no JSON of its
/// own and goes by its original's.
const List<String> takeoutEditedSuffixes = [
  '-edited', '-effects', '-smile', '-mix', '-edytowane', '-bearbeitet', //
  '-bewerkt', '-modificato', '-modifié', '-ha editado', '-editado', '-editat', //
  '-redigeret', '-redigert', '-muokattu', '-upraveno', '-編集済み', '-편집됨', //
];

/// Matches [media] with [sidecars], folds copies of one file into one item,
/// and puts each in the albums [albums] name. [partOrder] lists the parts
/// first to last.
///
/// When the export has details anywhere, only the photos and videos in the
/// same top folders as those details count, so other products picked in the
/// same export, such as Drive, are left out. A zip without any details is
/// taken whole, as a plain archive of photos.
TakeoutCatalog buildTakeoutCatalog({
  required List<TakeoutMedia> media,
  required List<TakeoutSidecar> sidecars,
  required List<TakeoutAlbum> albums,
  required List<String> partOrder,
}) {
  final roots = {
    for (final folder in [for (final s in sidecars) s.folder, for (final a in albums) a.folder])
      ?_root(folder),
  };
  final rank = {for (final (index, part) in partOrder.indexed) part: index};
  final byFolder = <String, _FolderDetails>{};
  for (final sidecar in sidecars) {
    (byFolder[sidecar.folder] ??= _FolderDetails()).add(sidecar);
  }
  final albumOf = {for (final album in albums) album.folder: album.title};

  final groups = <String, _Group>{};
  for (final file in media) {
    final entry = file.entry;
    if (roots.isNotEmpty && !roots.any((root) => entry.path.startsWith('$root/'))) continue;
    final key = takeoutKey(entry);
    final group = groups[key] ??= _Group(key);
    group.sources.add(file);
    if (albumOf[entry.folder] case final album?) group.albums.add(album);
    group.matches.add((file, byFolder[entry.folder]?.match(entry.name)));
  }

  int partRank(TakeoutMedia m) => rank[m.part] ?? partOrder.length;
  int byPlace(TakeoutMedia a, TakeoutMedia b) {
    final byPart = partRank(a).compareTo(partRank(b));
    return byPart != 0 ? byPart : a.entry.headerOffset.compareTo(b.entry.headerOffset);
  }

  final items = [
    for (final group in groups.values)
      () {
        group.sources.sort(byPlace);
        // The copy matched by its own name speaks for the file: an album's
        // copy can carry a counter its year's copy doesn't, and details
        // found through an original or a Live Photo partner say less.
        final ranked = [...group.matches]
          ..sort((a, b) {
            final byHow = (a.$2?.how.index ?? _How.values.length).compareTo(b.$2?.how.index ?? _How.values.length);
            return byHow != 0 ? byHow : byPlace(a.$1, b.$1);
          });
        final (source, match) = ranked.first;
        return TakeoutItem(
          key: group.key,
          name: _nameFor(source.entry.name, match),
          sources: List.unmodifiable(group.sources),
          takenAt: match?.sidecar.takenAt ?? takenFromName(source.entry.name),
          starred: group.matches.any((m) => (m.$2?.sidecar.favorited ?? false) && m.$2!.how != _How.sibling),
          albums: List.unmodifiable(group.albums.toList()..sort()),
          described: match != null,
        );
      }(),
  ];
  // A video beside a photo of the same name, in a folder that holds both,
  // is that photo's moving part.
  String place(TakeoutMedia m) => '${m.entry.folder}/${_withoutExtension(m.entry.name)}'.toLowerCase();
  final stills = <String, String>{};
  for (final item in items) {
    if (item.kind != FileKind.image) continue;
    for (final source in item.sources) {
      stills.putIfAbsent(place(source), () => item.key);
    }
  }
  for (final (index, item) in items.indexed) {
    if (item.kind != FileKind.video) continue;
    final still = item.sources.map((s) => stills[place(s)]).nonNulls.firstOrNull;
    if (still != null) items[index] = item._withMotionOf(still);
  }
  items.sort((a, b) {
    if (a.described != b.described) return a.described ? -1 : 1;
    final byPart = partRank(a.sources.first).compareTo(partRank(b.sources.first));
    if (byPart != 0) return byPart;
    return a.sources.first.entry.headerOffset.compareTo(b.sources.first.entry.headerOffset);
  });
  return TakeoutCatalog(List.unmodifiable(items));
}

/// The top two folders of [folder], `Takeout/Google Photos`, under which
/// Takeout puts everything of one product.
String? _root(String folder) {
  final parts = folder.split('/');
  return parts.length < 2 ? null : '${parts[0]}/${parts[1]}';
}

/// The name a file goes into the drive with: its name in the export, or,
/// when Takeout shortened that, the name it had in Google Photos.
String _nameFor(String name, _Match? match) {
  final title = match?.sidecar.title ?? '';
  if (match == null || match.how != _How.own || title.contains('/')) return name;
  if (title.length <= name.length) return name;
  return _extension(title).toLowerCase() == _extension(name).toLowerCase() ? title : name;
}

String _extension(String name) {
  final dot = name.lastIndexOf('.');
  return dot <= 0 ? '' : name.substring(dot);
}

String _withoutExtension(String name) {
  final dot = name.lastIndexOf('.');
  return dot <= 0 ? name : name.substring(0, dot);
}

/// How a file was matched with its details, best first.
enum _How {
  /// By its own name, however Takeout shortened or numbered it.
  own,

  /// As the edited copy of the photo the details belong to.
  edited,

  /// As the video half of a Live Photo or motion photo, whose details are
  /// the photo's.
  sibling,
}

@immutable
class _Match {
  const _Match(this.sidecar, this.how);

  final TakeoutSidecar sidecar;
  final _How how;
}

class _Group {
  _Group(this.key);

  final String key;
  final List<TakeoutMedia> sources = [];
  final Set<String> albums = {};

  /// Each copy, with the details it was matched with.
  final List<(TakeoutMedia, _Match?)> matches = [];
}

/// Takeout cuts a JSON file's name, before `.json` and its counter, to this
/// many characters.
const int _jsonStemLimit = 46;

/// The details in one folder, looked up the ways Takeout names them.
///
/// A JSON's name is the file's own name, then `.supplemental-metadata`
/// (since late 2024, plain before), then a counter when two files in the
/// folder share a name, then `.json`, cut to 46 characters before the
/// counter: `IMG_1.jpg.supplemental-metadata(1).json`,
/// `long_name.jpg.supplemental-me.json`. The file itself carries the
/// counter before its extension: `IMG_1(1).jpg`.
class _FolderDetails {
  final Map<(String, int), TakeoutSidecar> _byKey = {};
  final Map<String, TakeoutSidecar> _byTitle = {};
  final Map<String, TakeoutSidecar> _byStem = {};

  void add(TakeoutSidecar sidecar) {
    final (key, counter) = _jsonKey(sidecar.fileName);
    _byKey.putIfAbsent((key, counter), () => sidecar);
    if (counter == 0 && sidecar.title.isNotEmpty) _byTitle.putIfAbsent(sidecar.title, () => sidecar);
    if (counter == 0) _byStem.putIfAbsent(_withoutExtension(key).toLowerCase(), () => sidecar);
  }

  _Match? match(String name) {
    if (_own(name) case final found?) return _Match(found, _How.own);
    final stem = _withoutExtension(name);
    final extension = _extension(name);
    for (final suffix in takeoutEditedSuffixes) {
      if (!stem.toLowerCase().endsWith(suffix)) continue;
      final original = '${stem.substring(0, stem.length - suffix.length)}$extension';
      if (_own(original) case final found?) return _Match(found, _How.edited);
    }
    if (_byStem[stem.toLowerCase()] case final found?) return _Match(found, _How.sibling);
    return null;
  }

  TakeoutSidecar? _own(String name) {
    // The name as it is, then with a counter Takeout added taken off.
    final readings = [(name, 0), ?_counted(name)];
    for (final (key, counter) in readings) {
      final found = _byKey[(key, counter)] ??
          (key.length > _jsonStemLimit ? _byKey[(key.substring(0, _jsonStemLimit), counter)] : null);
      if (found != null) return found;
    }
    if (_byTitle[name] case final found?) return found;
    // A name Takeout shortened itself, keeping the extension.
    if (name.length >= 40) {
      final stem = _withoutExtension(name);
      final extension = _extension(name).toLowerCase();
      for (final MapEntry(key: title, value: sidecar) in _byTitle.entries) {
        if (title.length > name.length &&
            title.startsWith(stem) &&
            _extension(title).toLowerCase() == extension) {
          return sidecar;
        }
      }
    }
    return null;
  }

  /// `IMG_1(1).jpg` read as `IMG_1.jpg` with counter 1.
  static (String, int)? _counted(String name) {
    final match = RegExp(r'^(.*)\((\d+)\)(\.[^.]*)?$').firstMatch(name);
    if (match == null) return null;
    return ('${match[1]}${match[3] ?? ''}', int.parse(match[2]!));
  }

  /// The file name a JSON's name points to, as far as Takeout left it, and
  /// its counter.
  static (String, int) _jsonKey(String fileName) {
    var stem = fileName.substring(0, fileName.length - '.json'.length);
    var counter = 0;
    final counted = RegExp(r'^(.*)\((\d+)\)$').firstMatch(stem);
    if (counted != null) {
      stem = counted[1]!;
      counter = int.parse(counted[2]!);
    }
    final dot = stem.lastIndexOf('.');
    if (dot > 0) {
      final suffix = stem.substring(dot + 1);
      if (suffix.isEmpty || 'supplemental-metadata'.startsWith(suffix)) stem = stem.substring(0, dot);
    }
    return (stem, counter);
  }
}

// -----------------------------------------------------------------------------
// Dates in file names
// -----------------------------------------------------------------------------

final List<RegExp> _namedDates = [
  // IMG_20190615_142530, PXL_20230101_123456789, VID-20190615-WA0001's day.
  RegExp(r'(?<!\d)((?:19|20)\d{2})(\d{2})(\d{2})[_-](\d{2})(\d{2})(\d{2})'),
  // Screenshot_2019-06-15-14-25-30, 2019-06-15 14.25.30.
  RegExp(r'(?<!\d)((?:19|20)\d{2})-(\d{2})-(\d{2})[ _-](\d{2})[.:\-](\d{2})[.:\-](\d{2})'),
  // IMG-20190615-WA0001, which has the day alone.
  RegExp(r'(?<!\d)((?:19|20)\d{2})(\d{2})(\d{2})-WA\d'),
];

/// When a photo was taken, read from a name a camera or app gave it, such
/// as `IMG_20190615_142530.jpg`; null when the name holds no date. Names
/// hold the phone's own time, so it is read as local time.
DateTime? takenFromName(String name) {
  for (final pattern in _namedDates) {
    final match = pattern.firstMatch(name);
    if (match == null) continue;
    final numbers = [for (var i = 1; i <= match.groupCount; i++) int.parse(match[i]!)];
    final [year, month, day, ...time] = numbers;
    final [hour, minute, second] = time.isEmpty ? [0, 0, 0] : time;
    if (month < 1 || month > 12 || day < 1 || day > 31 || hour > 23 || minute > 59 || second > 59) continue;
    final date = DateTime(year, month, day, hour, minute, second);
    // Rolled over, like 31 June.
    if (date.month != month || date.day != day) continue;
    return date;
  }
  return null;
}

// -----------------------------------------------------------------------------
// Parts
// -----------------------------------------------------------------------------

/// Which export a part belongs to and its number in it, read from the name
/// Takeout gives it, such as `takeout-20261005T101010Z-001.zip`; null for a
/// name Takeout didn't give. A second download of a part, `… (1).zip`, has
/// the same number.
({String export, int number})? takeoutPartNumber(String fileName) {
  final match = RegExp(
    r'^takeout-(\d{8}T\d{6}Z(?:-\d+)?)-(\d{3,})(?: ?\(\d+\))?\.(?:zip|tgz)$',
    caseSensitive: false,
  ).firstMatch(fileName.trim());
  if (match == null) return null;
  return (export: match[1]!.toUpperCase(), number: int.parse(match[2]!));
}

/// When the export [export], as [takeoutPartNumber] gives it, was made.
DateTime? takeoutExportTime(String export) {
  final match = RegExp(r'^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})Z').firstMatch(export);
  if (match == null) return null;
  final [year, month, day, hour, minute, second] = [for (var i = 1; i <= 6; i++) int.parse(match[i]!)];
  return DateTime.utc(year, month, day, hour, minute, second);
}

/// The numbers missing between parts 1 and the highest added, per export,
/// for [names], the parts' file names. Parts after the highest can't be
/// known to be missing, since the names don't say how many there are.
List<int> missingTakeoutParts(Iterable<String> names) {
  final numbers = <String, Set<int>>{};
  for (final name in names) {
    if (takeoutPartNumber(name) case (:final export, :final number)) {
      (numbers[export] ??= {}).add(number);
    }
  }
  return [
    for (final present in numbers.values)
      for (var n = 1; n < present.reduce((a, b) => a > b ? a : b); n++)
        if (!present.contains(n)) n,
  ]..sort();
}

/// [names] in the order the parts go up: by export, then by number, with
/// parts Takeout didn't name after, by name.
int compareTakeoutParts(String a, String b) {
  final left = takeoutPartNumber(a);
  final right = takeoutPartNumber(b);
  if (left == null || right == null) {
    if (left != null) return -1;
    if (right != null) return 1;
    return a.compareTo(b);
  }
  final byExport = left.export.compareTo(right.export);
  return byExport != 0 ? byExport : left.number.compareTo(right.number);
}
