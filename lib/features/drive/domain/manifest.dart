import 'dart:convert';

import 'package:flutter/foundation.dart';

/// The wire format that makes the storage channel self-describing.
///
/// Every file message carries its manifest in the caption and every folder is
/// a small text message carrying its own, so the whole drive — names, folder
/// tree, stars, split parts — can be rebuilt from Telegram alone after a
/// reinstall or on a second device.
///
/// A caption is readable in the Telegram app too: the first line is the plain
/// name and the machine line underneath is wrapped in a spoiler, so the
/// channel looks like a tidy file list rather than a wall of JSON.
///
/// ```text
/// Quarterly report.pdf
/// tgr1:{"id":"…","n":"Quarterly report.pdf","f":"…","m":"application/pdf",…}
/// ```
///
/// Captions written before the rename to Telegrive used `gr1:` / `grf1:`;
/// those still decode.
abstract final class ManifestCodec {
  static const String filePrefix = 'tgr1:';
  static const String folderPrefix = 'tgrf1:';

  static final RegExp _fileLine = RegExp(
    r'(?:^|\n)(?:tgr1|gr1):(\{[^\n]*\})\s*$',
  );
  static final RegExp _folderLine = RegExp(
    r'(?:^|\n)(?:tgrf1|grf1):(\{[^\n]*\})\s*$',
  );

  /// Longest name shown on the human-readable line. The manifest keeps the
  /// full name either way.
  static const int _displayNameLimit = 96;

  static EncodedText encodeFile(FileManifest manifest) {
    final head = _displayName(manifest.name);
    return _withMachineLine(head, filePrefix + jsonEncode(manifest.toJson()));
  }

  static EncodedText encodeFolder(FolderManifest manifest) {
    final head = '📁 ${_displayName(manifest.name)}';
    return _withMachineLine(head, folderPrefix + jsonEncode(manifest.toJson()));
  }

  static FileManifest? decodeFile(String caption) {
    final json = _extract(_fileLine, caption);
    return json == null ? null : FileManifest.tryFromJson(json);
  }

  static FolderManifest? decodeFolder(String text) {
    final json = _extract(_folderLine, text);
    return json == null ? null : FolderManifest.tryFromJson(json);
  }

  static EncodedText _withMachineLine(String head, String machine) {
    final text = '$head\n$machine';
    // Dart strings are UTF-16, which is exactly the unit Telegram counts
    // entity offsets in.
    return EncodedText(text, spoilerOffset: head.length + 1, spoilerLength: machine.length);
  }

  static String _displayName(String name) {
    final oneLine = name.replaceAll('\n', ' ');
    if (oneLine.length <= _displayNameLimit) return oneLine;
    return '${oneLine.substring(0, _displayNameLimit - 1)}…';
  }

  static Map<String, dynamic>? _extract(RegExp pattern, String text) {
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

/// Caption text plus where the machine-readable part sits in it.
@immutable
class EncodedText {
  const EncodedText(
    this.text, {
    required this.spoilerOffset,
    required this.spoilerLength,
  });

  final String text;
  final int spoilerOffset;
  final int spoilerLength;
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
  });

  final String id;
  final String name;
  final String? folderId;
  final String mimeType;

  /// Capture time of a photo or video from the camera roll.
  final DateTime? takenAt;

  /// Size of the whole file, not of this part.
  final int size;
  final DateTime createdAt;
  final DateTime modifiedAt;
  final int partCount;
  final int partIndex;
  final bool starred;

  FileManifest copyWith({
    String? name,
    String? folderId,
    bool clearFolder = false,
    bool? starred,
    int? partIndex,
    DateTime? modifiedAt,
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
  );

  /// Short keys keep captions well under Telegram's 1024-character limit.
  Map<String, dynamic> toJson() => {
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
  });

  final String id;
  final String name;
  final String? parentId;
  final DateTime createdAt;
  final DateTime modifiedAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'n': name,
    if (parentId != null) 'p': parentId,
    'ct': createdAt.millisecondsSinceEpoch,
    'mt': modifiedAt.millisecondsSinceEpoch,
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
    );
  }
}

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
