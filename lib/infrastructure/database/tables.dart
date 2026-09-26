import 'package:drift/drift.dart';

import '../../core/files/file_kind.dart';

/// The local index of the drive. Telegram is the source of truth; everything
/// here can be rebuilt from the channel, which is what a full sync does.

/// One folder. Stored in the channel as a small text message, so [messageId]
/// is how a rename or delete finds it again.
@DataClassName('FolderRow')
class Folders extends Table {
  TextColumn get id => text()();
  TextColumn get parentId => text().nullable()();
  TextColumn get name => text()();
  IntColumn get messageId => integer()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get modifiedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// One logical file. Large files span several messages ([FileParts]); the
/// file only shows up once [partsPresent] reaches [partCount].
@DataClassName('FileRow')
class DriveFiles extends Table {
  TextColumn get id => text()();
  TextColumn get folderId => text().nullable()();
  TextColumn get name => text()();
  TextColumn get mimeType => text()();
  TextColumn get kind => textEnum<FileKind>()();
  IntColumn get size => integer()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get modifiedAt => dateTime()();
  IntColumn get partCount => integer().withDefault(const Constant(1))();
  IntColumn get partsPresent => integer().withDefault(const Constant(0))();
  BoolColumn get starred => boolean().withDefault(const Constant(false))();

  /// Telegram's inline blurred preview (base64 JPEG, ~40px), when it has one.
  TextColumn get minithumbnail => text().nullable()();

  /// TDLib file id of the server-made thumbnail, downloaded on demand.
  IntColumn get thumbnailFileId => integer().nullable()();

  /// When a photo or video was captured, for the Photos timeline. Null for
  /// anything that isn't from the camera roll.
  DateTimeColumn get takenAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Where each piece of a file lives in the channel.
@DataClassName('PartRow')
class FileParts extends Table {
  TextColumn get fileId => text()();
  IntColumn get partIndex => integer()();
  IntColumn get messageId => integer().unique()();

  /// TDLib's id for the document. Stable for as long as TDLib's database is.
  IntColumn get tdFileId => integer()();
  IntColumn get size => integer()();

  @override
  Set<Column> get primaryKey => {fileId, partIndex};
}

enum TransferKind { upload, download }

/// Who asked for a transfer: the person, or photo backup working through
/// the camera roll. Backup transfers are shown as one group, not one by one.
enum TransferOrigin { manual, backup }

enum TransferStatus {
  queued,
  running,
  failed,
  completed,
  cancelled;

  bool get isActive => this == queued || this == running;
  bool get isFinished => !isActive;
}

/// The upload/download queue. Persisted so a transfer interrupted by the
/// app being killed can be resumed (split uploads continue at the last
/// finished part) or retried.
@DataClassName('TransferRow')
class Transfers extends Table {
  TextColumn get id => text()();
  TextColumn get kind => textEnum<TransferKind>()();
  TextColumn get status => textEnum<TransferStatus>()();
  TextColumn get name => text()();
  TextColumn get mimeType => text()();

  /// Drive file this transfer creates (upload) or reads (download).
  TextColumn get fileId => text()();
  TextColumn get folderId => text().nullable()();

  /// Upload source on disk.
  TextColumn get sourcePath => text().nullable()();

  /// True when [sourcePath] is our own temporary copy (the file picker copies
  /// content URIs into the cache) and should be removed once uploaded.
  BoolColumn get ownsSource => boolean().withDefault(const Constant(false))();

  /// Download result on disk.
  TextColumn get resultPath => text().nullable()();
  IntColumn get totalBytes => integer()();
  IntColumn get doneBytes => integer().withDefault(const Constant(0))();
  IntColumn get partCount => integer().withDefault(const Constant(1))();
  IntColumn get completedParts => integer().withDefault(const Constant(0))();
  TextColumn get error => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get finishedAt => dateTime().nullable()();
  TextColumn get origin =>
      textEnum<TransferOrigin>().withDefault(Constant(TransferOrigin.manual.name))();

  /// Camera-roll asset a backup upload came from.
  TextColumn get assetId => text().nullable()();

  /// Capture time carried into the manifest (backup uploads).
  DateTimeColumn get takenAt => dateTime().nullable()();

  /// Small JPEG sent as the document's thumbnail, so videos get previews.
  TextColumn get thumbnailPath => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

enum BackupAssetState { done, failed }

/// Camera-roll assets photo backup has dealt with, keyed by the device's
/// media id, so each photo goes up exactly once.
@DataClassName('BackupAssetRow')
class BackupAssets extends Table {
  TextColumn get assetId => text()();
  TextColumn get state => textEnum<BackupAssetState>()();

  /// Drive file holding the asset, once backed up.
  TextColumn get fileId => text().nullable()();
  IntColumn get failures => integer().withDefault(const Constant(0))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {assetId};
}
