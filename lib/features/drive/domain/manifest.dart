import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'caption_text.dart';

export 'caption_text.dart' show CaptionStyle, EncodedText, StyledRange;

/// The wire format that makes the storage channel self-describing.
///
/// Every file message carries its manifest in the caption and every folder
/// and album is a small text message carrying its own, so the whole drive —
/// names, folder tree, stars, albums, split parts — can be rebuilt from
/// Telegram alone after a reinstall or on a second device.
///
/// A record reads well in the Telegram app too ([CaptionLayout]): the name
/// in bold, the folder as a hashtag to tap, a few plain notes, and the
/// manifest itself on a details line ([DetailsLine]) folded into a quote
/// under a spoiler:
///
/// ```text
/// Quarterly report.pdf
/// #Invoices #starred
/// Telegrive details
/// tgfile2;id=…;name=Quarterly report.pdf;folder=…;type=application/pdf;…
/// ```
///
/// Only the details line is read back. Records in the older layout, a name
/// line over `tgr1:` (`gr1:`) and JSON, `tgrf1:` (`grf1:`) for folders and
/// `tgra1:` for albums, still decode, and take the current layout the next
/// time they are written.
///
/// Fields a manifest carries that this version doesn't know were written by
/// a newer one. They are kept in `extra`, stored in the index, and written
/// back on every edit, so renaming or moving something here never drops
/// them.
abstract final class ManifestCodec {
  static const String fileKind = 'tgfile2';
  static const String folderKind = 'tgfolder2';
  static const String albumKind = 'tgalbum2';

  /// [manifest] as its caption. [folderName] names the folder it is in, for
  /// the tag; without it the caption carries none.
  static EncodedText encodeFile(FileManifest manifest, {String? folderName}) {
    return CaptionLayout.build(
      head: manifest.name,
      tags: [
        if (manifest.folderId != null && folderName != null) FolderTag.of(folderName),
        if (manifest.starred) _starredTag,
        if (manifest.trashedAt != null) _trashTag,
      ],
      notes: [
        if (manifest.partCount > 1)
          'Part ${manifest.partIndex + 1} of ${manifest.partCount}',
        if (manifest.originalSize != null) 'Small copy, the original follows',
      ],
      details: _details(fileKind, manifest.toJson(), _fileFields),
    );
  }

  /// [manifest] as its message. [parentName] names the folder it is in, so
  /// the message says where it sits.
  static EncodedText encodeFolder(FolderManifest manifest, {String? parentName}) {
    return CaptionLayout.build(
      head: '📁 ${manifest.name}',
      tags: [
        FolderTag.of(manifest.name),
        if (manifest.starred) _starredTag,
        if (manifest.trashedAt != null) _trashTag,
      ],
      tagSuffix: manifest.parentId != null && parentName != null
          ? ' · in ${FolderTag.of(parentName)}'
          : '',
      details: _details(folderKind, manifest.toJson(), _folderFields),
    );
  }

  static EncodedText encodeAlbum(AlbumManifest manifest) {
    return CaptionLayout.build(
      head: '🖼 ${manifest.name}',
      details: _details(albumKind, manifest.toJson(), _albumFields),
    );
  }

  static FileManifest? decodeFile(String caption) {
    final json = _read(fileKind, caption, _fileFields) ?? _legacy(_legacyFile, caption);
    return json == null ? null : FileManifest.tryFromJson(json);
  }

  static FolderManifest? decodeFolder(String text) {
    final json = _read(folderKind, text, _folderFields) ?? _legacy(_legacyFolder, text);
    return json == null ? null : FolderManifest.tryFromJson(json);
  }

  static AlbumManifest? decodeAlbum(String text) {
    final json = _read(albumKind, text, _albumFields) ?? _legacy(_legacyAlbum, text);
    return json == null ? null : AlbumManifest.tryFromJson(json);
  }

  /// Unknown keys as the index stores them: JSON, or null when there are
  /// none.
  static String? encodeExtra(Map<String, Object?> extra) =>
      extra.isEmpty ? null : jsonEncode(extra);

  /// What [encodeExtra] stored. Anything unreadable counts as none rather
  /// than failing the edit it is read for.
  static Map<String, Object?> decodeExtra(String? stored) {
    if (stored == null) return const {};
    try {
      final decoded = jsonDecode(stored);
      return decoded is Map<String, dynamic>
          ? Map.unmodifiable(decoded)
          : const {};
    } catch (_) {
      return const {};
    }
  }

  /// Tags every starred or trashed record carries, so Telegram can list
  /// them.
  static const String _starredTag = '#starred';
  static const String _trashTag = '#trash';

  /// The details-line field for each manifest key, in the order they are
  /// written. Keys a manifest holds that aren't here are a newer version's,
  /// and go first under their own names.
  static const List<_Field> _fileFields = [
    _Field('id', 'id', _Value.text),
    _Field('n', 'name', _Value.text),
    _Field('f', 'folder', _Value.text),
    _Field('m', 'type', _Value.text),
    _Field('s', 'size', _Value.number),
    _Field('pc', 'parts', _Value.number),
    _Field('pi', 'part', _Value.partNumber),
    _Field('st', 'star', _Value.number),
    _Field('tk', 'taken', _Value.number),
    _Field('tr', 'trashed', _Value.number),
    _Field('al', 'albums', _Value.list),
    _Field('du', 'length', _Value.number),
    _Field('rb', 'replacedby', _Value.text),
    _Field('lt', 'original', _Value.number),
    _Field('ct', 'added', _Value.number),
    _Field('mt', 'changed', _Value.number),
  ];

  static const List<_Field> _folderFields = [
    _Field('id', 'id', _Value.text),
    _Field('n', 'name', _Value.text),
    _Field('p', 'parent', _Value.text),
    _Field('st', 'star', _Value.number),
    _Field('tr', 'trashed', _Value.number),
    _Field('ct', 'added', _Value.number),
    _Field('mt', 'changed', _Value.number),
  ];

  static const List<_Field> _albumFields = [
    _Field('id', 'id', _Value.text),
    _Field('n', 'name', _Value.text),
    _Field('ct', 'added', _Value.number),
    _Field('mt', 'changed', _Value.number),
  ];

  /// The details line for [json], a manifest's own map.
  static String _details(String kind, Map<String, dynamic> json, List<_Field> fields) {
    final known = {for (final field in fields) field.key};
    final written = <MapEntry<String, String>>[
      for (final MapEntry(:key, :value) in json.entries)
        if (!known.contains(key) && value != null)
          MapEntry(DetailsLine.escape(key), _writeOther(value)),
      for (final field in fields)
        if (json[field.key] case final value?)
          if (field.write(value) case final text?) MapEntry(field.name, text),
    ];
    return DetailsLine.write(kind, written);
  }

  /// A value only a newer version knows: text as it is, anything else as
  /// JSON.
  static String _writeOther(Object value) =>
      DetailsLine.escape(value is String ? value : jsonEncode(value));

  /// What [_writeOther] wrote: JSON it wrote back as its own text, or the
  /// text, so the value goes back onto the line exactly as it came.
  static Object _readOther(String text) {
    try {
      final decoded = jsonDecode(text);
      if (decoded != null && decoded is! String && jsonEncode(decoded) == text) {
        return decoded as Object;
      }
    } on FormatException {
      // Text, not JSON.
    }
    return text;
  }

  /// The manifest map the details line of [kind] in [text] describes, or
  /// null when there is none. A field this version knows but can't read is
  /// left out, and the manifest decides whether it can do without it.
  static Map<String, dynamic>? _read(String kind, String text, List<_Field> fields) {
    final written = DetailsLine.read(kind, text);
    if (written == null) return null;
    final byName = {for (final field in fields) field.name: field};
    final json = <String, dynamic>{};
    for (final MapEntry(key: name, :value) in written.entries) {
      final field = byName[name];
      if (field == null) {
        // A newer version's field, unless it would stand in for a key of
        // this version's own.
        if (fields.any((known) => known.key == name)) continue;
        if (DetailsLine.value(value) case final other?) json[name] = _readOther(other);
        continue;
      }
      if (field.read(value) case final read?) json[field.key] = read;
    }
    return json;
  }

  static final RegExp _legacyFile = RegExp(
    r'(?:^|\n)(?:tgr1|gr1):(\{[^\n]*\})\s*$',
  );
  static final RegExp _legacyFolder = RegExp(
    r'(?:^|\n)(?:tgrf1|grf1):(\{[^\n]*\})\s*$',
  );
  static final RegExp _legacyAlbum = RegExp(r'(?:^|\n)tgra1:(\{[^\n]*\})\s*$');

  static Map<String, dynamic>? _legacy(RegExp pattern, String text) {
    final match = pattern.firstMatch(text);
    if (match == null) return null;
    try {
      final decoded = jsonDecode(match.group(1)!);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}

enum _Value { text, number, partNumber, list }

/// One manifest key as the details line writes it: [key] in the manifest's
/// own map, [name] on the line.
class _Field {
  const _Field(this.key, this.name, this.value);

  final String key;
  final String name;
  final _Value value;

  /// [json] as the line holds it, or null when it isn't of this field's
  /// kind and is left out. Part numbers count from 1 on the line, as the
  /// part's note and file name do.
  String? write(Object json) => switch ((value, json)) {
    (_Value.text, final String text) => DetailsLine.escape(text),
    (_Value.number, final int number) => '$number',
    (_Value.number, true) => '1',
    (_Value.partNumber, final int index) => '${index + 1}',
    (_Value.list, final List<dynamic> items) =>
      DetailsLine.list([for (final item in items) '$item']),
    _ => null,
  };

  /// What the line holds as the manifest's map has it, or null when it
  /// can't be read.
  Object? read(String written) => switch (value) {
    _Value.text => DetailsLine.value(written),
    _Value.number => int.tryParse(written),
    _Value.partNumber => switch (int.tryParse(written)) {
      final number? when number > 0 => number - 1,
      _ => null,
    },
    _Value.list => DetailsLine.items(written),
  };
}

/// Metadata for one message of a file. Split files repeat the same manifest
/// in every part with a different [partIndex].
@immutable
class FileManifest {
  const FileManifest({
    required this.id,
    required this.name,
    required this.folderId,
    required this.mimeType,
    required this.size,
    required this.createdAt,
    required this.modifiedAt,
    this.partCount = 1,
    this.partIndex = 0,
    this.starred = false,
    this.takenAt,
    this.trashedAt,
    this.albums = const [],
    this.durationSeconds,
    this.replacedBy,
    this.originalSize,
    this.extra = const {},
  });

  /// Every key [toJson] can write. Anything else in a caption goes to
  /// [extra]. A key toJson writes that is missing here is also copied into
  /// [extra], and comes back after it is cleared.
  static const Set<String> _keys = {
    'id', 'n', 'f', 'm', 's', 'ct', 'mt', 'pc', 'pi', 'st', 'tk', 'tr', 'al', //
    'du', 'rb', 'lt',
  };

  final String id;
  final String name;
  final String? folderId;
  final String mimeType;

  /// When it was moved to the trash; null while it isn't there.
  final DateTime? trashedAt;

  /// Ids of the albums it is in.
  final List<String> albums;

  /// Capture time of a photo or video from the camera roll.
  final DateTime? takenAt;

  /// Length of a video or audio file, in seconds. Written when it is known,
  /// and never worth a caption edit of its own.
  final int? durationSeconds;

  /// Id of the file that took this one's place when Replace moved it to the
  /// trash. It means something only while [trashedAt] is set: a version
  /// that didn't know the key keeps it as an extra when it restores the
  /// file.
  final String? replacedBy;

  /// Byte size of the original photo while this message holds only a small
  /// copy of it, which backup sent on mobile data; [size] is the copy's
  /// own. Null once the original replaces it, and for anything else.
  final int? originalSize;

  /// Size of the whole file, not of this part.
  final int size;
  final DateTime createdAt;
  final DateTime modifiedAt;
  final int partCount;
  final int partIndex;
  final bool starred;

  /// Keys a newer version wrote that this one doesn't know, kept as they
  /// were. A key [toJson] writes wins over one of the same name here.
  final Map<String, Object?> extra;

  FileManifest copyWith({
    String? name,
    String? folderId,
    bool clearFolder = false,
    bool? starred,
    int? partIndex,
    DateTime? modifiedAt,
    DateTime? trashedAt,
    bool restore = false,
    List<String>? albums,
    String? replacedBy,
    bool clearOriginalSize = false,
  }) => FileManifest(
    id: id,
    name: name ?? this.name,
    folderId: clearFolder ? null : (folderId ?? this.folderId),
    mimeType: mimeType,
    size: size,
    createdAt: createdAt,
    modifiedAt: modifiedAt ?? this.modifiedAt,
    partCount: partCount,
    partIndex: partIndex ?? this.partIndex,
    starred: starred ?? this.starred,
    takenAt: takenAt,
    trashedAt: restore ? null : (trashedAt ?? this.trashedAt),
    albums: albums ?? this.albums,
    durationSeconds: durationSeconds,
    replacedBy: restore ? null : (replacedBy ?? this.replacedBy),
    originalSize: clearOriginalSize ? null : originalSize,
    extra: extra,
  );

  /// The manifest under short keys: what the caption's details line is
  /// written from and what waiting changes are recorded under (see
  /// [ManifestCodec] for the names the line gives them). [extra] goes first
  /// so the known keys written after it win. A key this
  /// version leaves out can still come from [extra]. Decoding keeps this
  /// version's own keys out of it, so that only happens for a key an older
  /// version indexed before it knew it, and writing it back keeps it.
  Map<String, dynamic> toJson() => {
    ...extra,
    'id': id,
    'n': name,
    if (folderId != null) 'f': folderId,
    'm': mimeType,
    's': size,
    'ct': createdAt.millisecondsSinceEpoch,
    'mt': modifiedAt.millisecondsSinceEpoch,
    if (partCount > 1) 'pc': partCount,
    if (partIndex > 0) 'pi': partIndex,
    if (starred) 'st': 1,
    if (takenAt != null) 'tk': takenAt!.millisecondsSinceEpoch,
    if (trashedAt != null) 'tr': trashedAt!.millisecondsSinceEpoch,
    if (albums.isNotEmpty) 'al': albums,
    if (durationSeconds != null) 'du': durationSeconds,
    if (replacedBy != null) 'rb': replacedBy,
    if (originalSize != null) 'lt': originalSize,
  };

  static FileManifest? tryFromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['n'];
    final size = json['s'];
    if (id is! String || name is! String || size is! int) return null;
    final partCount = (json['pc'] as int?) ?? 1;
    final partIndex = (json['pi'] as int?) ?? 0;
    if (partCount < 1 || partIndex < 0 || partIndex >= partCount) return null;
    return FileManifest(
      id: id,
      name: name,
      folderId: json['f'] as String?,
      mimeType: (json['m'] as String?) ?? 'application/octet-stream',
      size: size,
      createdAt: _time(json['ct']),
      modifiedAt: _time(json['mt'] ?? json['ct']),
      partCount: partCount,
      partIndex: partIndex,
      starred: json['st'] == 1 || json['st'] == true,
      takenAt: json['tk'] is int ? _time(json['tk']) : null,
      trashedAt: json['tr'] is int ? _time(json['tr']) : null,
      albums: [
        if (json['al'] case final List<dynamic> ids)
          for (final id in ids)
            if (id is String) id,
      ],
      durationSeconds: switch (json['du']) {
        final int seconds when seconds > 0 => seconds,
        _ => null,
      },
      replacedBy: json['rb'] as String?,
      originalSize: json['lt'] is int ? json['lt'] as int : null,
      extra: Map.unmodifiable(_unknown(json, _keys)),
    );
  }
}

@immutable
class FolderManifest {
  const FolderManifest({
    required this.id,
    required this.name,
    required this.parentId,
    required this.createdAt,
    required this.modifiedAt,
    this.trashedAt,
    this.starred = false,
    this.extra = const {},
  });

  /// Every key [toJson] can write. A key toJson writes that is missing here
  /// is also copied into [extra], and comes back after it is cleared.
  static const Set<String> _keys = {'id', 'n', 'p', 'ct', 'mt', 'tr', 'st'};

  final String id;
  final String name;
  final String? parentId;
  final DateTime createdAt;
  final DateTime modifiedAt;

  /// When it was moved to the trash, with everything inside it.
  final DateTime? trashedAt;

  /// Starred, the way a file is; omitted from the message otherwise.
  final bool starred;

  /// Keys a newer version wrote that this one doesn't know; see
  /// [FileManifest.extra].
  final Map<String, Object?> extra;

  /// [extra] goes first so the known keys written after it win; see
  /// [FileManifest.toJson].
  Map<String, dynamic> toJson() => {
    ...extra,
    'id': id,
    'n': name,
    if (parentId != null) 'p': parentId,
    'ct': createdAt.millisecondsSinceEpoch,
    'mt': modifiedAt.millisecondsSinceEpoch,
    if (trashedAt != null) 'tr': trashedAt!.millisecondsSinceEpoch,
    if (starred) 'st': 1,
  };

  static FolderManifest? tryFromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['n'];
    if (id is! String || name is! String) return null;
    return FolderManifest(
      id: id,
      name: name,
      parentId: json['p'] as String?,
      createdAt: _time(json['ct']),
      modifiedAt: _time(json['mt'] ?? json['ct']),
      trashedAt: json['tr'] is int ? _time(json['tr']) : null,
      starred: json['st'] == 1 || json['st'] == true,
      extra: Map.unmodifiable(_unknown(json, _keys)),
    );
  }
}

/// A photo album. Which files are in it is kept in their own manifests.
@immutable
class AlbumManifest {
  const AlbumManifest({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.modifiedAt,
  });

  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime modifiedAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'n': name,
    'ct': createdAt.millisecondsSinceEpoch,
    'mt': modifiedAt.millisecondsSinceEpoch,
  };

  static AlbumManifest? tryFromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['n'];
    if (id is! String || name is! String) return null;
    return AlbumManifest(
      id: id,
      name: name,
      createdAt: _time(json['ct']),
      modifiedAt: _time(json['mt'] ?? json['ct']),
    );
  }
}

/// The entries of [json] whose key isn't one of [known]. Decoding keeps only
/// these as `extra`, so this version never indexes a key it writes itself.
Map<String, Object?> _unknown(Map<String, Object?> json, Set<String> known) => {
  for (final MapEntry(:key, :value) in json.entries)
    if (!known.contains(key)) key: value,
};

DateTime _time(Object? millis) => millis is int
    ? DateTime.fromMillisecondsSinceEpoch(millis)
    : DateTime.fromMillisecondsSinceEpoch(0);

/// How large files are cut up. Telegram caps a single document at 2000 MiB
/// (4000 MiB with Premium) — the real limit is 4000/8000 upload parts of
/// 512 KiB, a little under the advertised "2 GB". Anything bigger is stored
/// as several messages.
abstract final class SplitPolicy {
  static const int _uploadPartBytes = 512 * 1024;
  static const int regularLimit = 4000 * _uploadPartBytes;
  static const int premiumLimit = 8000 * _uploadPartBytes;

  /// Parts are much smaller than the cap on purpose: an interrupted upload
  /// only loses the part in flight, and the temporary copy stays small.
  static const int partBytes = 512 * 1024 * 1024;

  static int partCountFor(int size, {required int limit}) {
    if (size <= limit) return 1;
    return (size + partBytes - 1) ~/ partBytes;
  }

  static int offsetOf(int partIndex) => partIndex * partBytes;

  static int sizeOf(int partIndex, int totalSize) {
    final remaining = totalSize - offsetOf(partIndex);
    return remaining.clamp(0, partBytes);
  }

  /// `movie.mkv` part 0 → `movie.mkv.001`, so the parts sort and read
  /// sensibly if someone looks at the channel in Telegram.
  static String partName(String name, int partIndex) =>
      '$name.${(partIndex + 1).toString().padLeft(3, '0')}';
}
