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

  /// When it was moved to the trash; everything inside goes with it.
  DateTimeColumn get trashedAt => dateTime().nullable()();

  /// In the trash, or inside a folder that is: shown nowhere but Trash.
  /// Worked out locally from [trashedAt] up the folder tree.
  BoolColumn get hidden => boolean().withDefault(const Constant(false))();

  /// Manifest keys this version doesn't know, as JSON, so a rename or move
  /// made here writes them back instead of dropping what a newer version
  /// stored. Null when there are none.
  TextColumn get manifestExtra => text().nullable()();

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

  /// When it was moved to the trash.
  DateTimeColumn get trashedAt => dateTime().nullable()();

  /// In the trash itself or inside a trashed folder; see [Folders.hidden].
  BoolColumn get hidden => boolean().withDefault(const Constant(false))();

  /// Manifest keys this version doesn't know; see [Folders.manifestExtra].
  TextColumn get manifestExtra => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// A photo album. Stored in the channel as a small text message, like a
/// folder; which files are in it lives in each file's own manifest, so a
/// photo can be in several albums without being copied.
@DataClassName('AlbumRow')
class Albums extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get messageId => integer()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get modifiedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Which files are in which album, as their manifests say.
@DataClassName('AlbumFileRow')
class AlbumFiles extends Table {
  TextColumn get albumId => text()();
  TextColumn get fileId => text()();

  @override
  Set<Column> get primaryKey => {albumId, fileId};
}

/// Files and folders this phone keeps available offline. Per phone, so it
/// is not in the channel.
@DataClassName('OfflinePinRow')
class OfflinePins extends Table {
  TextColumn get itemId => text()();
  BoolColumn get isFolder => boolean()();
  DateTimeColumn get pinnedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {itemId};
}

/// The copies this phone keeps for offline use, outside TDLib's cache so
/// clearing downloaded copies leaves them alone.
@DataClassName('OfflineCopyRow')
class OfflineCopies extends Table {
  TextColumn get fileId => text()();
  TextColumn get path => text()();
  IntColumn get size => integer()();

  @override
  Set<Column> get primaryKey => {fileId};
}

/// What is in a photo or document, for search: recognised text and what
/// the picture shows, lower-cased. Worked out on this phone.
@DataClassName('FileContentRow')
class FileContents extends Table {
  TextColumn get fileId => text()();
  TextColumn get content => text()();

  /// Indexer version that produced it; older entries are redone.
  IntColumn get version => integer()();
  DateTimeColumn get indexedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {fileId};
}

/// When this phone last opened, shared or sent each file. Per phone, so it
/// is not in the channel; file ids are stable, so rebuilding the index
/// keeps it.
@DataClassName('FileOpenRow')
class FileOpens extends Table {
  TextColumn get fileId => text()();
  DateTimeColumn get openedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {fileId};
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

/// Who asked for a transfer: the person, photo backup working through the
/// camera roll, or a download to this phone (often the whole drive, on a new
/// one). Backup and save transfers are shown as a group each, not one by one.
enum TransferOrigin { manual, backup, save }

/// Where a saved download ends up: a folder the phone's file manager shows,
/// the photo gallery, or the app's own offline store.
enum SaveTarget { files, gallery, offline }

enum TransferStatus {
  queued,
  running,

  /// Stopped by the person, to carry on later; neither running nor done.
  paused,
  failed,
  completed,
  cancelled;

  bool get isActive => this == queued || this == running;
  bool get isFinished => this == failed || this == completed || this == cancelled;

  /// Still to happen: running, waiting, or paused.
  bool get isPending => !isFinished;
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

  /// Where a download is copied once it arrives (save transfers).
  TextColumn get saveTo => textEnum<SaveTarget>().nullable()();

  /// Folders under the save location, `/`-separated, so the drive's layout
  /// carries over; for the gallery, the album it goes back into.
  TextColumn get saveFolder => text().nullable()();

  /// Waits for an unmetered network: chosen as "Later, on Wi-Fi", or big and
  /// started on Wi-Fi. A phone's hotspot counts as mobile data.
  BoolColumn get wifiOnly => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

enum BackupAssetState { done, failed, skipped }

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

  /// Why the last attempt failed, in the sentence the transfer would have
  /// shown, so the Backup screen can say it per photo.
  TextColumn get reason => text().nullable()();

  @override
  Set<Column> get primaryKey => {assetId};
}
