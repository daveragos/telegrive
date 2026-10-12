import 'dart:io';
import 'dart:math' as math;

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

/// A file this phone stopped partway through, with where it stopped and
/// the name of the folder it sits in, or null at the root.
class ResumePoint {
  const ResumePoint(
    this.file,
    this.positionMs,
    this.durationMs,
    this.folderName,
  );

  final FileRow file;
  final int positionMs;
  final int durationMs;
  final String? folderName;
}

/// A top-level folder with how many files it holds, in it or in any folder
/// below it, and their size. A [folderId] of null stands for the files in
/// no folder, and has an empty [name].
class FolderSize {
  const FolderSize(this.folderId, this.name, this.count, this.bytes);

  final String? folderId;
  final String name;
  final int count;
  final int bytes;
}

/// A file's row read without its inline preview, which weighs more than
/// the rest of the row, and whether it has one, so a list of thousands of
/// photos doesn't carry every preview along. Tiles read the preview on
/// their own with [AppDatabase.minithumbnailOf].
class LiteFileRow {
  const LiteFileRow(this.row, this.hasMinithumbnail);

  /// Every column but minithumbnail, which is null here.
  final FileRow row;
  final bool hasMinithumbnail;
}

/// A photo album with how many files it holds and the newest one, for its
/// cover.
class AlbumSummary {
  const AlbumSummary(this.album, this.count, this.coverFileId);

  final AlbumRow album;
  final int count;
  final String? coverFileId;
}

/// When one part's message may write its file's row.
enum FileRowWrite {
  /// The file's first part, or its only one: its caption says what the
  /// file is.
  always,

  /// A later part carrying the whole manifest, which a change to a file
  /// whose first part is gone writes: it stands in for the first part only
  /// while the index doesn't hold that one.
  unlessFirstPartKnown,

  /// A later part that only says whose part it is: it makes a row when
  /// there is none yet, for the first part to replace.
  ifAbsent,
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
    FileOpens,
    PlayPositions,
    WatchedFolders,
    WatchedFiles,
    PendingEdits,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// Android's file picker reads this same file from its own process with
  /// its own copy of SQLite, one short connection per call. A write here
  /// that meets one of those reads waits it out, up to three seconds,
  /// rather than fail with "database is locked". The closure captures
  /// nothing, so drift can hand it to the isolate that opens the file.
  AppDatabase([QueryExecutor? executor])
    : super(
        executor ??
            driftDatabase(
              name: 'telegrive',
              native: DriftNativeOptions(
                databaseDirectory: _directory,
                setup: (db) => db.execute('PRAGMA busy_timeout = 3000;'),
              ),
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
  int get schemaVersion => 12;

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
      await customStatement(
        'CREATE INDEX folders_parent ON folders (parent_id)',
      );
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
      if (from < 4) {
        await m.createTable(fileOpens);
        await m.addColumn(driveFiles, driveFiles.manifestExtra);
        await m.addColumn(folders, folders.manifestExtra);
      }
      if (from < 5) await m.addColumn(transfers, transfers.wifiOnly);
      if (from < 6) await m.addColumn(backupAssets, backupAssets.reason);
      if (from < 7) {
        await m.addColumn(driveFiles, driveFiles.durationSeconds);
        await m.addColumn(transfers, transfers.durationSeconds);
        await m.addColumn(folders, folders.starred);
        await m.addColumn(driveFiles, driveFiles.replacedBy);
        await m.addColumn(transfers, transfers.replacesFileId);
        await m.createTable(playPositions);
        // Schemas 4 to 6 keep st, du and rb among the extras, so a star,
        // length or replacement written by another phone may already be in
        // the index. Each moves into its column and out of the extras, which
        // hold only the keys this schema has no column for.
        await customStatement(
          'UPDATE folders SET starred = 1 '
          "WHERE json_extract(manifest_extra, '\$.st') = 1",
        );
        await customStatement(
          'UPDATE folders SET manifest_extra = '
          "NULLIF(json_remove(manifest_extra, '\$.st'), '{}') "
          "WHERE json_type(manifest_extra, '\$.st') IS NOT NULL",
        );
        await customStatement(
          "UPDATE drive_files SET duration_seconds = json_extract(manifest_extra, '\$.du') "
          "WHERE json_type(manifest_extra, '\$.du') = 'integer' "
          "AND json_extract(manifest_extra, '\$.du') > 0",
        );
        await customStatement(
          "UPDATE drive_files SET replaced_by = json_extract(manifest_extra, '\$.rb') "
          "WHERE json_type(manifest_extra, '\$.rb') = 'text'",
        );
        await customStatement(
          'UPDATE drive_files SET manifest_extra = '
          "NULLIF(json_remove(manifest_extra, '\$.du', '\$.rb'), '{}') "
          "WHERE json_type(manifest_extra, '\$.du') IS NOT NULL "
          "OR json_type(manifest_extra, '\$.rb') IS NOT NULL",
        );
      }
      if (from < 8) {
        await m.addColumn(transfers, transfers.sourceChatId);
        await m.addColumn(transfers, transfers.sourceMessageId);
        await m.addColumn(driveFiles, driveFiles.adopted);
      }
      if (from < 9) {
        await m.createTable(watchedFolders);
        await m.createTable(watchedFiles);
      }
      if (from < 10) {
        await m.createTable(pendingEdits);
        await m.addColumn(driveFiles, driveFiles.originalSize);
      }
      if (from == 11) {
        // Version 11 alone kept the layout each message's caption was in.
        for (final TableInfo<Table, dynamic> table in [fileParts, folders, albums]) {
          await m.dropColumn(table, 'caption_layout');
        }
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
  /// Android's file picker reads the index with its own SQL that follows
  /// this rule and [_inFolder]; test/picker_contract_test.dart runs it.
  Expression<bool> _shown(DriveFiles f) =>
      _complete(f) & f.hidden.equals(false);

  /// Items whose parent is gone (deleted from another device, or forwarded
  /// in without one) are shown at the root rather than lost.
  Expression<bool> _inFolder(GeneratedColumn<String> column, String? folderId) {
    if (folderId != null) return column.equals(folderId);
    return column.isNull() |
        column.isNotInQuery(selectOnly(folders)..addColumns([folders.id]));
  }

  Stream<List<FolderRow>> watchChildFolders(String? parentId) =>
      (select(folders)
            ..where(
              (f) => f.hidden.equals(false) & _inFolder(f.parentId, parentId),
            )
            ..orderBy([
              (f) => OrderingTerm.asc(f.name.collate(Collate.noCase)),
            ]))
          .watch();

  Stream<List<FileRow>> watchFilesIn(String? folderId) => (select(
    driveFiles,
  )..where((f) => _shown(f) & _inFolder(f.folderId, folderId))).watch();

  /// What [watchFilesIn] shows for [folderId], read once.
  Future<List<FileRow>> filesIn(String? folderId) => (select(
    driveFiles,
  )..where((f) => _shown(f) & _inFolder(f.folderId, folderId))).get();

  /// Newest additions first. With [excludeCameraRoll], only files added by
  /// hand or forwarded in: photo backup is the only thing that records a
  /// capture time, and a batch of new photos shouldn't bury the rest.
  Stream<List<FileRow>> watchRecent({
    int limit = 20,
    bool excludeCameraRoll = false,
  }) =>
      (select(driveFiles)
            ..where(
              (f) => excludeCameraRoll
                  ? _shown(f) & f.takenAt.isNull()
                  : _shown(f),
            )
            ..orderBy([(f) => OrderingTerm.desc(f.createdAt)])
            ..limit(limit))
          .watch();

  /// How many opened files this phone remembers.
  static const int keptOpens = 200;

  /// Remembers that this phone just opened, shared or sent [fileId], and
  /// forgets all but the newest [keptOpens].
  Future<void> recordOpen(String fileId) => recordOpens([fileId]);

  /// [recordOpen] for several files at once, as when they are sent
  /// together. One transaction, so Recent updates once rather than per file.
  Future<void> recordOpens(List<String> fileIds) => transaction(() async {
    final now = DateTime.now();
    await batch(
      (b) => b.insertAllOnConflictUpdate(fileOpens, [
        for (final id in fileIds)
          FileOpensCompanion.insert(fileId: id, openedAt: now),
      ]),
    );
    await customUpdate(
      'DELETE FROM file_opens WHERE file_id NOT IN '
      '(SELECT file_id FROM file_opens ORDER BY opened_at DESC LIMIT $keptOpens)',
      updates: {fileOpens},
    );
  });

  /// Files this phone opened, shared or sent, with when, most recent first.
  Stream<List<(FileRow, DateTime)>> watchRecentOpens({int limit = 20}) {
    final query =
        select(fileOpens).join([
            innerJoin(driveFiles, driveFiles.id.equalsExp(fileOpens.fileId)),
          ])
          ..where(_shown(driveFiles))
          ..orderBy([OrderingTerm.desc(fileOpens.openedAt)])
          ..limit(limit);
    return query.watch().map(
      (rows) => [
        for (final row in rows)
          (row.readTable(driveFiles), row.readTable(fileOpens).openedAt),
      ],
    );
  }

  Stream<List<FileRow>> watchStarred() =>
      (select(driveFiles)
            ..where((f) => _shown(f) & f.starred.equals(true))
            ..orderBy([(f) => OrderingTerm.desc(f.modifiedAt)]))
          .watch();

  /// How long a play position is kept after it was last written.
  static const Duration keptPositions = Duration(days: 60);

  /// Remembers that playback of [fileId] stopped at [positionMs] of
  /// [durationMs], and lets go of positions nothing has touched for
  /// [keptPositions].
  Future<void> savePlayPosition(
    String fileId,
    int positionMs,
    int durationMs,
  ) => transaction(() async {
    final now = DateTime.now();
    await into(playPositions).insertOnConflictUpdate(
      PlayPositionsCompanion.insert(
        fileId: fileId,
        positionMs: positionMs,
        durationMs: durationMs,
        updatedAt: now,
      ),
    );
    await (delete(playPositions)..where(
          (p) => p.updatedAt.isSmallerThanValue(now.subtract(keptPositions)),
        ))
        .go();
  });

  /// Where playback of [fileId] stopped, or null when nothing is kept.
  Future<PlayPositionRow?> playPositionOf(String fileId) => (select(
    playPositions,
  )..where((p) => p.fileId.equals(fileId))).getSingleOrNull();

  Future<void> forgetPlayPosition(String fileId) =>
      (delete(playPositions)..where((p) => p.fileId.equals(fileId))).go();

  /// Files this phone stopped partway through since [since], most recently
  /// played first, with the name of the folder each is in. Trashed and
  /// incomplete files are left out.
  Stream<List<ResumePoint>> watchResumePoints({
    required DateTime since,
    int limit = 3,
  }) {
    final query =
        select(playPositions).join([
            innerJoin(
              driveFiles,
              driveFiles.id.equalsExp(playPositions.fileId),
            ),
            leftOuterJoin(folders, folders.id.equalsExp(driveFiles.folderId)),
          ])
          ..where(
            _shown(driveFiles) &
                playPositions.updatedAt.isBiggerThanValue(since),
          )
          ..orderBy([OrderingTerm.desc(playPositions.updatedAt)])
          ..limit(limit);
    return query.watch().map(
      (rows) => [
        for (final row in rows)
          ResumePoint(
            row.readTable(driveFiles),
            row.readTable(playPositions).positionMs,
            row.readTable(playPositions).durationMs,
            row.readTableOrNull(folders)?.name,
          ),
      ],
    );
  }

  /// Starred folders that aren't in the trash, in name order.
  Stream<List<FolderRow>> watchStarredFolders() =>
      (select(folders)
            ..where((f) => f.hidden.equals(false) & f.starred.equals(true))
            ..orderBy([
              (f) => OrderingTerm.asc(f.name.collate(Collate.noCase)),
            ]))
          .watch();

  /// [_shown] as SQL, for the lite queries.
  static const _shownSql = 'parts_present >= part_count AND hidden = 0';

  /// Shown files matching [where], in [orderBy] order, as [LiteFileRow]s.
  /// The column list is taken from the table, so a column added later is
  /// read here too rather than coming back null. [readsFrom] names any
  /// other table [where] looks at, so a change there updates the list.
  Stream<List<LiteFileRow>> _liteSelect(
    String where,
    String orderBy, {
    List<Variable> variables = const [],
    Set<ResultSetImplementation> readsFrom = const {},
  }) {
    final columns = [
      for (final column in driveFiles.$columns)
        if (column.name != driveFiles.minithumbnail.name)
          column.escapedNameFor(SqlDialect.sqlite),
    ].join(', ');
    return customSelect(
      'SELECT $columns, NULL AS minithumbnail, '
      'minithumbnail IS NOT NULL AS has_mini '
      'FROM drive_files WHERE $_shownSql AND $where ORDER BY $orderBy',
      variables: variables,
      readsFrom: {driveFiles, ...readsFrom},
    ).watch().map(
      (rows) => [
        for (final row in rows)
          LiteFileRow(driveFiles.map(row.data), row.read<bool>('has_mini')),
      ],
    );
  }

  /// Photos and videos, newest capture first — the Photos timeline.
  Stream<List<LiteFileRow>> watchMediaLite() => _liteSelect(
    'kind IN (?1, ?2)',
    'COALESCE(taken_at, created_at) DESC',
    variables: [
      Variable.withString(FileKind.image.name),
      Variable.withString(FileKind.video.name),
    ],
  );

  /// Telegram's inline preview of file [id], base64 as stored, or null.
  Future<String?> minithumbnailOf(String id) async {
    final row =
        await (selectOnly(driveFiles)
              ..addColumns([driveFiles.minithumbnail])
              ..where(driveFiles.id.equals(id)))
            .getSingleOrNull();
    return row?.read(driveFiles.minithumbnail);
  }

  /// Telegram's thumbnail of every shown photo and video that has one,
  /// newest capture first, the order the Photos timeline shows them in.
  Future<List<({String fileId, int thumbnailFileId})>> mediaThumbnails() async {
    final when = coalesce([driveFiles.takenAt, driveFiles.createdAt]);
    final rows =
        await (selectOnly(driveFiles)
              ..addColumns([driveFiles.id, driveFiles.thumbnailFileId])
              ..where(
                _shown(driveFiles) &
                    driveFiles.kind.isIn([
                      FileKind.image.name,
                      FileKind.video.name,
                    ]) &
                    driveFiles.thumbnailFileId.isNotNull(),
              )
              ..orderBy([
                OrderingTerm(expression: when, mode: OrderingMode.desc),
              ]))
            .get();
    return [
      for (final row in rows)
        (
          fileId: row.read(driveFiles.id)!,
          thumbnailFileId: row.read(driveFiles.thumbnailFileId)!,
        ),
    ];
  }

  /// `name|size` of every file in the drive, to its file id. How backup
  /// recognises what is already up there after a reinstall or on a new
  /// phone, where device media ids mean nothing. Every kind counts, so a
  /// photo uploaded by hand, or one whose type was guessed differently,
  /// isn't sent again either. A small copy is keyed by its original's size
  /// and flagged, so the photo it stands in for is known by the size it
  /// has on the phone, and its original still goes up.
  Future<Map<String, ({String fileId, bool smallCopy})>> mediaFingerprints() async {
    final rows = await (selectOnly(driveFiles)..addColumns([
          driveFiles.id,
          driveFiles.name,
          driveFiles.size,
          driveFiles.originalSize,
        ]))
        .get();
    return {
      for (final row in rows)
        '${row.read(driveFiles.name)}|${row.read(driveFiles.originalSize) ?? row.read(driveFiles.size)}':
            (
              fileId: row.read(driveFiles.id)!,
              smallCopy: row.read(driveFiles.originalSize) != null,
            ),
    };
  }

  /// The backup states whose drive file stands for a photo still on this
  /// phone: backed up, or so far only as a small copy.
  static const _onPhone = [BackupAssetState.done, BackupAssetState.smallCopy];

  /// Drive file id to the phone's media id, for every backed-up photo this
  /// phone still knows, small copies included. Lets the app show the
  /// phone's own sharp copy.
  Stream<Map<String, String>> watchLocalAssets() {
    return (select(backupAssets)..where(
          (a) => a.state.isInValues(_onPhone) & a.fileId.isNotNull(),
        ))
        .watch()
        .map((rows) => {for (final row in rows) row.fileId!: row.assetId});
  }

  /// The phone's media id for drive file [fileId], if it has a copy, the
  /// original of a small copy included.
  Future<String?> localAssetOf(String fileId) =>
      (select(backupAssets)
            ..where(
              (a) => a.fileId.equals(fileId) & a.state.isInValues(_onPhone),
            )
            ..limit(1))
          .map((a) => a.assetId)
          .getSingleOrNull();

  /// How many of this phone's photos have only a small copy in the drive,
  /// and how big their originals are, live: what backup still has to send
  /// once it may. Files in the trash or not yet whole are left out.
  Stream<({int count, int bytes})> watchPendingOriginals() => customSelect(
    'SELECT COUNT(*) AS n, COALESCE(SUM(f.original_size), 0) AS bytes '
    'FROM backup_assets a JOIN drive_files f ON f.id = a.file_id '
    "WHERE a.state = 'smallCopy' AND f.original_size IS NOT NULL "
    'AND f.parts_present >= f.part_count AND f.hidden = 0',
    readsFrom: {backupAssets, driveFiles},
  ).watchSingle().map((row) => (count: row.read<int>('n'), bytes: row.read<int>('bytes')));

  /// Drive file id to the phone's media ids, for those of [fileIds] backed
  /// up from this phone. One drive file can stand for several of the
  /// phone's photos, when backup found one with the same name and size
  /// already in the drive. Only finished backups count, so a photo whose
  /// drive copy isn't whole is never offered for deleting from the phone.
  /// In slices, since a big selection is more ids than SQLite takes in one
  /// statement.
  Future<Map<String, List<String>>> localAssetsOf(
    Iterable<String> fileIds,
  ) async {
    final ids = fileIds.toList();
    final found = <String, List<String>>{};
    for (var i = 0; i < ids.length; i += 500) {
      final slice = ids.sublist(i, (i + 500).clamp(0, ids.length));
      final rows =
          await (select(backupAssets)..where(
                (a) =>
                    a.fileId.isIn(slice) &
                    a.state.equalsValue(BackupAssetState.done),
              ))
              .get();
      for (final row in rows) {
        (found[row.fileId!] ??= []).add(row.assetId);
      }
    }
    return found;
  }

  /// Files of one kind, newest addition first.
  Stream<List<LiteFileRow>> watchKindLite(FileKind kind) => _liteSelect(
    'kind = ?1',
    'created_at DESC',
    variables: [Variable.withString(kind.name)],
  );

  /// The most files one search returns.
  static const searchLimit = 500;

  /// Files named like [query], or whose recognised content mentions it,
  /// that were taken or added within [range], are one of [kinds] and sit in
  /// one of [folderIds]; each left out matches everything. [literal] is the
  /// text as typed: a file whose name holds all of it matches too, so
  /// "report 2024" still finds "report 2024.pdf" uploaded in another year
  /// after "2024" was read as a date.
  ///
  /// Newest change first, or newest moment first with [range] or
  /// [byMoment], so a cut-off list keeps the files a timeline shows first.
  Stream<List<FileRow>> watchSearch(
    String query, {
    Set<FileKind>? kinds,
    (DateTime, DateTime)? range,
    Iterable<String>? folderIds,
    String? literal,
    bool byMoment = false,
  }) {
    final words = query.trim();
    final typed = literal?.trim() ?? '';
    final when = coalesce([driveFiles.takenAt, driveFiles.createdAt]);
    return (select(driveFiles)
          ..where((f) {
            var condition = _shown(f);
            if (words.isNotEmpty) {
              // The indexer stores content in lower case.
              final inContent = selectOnly(fileContents)
                ..addColumns([fileContents.fileId])
                ..where(
                  fileContents.content.like(
                    _like(words.toLowerCase()),
                    escapeChar: r'\',
                  ),
                );
              condition &=
                  f.name.like(_like(words), escapeChar: r'\') |
                  f.id.isInQuery(inContent);
            }
            if (range != null) {
              condition &= when.isBetweenValues(range.$1, range.$2);
            }
            if (typed.isNotEmpty &&
                typed.toLowerCase() != words.toLowerCase()) {
              condition |=
                  _shown(f) & f.name.like(_like(typed), escapeChar: r'\');
            }
            if (kinds != null) {
              condition &= f.kind.isIn([for (final kind in kinds) kind.name]);
            }
            if (folderIds != null) condition &= f.folderId.isIn(folderIds);
            return condition;
          })
          ..orderBy([
            (f) => range != null || byMoment
                ? OrderingTerm(expression: when, mode: OrderingMode.desc)
                : OrderingTerm.desc(f.modifiedAt),
          ])
          ..limit(searchLimit))
        .watch();
  }

  /// Folders named like [query], only those among [within] when given.
  /// Starred folders come first, then the rest by name.
  Stream<List<FolderRow>> watchFolderSearch(
    String query, {
    Iterable<String>? within,
  }) {
    final pattern = _like(query);
    return (select(folders)
          ..where((f) {
            var condition =
                f.hidden.equals(false) & f.name.like(pattern, escapeChar: r'\');
            if (within != null) condition &= f.id.isIn(within);
            return condition;
          })
          ..orderBy([
            (f) => OrderingTerm.desc(f.starred),
            (f) => OrderingTerm.asc(f.name),
          ])
          ..limit(50))
        .watch();
  }

  /// A LIKE pattern for text containing [text], with its own `%`, `_` and
  /// `\` taken literally. LIKE ignores case only for plain Latin letters,
  /// so [text] keeps its own.
  static String _like(String text) =>
      '%${text.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_')}%';

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

  /// The [limit] biggest files the drive shows, biggest first.
  Stream<List<FileRow>> watchLargestFiles({int limit = 50}) =>
      (select(driveFiles)
            ..where(_shown)
            ..orderBy([
              (f) => OrderingTerm.desc(f.size),
              (f) => OrderingTerm.asc(f.name),
            ])
            ..limit(limit))
          .watch();

  /// Every top-level folder that holds files, with what is in it and below
  /// it, biggest first, then one row for the files in no folder when there
  /// are any. A folder or file whose parent is gone counts as top-level, as
  /// Files lists it at the root, so the rows add up to the drive's total.
  /// UNION rather than UNION ALL, so a folder tree that loops ends anyway.
  Stream<List<FolderSize>> watchFolderSizes() =>
      customSelect(
        'WITH RECURSIVE tree(root, id) AS ('
        'SELECT id, id FROM folders WHERE hidden = 0 '
        'AND (parent_id IS NULL OR parent_id NOT IN (SELECT id FROM folders)) '
        'UNION SELECT t.root, f.id FROM folders f JOIN tree t ON f.parent_id = t.id '
        'WHERE f.hidden = 0) '
        'SELECT * FROM ('
        'SELECT t.root AS id, r.name AS name, COUNT(d.id) AS n, '
        'COALESCE(SUM(d.size), 0) AS bytes '
        'FROM tree t JOIN drive_files d ON d.folder_id = t.id '
        'JOIN folders r ON r.id = t.root '
        'WHERE d.hidden = 0 AND d.parts_present >= d.part_count '
        'GROUP BY t.root '
        'UNION ALL '
        "SELECT NULL, '', COUNT(*), COALESCE(SUM(size), 0) FROM drive_files "
        'WHERE hidden = 0 AND parts_present >= part_count '
        'AND (folder_id IS NULL OR folder_id NOT IN (SELECT id FROM folders))'
        ') ORDER BY id IS NULL, bytes DESC, name',
        readsFrom: {folders, driveFiles},
      ).watch().map(
        (rows) => [
          for (final row in rows)
            if (row.read<String?>('id') != null || row.read<int>('n') > 0)
              FolderSize(
                row.read<String?>('id'),
                row.read<String>('name'),
                row.read<int>('n'),
                row.read<int>('bytes'),
              ),
        ],
      );

  /// Every starred folder that isn't in the trash, with how many files it
  /// holds, in it or in any folder below it, and their size; a starred
  /// folder with nothing in it has a row of zeros. The same tree walk as
  /// [watchFolderSizes], rooted at the starred folders rather than the
  /// top-level ones, since a starred folder can sit anywhere. UNION rather
  /// than UNION ALL, so a folder tree that loops ends anyway.
  Stream<List<FolderSize>> watchStarredFolderSizes() =>
      customSelect(
        'WITH RECURSIVE tree(root, id) AS ('
        'SELECT id, id FROM folders WHERE hidden = 0 AND starred = 1 '
        'UNION SELECT t.root, f.id FROM folders f JOIN tree t ON f.parent_id = t.id '
        'WHERE f.hidden = 0) '
        'SELECT t.root AS id, r.name AS name, COUNT(d.id) AS n, '
        'COALESCE(SUM(d.size), 0) AS bytes '
        'FROM tree t JOIN folders r ON r.id = t.root '
        'LEFT JOIN drive_files d ON d.folder_id = t.id '
        'AND d.hidden = 0 AND d.parts_present >= d.part_count '
        'GROUP BY t.root ORDER BY r.name COLLATE NOCASE',
        readsFrom: {folders, driveFiles},
      ).watch().map(
        (rows) => [
          for (final row in rows)
            FolderSize(
              row.read<String>('id'),
              row.read<String>('name'),
              row.read<int>('n'),
              row.read<int>('bytes'),
            ),
        ],
      );

  /// How many files the trash holds, those inside trashed folders included,
  /// and their size.
  Stream<(int count, int bytes)> watchTrashTotals() => customSelect(
    'SELECT COUNT(*) AS n, COALESCE(SUM(size), 0) AS bytes FROM drive_files '
    'WHERE hidden = 1 AND parts_present >= part_count',
    readsFrom: {driveFiles},
  ).watchSingle().map((row) => (row.read<int>('n'), row.read<int>('bytes')));

  Stream<FileRow?> watchFile(String id) =>
      (select(driveFiles)..where((f) => f.id.equals(id))).watchSingleOrNull();

  Future<FileRow?> fileById(String id) =>
      (select(driveFiles)..where((f) => f.id.equals(id))).getSingleOrNull();

  Future<FolderRow?> folderById(String id) =>
      (select(folders)..where((f) => f.id.equals(id))).getSingleOrNull();

  Stream<FolderRow?> watchFolder(String id) =>
      (select(folders)..where((f) => f.id.equals(id))).watchSingleOrNull();

  Future<List<FolderRow>> allFolders() => select(folders).get();

  /// Every folder, trashed ones too; the table is small enough to read whole.
  Stream<List<FolderRow>> watchAllFolders() => select(folders).watch();

  /// [rootId] and every folder below it that isn't in the trash. UNION
  /// rather than UNION ALL, so a folder tree that loops ends anyway.
  Future<Set<String>> descendantFolderIds(String rootId) async {
    final rows = await customSelect(
      'WITH RECURSIVE tree(id) AS ('
      'SELECT ?1 '
      'UNION SELECT f.id FROM folders f JOIN tree t ON f.parent_id = t.id '
      'WHERE f.hidden = 0) '
      'SELECT id FROM tree',
      variables: [Variable.withString(rootId)],
      readsFrom: {folders},
    ).get();
    return {for (final row in rows) row.read<String>('id')};
  }

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

  /// Files with a part gone from the channel, so they can't be opened, by
  /// name. Those in the trash are left out: they go with it.
  Future<List<FileRow>> incompleteFiles() =>
      (select(driveFiles)
            ..where((f) => f.partsPresent.isSmallerThan(f.partCount) & f.hidden.equals(false))
            ..orderBy([(f) => OrderingTerm.asc(f.name.collate(Collate.noCase))]))
          .get();

  /// How many files the drive shows that are kept in parts, whether or not
  /// every part is still there.
  Future<int> countSplitFiles() {
    final count = driveFiles.id.count();
    return (selectOnly(driveFiles)
          ..addColumns([count])
          ..where(driveFiles.partCount.isBiggerThanValue(1) & driveFiles.hidden.equals(false)))
        .map((r) => r.read(count) ?? 0)
        .getSingle();
  }

  /// [ids] that are still shown files (not trashed, not gone).
  Future<List<FileRow>> shownFiles(Iterable<String> ids) =>
      (select(driveFiles)..where((f) => _shown(f) & f.id.isIn(ids))).get();

  /// Every channel message the index knows about, for reconciliation.
  Future<Set<int>> knownMessageIds() async {
    final partIds =
        await (selectOnly(fileParts)..addColumns([fileParts.messageId]))
            .map((r) => r.read(fileParts.messageId)!)
            .get();
    final folderIds =
        await (selectOnly(folders)..addColumns([folders.messageId]))
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

  /// Works out [DriveFiles.hidden] again for one file, after a change made
  /// on this phone moved it to or out of the trash or into another folder.
  Future<void> refreshHiddenFile(String fileId) => _refreshHiddenFile(fileId);

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
                  _complete(f) &
                  f.trashedAt.isNotNull() &
                  _parentShown(f.folderId),
            )
            ..orderBy([(f) => OrderingTerm.desc(f.trashedAt)]))
          .watch();

  /// The files in the trash that [fileId] replaced, the one trashed last
  /// first. A replacement counts only while the file is in the trash: a
  /// restore clears it, and a build that doesn't know the key leaves it
  /// behind when it restores.
  Future<List<FileRow>> trashedReplacementsOf(String fileId) =>
      (select(driveFiles)
            ..where(
              (f) => f.replacedBy.equals(fileId) & f.trashedAt.isNotNull(),
            )
            ..orderBy([(f) => OrderingTerm.desc(f.trashedAt)]))
          .get();

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

  Future<List<String>> albumIdsOf(String fileId) => (select(
    albumFiles,
  )..where((a) => a.fileId.equals(fileId))).map((a) => a.albumId).get();

  /// The names of the albums [fileId] is in, in name order, for Details.
  /// An album whose message is gone drops out even while its links remain.
  Future<List<String>> albumNamesOf(String fileId) async {
    final query =
        select(albums).join([
            innerJoin(albumFiles, albumFiles.albumId.equalsExp(albums.id)),
          ])
          ..where(albumFiles.fileId.equals(fileId))
          ..orderBy([OrderingTerm.asc(albums.name)]);
    return [for (final row in await query.get()) row.readTable(albums).name];
  }

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
  Stream<List<LiteFileRow>> watchAlbumFilesLite(String albumId) => _liteSelect(
    'id IN (SELECT file_id FROM album_files WHERE album_id = ?1)',
    'COALESCE(taken_at, created_at) DESC',
    variables: [Variable.withString(albumId)],
    readsFrom: {albumFiles},
  );

  /// Those of the files [ids] that are shown, newest moment first, as the
  /// timeline orders them. Ids go in as variables, so keep them to a few
  /// hundred.
  Stream<List<LiteFileRow>> watchFilesLite(List<String> ids) => ids.isEmpty
      ? Stream.value(const [])
      : _liteSelect(
          'id IN (${List.filled(ids.length, '?').join(', ')})',
          'COALESCE(taken_at, created_at) DESC',
          variables: [for (final id in ids) Variable.withString(id)],
        );

  /// An album's files, newest moment first, previews and all.
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
          ..orderBy([
            (_) => OrderingTerm(expression: when, mode: OrderingMode.desc),
          ]))
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

  Stream<Set<String>> watchOfflinePins() =>
      select(offlinePins)
          .watch()
          .map((rows) => {for (final row in rows) row.itemId});

  Future<List<OfflineCopyRow>> offlineCopyList() => select(offlineCopies).get();

  Stream<Map<String, String>> watchOfflineCopies() =>
      select(offlineCopies)
          .watch()
          .map((rows) => {for (final row in rows) row.fileId: row.path});

  Future<OfflineCopyRow?> offlineCopyOf(String fileId) => (select(
    offlineCopies,
  )..where((c) => c.fileId.equals(fileId))).getSingleOrNull();

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
    for (final row in await (select(
      fileContents,
    )..where((c) => c.version.isBiggerOrEqualValue(version))).get())
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
  Future<void> dropContentBefore(int version) => (delete(
    fileContents,
  )..where((c) => c.version.isSmallerThanValue(version))).go();

  Stream<int> watchIndexedCount() {
    final count = fileContents.fileId.count();
    return (selectOnly(
      fileContents,
    )..addColumns([count])).map((r) => r.read(count) ?? 0).watchSingle();
  }

  // ---------------------------------------------------------------------------
  // Freeing up space
  // ---------------------------------------------------------------------------

  /// Phone media id to its drive copy, for every photo and video backed up
  /// from this phone whose copy is complete and not in the trash: the ones
  /// safe to delete from the phone. The row carries the copy's size and
  /// when the photo was taken, which Free up space counts and dates by.
  /// Only finished backups count: a photo with just a small copy in the
  /// drive is never freeable, since its original exists only on the phone.
  Future<Map<String, FileRow>> safelyBackedUp() async {
    final query =
        select(backupAssets).join([
          innerJoin(driveFiles, driveFiles.id.equalsExp(backupAssets.fileId)),
        ])..where(
          backupAssets.state.equalsValue(BackupAssetState.done) &
              _shown(driveFiles),
        );
    return {
      for (final row in await query.get())
        row.readTable(backupAssets).assetId: row.readTable(driveFiles),
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

  /// Inserts or refreshes one of a file's parts, keeping
  /// [DriveFiles.partsPresent] in step, and writes the file's row as
  /// [write] allows. True when the row was written from [file].
  Future<bool> upsertFilePart(
    DriveFilesCompanion file,
    FilePartsCompanion part, {
    FileRowWrite write = FileRowWrite.always,
  }) {
    return transaction(() async {
      // A message id belongs to exactly one part; if a caption edit moved it
      // (rare, but forwarded files get adopted this way) drop the stale row.
      Expression<bool> stale($FilePartsTable p) =>
          p.messageId.equals(part.messageId.value) &
          p.fileId.equals(part.fileId.value).not();
      final previousOwners = await (select(
        fileParts,
      )..where(stale)).map((p) => p.fileId).get();
      await (delete(fileParts)..where(stale)).go();
      for (final owner in previousOwners) {
        await _recountParts(owner);
      }
      final fileId = part.fileId.value;
      final writes = switch (write) {
        FileRowWrite.always => true,
        FileRowWrite.unlessFirstPartKnown => !await _hasFirstPart(fileId),
        FileRowWrite.ifAbsent => await fileById(fileId) == null,
      };
      // partsPresent is absent from [file], so an update leaves it alone.
      if (writes) await into(driveFiles).insertOnConflictUpdate(file);
      await into(fileParts).insertOnConflictUpdate(part);
      await _recountParts(fileId);
      await _refreshHiddenFile(fileId);
      return writes;
    });
  }

  Future<bool> _hasFirstPart(String fileId) async =>
      await (select(fileParts)
            ..where((p) => p.fileId.equals(fileId) & p.partIndex.equals(0)))
          .getSingleOrNull() !=
      null;

  Future<void> _recountParts(String fileId) async {
    final count = fileParts.fileId.count();
    final present =
        await (selectOnly(fileParts)
              ..addColumns([count])
              ..where(fileParts.fileId.equals(fileId)))
            .map((r) => r.read(count) ?? 0)
            .getSingle();
    if (present == 0) {
      await (delete(driveFiles)..where((f) => f.id.equals(fileId))).go();
      await (delete(albumFiles)..where((a) => a.fileId.equals(fileId))).go();
      await (delete(fileOpens)..where((o) => o.fileId.equals(fileId))).go();
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
      final affected =
          await (selectOnly(fileParts, distinct: true)
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

  /// Swaps the whole index for the rows given, in one transaction: what a
  /// copy of the index read from the channel holds.
  Future<void> replaceIndex({
    required List<FoldersCompanion> folderRows,
    required List<AlbumsCompanion> albumRows,
    required List<DriveFilesCompanion> fileRows,
    required List<FilePartsCompanion> partRows,
    required List<AlbumFilesCompanion> albumFileRows,
  }) => transaction(() async {
    await clearIndex();
    await batch((b) {
      b
        ..insertAll(folders, folderRows)
        ..insertAll(albums, albumRows)
        ..insertAll(driveFiles, fileRows)
        ..insertAll(fileParts, partRows)
        ..insertAll(albumFiles, albumFileRows);
    });
    await refreshHidden();
  });

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
    await delete(fileOpens).go();
    await delete(playPositions).go();
    await delete(watchedFiles).go();
    await delete(watchedFolders).go();
    await delete(pendingEdits).go();
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

  /// Records that only a small copy of [assetId] is in the drive, as
  /// [fileId], so its original still goes up and the phone's copy is never
  /// offered for deleting meanwhile. The original starts with fresh tries.
  Future<void> markAssetSmallCopy(String assetId, String fileId) =>
      into(backupAssets).insertOnConflictUpdate(
        BackupAssetsCompanion.insert(
          assetId: assetId,
          state: BackupAssetState.smallCopy,
          fileId: Value(fileId),
          failures: const Value(0),
          updatedAt: DateTime.now(),
          reason: const Value(null),
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

  /// Records a failed attempt, with [reason] as the sentence the Not backed
  /// up screen shows for it.
  Future<void> markAssetFailed(
    String assetId,
    int failures, {
    String? reason,
  }) => into(backupAssets).insertOnConflictUpdate(
    BackupAssetsCompanion.insert(
      assetId: assetId,
      state: BackupAssetState.failed,
      failures: Value(failures),
      updatedAt: DateTime.now(),
      reason: Value(reason),
    ),
  );

  /// What backup knows of one photo, or null when it was never tried.
  Future<BackupAssetRow?> backupAssetOf(String assetId) => (select(
    backupAssets,
  )..where((a) => a.assetId.equals(assetId))).getSingleOrNull();

  /// Sets a failed photo aside until the person brings it back; it keeps
  /// its failures and reason meanwhile. Returns 0 when the photo wasn't
  /// failed, so a second tap changes nothing.
  Future<int> markAssetSkipped(String assetId) =>
      (update(backupAssets)..where(
            (a) =>
                a.assetId.equals(assetId) &
                a.state.equalsValue(BackupAssetState.failed),
          ))
          .write(
            BackupAssetsCompanion(
              state: const Value(BackupAssetState.skipped),
              updatedAt: Value(DateTime.now()),
            ),
          );

  /// Puts a photo set aside back among the failed ones, with the failures
  /// and reason it kept. Returns 0 when it isn't set aside any more, so a
  /// late Undo leaves a photo that has moved on as it is.
  Future<int> unmarkAssetSkipped(String assetId) =>
      (update(backupAssets)..where(
            (a) =>
                a.assetId.equals(assetId) &
                a.state.equalsValue(BackupAssetState.skipped),
          ))
          .write(
            BackupAssetsCompanion(
              state: const Value(BackupAssetState.failed),
              updatedAt: Value(DateTime.now()),
            ),
          );

  /// Sets [assetId] aside however backup knew it, never tried included,
  /// keeping its failures, reason and drive file, so [unskipAsset] can put
  /// it back as it was.
  Future<void> setAssetSkipped(String assetId) {
    final now = DateTime.now();
    return into(backupAssets).insert(
      BackupAssetsCompanion.insert(
        assetId: assetId,
        state: BackupAssetState.skipped,
        updatedAt: now,
      ),
      onConflict: DoUpdate(
        (_) => BackupAssetsCompanion(
          state: const Value(BackupAssetState.skipped),
          updatedAt: Value(now),
        ),
      ),
    );
  }

  /// Puts back the record [assetId] had before [setAssetSkipped], which is
  /// [previous], or none. Returns 0 when it isn't set aside any more (Bring
  /// back ran, and it may have gone up since), and changes nothing then.
  Future<int> unskipAsset(String assetId, BackupAssetRow? previous) {
    Expression<bool> skipped($BackupAssetsTable a) =>
        a.assetId.equals(assetId) & a.state.equalsValue(BackupAssetState.skipped);
    if (previous == null) return (delete(backupAssets)..where(skipped)).go();
    return (update(backupAssets)..where(skipped)).write(previous.toCompanion(true));
  }

  /// Forgets one photo's failures, so the next pass tries it afresh.
  /// Returns 0 when there was nothing to forget.
  Future<int> clearBackupFailure(String assetId) =>
      (delete(backupAssets)..where(
            (a) =>
                a.assetId.equals(assetId) &
                a.state.equalsValue(BackupAssetState.failed),
          ))
          .go();

  Future<void> clearBackupFailures() => (delete(
    backupAssets,
  )..where((a) => a.state.equalsValue(BackupAssetState.failed))).go();

  /// Brings every skipped photo back into backup.
  Future<void> clearSkipped() => (delete(
    backupAssets,
  )..where((a) => a.state.equalsValue(BackupAssetState.skipped))).go();

  /// Photos that failed at least [minFailures] times, most recent first.
  Stream<List<BackupAssetRow>> watchFailedAssets({required int minFailures}) =>
      (select(backupAssets)
            ..where(
              (a) =>
                  a.state.equalsValue(BackupAssetState.failed) &
                  a.failures.isBiggerOrEqualValue(minFailures),
            )
            ..orderBy([(a) => OrderingTerm.desc(a.updatedAt)]))
          .watch();

  /// Media ids of the photos set aside, live.
  Stream<List<String>> watchSkippedAssetIds() =>
      (selectOnly(backupAssets)
            ..addColumns([backupAssets.assetId])
            ..where(backupAssets.state.equalsValue(BackupAssetState.skipped)))
          .map((r) => r.read(backupAssets.assetId)!)
          .watch();

  /// Media ids of photos backed up from this phone whose drive file is gone
  /// or has lost a part. A file in the trash still has its row, so it
  /// counts as present, and a record with no file to point at is left
  /// alone: there is nothing to check it against.
  Future<List<String>> backedUpButMissing() async {
    final rows = await customSelect(
      'SELECT a.asset_id FROM backup_assets a '
      'LEFT JOIN drive_files f ON f.id = a.file_id '
      "WHERE a.state = 'done' AND a.file_id IS NOT NULL "
      'AND (f.id IS NULL OR f.parts_present < f.part_count)',
      readsFrom: {backupAssets, driveFiles},
    ).get();
    return [for (final row in rows) row.read<String>('asset_id')];
  }

  /// How many backed-up photos point at a drive file.
  Future<int> countBackedUpWithFile() {
    final count = backupAssets.assetId.count();
    return (selectOnly(backupAssets)
          ..addColumns([count])
          ..where(
            backupAssets.state.equalsValue(BackupAssetState.done) &
                backupAssets.fileId.isNotNull(),
          ))
        .map((r) => r.read(count) ?? 0)
        .getSingle();
  }

  /// Records that [assetIds] were backed up once and their files are no
  /// longer in the drive, so the person can say whether they go up again.
  Future<void> markAssetsMissing(List<String> assetIds) => transaction(() async {
    for (final slice in _slices(assetIds)) {
      await (update(backupAssets)..where((a) => a.assetId.isIn(slice))).write(
        BackupAssetsCompanion(
          state: const Value(BackupAssetState.missing),
          fileId: const Value(null),
          updatedAt: Value(DateTime.now()),
        ),
      );
    }
  });

  /// How many backed-up photos are no longer in the drive and wait for the
  /// person's choice, live.
  Stream<int> watchMissingCount() {
    final count = backupAssets.assetId.count();
    return (selectOnly(backupAssets)
          ..addColumns([count])
          ..where(backupAssets.state.equalsValue(BackupAssetState.missing)))
        .map((r) => r.read(count) ?? 0)
        .watchSingle();
  }

  /// Forgets the missing photos' records, so the next pass judges them
  /// afresh and sends up what the drive lacks.
  Future<void> backUpMissingAgain() => (delete(
    backupAssets,
  )..where((a) => a.state.equalsValue(BackupAssetState.missing))).go();

  /// Leaves the missing photos out of backup for good.
  Future<void> leaveOutMissing() =>
      (update(backupAssets)..where((a) => a.state.equalsValue(BackupAssetState.missing))).write(
        BackupAssetsCompanion(
          state: const Value(BackupAssetState.removed),
          updatedAt: Value(DateTime.now()),
        ),
      );

  /// Records that the files [fileIds] were deleted for good here, so the
  /// photos behind them are never offered for backing up again.
  Future<void> markFilesRemoved(Iterable<String> fileIds) => transaction(() async {
    for (final slice in _slices(fileIds.toList())) {
      await (update(backupAssets)..where((a) => a.fileId.isIn(slice))).write(
        BackupAssetsCompanion(
          state: const Value(BackupAssetState.removed),
          updatedAt: Value(DateTime.now()),
        ),
      );
    }
  });

  /// [ids] in runs short enough for one SQLite statement.
  static Iterable<List<String>> _slices(List<String> ids) sync* {
    for (var i = 0; i < ids.length; i += 500) {
      yield ids.sublist(i, math.min(i + 500, ids.length));
    }
  }

  // ---------------------------------------------------------------------------
  // Watched phone folders (this phone only)
  // ---------------------------------------------------------------------------

  /// The watched folders, in the order they were added.
  Stream<List<WatchedFolderRow>> watchWatchedFolders() =>
      (select(watchedFolders)..orderBy([(w) => OrderingTerm.asc(w.createdAt)])).watch();

  Future<List<WatchedFolderRow>> watchedFolderList() =>
      (select(watchedFolders)..orderBy([(w) => OrderingTerm.asc(w.createdAt)])).get();

  Future<void> saveWatchedFolder(WatchedFoldersCompanion row) =>
      into(watchedFolders).insertOnConflictUpdate(row);

  /// Writes only the fields [changes] holds, so a check that finishes while
  /// the person edits the folder never puts back what they changed.
  Future<void> updateWatchedFolder(String id, WatchedFoldersCompanion changes) =>
      (update(watchedFolders)..where((w) => w.id.equals(id))).write(changes);

  /// Forgets a watched folder together with its ledger, so a folder added
  /// again starts over.
  Future<void> deleteWatchedFolder(String id) => transaction(() async {
    await (delete(watchedFiles)..where((f) => f.ruleId.equals(id))).go();
    await (delete(watchedFolders)..where((w) => w.id.equals(id))).go();
  });

  /// What watched folder [ruleId] has settled so far, by document id.
  Future<Map<String, WatchedFileRow>> watchedLedger(String ruleId) async => {
    for (final row in await (select(watchedFiles)..where((f) => f.ruleId.equals(ruleId))).get())
      row.documentId: row,
  };

  Future<void> saveWatchedFiles(Iterable<WatchedFilesCompanion> rows) =>
      batch((b) => b.insertAllOnConflictUpdate(watchedFiles, rows.toList()));

  /// How many files each watched folder has in the drive, by rule id.
  Stream<Map<String, int>> watchUploadedCounts() => customSelect(
    "SELECT rule_id, COUNT(*) AS n FROM watched_files WHERE state = 'done' GROUP BY rule_id",
    readsFrom: {watchedFiles},
  ).watch().map(
    (rows) => {for (final row in rows) row.read<String>('rule_id'): row.read<int>('n')},
  );

  // ---------------------------------------------------------------------------
  // Waiting changes (this phone only)
  // ---------------------------------------------------------------------------

  Future<PendingEditRow?> pendingEditOf(EditTarget target, String itemId) =>
      (select(pendingEdits)
            ..where((e) => e.target.equalsValue(target) & e.itemId.equals(itemId)))
          .getSingleOrNull();

  /// Waiting changes, the one made first first. Times are kept to the
  /// second, so changes made within one keep the order their rows were
  /// added in, which a later edit of the same item leaves alone.
  SimpleSelectStatement<$PendingEditsTable, PendingEditRow> get _pendingInOrder =>
      select(pendingEdits)..orderBy([
        (e) => OrderingTerm.asc(e.createdAt),
        (e) => OrderingTerm.asc(e.rowId),
      ]);

  /// Every waiting change, in the order they go to Telegram.
  Future<List<PendingEditRow>> pendingEditList() => _pendingInOrder.get();

  /// [pendingEditList] as it changes.
  Stream<List<PendingEditRow>> watchPendingEdits() => _pendingInOrder.watch();

  Selectable<String> get _pendingItemIds =>
      (selectOnly(pendingEdits)..addColumns([pendingEdits.itemId]))
          .map((row) => row.read(pendingEdits.itemId)!);

  /// The ids of the items with a change waiting, whatever they are.
  Future<Set<String>> pendingEditIds() async => (await _pendingItemIds.get()).toSet();

  /// [pendingEditIds] as they change.
  Stream<Set<String>> watchPendingItemIds() =>
      _pendingItemIds.watch().map((ids) => ids.toSet());

  Future<void> savePendingEdit(PendingEditsCompanion row) =>
      into(pendingEdits).insertOnConflictUpdate(row);

  Future<void> deletePendingEdit(EditTarget target, String itemId) =>
      (delete(pendingEdits)
            ..where((e) => e.target.equalsValue(target) & e.itemId.equals(itemId)))
          .go();

  /// Drops the changes waiting for the files and folders [ids], which are
  /// being deleted for good.
  Future<void> deletePendingEditsFor(Iterable<String> ids) => transaction(() async {
    for (final slice in _slices(ids.toList())) {
      await (delete(pendingEdits)..where(
            (e) =>
                e.itemId.isIn(slice) &
                e.target.isInValues([EditTarget.file, EditTarget.folder]),
          ))
          .go();
    }
  });

  /// Counts one more try at sending a waiting change that failed, and why,
  /// leaving its patch as it is, so an edit made meanwhile stays.
  Future<void> failPendingEdit(EditTarget target, String itemId, String error) =>
      customUpdate(
        'UPDATE pending_edits SET attempts = attempts + 1, last_error = ? '
        'WHERE target = ? AND item_id = ?',
        variables: [
          Variable.withString(error),
          Variable.withString(target.name),
          Variable.withString(itemId),
        ],
        updates: {pendingEdits},
      );

  /// Gives every waiting change that failed its tries back.
  Future<void> retryPendingEdits() => update(pendingEdits).write(
    const PendingEditsCompanion(attempts: Value(0), lastError: Value(null)),
  );

  // ---------------------------------------------------------------------------
  // Transfers
  // ---------------------------------------------------------------------------

  Future<List<TransferRow>> allTransfers() => (select(
    transfers,
  )..orderBy([(t) => OrderingTerm.asc(t.createdAt)])).get();

  /// The files that transfers not yet completed or cancelled still need:
  /// what each sends, its thumbnail and where a download lands. A failed
  /// one counts, since Retry starts it from the same files.
  Future<Set<String>> pathsInUse() async {
    final rows =
        await (select(transfers)..where(
              (t) => t.status.isNotInValues([
                TransferStatus.completed,
                TransferStatus.cancelled,
              ]),
            ))
            .get();
    return {
      for (final row in rows) ...[
        ?row.sourcePath,
        ?row.thumbnailPath,
        ?row.resultPath,
      ],
    };
  }

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
