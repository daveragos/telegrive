import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

@DriftDatabase(tables: [Folders, DriveFiles, FileParts, Transfers, BackupAssets])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'telegrive'));

  @override
  int get schemaVersion => 1;

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
  );

  // ---------------------------------------------------------------------------
  // Browsing
  // ---------------------------------------------------------------------------

  /// A file is visible once every part of it has arrived.
  Expression<bool> _complete(DriveFiles f) =>
      f.partsPresent.isBiggerOrEqual(f.partCount);

  /// Items whose parent is gone (deleted from another device, or forwarded
  /// in without one) are shown at the root rather than lost.
  Expression<bool> _inFolder(GeneratedColumn<String> column, String? folderId) {
    if (folderId != null) return column.equals(folderId);
    return column.isNull() |
        column.isNotInQuery(selectOnly(folders)..addColumns([folders.id]));
  }

  Stream<List<FolderRow>> watchChildFolders(String? parentId) =>
      (select(folders)
            ..where((f) => _inFolder(f.parentId, parentId))
            ..orderBy([(f) => OrderingTerm.asc(f.name.collate(Collate.noCase))]))
          .watch();

  Stream<List<FileRow>> watchFilesIn(String? folderId) =>
      (select(driveFiles)
            ..where((f) => _complete(f) & _inFolder(f.folderId, folderId)))
          .watch();

  Stream<List<FileRow>> watchRecent({int limit = 20}) =>
      (select(driveFiles)
            ..where(_complete)
            ..orderBy([(f) => OrderingTerm.desc(f.createdAt)])
            ..limit(limit))
          .watch();

  Stream<List<FileRow>> watchStarred() =>
      (select(driveFiles)
            ..where((f) => _complete(f) & f.starred.equals(true))
            ..orderBy([(f) => OrderingTerm.desc(f.modifiedAt)]))
          .watch();

  /// Photos and videos, newest capture first — the Photos timeline.
  Stream<List<FileRow>> watchMedia() {
    final when = coalesce([driveFiles.takenAt, driveFiles.createdAt]);
    return (select(driveFiles)
          ..where(
            (f) =>
                _complete(f) &
                f.kind.isIn([FileKind.image.name, FileKind.video.name]),
          )
          ..orderBy([(_) => OrderingTerm(expression: when, mode: OrderingMode.desc)]))
        .watch();
  }

  /// `name|size` of every photo and video in the drive, to its file id. How
  /// backup recognises what is already up there after a reinstall or on a
  /// new phone, where device media ids mean nothing.
  Future<Map<String, String>> mediaFingerprints() async {
    final rows = await (selectOnly(driveFiles)
          ..addColumns([driveFiles.id, driveFiles.name, driveFiles.size])
          ..where(
            driveFiles.kind.isIn([FileKind.image.name, FileKind.video.name]),
          ))
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

  Stream<List<FileRow>> watchKind(FileKind kind) =>
      (select(driveFiles)
            ..where((f) => _complete(f) & f.kind.equalsValue(kind))
            ..orderBy([(f) => OrderingTerm.desc(f.createdAt)]))
          .watch();

  Stream<List<FileRow>> watchSearch(String query, {FileKind? kind}) {
    final pattern = '%${query.replaceAll('%', r'\%').replaceAll('_', r'\_')}%';
    return (select(driveFiles)
          ..where((f) {
            var condition =
                _complete(f) &
                f.name.like(pattern, escapeChar: r'\');
            if (kind != null) condition = condition & f.kind.equalsValue(kind);
            return condition;
          })
          ..orderBy([(f) => OrderingTerm.desc(f.modifiedAt)])
          ..limit(300))
        .watch();
  }

  Stream<List<FolderRow>> watchFolderSearch(String query) {
    final pattern = '%${query.replaceAll('%', r'\%').replaceAll('_', r'\_')}%';
    return (select(folders)
          ..where((f) => f.name.like(pattern, escapeChar: r'\'))
          ..orderBy([(f) => OrderingTerm.asc(f.name)])
          ..limit(50))
        .watch();
  }

  Stream<List<KindTotal>> watchTotals() {
    return customSelect(
      'SELECT kind, COUNT(*) AS c, COALESCE(SUM(size), 0) AS s '
      'FROM drive_files WHERE parts_present >= part_count GROUP BY kind',
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
    return {...partIds, ...folderIds};
  }

  // ---------------------------------------------------------------------------
  // Writing the index
  // ---------------------------------------------------------------------------

  Future<void> upsertFolder(FoldersCompanion folder) =>
      into(folders).insertOnConflictUpdate(folder);

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
    });
  }

  Future<void> clearIndex() => transaction(() async {
    await delete(fileParts).go();
    await delete(driveFiles).go();
    await delete(folders).go();
  });

  Future<void> clearAll() => transaction(() async {
    await clearIndex();
    await delete(transfers).go();
    await delete(backupAssets).go();
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

  Future<void> deleteTransfers(Iterable<String> ids) =>
      (delete(transfers)..where((t) => t.id.isIn(ids))).go();
}

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
