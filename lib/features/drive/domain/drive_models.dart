import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../../core/files/file_kind.dart';
import '../../../infrastructure/database/app_database.dart';

@immutable
class DriveFolder {
  const DriveFolder({
    required this.id,
    required this.parentId,
    required this.name,
    required this.createdAt,
    required this.modifiedAt,
    this.trashedAt,
  });

  factory DriveFolder.fromRow(FolderRow row) => DriveFolder(
    id: row.id,
    parentId: row.parentId,
    name: row.name,
    createdAt: row.createdAt,
    modifiedAt: row.modifiedAt,
    trashedAt: row.trashedAt,
  );

  final String id;
  final String? parentId;
  final String name;
  final DateTime createdAt;
  final DateTime modifiedAt;

  /// When it was moved to the trash, for items listed in Trash.
  final DateTime? trashedAt;

  @override
  bool operator ==(Object other) =>
      other is DriveFolder &&
      other.id == id &&
      other.name == name &&
      other.parentId == parentId &&
      other.modifiedAt == modifiedAt;

  @override
  int get hashCode => Object.hash(id, name, parentId, modifiedAt);
}

@immutable
class DriveFile {
  const DriveFile({
    required this.id,
    required this.folderId,
    required this.name,
    required this.mimeType,
    required this.kind,
    required this.size,
    required this.createdAt,
    required this.modifiedAt,
    required this.partCount,
    required this.starred,
    this.minithumbnail,
    this.thumbnailFileId,
    this.takenAt,
    this.trashedAt,
  });

  factory DriveFile.fromRow(FileRow row) => DriveFile(
    id: row.id,
    folderId: row.folderId,
    name: row.name,
    mimeType: row.mimeType,
    kind: row.kind,
    size: row.size,
    createdAt: row.createdAt,
    modifiedAt: row.modifiedAt,
    partCount: row.partCount,
    starred: row.starred,
    minithumbnail: _decodeThumb(row.minithumbnail),
    thumbnailFileId: row.thumbnailFileId,
    takenAt: row.takenAt,
    trashedAt: row.trashedAt,
  );

  final String id;
  final String? folderId;
  final String name;
  final String mimeType;
  final FileKind kind;
  final int size;
  final DateTime createdAt;
  final DateTime modifiedAt;
  final int partCount;
  final bool starred;

  /// Tiny blurred JPEG Telegram inlines with the message; free to show.
  final Uint8List? minithumbnail;

  /// TDLib id of the real thumbnail, fetched lazily.
  final int? thumbnailFileId;

  /// Capture time, for photos and videos that came from a camera roll.
  final DateTime? takenAt;

  /// When it was moved to the trash, for items listed in Trash.
  final DateTime? trashedAt;

  /// When the moment happened, as far as we know — what the Photos
  /// timeline sorts and groups by.
  DateTime get momentAt => takenAt ?? createdAt;

  String get extension =>
      p.extension(name).replaceFirst('.', '').toUpperCase();

  bool get isSplit => partCount > 1;

  /// A photo or video in a format every phone's gallery takes.
  bool get fitsGallery => _galleryExtensions.contains(extension.toLowerCase());

  static const Set<String> _galleryExtensions = {
    'jpg', 'jpeg', 'png', 'heic', 'heif', 'gif', 'webp', 'dng', //
    'mp4', 'mov', 'm4v', '3gp',
  };

  bool get hasPreview => minithumbnail != null || thumbnailFileId != null;

  static Uint8List? _decodeThumb(String? data) {
    if (data == null || data.isEmpty) return null;
    try {
      return base64Decode(data);
    } catch (_) {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is DriveFile &&
      other.id == id &&
      other.name == name &&
      other.folderId == folderId &&
      other.starred == starred &&
      other.modifiedAt == modifiedAt &&
      other.thumbnailFileId == thumbnailFileId;

  @override
  int get hashCode =>
      Object.hash(id, name, folderId, starred, modifiedAt, thumbnailFileId);
}

enum SortField {
  name('Name'),
  modified('Last modified'),
  size('Size'),
  type('Type');

  const SortField(this.label);

  final String label;

  static SortField fromName(String? name) =>
      values.firstWhere((s) => s.name == name, orElse: () => SortField.name);
}

@immutable
class SortOrder {
  const SortOrder(this.field, {this.descending = false});

  final SortField field;
  final bool descending;

  int compareFiles(DriveFile a, DriveFile b) {
    final result = switch (field) {
      SortField.name => _byName(a.name, b.name),
      SortField.modified => a.modifiedAt.compareTo(b.modifiedAt),
      SortField.size => a.size.compareTo(b.size),
      SortField.type => a.extension.compareTo(b.extension) != 0
          ? a.extension.compareTo(b.extension)
          : _byName(a.name, b.name),
    };
    return descending ? -result : result;
  }

  /// Folders have no size or type, so those orders fall back to name.
  int compareFolders(DriveFolder a, DriveFolder b) {
    final result = field == SortField.modified
        ? a.modifiedAt.compareTo(b.modifiedAt)
        : _byName(a.name, b.name);
    return descending ? -result : result;
  }

  static int _byName(String a, String b) =>
      a.toLowerCase().compareTo(b.toLowerCase());

  @override
  bool operator ==(Object other) =>
      other is SortOrder &&
      other.field == field &&
      other.descending == descending;

  @override
  int get hashCode => Object.hash(field, descending);
}

/// A photo album, with how many photos and videos it holds and the newest
/// one, for its cover.
@immutable
class DriveAlbum {
  const DriveAlbum({
    required this.id,
    required this.name,
    required this.count,
    this.coverFileId,
  });

  final String id;
  final String name;
  final int count;
  final String? coverFileId;

  @override
  bool operator ==(Object other) =>
      other is DriveAlbum &&
      other.id == id &&
      other.name == name &&
      other.count == count &&
      other.coverFileId == coverFileId;

  @override
  int get hashCode => Object.hash(id, name, count, coverFileId);
}

/// Photos backed up more than once, as a reinstall with a half-read index
/// used to do, and what to do about it.
@immutable
class DuplicateBackups {
  const DuplicateBackups({
    this.extras = const [],
    this.keptFor = const {},
    this.primary,
    this.extraRoots = const [],
  });

  static const none = DuplicateBackups();

  /// Later copies, for the trash.
  final List<DriveFile> extras;

  /// Extra copy's id to the id of the copy that stays.
  final Map<String, String> keptFor;

  /// The first backup folder, which keeps everything.
  final DriveFolder? primary;

  /// Backup folders made again beside it, to fold into it.
  final List<DriveFolder> extraRoots;

  bool get isEmpty => extras.isEmpty && extraRoots.isEmpty;
  int get bytes => extras.fold(0, (sum, f) => sum + f.size);
}

/// What is in the trash: the files and folders put there, not everything
/// inside a trashed folder.
@immutable
class TrashContents {
  const TrashContents({required this.folders, required this.files});

  final List<DriveFolder> folders;
  final List<DriveFile> files;

  bool get isEmpty => folders.isEmpty && files.isEmpty;
  int get count => folders.length + files.length;

  /// What is left once [ids] are taken out, e.g. what is being deleted for
  /// good.
  TrashContents without(Set<String> ids) => ids.isEmpty
      ? this
      : TrashContents(
          folders: [for (final folder in folders) if (!ids.contains(folder.id)) folder],
          files: [for (final file in files) if (!ids.contains(file.id)) file],
        );
}

/// A file to download to the phone, with the names of the folders leading
/// to it from where the download was asked for, and from the drive's root.
typedef SaveItem = ({DriveFile file, List<String> folders, List<String> path});

@immutable
class FolderContents {
  const FolderContents({required this.folders, required this.files});

  static const empty = FolderContents(folders: [], files: []);

  final List<DriveFolder> folders;
  final List<DriveFile> files;

  bool get isEmpty => folders.isEmpty && files.isEmpty;

  int get totalBytes => files.fold(0, (sum, f) => sum + f.size);

  FolderContents sorted(SortOrder order) => FolderContents(
    folders: [...folders]..sort(order.compareFolders),
    files: [...files]..sort(order.compareFiles),
  );
}

@immutable
class StorageSummary {
  const StorageSummary({required this.totals});

  final List<KindTotal> totals;

  int get fileCount => totals.fold(0, (sum, t) => sum + t.count);
  int get bytes => totals.fold(0, (sum, t) => sum + t.bytes);

  KindTotal totalFor(FileKind kind) => totals.firstWhere(
    (t) => t.kind == kind,
    orElse: () => KindTotal(kind, 0, 0),
  );
}
