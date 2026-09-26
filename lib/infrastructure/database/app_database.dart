import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/files/file_kind.dart';
import 'tables.dart';

export 'tables.dart';

part 'app_database.g.dart';

/// Per-kind totals for the home screen.
class KindTotal {
  const KindTotal(this.kind, this.count, this.bytes);

  final FileKind kind;
  final int count;
  final int bytes;
}

/// A photo album with how many files it holds and the newest one, for its
/// cover.
class AlbumSummary {
  const AlbumSummary(this.album, this.count, this.coverFileId);

  final AlbumRow album;
  final int count;
  final String? coverFileId;
}

@DriftDatabase(
  tables: [
    Folders,
    DriveFiles,
    FileParts,
    Transfers,
    BackupAssets,
    Albums,
    AlbumFiles,
    OfflinePins,
    OfflineCopies,
    FileContents,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
    : super(
        executor ??
            driftDatabase(
              name: 'telegrive',
              native: const DriftNativeOptions(databaseDirectory: _directory),
            ),
      );

  /// Application Support, not drift's default of Documents: on iOS the
  /// Documents folder is shown in the Files app, as the place downloads to
  /// this phone go. A database left there by an earlier version moves over.
  static Future<Directory> _directory() async {
    final support = await getApplicationSupportDirectory();
    await support.create(recursive: true);
    final documents = await getApplicationDocumentsDirectory();
    final old = File(p.join(documents.path, 'telegrive.sqlite'));
    if (await old.exists() &&
        !await File(p.join(support.path, 'telegrive.sqlite')).exists()) {
      for (final suffix in ['', '-wal', '-shm', '-journal']) {
        final file = File('${old.path}$suffix');
        if (await file.exists()) {
          await file.rename(p.join(support.path, 'telegrive.sqlite$suffix'));
        }
      }
    }
    return support;
  }

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await customStatement(
        'CREATE INDEX files_folder ON drive_files (folder_id)',
      );
      await customStatement(
        'CREATE INDEX files_created ON drive_files (created_at)',
      );
      await customStatement('CREATE INDEX folders_parent ON folders (parent_id)');
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(transfers, transfers.saveTo);
        await m.addColumn(transfers, transfers.saveFolder);
      }
      if (from < 3) {
        await m.addColumn(folders, folders.trashedAt);
        await m.addColumn(folders, folders.hidden);
        await m.addColumn(driveFiles, driveFiles.trashedAt);
        await m.addColumn(driveFiles, driveFiles.hidden);
        await m.createTable(albums);
        await m.createTable(albumFiles);
        await m.createTable(offlinePins);
        await m.createTable(offlineCopies);
        await m.createTable(fileContents);
      }
    },
  );

  // ---------------------------------------------------------------------------
  // Browsing
  // ---------------------------------------------------------------------------

  /// A file is visible once every part of it has arrived.
  Expression<bool> _complete(DriveFiles f) =>
      f.partsPresent.isBiggerOrEqual(f.partCount);

  /// Complete and not in the trash: what every view but Trash shows.
  Expression<bool> _shown(DriveFiles f) => _complete(f) & f.hidden.equals(false);

  /// Items whose parent is gone (deleted from another device, or forwarded
  /// in without one) are shown at the root rather than lost.
  Expression<bool> _inFolder(GeneratedColumn<String> column, String? folderId) {
    if (folderId != null) return column.equals(folderId);
    return column.isNull() |
        column.isNotInQuery(selectOnly(folders)..addColumns([folders.id]));
  }

  Stream<List<FolderRow>> watchChildFolders(String? parentId) =>
      (select(folders)
            ..where((f) => f.hidden.equals(false) & _inFolder(f.parentId, parentId))
            ..orderBy([(f) => OrderingTerm.asc(f.name.collate(Collate.noCase))]))
          .watch();

  Stream<List<FileRow>> watchFilesIn(String? folderId) =>
      (select(driveFiles)
            ..where((f) => _shown(f) & _inFolder(f.folderId, folderId)))
          .watch();

  Stream<List<FileRow>> watchRecent({int limit = 20}) =>
      (select(driveFiles)
            ..where(_shown)
            ..orderBy([(f) => OrderingTerm.desc(f.createdAt)])
            ..limit(limit))
          .watch();

  Stream<List<FileRow>> watchStarred() =>
      (select(driveFiles)
            ..where((f) => _shown(f) & f.starred.equals(true))
            ..orderBy([(f) => OrderingTerm.desc(f.modifiedAt)]))
          .watch();

  /// Photos and videos, newest capture first — the Photos timeline.
  Stream<List<FileRow>> watchMedia() {
    final when = coalesce([driveFiles.takenAt, driveFiles.createdAt]);
    return (select(driveFiles)
          ..where(
            (f) =>
                _shown(f) &
                f.kind.isIn([FileKind.image.name, FileKind.video.name]),
          )
          ..orderBy([(_) => OrderingTerm(expression: when, mode: OrderingMode.desc)]))
        .watch();
  }

  /// `name|size` of every file in the drive, to its file id. How backup
  /// recognises what is already up there after a reinstall or on a new
  /// phone, where device media ids mean nothing. Every kind counts, so a
  /// photo uploaded by hand, or one whose type was guessed differently,
  /// isn't sent again either.
  Future<Map<String, String>> mediaFingerprints() async {
    final rows = await (selectOnly(driveFiles)
          ..addColumns([driveFiles.id, driveFiles.name, driveFiles.size]))
        .get();
    return {
      for (final row in rows)
        '${row.read(driveFiles.name)}|${row.read(driveFiles.size)}':
            row.read(driveFiles.id)!,
    };
  }

  /// Drive file id to the phone's media id, for every backed-up photo this
  /// phone still knows. Lets the app show the phone's own sharp copy.
  Stream<Map<String, String>> watchLocalAssets() {
    return (select(backupAssets)
          ..where(
            (a) => a.state.equalsValue(BackupAssetState.done) & a.fileId.isNotNull(),
          ))
        .watch()
        .map((rows) => {for (final row in rows) row.fileId!: row.assetId});
  }

  /// The phone's media id for drive file [fileId], if it has a copy.
  Future<String?> localAssetOf(String fileId) =>
      (select(backupAssets)
            ..where(
              (a) =>
                  a.fileId.equals(fileId) &
                  a.state.equalsValue(BackupAssetState.done),
            )
            ..limit(1))
          .map((a) => a.assetId)
          .getSingleOrNull();

  Stream<List<FileRow>> watchKind(FileKind kind) =>
      (select(driveFiles)
            ..where((f) => _shown(f) & f.kind.equalsValue(kind))
            ..orderBy([(f) => OrderingTerm.desc(f.createdAt)]))
          .watch();

  /// Files named like [query], or whose recognised content mentions it,
  /// plus — with [range] — everything taken or added within it.
  Stream<List<FileRow>> watchSearch(
    String query, {
    FileKind? kind,
    (DateTime, DateTime)? range,
  }) {
    final pattern = '%${query.toLowerCase().replaceAll('%', r'\%').replaceAll('_', r'\_')}%';
    final when = coalesce([driveFiles.takenAt, driveFiles.createdAt]);
    final inContent = selectOnly(fileContents)
      ..addColumns([fileContents.fileId])
      ..where(fileContents.content.like(pattern, escapeChar: r'\'));
    return (select(driveFiles)
          ..where((f) {
            var match =
                f.name.like(pattern, escapeChar: r'\') | f.id.isInQuery(inContent);
            if (range != null) {
              match = match | when.isBetweenValues(range.$1, range.$2);
            }
            var condition = _shown(f) & match;
            if (kind != null) condition = condition & f.kind.equalsValue(kind);
            return condition;
          })
          ..orderBy([
            (f) => range != null
                ? OrderingTerm(expression: when, mode: OrderingMode.desc)
                : OrderingTerm.desc(f.modifiedAt),
          ])
          ..limit(500))
        .watch();
  }

  Stream<List<FolderRow>> watchFolderSearch(String query) {
    final pattern = '%${query.replaceAll('%', r'\%').replaceAll('_', r'\_')}%';
    return (select(folders)
          ..where((f) => f.hidden.equals(false) & f.name.like(pattern, escapeChar: r'\'))
          ..orderBy([(f) => OrderingTerm.asc(f.name)])
          ..limit(50))
        .watch();
  }

  Stream<List<KindTotal>> watchTotals() {
    return customSelect(
      'SELECT kind, COUNT(*) AS c, COALESCE(SUM(size), 0) AS s '
      'FROM drive_files WHERE parts_present >= part_count AND hidden = 0 '
      'GROUP BY kind',
      readsFrom: {driveFiles},
    ).watch().map(
      (rows) => [
        for (final row in rows)
          KindTotal(
            FileKind.fromName(row.read<String>('kind')),
            row.read<int>('c'),
            row.read<int>('s'),
          ),
      ],
    );
  }

  Stream<FileRow?> watchFile(String id) =>
      (select(driveFiles)..where((f) => f.id.equals(id))).watchSingleOrNull();

  Future<FileRow?> fileById(String id) =>
      (select(driveFiles)..where((f) => f.id.equals(id))).getSingleOrNull();

  Future<FolderRow?> folderById(String id) =>
      (select(folders)..where((f) => f.id.equals(id))).getSingleOrNull();

  Stream<FolderRow?> watchFolder(String id) =>
      (select(folders)..where((f) => f.id.equals(id))).watchSingleOrNull();

  Future<List<FolderRow>> allFolders() => select(folders).get();

  Future<List<PartRow>> partsOf(String fileId) =>
      (select(fileParts)
            ..where((p) => p.fileId.equals(fileId))
            ..orderBy([(p) => OrderingTerm.asc(p.partIndex)]))
          .get();

  Future<List<FileRow>> filesInFolders(Iterable<String> folderIds) =>
      (select(driveFiles)..where((f) => f.folderId.isIn(folderIds))).get();

  /// Every file that has all its parts and is not in the trash, or only
  /// those directly inside [folderIds].
  Future<List<FileRow>> completeFiles([Iterable<String>? folderIds]) =>
      (select(driveFiles)..where(
            (f) => folderIds == null
                ? _shown(f)
                : _shown(f) & f.folderId.isIn(folderIds),
          ))
          .get();

  /// [ids] that are still shown files (not trashed, not gone).
  Future<List<FileRow>> shownFiles(Iterable<String> ids) =>
      (select(driveFiles)..where((f) => _shown(f) & f.id.isIn(ids))).get();

  /// Every channel message the index knows about, for reconciliation.
  Future<Set<int>> knownMessageIds() async {
    final partIds = await (selectOnly(fileParts)
          ..addColumns([fileParts.messageId]))
        .map((r) => r.read(fileParts.messageId)!)
        .get();
    final folderIds = await (selectOnly(folders)
          ..addColumns([folders.messageId]))
        .map((r) => r.read(folders.messageId)!)
        .get();
    final albumIds = await (selectOnly(albums)..addColumns([albums.messageId]))
        .map((r) => r.read(albums.messageId)!)
        .get();
    return {...partIds, ...folderIds, ...albumIds};
  }

  // ---------------------------------------------------------------------------
  // Trash
  // ---------------------------------------------------------------------------

  /// Every folder in the trash or inside one.
  static const String _trashedTree =
      'WITH RECURSIVE gone(id) AS ('
      'SELECT id FROM folders WHERE trashed_at IS NOT NULL '
      'UNION SELECT f.id FROM folders f JOIN gone g ON f.parent_id = g.id) ';

  static const String _fileHidden =
      '(trashed_at IS NOT NULL OR COALESCE(folder_id IN gone, 0))';

  /// Works [Folders.hidden] and [DriveFiles.hidden] out again, after the
  /// trash or the folder tree changed.
  Future<void> refreshHidden() async {
    await customUpdate(
      '${_trashedTree}UPDATE folders SET hidden = (id IN gone) '
      'WHERE hidden != (id IN gone)',
      updates: {folders},
    );
    await customUpdate(
      '${_trashedTree}UPDATE drive_files SET hidden = $_fileHidden '
      'WHERE hidden != $_fileHidden',
      updates: {driveFiles},
    );
  }

  Future<void> _refreshHiddenFile(String fileId) => customUpdate(
    '${_trashedTree}UPDATE drive_files SET hidden = $_fileHidden '
    'WHERE id = ? AND hidden != $_fileHidden',
    variables: [Variable.withString(fileId)],
    updates: {driveFiles},
  );

  /// Not inside a hidden folder: how Trash lists only what was put there,
  /// not everything inside a trashed folder too.
  Expression<bool> _parentShown(GeneratedColumn<String> parent) =>
      parent.isNull() |
      parent.isNotInQuery(
        selectOnly(folders)
          ..addColumns([folders.id])
          ..where(folders.hidden.equals(true)),
      );

  Stream<List<FolderRow>> watchTrashedFolders() =>
      (select(folders)
            ..where((f) => f.trashedAt.isNotNull() & _parentShown(f.parentId))
            ..orderBy([(f) => OrderingTerm.desc(f.trashedAt)]))
          .watch();

  Stream<List<FileRow>> watchTrashedFiles() =>
      (select(driveFiles)
            ..where(
              (f) =>
                  _complete(f) & f.trashedAt.isNotNull() & _parentShown(f.folderId),
            )
            ..orderBy([(f) => OrderingTerm.desc(f.trashedAt)]))
          .watch();

  // ---------------------------------------------------------------------------
  // Albums
  // ---------------------------------------------------------------------------

  Future<void> upsertAlbum(AlbumsCompanion album) =>
      into(albums).insertOnConflictUpdate(album);

  Future<AlbumRow?> albumById(String id) =>
      (select(albums)..where((a) => a.id.equals(id))).getSingleOrNull();

  Stream<AlbumRow?> watchAlbum(String id) =>
      (select(albums)..where((a) => a.id.equals(id))).watchSingleOrNull();

  /// Replaces the albums [fileId] is in with [albumIds].
  Future<void> setFileAlbums(String fileId, List<String> albumIds) =>
      transaction(() async {
        await (delete(albumFiles)..where((a) => a.fileId.equals(fileId))).go();
        await batch(
          (b) => b.insertAll(albumFiles, [
            for (final id in albumIds)
              AlbumFilesCompanion.insert(albumId: id, fileId: fileId),
          ], mode: InsertMode.insertOrIgnore),
        );
      });

  Future<List<String>> albumIdsOf(String fileId) =>
      (select(albumFiles)..where((a) => a.fileId.equals(fileId)))
          .map((a) => a.albumId)
          .get();

  /// Albums with how many shown files each holds and its newest one, most
  /// recently changed first.
  Stream<List<AlbumSummary>> watchAlbums() {
    const shown = 'f.hidden = 0 AND f.parts_present >= f.part_count';
    return customSelect(
      'SELECT a.*, '
      '(SELECT COUNT(*) FROM album_files af JOIN drive_files f ON f.id = af.file_id '
      'WHERE af.album_id = a.id AND $shown) AS n, '
      '(SELECT f.id FROM album_files af JOIN drive_files f ON f.id = af.file_id '
      'WHERE af.album_id = a.id AND $shown '
      'ORDER BY COALESCE(f.taken_at, f.created_at) DESC LIMIT 1) AS cover '
      'FROM albums a ORDER BY a.modified_at DESC',
      readsFrom: {albums, albumFiles, driveFiles},
    ).watch().map(
      (rows) => [
        for (final row in rows)
          AlbumSummary(
            albums.map(row.data),
            row.read<int>('n'),
            row.readNullable<String>('cover'),
          ),
      ],
    );
  }

  /// An album's files, newest moment first.
  Stream<List<FileRow>> watchAlbumFiles(String albumId) {
    final when = coalesce([driveFiles.takenAt, driveFiles.createdAt]);
    return (select(driveFiles)
          ..where(
            (f) =>
                _shown(f) &
                f.id.isInQuery(
                  selectOnly(albumFiles)
                    ..addColumns([albumFiles.fileId])
                    ..where(albumFiles.albumId.equals(albumId)),
                ),
          )
          ..orderBy([(_) => OrderingTerm(expression: when, mode: OrderingMode.desc)]))
        .watch();
  }

  // ---------------------------------------------------------------------------
  // Available offline (this phone only)
  // ---------------------------------------------------------------------------

  Future<void> pinOffline(String itemId, {required bool isFolder}) =>
      into(offlinePins).insertOnConflictUpdate(
        OfflinePinsCompanion.insert(
          itemId: itemId,
          isFolder: isFolder,
          pinnedAt: DateTime.now(),
        ),
      );

  Future<void> unpinOffline(String itemId) =>
      (delete(offlinePins)..where((p) => p.itemId.equals(itemId))).go();

  Future<List<OfflinePinRow>> offlinePinList() => select(offlinePins).get();

  Stream<Set<String>> watchOfflinePins() => select(
    offlinePins,
  ).watch().map((rows) => {for (final row in rows) row.itemId});

  Future<List<OfflineCopyRow>> offlineCopyList() => select(offlineCopies).get();

  Stream<Map<String, String>> watchOfflineCopies() => select(
    offlineCopies,
  ).watch().map((rows) => {for (final row in rows) row.fileId: row.path});

  Future<OfflineCopyRow?> offlineCopyOf(String fileId) =>
      (select(offlineCopies)..where((c) => c.fileId.equals(fileId)))
          .getSingleOrNull();

  Future<void> saveOfflineCopy(String fileId, String path, int size) =>
      into(offlineCopies).insertOnConflictUpdate(
        OfflineCopiesCompanion.insert(fileId: fileId, path: path, size: size),
      );

  Future<void> deleteOfflineCopy(String fileId) =>
      (delete(offlineCopies)..where((c) => c.fileId.equals(fileId))).go();

  Future<void> clearOffline() => transaction(() async {
    await delete(offlinePins).go();
    await delete(offlineCopies).go();
  });

  // ---------------------------------------------------------------------------
  // Content search (this phone only)
  // ---------------------------------------------------------------------------

  /// Files already read by indexer [version] or later.
  Future<Set<String>> indexedFileIds(int version) async => {
    for (final row in await (select(fileContents)
          ..where((c) => c.version.isBiggerOrEqualValue(version)))
        .get())
      row.fileId,
  };

  Future<void> saveContent(String fileId, String content, int version) =>
      into(fileContents).insertOnConflictUpdate(
        FileContentsCompanion.insert(
          fileId: fileId,
          content: content,
          version: version,
          indexedAt: DateTime.now(),
        ),
      );

  /// Forgets what older indexer versions read, so it is read again (or,
  /// for kinds no longer read, not at all).
  Future<void> dropContentBefore(int version) =>
      (delete(fileContents)..where((c) => c.version.isSmallerThanValue(version))).go();

  Stream<int> watchIndexedCount() {
    final count = fileContents.fileId.count();
    return (selectOnly(fileContents)..addColumns([count]))
        .map((r) => r.read(count) ?? 0)
        .watchSingle();
  }

  // ---------------------------------------------------------------------------
  // Freeing up space
  // ---------------------------------------------------------------------------

  /// Phone media id to the size of its drive copy, for every photo and
  /// video backed up from this phone whose copy is complete and not in the
  /// trash — the ones safe to delete from the phone.
  Future<Map<String, int>> safelyBackedUp() async {
    final query = select(backupAssets).join([
      innerJoin(driveFiles, driveFiles.id.equalsExp(backupAssets.fileId)),
    ])..where(
        backupAssets.state.equalsValue(BackupAssetState.done) &
            _shown(driveFiles),
      );
    return {
      for (final row in await query.get())
        row.readTable(backupAssets).assetId: row.readTable(driveFiles).size,
    };
  }

  // ---------------------------------------------------------------------------
  // Writing the index
  // ---------------------------------------------------------------------------

  /// A folder's trash state or place in the tree may have changed, which
  /// can show or hide everything beneath it.
  Future<void> upsertFolder(FoldersCompanion folder) => transaction(() async {
    await into(folders).insertOnConflictUpdate(folder);
    await refreshHidden();
  });

  /// Inserts or refreshes a file and one of its parts, keeping
  /// [DriveFiles.partsPresent] in step.
  Future<void> upsertFilePart(
    DriveFilesCompanion file,
    FilePartsCompanion part,
  ) {
    return transaction(() async {
      // A message id belongs to exactly one part; if a caption edit moved it
      // (rare, but forwarded files get adopted this way) drop the stale row.
      Expression<bool> stale($FilePartsTable p) =>
          p.messageId.equals(part.messageId.value) &
          p.fileId.equals(part.fileId.value).not();
      final previousOwners = await (select(fileParts)..where(stale))
          .map((p) => p.fileId)
          .get();
      await (delete(fileParts)..where(stale)).go();
      for (final owner in previousOwners) {
        await _recountParts(owner);
      }
      // partsPresent is absent from [file], so an update leaves it alone.
      await into(driveFiles).insertOnConflictUpdate(file);
      await into(fileParts).insertOnConflictUpdate(part);
      await _recountParts(part.fileId.value);
      await _refreshHiddenFile(part.fileId.value);
    });
  }

  Future<void> _recountParts(String fileId) async {
    final count = fileParts.fileId.count();
    final present = await (selectOnly(fileParts)
          ..addColumns([count])
          ..where(fileParts.fileId.equals(fileId)))
        .map((r) => r.read(count) ?? 0)
        .getSingle();
    if (present == 0) {
      await (delete(driveFiles)..where((f) => f.id.equals(fileId))).go();
      await (delete(albumFiles)..where((a) => a.fileId.equals(fileId))).go();
    } else {
      await (update(driveFiles)..where((f) => f.id.equals(fileId))).write(
        DriveFilesCompanion(partsPresent: Value(present)),
      );
    }
  }

  Future<void> updateFile(String id, DriveFilesCompanion changes) =>
      (update(driveFiles)..where((f) => f.id.equals(id))).write(changes);

  Future<void> updateFolder(String id, FoldersCompanion changes) =>
      (update(folders)..where((f) => f.id.equals(id))).write(changes);

  /// Drops everything stored in the given channel messages.
  Future<void> removeMessages(Iterable<int> messageIds) {
    final ids = messageIds.toList();
    if (ids.isEmpty) return Future.value();
    return transaction(() async {
      final affected = await (selectOnly(fileParts, distinct: true)
            ..addColumns([fileParts.fileId])
            ..where(fileParts.messageId.isIn(ids)))
          .map((r) => r.read(fileParts.fileId)!)
          .get();
      await (delete(fileParts)..where((p) => p.messageId.isIn(ids))).go();
      for (final fileId in affected) {
        await _recountParts(fileId);
      }
      await (delete(folders)..where((f) => f.messageId.isIn(ids))).go();
      await (delete(albums)..where((a) => a.messageId.isIn(ids))).go();
      await refreshHidden();
    });
  }

  Future<void> clearIndex() => transaction(() async {
    await delete(fileParts).go();
    await delete(driveFiles).go();
    await delete(folders).go();
    await delete(albums).go();
    await delete(albumFiles).go();
  });

  Future<void> clearAll() => transaction(() async {
    await clearIndex();
    await delete(transfers).go();
    await delete(backupAssets).go();
    await delete(offlinePins).go();
    await delete(offlineCopies).go();
    await delete(fileContents).go();
  });

  // ---------------------------------------------------------------------------
  // Photo backup
  // ---------------------------------------------------------------------------

  Future<Map<String, BackupAssetRow>> backupAssetMap() async => {
    for (final row in await select(backupAssets).get()) row.assetId: row,
  };

  Stream<int> watchBackedUpCount() {
    final count = backupAssets.assetId.count();
    return (selectOnly(backupAssets)
          ..addColumns([count])
          ..where(backupAssets.state.equalsValue(BackupAssetState.done)))
        .map((r) => r.read(count) ?? 0)
        .watchSingle();
  }

  Future<void> markAssetBackedUp(String assetId, String? fileId) =>
      into(backupAssets).insertOnConflictUpdate(
        BackupAssetsCompanion.insert(
          assetId: assetId,
          state: BackupAssetState.done,
          fileId: Value(fileId),
          updatedAt: DateTime.now(),
        ),
      );

  /// Points backup's records at other drive files, as `from → to`: after
  /// duplicates are cleared, photos map to the copy that was kept.
  Future<void> repointBackupAssets(Map<String, String> fileIds) => batch((b) {
    for (final MapEntry(key: from, value: to) in fileIds.entries) {
      b.update(
        backupAssets,
        BackupAssetsCompanion(fileId: Value(to)),
        where: (a) => a.fileId.equals(from),
      );
    }
  });

  Future<void> markAssetsBackedUp(Iterable<String> assetIds) => batch((b) {
    final now = DateTime.now();
    b.insertAllOnConflictUpdate(backupAssets, [
      for (final id in assetIds)
        BackupAssetsCompanion.insert(
          assetId: id,
          state: BackupAssetState.done,
          updatedAt: now,
        ),
    ]);
  });

  Future<void> markAssetFailed(String assetId, int failures) =>
      into(backupAssets).insertOnConflictUpdate(
        BackupAssetsCompanion.insert(
          assetId: assetId,
          state: BackupAssetState.failed,
          failures: Value(failures),
          updatedAt: DateTime.now(),
        ),
      );

  Future<void> clearBackupFailures() =>
      (delete(backupAssets)
            ..where((a) => a.state.equalsValue(BackupAssetState.failed)))
          .go();

  // ---------------------------------------------------------------------------
  // Transfers
  // ---------------------------------------------------------------------------

  Future<List<TransferRow>> allTransfers() =>
      (select(transfers)..orderBy([(t) => OrderingTerm.asc(t.createdAt)])).get();

  Future<void> saveTransfer(TransferRow row) =>
      into(transfers).insertOnConflictUpdate(row);

  Future<void> saveTransfers(Iterable<TransferRow> rows) =>
      batch((b) => b.insertAllOnConflictUpdate(transfers, rows.toList()));

  /// In slices, since a whole drive saved to the phone is more ids than
  /// SQLite takes in one statement.
  Future<void> deleteTransfers(Iterable<String> ids) => transaction(() async {
    final all = ids.toList();
    for (var i = 0; i < all.length; i += 500) {
      final slice = all.sublist(i, (i + 500).clamp(0, all.length));
      await (delete(transfers)..where((t) => t.id.isIn(slice))).go();
    }
  });
}

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
