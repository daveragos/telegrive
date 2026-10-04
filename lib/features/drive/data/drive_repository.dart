import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value, BooleanExpressionOperators;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:uuid/uuid.dart';

import '../../../core/async/combine.dart';
import '../../../core/files/file_kind.dart';
import '../../../infrastructure/database/app_database.dart';
import '../../../infrastructure/storage/device_storage.dart';
import '../../../infrastructure/telegram/telegram_client.dart';
import '../../../infrastructure/telegram/telegram_exception.dart';
import '../domain/drive_models.dart';
import '../domain/edit_patch.dart';
import '../domain/manifest.dart';
import 'channel_messenger.dart';
import 'drive_session.dart';
import 'edit_outbox.dart';
import 'message_indexer.dart';
import 'telegram_wait.dart';

/// A request the drive cannot carry out, phrased for a person.
class DriveException implements Exception {
  const DriveException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// What a change says while Home shows the drive from the index and
/// Telegram is still starting behind it.
const stillConnecting = 'Still connecting to Telegram. Try again in a moment.';

/// Why a change can't reach the drive's channel: Telegram is still starting
/// behind the drive saved as [snapshot], or no drive is open at all.
DriveException driveNotOpen(DriveSession? snapshot) => snapshot != null
    ? const DriveException(stillConnecting)
    : const DriveException('Your drive is not open.');

/// Reads the local index and changes the drive.
///
/// Every change goes to Telegram first and is written to the index from the
/// message Telegram hands back, so the index never claims something the
/// channel does not hold. The one exception is a rename, move, star, trash,
/// restore or album change made while Telegram can't be reached: it is made
/// in the index at once and waits in the outbox, and [replay] sends it once
/// the connection is back.
class DriveRepository {
  DriveRepository(this._ref);

  final Ref _ref;
  final _uuid = const Uuid();
  final _ingested = StreamController<String>.broadcast();

  AppDatabase get _db => _ref.read(appDatabaseProvider);
  ChannelMessenger get _messenger => _ref.read(channelMessengerProvider);
  TelegramClient get _client => _ref.read(telegramClientProvider);

  /// Ids of the items with a change waiting, read from the outbox the first
  /// time they are needed and kept in step with it from then on, so a sync
  /// that reads thousands of messages looks up only those few.
  Set<String>? _pendingIds;

  /// Items whose waiting change is being sent: what Telegram hands back for
  /// them is indexed as it is.
  final Set<String> _settling = {};

  int get _chatId {
    final session = _ref.read(driveSessionProvider);
    if (session == null) throw driveNotOpen(_ref.read(driveSnapshotProvider));
    return session.chatId;
  }

  String newId() => _uuid.v4();

  /// Ids of files that just gained a part — how the transfer queue notices
  /// an upload TDLib finished on its own after a restart.
  Stream<String> get ingestedFileIds => _ingested.stream;

  // ---------------------------------------------------------------------------
  // Index maintenance
  // ---------------------------------------------------------------------------

  /// Writes what [message] holds into the index. An item with a change
  /// waiting shows that change over what the message says, so a sync never
  /// makes a change made on this phone look undone.
  Future<void> ingest(td.Message message) async {
    switch (await _withWaitingChange(MessageIndexer.entryFor(message))) {
      case FilePartEntry(:final file, :final part, :final albums):
        await _db.upsertFilePart(file, part);
        await _db.setFileAlbums(part.fileId.value, albums);
        _ingested.add(part.fileId.value);
      case FolderEntry(:final folder):
        await _db.upsertFolder(folder);
      case AlbumEntry(:final album):
        await _db.upsertAlbum(album);
      case null:
        break;
    }
  }

  Future<void> forget(Iterable<int> messageIds) =>
      _db.removeMessages(messageIds);

  Future<Set<int>> knownMessageIds() => _db.knownMessageIds();

  // ---------------------------------------------------------------------------
  // Queries
  // ---------------------------------------------------------------------------

  Stream<FolderContents> watchFolder(String? folderId) => combineLatest2(
    _db.watchChildFolders(folderId),
    _db.watchFilesIn(folderId),
    (folders, files) => FolderContents(
      folders: folders.map(DriveFolder.fromRow).toList(),
      files: files.map(DriveFile.fromRow).toList(),
    ),
  );

  Stream<TrashContents> watchTrash() => combineLatest2(
    _db.watchTrashedFolders(),
    _db.watchTrashedFiles(),
    (folders, files) => TrashContents(
      folders: folders.map(DriveFolder.fromRow).toList(),
      files: files.map(DriveFile.fromRow).toList(),
    ),
  );

  Stream<List<DriveAlbum>> watchAlbums() => _db.watchAlbums().map(
    (rows) => [
      for (final row in rows)
        DriveAlbum(
          id: row.album.id,
          name: row.album.name,
          count: row.count,
          coverFileId: row.coverFileId,
        ),
    ],
  );

  /// An album's files, newest moment first, read and throttled as the
  /// timeline is.
  Stream<List<DriveFile>> watchAlbumFiles(String albumId) =>
      throttleLatest(_db.watchAlbumFilesLite(albumId).map(_liteFiles), _settle);

  Stream<DriveFolder?> watchFolderInfo(String id) =>
      _db.watchFolder(id).map((r) => r == null ? null : DriveFolder.fromRow(r));

  Stream<DriveFile?> watchFile(String id) =>
      _db.watchFile(id).map((r) => r == null ? null : DriveFile.fromRow(r));

  Stream<List<DriveFile>> watchRecent({
    int limit = 20,
    bool excludeCameraRoll = false,
  }) => _db
      .watchRecent(limit: limit, excludeCameraRoll: excludeCameraRoll)
      .map(_files);

  /// Remembers, on this phone only, that [fileId] was just opened, shared
  /// or sent.
  Future<void> recordOpen(String fileId) => _db.recordOpen(fileId);

  /// [recordOpen] for files sent together, in one write.
  Future<void> recordOpens(List<String> fileIds) => _db.recordOpens(fileIds);

  Stream<List<(DriveFile, DateTime)>> watchRecentOpens({int limit = 20}) => _db
      .watchRecentOpens(limit: limit)
      .map(
        (rows) => [for (final (row, at) in rows) (DriveFile.fromRow(row), at)],
      );

  /// What this phone opened lately merged with what was added lately,
  /// leaving out camera-roll backups, which Photos shows.
  Stream<List<RecentEntry>> watchRecentActivity({int limit = 12}) =>
      combineLatest2(
        watchRecentOpens(limit: limit),
        watchRecent(limit: limit, excludeCameraRoll: true),
        (opened, added) =>
            RecentEntry.merge(opened: opened, added: added, limit: limit),
      );

  Stream<List<DriveFile>> watchStarred() => _db.watchStarred().map(_files);

  /// Starred folders that aren't in the trash, in name order.
  Stream<List<DriveFolder>> watchStarredFolders() => _db
      .watchStarredFolders()
      .map((rows) => rows.map(DriveFolder.fromRow).toList());

  /// Each starred folder's id to how many files it holds, in it or below
  /// it, and their size.
  Stream<Map<String, FolderSize>> watchStarredFolderSizes() => _db
      .watchStarredFolderSizes()
      .map((sizes) => {for (final size in sizes) size.folderId!: size});

  /// Every photo and video, newest moment first, read without their
  /// inline previews, which tiles fetch for themselves. While backup adds
  /// photos one after another the list comes at most once every [_settle],
  /// the newest each time, rather than once per photo; the first comes at
  /// once.
  Stream<List<DriveFile>> watchMedia() =>
      throttleLatest(_db.watchMediaLite().map(_liteFiles), _settle);

  /// The least time between two lists of the timeline or an album.
  static const _settle = Duration(milliseconds: 750);

  Future<Map<String, String>> mediaFingerprints() => _db.mediaFingerprints();

  /// Files of one kind, newest first, read without their inline previews.
  Stream<List<DriveFile>> watchKind(FileKind kind) =>
      _db.watchKindLite(kind).map(_liteFiles);

  /// The most files one search returns; a list this long was cut off.
  static const int searchLimit = AppDatabase.searchLimit;

  Stream<List<DriveFile>> watchSearch(
    String query, {
    Set<FileKind>? kinds,
    (DateTime, DateTime)? range,
    Iterable<String>? folderIds,
    String? literal,
    bool byMoment = false,
  }) => _db
      .watchSearch(
        query,
        kinds: kinds,
        range: range,
        folderIds: folderIds,
        literal: literal,
        byMoment: byMoment,
      )
      .map(_files);

  Stream<List<DriveFolder>> watchFolderSearch(
    String query, {
    Iterable<String>? within,
  }) => _db
      .watchFolderSearch(query, within: within)
      .map((rows) => rows.map(DriveFolder.fromRow).toList());

  /// Every folder, trashed ones too.
  Stream<List<DriveFolder>> watchAllFolders() => _db.watchAllFolders().map(
    (rows) => rows.map(DriveFolder.fromRow).toList(),
  );

  /// [rootId] and every folder below it that isn't in the trash.
  Future<Set<String>> descendantFolderIds(String rootId) =>
      _db.descendantFolderIds(rootId);

  /// Every folder the drive shows: not in the trash, nor inside a folder
  /// that is.
  Future<List<DriveFolder>> visibleFolders() async => [
    for (final row in await _db.allFolders())
      if (!row.hidden) DriveFolder.fromRow(row),
  ];

  Stream<StorageSummary> watchSummary() =>
      _db.watchTotals().map((totals) => StorageSummary(totals: totals));

  /// The [limit] biggest files the drive shows, biggest first.
  Stream<List<DriveFile>> watchLargestFiles({int limit = 50}) =>
      _db.watchLargestFiles(limit: limit).map(_files);

  /// Each top-level folder's share of the drive, biggest first, then the
  /// files in no folder.
  Stream<List<FolderSize>> watchFolderSizes() => _db.watchFolderSizes();

  /// How many files the trash holds, those in trashed folders included,
  /// and their size.
  Stream<(int count, int bytes)> watchTrashTotals() => _db.watchTrashTotals();

  /// Root-first chain of folders leading to [folderId], for breadcrumbs.
  Future<List<DriveFolder>> pathTo(String? folderId) async {
    if (folderId == null) return const [];
    final byId = {for (final f in await _db.allFolders()) f.id: f};
    final path = <DriveFolder>[];
    String? cursor = folderId;
    final seen = <String>{};
    while (cursor != null && seen.add(cursor)) {
      final row = byId[cursor];
      if (row == null) break;
      path.insert(0, DriveFolder.fromRow(row));
      cursor = row.parentId;
    }
    return path;
  }

  /// [files], plus everything inside [folders], each with the folders
  /// between the selection and it — how a download to the phone keeps the
  /// drive's layout. With [everything], the whole drive from its root.
  Future<List<SaveItem>> collectForSaving({
    List<DriveFile> files = const [],
    List<DriveFolder> folders = const [],
    bool everything = false,
  }) async {
    final all = await _db.allFolders();
    final byId = {for (final f in all) f.id: f};
    final children = <String?, List<FolderRow>>{};
    for (final f in all) {
      (children[f.parentId] ??= []).add(f);
    }

    // Names from just below [top] down to [folderId]. A folder whose parent
    // is gone sits at the root, as the browser shows it.
    List<String> namesDown(String? folderId, {String? top}) {
      final names = <String>[];
      final seen = <String>{};
      for (var id = folderId; id != null && id != top && seen.add(id);) {
        final row = byId[id];
        if (row == null) break;
        names.insert(0, row.name);
        id = row.parentId;
      }
      return names;
    }

    if (everything) {
      return [
        for (final row in await _db.completeFiles())
          if (namesDown(row.folderId) case final path)
            (file: DriveFile.fromRow(row), folders: path, path: path),
      ];
    }

    final items = <String, SaveItem>{
      for (final file in files)
        file.id: (
          file: file,
          folders: const <String>[],
          path: namesDown(file.folderId),
        ),
    };
    for (final folder in folders) {
      final ids = <String>{};
      void collect(String id) {
        if (!ids.add(id)) return;
        for (final child in children[id] ?? const <FolderRow>[]) {
          collect(child.id);
        }
      }

      collect(folder.id);
      for (final row in await _db.completeFiles(ids)) {
        items.putIfAbsent(
          row.id,
          () => (
            file: DriveFile.fromRow(row),
            folders: namesDown(row.folderId, top: folder.parentId),
            path: namesDown(row.folderId),
          ),
        );
      }
    }
    return items.values.toList();
  }

  Future<DriveFile?> fileById(String id) async {
    final row = await _db.fileById(id);
    return row == null ? null : DriveFile.fromRow(row);
  }

  Future<DriveFolder?> folderById(String id) async {
    final row = await _db.folderById(id);
    return row == null ? null : DriveFolder.fromRow(row);
  }

  /// The folder [id] while the drive shows it: null once it is gone, or in
  /// the trash or inside a folder that is, so nothing is put where only
  /// Trash would show it.
  Future<DriveFolder?> shownFolder(String id) async {
    final row = await _db.folderById(id);
    return row == null || row.hidden ? null : DriveFolder.fromRow(row);
  }

  Future<List<PartRow>> partsOf(String fileId) => _db.partsOf(fileId);

  Future<void> rememberTdFileId(String fileId, int partIndex, int tdFileId) =>
      (_db.update(_db.fileParts)..where(
            (p) => p.fileId.equals(fileId) & p.partIndex.equals(partIndex),
          ))
          .write(FilePartsCompanion(tdFileId: Value(tdFileId)));

  /// TDLib's file for [part]. The stored id is tried first; if TDLib no
  /// longer knows it (its database was reset), it is looked up again from
  /// the message and remembered. Downloads, previews, streaming and reading
  /// documents for search all come through here, so each waits a minute at
  /// most for Telegram to finish starting, as it may not have when Home
  /// opens.
  Future<td.File> resolveTdFile(PartRow part) async {
    final client = _ref.read(telegramClientProvider);
    await client.ready.timeout(const Duration(minutes: 1));
    try {
      return await client.send<td.File>(td.GetFile(fileId: part.tdFileId));
    } on TelegramException {
      final message = await client.send<td.Message>(
        td.GetMessage(chatId: _chatId, messageId: part.messageId),
      );
      final file = MessageIndexer.mediaFile(message);
      if (file == null) {
        throw const DriveException('This file is no longer in your drive.');
      }
      await rememberTdFileId(part.fileId, part.partIndex, file.id);
      return file;
    }
  }

  static List<DriveFile> _files(List<FileRow> rows) =>
      rows.map(DriveFile.fromRow).toList();

  static List<DriveFile> _liteFiles(List<LiteFileRow> rows) => [
    for (final lite in rows)
      DriveFile.fromRow(lite.row, hasMinithumbnail: lite.hasMinithumbnail),
  ];

  // ---------------------------------------------------------------------------
  // Folders
  // ---------------------------------------------------------------------------

  Future<void> createFolder(String name, {String? parentId}) async {
    final clean = await _validFolderName(name, parentId);
    final now = DateTime.now();
    final manifest = FolderManifest(
      id: newId(),
      name: clean,
      parentId: parentId,
      createdAt: now,
      modifiedAt: now,
    );
    final message = await _messenger.sendText(
      _chatId,
      ManifestCodec.encodeFolder(manifest),
    );
    await ingest(message);
  }

  Future<void> renameFolder(DriveFolder folder, String name) async {
    if (name.trim() == folder.name) return;
    final clean = await _validFolderName(name, folder.parentId);
    await _rewriteFolder(folder, name: clean, parentId: folder.parentId);
  }

  Future<void> moveFolder(DriveFolder folder, String? parentId) async {
    if (parentId == folder.parentId) return;
    if (await _isInside(parentId, folder.id)) {
      throw const DriveException('A folder can\'t be moved inside itself.');
    }
    await _rewriteFolder(folder, name: folder.name, parentId: parentId);
  }

  /// Stars or unstars [folders], one message edit each. A folder already
  /// the way it is asked for is passed over.
  Future<void> setFolderStarred(
    List<DriveFolder> folders, {
    required bool starred,
  }) async {
    for (final folder in folders) {
      if (folder.starred == starred) continue;
      await _rewriteFolder(
        folder,
        name: folder.name,
        parentId: folder.parentId,
        starred: starred,
      );
    }
  }

  /// Rewrites a folder's message from what the index holds, so a rename or
  /// move keeps the star and the keys only a newer version knows. While
  /// Telegram can't be reached, or the folder already has a change waiting,
  /// the change is made on the phone and waits instead, as does one whose
  /// request timed out.
  Future<void> _rewriteFolder(
    DriveFolder folder, {
    required String name,
    required String? parentId,
    DateTime? trashedAt,
    bool restore = false,
    bool? starred,
  }) async {
    final row = await _db.folderById(folder.id);
    if (row == null) return;
    final current = _folderManifest(row);
    final next = FolderManifest(
      id: folder.id,
      name: name,
      parentId: parentId,
      createdAt: folder.createdAt,
      modifiedAt: DateTime.now(),
      trashedAt: restore ? null : (trashedAt ?? row.trashedAt),
      starred: starred ?? row.starred,
      extra: current.extra,
    );
    final patch = EditPatch.folderDiff(current, next);
    if (patch.isEmpty) return;
    if (await _mustQueue(EditTarget.folder, row.id)) {
      return _queueFolder(row, next, patch);
    }
    try {
      await _writeFolderManifest(row.messageId, next);
    } on TelegramException catch (e) {
      if (!e.isNetworkProblem) rethrow;
      await _queueFolder(row, next, patch);
    }
  }

  /// What the index holds of a folder, as its manifest.
  static FolderManifest _folderManifest(FolderRow row) => FolderManifest(
    id: row.id,
    name: row.name,
    parentId: row.parentId,
    createdAt: row.createdAt,
    modifiedAt: row.modifiedAt,
    trashedAt: row.trashedAt,
    starred: row.starred,
    extra: ManifestCodec.decodeExtra(row.manifestExtra),
  );

  /// Writes [manifest] into the folder's message [messageId] and indexes
  /// what Telegram hands back. Flood waits are sat out when [patient].
  Future<void> _writeFolderManifest(
    int messageId,
    FolderManifest manifest, {
    bool patient = true,
  }) async {
    Future<td.Message> edit() => _messenger.editText(
      _chatId,
      messageId,
      ManifestCodec.encodeFolder(manifest),
    );
    final message = await _ignoreUnchanged(
      () => patient ? _patiently(edit) : edit(),
    );
    if (message != null) await ingest(message);
  }

  /// Id of the folder at [names] (e.g. `['Photo backup', 'Camera']`),
  /// creating whatever part of the path doesn't exist yet. Matching is
  /// case-insensitive, so it reuses folders people made by hand.
  Future<String> ensureFolderPath(List<String> names) async {
    String? parentId;
    for (final name in names) {
      final siblings = await _db.watchChildFolders(parentId).first;
      final existing = siblings.where(
        (f) => f.name.toLowerCase() == name.toLowerCase(),
      );
      if (existing.isNotEmpty) {
        parentId = existing.first.id;
        continue;
      }
      final now = DateTime.now();
      final manifest = FolderManifest(
        id: newId(),
        name: name,
        parentId: parentId,
        createdAt: now,
        modifiedAt: now,
      );
      final message = await _messenger.sendText(
        _chatId,
        ManifestCodec.encodeFolder(manifest),
      );
      await ingest(message);
      parentId = manifest.id;
    }
    return parentId!;
  }

  Future<String> _validFolderName(String name, String? parentId) async {
    final clean = name.trim();
    if (clean.isEmpty) throw const DriveException('Give the folder a name.');
    if (clean.length > 128) {
      throw const DriveException('That name is too long.');
    }
    final siblings = await _db.watchChildFolders(parentId).first;
    final taken = siblings.any(
      (f) => f.name.toLowerCase() == clean.toLowerCase(),
    );
    if (taken) throw DriveException('"$clean" already exists here.');
    return clean;
  }

  /// Whether [candidate] is [ancestorId] or somewhere beneath it.
  Future<bool> _isInside(String? candidate, String ancestorId) async {
    final byId = {for (final f in await _db.allFolders()) f.id: f};
    String? cursor = candidate;
    final seen = <String>{};
    while (cursor != null && seen.add(cursor)) {
      if (cursor == ancestorId) return true;
      cursor = byId[cursor]?.parentId;
    }
    return false;
  }

  // ---------------------------------------------------------------------------
  // Files
  // ---------------------------------------------------------------------------

  /// [name] when no name in [takenLower], which holds lower-cased names,
  /// matches it regardless of case; otherwise the first of `name (2)`,
  /// `name (3)` and so on that is free.
  String freeName(String name, Set<String> takenLower) {
    if (!takenLower.contains(name.toLowerCase())) return name;
    for (var n = 2; ; n++) {
      final candidate = DeviceStorage.numbered(name, n);
      if (!takenLower.contains(candidate.toLowerCase())) return candidate;
    }
  }

  /// The shown files in [folderId] (the root when null) whose name is one
  /// of [names] regardless of case, by their lower-cased name.
  Future<Map<String, DriveFile>> nameClashes(
    Iterable<String> names,
    String? folderId,
  ) async {
    final wanted = {for (final name in names) name.toLowerCase()};
    if (wanted.isEmpty) return const {};
    final rows = await _db.filesIn(folderId);
    return {
      for (final row in rows)
        if (wanted.contains(row.name.toLowerCase()))
          row.name.toLowerCase(): DriveFile.fromRow(row),
    };
  }

  /// The names of the shown files in [folderId], lower-cased, so a name can
  /// be checked against them regardless of case.
  Future<Set<String>> takenNamesIn(String? folderId) async => {
    for (final row in await _db.filesIn(folderId)) row.name.toLowerCase(),
  };

  /// Renames [file] to [name]. A name a sibling already has, in any case,
  /// is refused, so two files in one folder never read the same. The
  /// siblings of a file whose folder is gone are the root's files, where
  /// it shows.
  Future<void> renameFile(DriveFile file, String name) async {
    final clean = name.trim();
    if (clean.isEmpty) throw const DriveException('Give the file a name.');
    if (clean == file.name) return;
    final folderId = file.folderId;
    final shownIn = folderId != null && await _db.folderById(folderId) != null
        ? folderId
        : null;
    final sibling = (await nameClashes([clean], shownIn))[clean.toLowerCase()];
    if (sibling != null && sibling.id != file.id) {
      throw DriveException('"$clean" already exists here.');
    }
    await _rewriteFile(file, (m) => m.copyWith(name: clean));
  }

  /// Moves [files] into [folderId], the root when null. A file named in
  /// [renames] takes that name as it goes, which is how Keep both settles
  /// a clash with a file already there; one already in the folder and
  /// keeping its name is passed over.
  Future<void> moveFiles(
    List<DriveFile> files,
    String? folderId, {
    Map<String, String> renames = const {},
  }) async {
    for (final file in files) {
      final newName = renames[file.id];
      if (file.folderId == folderId && newName == null) continue;
      await _rewriteFile(
        file,
        (m) =>
            (folderId == null
                    ? m.copyWith(clearFolder: true)
                    : m.copyWith(folderId: folderId))
                .copyWith(name: newName),
      );
    }
  }

  /// Gives [files] that came in without a manifest one at the root, so they
  /// leave Forwarded and are the drive's own: an edit for media the account
  /// sent itself, and an own copy for a forward.
  Future<void> keepAtRoot(List<DriveFile> files) async {
    for (final file in files) {
      await _rewriteFile(file, (m) => m);
    }
  }

  /// Deletes the text message [messageId], a forward's comment once every
  /// file it named a folder for has gone there, sitting out flood waits.
  Future<void> deleteComment(int messageId) =>
      _patiently(() => _messenger.deleteMessages(_chatId, [messageId]));

  /// Moves the file [oldFileId] to the trash, marked as replaced by
  /// [newFileId], once that file has landed in its place. A file already
  /// gone or in the trash is left as it is.
  Future<void> replaceWith({
    required String oldFileId,
    required String newFileId,
  }) async {
    final old = await fileById(oldFileId);
    if (old == null || old.trashedAt != null) return;
    await _rewriteFile(
      old,
      (m) => m.copyWith(trashedAt: DateTime.now(), replacedBy: newFileId),
    );
  }

  /// The file [fileId] replaced, while it is still in the trash; the one
  /// trashed last when there are several.
  Future<DriveFile?> previousVersionOf(String fileId) async {
    final row = (await _db.trashedReplacementsOf(fileId)).firstOrNull;
    return row == null ? null : DriveFile.fromRow(row);
  }

  Future<void> setStarred(
    List<DriveFile> files, {
    required bool starred,
  }) async {
    for (final file in files) {
      if (file.starred == starred) continue;
      await _rewriteFile(file, (m) => m.copyWith(starred: starred));
    }
  }

  /// Rewrites the manifest on every part of [file], starting from what the
  /// index holds so nothing the caller doesn't touch is lost, including
  /// keys only a newer version knows. While Telegram can't be reached, or
  /// the file already has a change waiting, the change is made on the phone
  /// and waits instead, as does one whose request timed out. A file that
  /// came in without a manifest is written even when nothing else about it
  /// changes, since giving it one is the change.
  Future<void> _rewriteFile(
    DriveFile file,
    FileManifest Function(FileManifest current) change,
  ) async {
    final row = await _db.fileById(file.id);
    if (row == null) return;
    final current = await _fileManifest(row);
    final next = change(current);
    final patch = EditPatch.fileDiff(current, next);
    if (patch.isEmpty && !row.adopted) return;
    if (!patch.isEmpty && await _mustQueue(EditTarget.file, row.id)) {
      return _queueFile(row, next, patch);
    }
    try {
      await _writeFileManifest(
        await _db.partsOf(row.id),
        next.copyWith(modifiedAt: DateTime.now()),
      );
    } on TelegramException catch (e) {
      if (!e.isNetworkProblem || patch.isEmpty) rethrow;
      await _queueFile(row, next, patch);
    }
  }

  /// What the index holds of a file, as its manifest.
  Future<FileManifest> _fileManifest(FileRow row) async => FileManifest(
    id: row.id,
    name: row.name,
    folderId: row.folderId,
    mimeType: row.mimeType,
    size: row.size,
    createdAt: row.createdAt,
    modifiedAt: row.modifiedAt,
    partCount: row.partCount,
    starred: row.starred,
    takenAt: row.takenAt,
    trashedAt: row.trashedAt,
    albums: await _db.albumIdsOf(row.id),
    durationSeconds: row.durationSeconds,
    replacedBy: row.replacedBy,
    extra: ManifestCodec.decodeExtra(row.manifestExtra),
  );

  /// Writes [manifest] onto each of [parts], with that part's index, and
  /// indexes what Telegram hands back. Flood waits are sat out when
  /// [patient]; a waiting change being sent lets them through, for the
  /// outbox to pause on.
  Future<void> _writeFileManifest(
    List<PartRow> parts,
    FileManifest manifest, {
    bool patient = true,
  }) async {
    // Once one part carries the change, Stop no longer cuts a wait short,
    // so a split file never ends up with parts that disagree.
    var stoppable = true;
    for (final part in parts) {
      final caption = ManifestCodec.encodeFile(
        manifest.copyWith(partIndex: part.partIndex),
      );
      Future<td.Message> edit() =>
          _messenger.editCaption(_chatId, part.messageId, caption);
      td.Message? message;
      try {
        message = await _ignoreUnchanged(
          () => patient ? _patiently(edit, stoppable: stoppable) : edit(),
        );
      } on TelegramException catch (e) {
        if (!e.isNotEditable) rethrow;
        message = await _replaceWithOwnCopy(
          part.messageId,
          caption,
          stoppable: stoppable,
          patient: patient,
        );
      }
      if (message != null) await ingest(message);
      stoppable = false;
    }
  }

  /// Telegram won't edit a message forwarded into the channel, so a file
  /// that arrived that way can't be renamed, moved, starred or trashed as
  /// it is. This swaps it for the drive's own copy of the same message,
  /// made by Telegram with no upload, which can be: the copy arrives with
  /// [caption] already on it, so it is never a caption-less forward the
  /// drive could take for a new one, and the original goes. The file keeps
  /// its id throughout. Flood waits are sat out when [patient].
  Future<td.Message> _replaceWithOwnCopy(
    int messageId,
    EncodedText caption, {
    bool stoppable = true,
    bool patient = true,
  }) async {
    Future<td.Message> copyOnce() async {
      try {
        return await _messenger.sendCopy(
          _chatId,
          fromChatId: _chatId,
          messageId: messageId,
          caption: caption,
        );
      } on SendFailed catch (e) {
        // TDLib keeps the copy that failed, under a new id. It never reached
        // the channel, so deleting it only drops that local copy, and the
        // next try doesn't leave a second one.
        try {
          await _messenger.deleteMessages(_chatId, [e.failedMessageId]);
        } catch (error) {
          debugPrint('[Drive] Could not drop a failed copy: $error');
        }
        rethrow;
      }
    }

    // Telegram usually turns a copy away only once it is being sent, so the
    // wait covers the delivery as well as the request.
    final copy = patient
        ? await _patiently(copyOnce, stoppable: stoppable)
        : await copyOnce();
    await ingest(copy);
    await _messenger.deleteMessages(_chatId, [messageId]);
    await _db.removeMessages([messageId]);
    return copy;
  }

  // ---------------------------------------------------------------------------
  // Trash
  // ---------------------------------------------------------------------------

  /// How long things stay in the trash before they go for good.
  static const Duration trashKeepsFor = Duration(days: 30);

  /// Moves [files] and [folders] to the trash. A folder goes with everything
  /// inside it, in one edit; the drive can still be rebuilt from Telegram.
  Future<void> trash({
    List<DriveFile> files = const [],
    List<DriveFolder> folders = const [],
  }) async {
    final now = DateTime.now();
    for (final folder in folders) {
      await _rewriteFolder(
        folder,
        name: folder.name,
        parentId: folder.parentId,
        trashedAt: now,
      );
    }
    for (final file in files) {
      await _rewriteFile(file, (m) => m.copyWith(trashedAt: now));
    }
  }

  Future<void> restore({
    List<DriveFile> files = const [],
    List<DriveFolder> folders = const [],
  }) async {
    for (final folder in folders) {
      await _rewriteFolder(
        folder,
        name: folder.name,
        parentId: folder.parentId,
        restore: true,
      );
    }
    for (final file in files) {
      await _rewriteFile(file, (m) => m.copyWith(restore: true));
    }
  }

  /// Deletes everything in the trash for good. Returns how many files went.
  Future<int> emptyTrash({DateTime? trashedBefore}) async {
    final contents = await watchTrash().first;
    bool due(DateTime? at) =>
        trashedBefore == null || (at != null && at.isBefore(trashedBefore));
    return delete(
      files: contents.files.where((f) => due(f.trashedAt)).toList(),
      folders: contents.folders.where((f) => due(f.trashedAt)).toList(),
    );
  }

  /// Clears out what has been in the trash longer than [trashKeepsFor].
  Future<void> purgeTrash() =>
      emptyTrash(trashedBefore: DateTime.now().subtract(trashKeepsFor));

  // ---------------------------------------------------------------------------
  // Duplicate backups
  // ---------------------------------------------------------------------------

  /// Photos under the [rootName] folders with the same name and size as
  /// another, and any second [rootName] folder made beside the first.
  Future<DuplicateBackups> findDuplicateBackups(String rootName) async {
    final all = [
      for (final f in await _db.allFolders())
        if (!f.hidden) f,
    ];
    final roots =
        all
            .where(
              (f) =>
                  f.parentId == null &&
                  f.name.toLowerCase() == rootName.toLowerCase(),
            )
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    if (roots.isEmpty) return DuplicateBackups.none;

    final children = <String, List<FolderRow>>{};
    for (final f in all) {
      if (f.parentId != null) (children[f.parentId!] ??= []).add(f);
    }
    final ids = <String>{};
    void collect(String id) {
      if (!ids.add(id)) return;
      for (final child in children[id] ?? const <FolderRow>[]) {
        collect(child.id);
      }
    }

    for (final root in roots) {
      collect(root.id);
    }

    final byFingerprint = <String, List<FileRow>>{};
    for (final row in await _db.completeFiles(ids)) {
      (byFingerprint['${row.name}|${row.size}'] ??= []).add(row);
    }
    final extras = <DriveFile>[];
    final keptFor = <String, String>{};
    for (final copies in byFingerprint.values.where((c) => c.length > 1)) {
      // The first upload stays; it is the one other phones know.
      copies.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      for (final extra in copies.skip(1)) {
        extras.add(DriveFile.fromRow(extra));
        keptFor[extra.id] = copies.first.id;
      }
    }
    return DuplicateBackups(
      extras: extras,
      keptFor: keptFor,
      primary: DriveFolder.fromRow(roots.first),
      extraRoots: roots.skip(1).map(DriveFolder.fromRow).toList(),
    );
  }

  /// Moves the extra copies to the trash, points backup at the copies kept,
  /// and folds any second backup folder into the first.
  Future<void> removeDuplicateBackups(
    DuplicateBackups found, {
    void Function(int done, int total)? onProgress,
  }) async {
    final now = DateTime.now();
    final total = found.extras.length;
    for (final (index, file) in found.extras.indexed) {
      await _rewriteFile(file, (m) => m.copyWith(trashedAt: now));
      onProgress?.call(index + 1, total);
    }
    await _db.repointBackupAssets(found.keptFor);

    final primary = found.primary;
    if (primary == null) return;
    for (final root in found.extraRoots) {
      // Whatever is left in a second folder (new photos, not copies) moves
      // into the same-named folder in the first, then the empty one goes to
      // the trash.
      for (final sub in await _db.watchChildFolders(root.id).first) {
        final target = await _childFolder(primary.id, sub.name);
        await moveFiles(
          (await _db.watchFilesIn(sub.id).first)
              .map(DriveFile.fromRow)
              .toList(),
          target,
        );
      }
      await moveFiles(
        (await _db.watchFilesIn(root.id).first).map(DriveFile.fromRow).toList(),
        primary.id,
      );
      await trash(folders: [root]);
    }
  }

  /// The folder called [name] in [parentId], made if it isn't there.
  Future<String> _childFolder(String parentId, String name) async {
    final existing = (await _db.watchChildFolders(parentId).first).where(
      (f) => f.name.toLowerCase() == name.toLowerCase(),
    );
    if (existing.isNotEmpty) return existing.first.id;
    final now = DateTime.now();
    final manifest = FolderManifest(
      id: newId(),
      name: name,
      parentId: parentId,
      createdAt: now,
      modifiedAt: now,
    );
    await ingest(
      await _messenger.sendText(_chatId, ManifestCodec.encodeFolder(manifest)),
    );
    return manifest.id;
  }

  // ---------------------------------------------------------------------------
  // Albums
  // ---------------------------------------------------------------------------

  /// Short ids: every album a photo is in is spelled out in its caption.
  String _albumId() => newId().replaceAll('-', '').substring(0, 12);

  Future<String> createAlbum(String name) async {
    final clean = name.trim();
    if (clean.isEmpty) throw const DriveException('Give the album a name.');
    final now = DateTime.now();
    final manifest = AlbumManifest(
      id: _albumId(),
      name: clean,
      createdAt: now,
      modifiedAt: now,
    );
    final message = await _messenger.sendText(
      _chatId,
      ManifestCodec.encodeAlbum(manifest),
    );
    await ingest(message);
    return manifest.id;
  }

  /// Renames the album, on the phone at once and in Telegram later when it
  /// can't be reached now, as a file's rename is.
  Future<void> renameAlbum(String albumId, String name) async {
    final clean = name.trim();
    if (clean.isEmpty) throw const DriveException('Give the album a name.');
    final row = await _db.albumById(albumId);
    if (row == null || row.name == clean) return;
    final patch = EditPatch.albumRename(row.name, clean);
    if (await _mustQueue(EditTarget.album, albumId)) {
      return _queueAlbum(row, clean, patch);
    }
    try {
      await _writeAlbumManifest(
        row.messageId,
        AlbumManifest(
          id: row.id,
          name: clean,
          createdAt: row.createdAt,
          modifiedAt: DateTime.now(),
        ),
      );
    } on TelegramException catch (e) {
      if (!e.isNetworkProblem) rethrow;
      await _queueAlbum(row, clean, patch);
    }
  }

  /// Writes [manifest] into the album's message [messageId] and indexes
  /// what Telegram hands back. Flood waits are sat out when [patient].
  Future<void> _writeAlbumManifest(
    int messageId,
    AlbumManifest manifest, {
    bool patient = true,
  }) async {
    Future<td.Message> edit() => _messenger.editText(
      _chatId,
      messageId,
      ManifestCodec.encodeAlbum(manifest),
    );
    final message = await _ignoreUnchanged(
      () => patient ? _patiently(edit) : edit(),
    );
    if (message != null) await ingest(message);
  }

  /// Deletes the album; its photos stay in the drive. Deleting is not a
  /// change that can wait on the phone, so it is refused up front while
  /// Telegram can't be reached, rather than taking the photos out of the
  /// album and then failing to delete it.
  Future<void> deleteAlbum(String albumId) async {
    if (_ref.read(driveSessionProvider) == null) {
      throw driveNotOpen(_ref.read(driveSnapshotProvider));
    }
    if (!_client.isOnline) {
      throw const DriveException(
        'No connection to Telegram. Try again when you\'re back online.',
      );
    }
    final row = await _db.albumById(albumId);
    if (row == null) return;
    final members = await _db.watchAlbumFiles(albumId).first;
    await removeFromAlbum(members.map(DriveFile.fromRow).toList(), albumId);
    await _messenger.deleteMessages(_chatId, [row.messageId]);
    await _db.removeMessages([row.messageId]);
    await _dropPending(EditTarget.album, albumId);
  }

  /// Adds [files] to the album and lifts it to the top of the list. A bulk
  /// add that goes one file at a time passes [touch] as false and calls
  /// [touchAlbum] once at the end, so the album's own message is edited
  /// once rather than once per file.
  Future<void> addToAlbum(
    List<DriveFile> files,
    String albumId, {
    bool touch = true,
  }) async {
    for (final file in files) {
      final current = await _db.albumIdsOf(file.id);
      if (current.contains(albumId)) continue;
      await _rewriteFile(
        file,
        (m) => m.copyWith(albums: [...current, albumId]),
      );
    }
    if (touch) await touchAlbum(albumId);
  }

  Future<void> removeFromAlbum(List<DriveFile> files, String albumId) async {
    for (final file in files) {
      final current = await _db.albumIdsOf(file.id);
      if (!current.contains(albumId)) continue;
      await _rewriteFile(
        file,
        (m) =>
            m.copyWith(albums: current.where((id) => id != albumId).toList()),
      );
    }
  }

  /// Albums sort by when they last changed, so adding photos lifts one to
  /// the top. While Telegram can't be reached, or a rename of the album
  /// waits, the album stays where it is: lifting it is not worth a change
  /// of its own to wait, and would send the waiting name past the outbox.
  Future<void> touchAlbum(String albumId) async {
    final row = await _db.albumById(albumId);
    if (row == null || await _mustQueue(EditTarget.album, albumId)) return;
    await _writeAlbumManifest(
      row.messageId,
      AlbumManifest(
        id: row.id,
        name: row.name,
        createdAt: row.createdAt,
        modifiedAt: DateTime.now(),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Deleting
  // ---------------------------------------------------------------------------

  /// Deletes [files] and [folders] (with everything inside them) from
  /// Telegram and the index for good. Returns how many files went.
  Future<int> delete({
    List<DriveFile> files = const [],
    List<DriveFolder> folders = const [],
  }) async {
    final allFolders = await _db.allFolders();
    final folderIds = <String>{};
    void collect(String id) {
      if (!folderIds.add(id)) return;
      for (final child in allFolders.where((f) => f.parentId == id)) {
        collect(child.id);
      }
    }

    for (final folder in folders) {
      collect(folder.id);
    }

    final fileIds = {
      ...files.map((f) => f.id),
      ...(await _db.filesInFolders(folderIds)).map((f) => f.id),
    };

    final messageIds = <int>[
      for (final id in fileIds)
        ...(await _db.partsOf(id)).map((p) => p.messageId),
      ...allFolders
          .where((f) => folderIds.contains(f.id))
          .map((f) => f.messageId),
    ];
    if (messageIds.isEmpty) return 0;

    // A photo deleted for good here was meant to go, so backup never
    // offers to send it up again; the record is kept before the file is,
    // so a delete cut short still remembers the choice.
    await _db.markFilesRemoved(fileIds);
    await _messenger.deleteMessages(_chatId, messageIds);
    await _db.removeMessages(messageIds);
    await _forgetWaitingChanges([...fileIds, ...folderIds]);
    return fileIds.length;
  }

  Future<void> deleteFileById(String fileId) async {
    final ids = (await _db.partsOf(fileId)).map((p) => p.messageId).toList();
    if (ids.isEmpty) return;
    await _messenger.deleteMessages(_chatId, ids);
    await _db.removeMessages(ids);
    await _forgetWaitingChanges([fileId]);
  }

  /// Drops the changes waiting for files and folders that are gone for
  /// good, which have nothing left to change.
  Future<void> _forgetWaitingChanges(List<String> ids) async {
    await _db.deletePendingEditsFor(ids);
    _pendingIds?.removeAll(ids);
  }

  // ---------------------------------------------------------------------------
  // Waiting changes
  // ---------------------------------------------------------------------------

  /// Whether a change to [id] waits on the phone instead of going to
  /// Telegram now: Telegram can't be reached, or is still starting behind
  /// the drive Home shows, or the item already has a change waiting, which
  /// a newer one joins so the two reach Telegram in the order they were
  /// made. With no drive open or saved, there is nothing to change.
  Future<bool> _mustQueue(EditTarget target, String id) async {
    if (_ref.read(driveSessionProvider) == null) {
      final snapshot = _ref.read(driveSnapshotProvider);
      if (snapshot == null) throw driveNotOpen(null);
      return true;
    }
    if (!_client.isOnline) return true;
    return (await _pending()).contains(id) &&
        await _db.pendingEditOf(target, id) != null;
  }

  /// Whether a change sent now reaches Telegram.
  bool get _reachable =>
      _ref.read(driveSessionProvider) != null && _client.isOnline;

  Future<Set<String>> _pending() async =>
      _pendingIds ??= await _db.pendingEditIds();

  Future<void> _queueFile(
    FileRow row,
    FileManifest next,
    EditPatch patch,
  ) async {
    await _applyFileLocally(row, next);
    await _enqueue(EditTarget.file, row.id, patch);
  }

  Future<void> _queueFolder(
    FolderRow row,
    FolderManifest next,
    EditPatch patch,
  ) async {
    await _applyFolderLocally(row, next);
    await _enqueue(EditTarget.folder, row.id, patch);
  }

  Future<void> _queueAlbum(AlbumRow row, String name, EditPatch patch) async {
    await _applyAlbumLocally(row, name);
    await _enqueue(EditTarget.album, row.id, patch);
  }

  /// Shows [next] in the index as if Telegram had taken it.
  Future<void> _applyFileLocally(FileRow row, FileManifest next) async {
    await _db.updateFile(
      row.id,
      DriveFilesCompanion(
        name: Value(next.name),
        kind: Value(
          FileKind.detect(fileName: next.name, mimeType: row.mimeType),
        ),
        folderId: Value(next.folderId),
        starred: Value(next.starred),
        trashedAt: Value(next.trashedAt),
        modifiedAt: Value(DateTime.now()),
      ),
    );
    await _db.setFileAlbums(row.id, next.albums);
    await _db.refreshHiddenFile(row.id);
  }

  /// Shows [next] in the index as if Telegram had taken it, with whatever
  /// it moved into or out of the trash along with it.
  Future<void> _applyFolderLocally(FolderRow row, FolderManifest next) async {
    await _db.updateFolder(
      row.id,
      FoldersCompanion(
        name: Value(next.name),
        parentId: Value(next.parentId),
        trashedAt: Value(next.trashedAt),
        starred: Value(next.starred),
        modifiedAt: Value(DateTime.now()),
      ),
    );
    await _db.refreshHidden();
  }

  Future<void> _applyAlbumLocally(AlbumRow row, String name) => _db.upsertAlbum(
    row
        .toCompanion(false)
        .copyWith(name: Value(name), modifiedAt: Value(DateTime.now())),
  );

  /// Adds [patch] to what waits for [id], after any change already waiting
  /// for it. A change that ends where Telegram has it leaves nothing to
  /// send, which is how Undo of a change made offline costs nothing. A new
  /// change gets fresh tries, even on one that had failed.
  Future<void> _enqueue(EditTarget target, String id, EditPatch patch) async {
    await _db.transaction(() async {
      final old = await _db.pendingEditOf(target, id);
      final merged = old == null ? patch : _decode(old.patch).then(patch);
      if (merged.isEmpty) {
        await _dropPending(target, id);
        return;
      }
      final now = DateTime.now();
      await _db.savePendingEdit(
        PendingEditsCompanion.insert(
          target: target,
          itemId: id,
          patch: jsonEncode(merged.toJson()),
          createdAt: old?.createdAt ?? now,
          updatedAt: now,
          attempts: const Value(0),
          lastError: const Value(null),
        ),
      );
      (await _pending()).add(id);
    });
    _ref.read(editOutboxProvider.notifier).soon();
  }

  Future<void> _dropPending(EditTarget target, String id) async {
    await _db.deletePendingEdit(target, id);
    _pendingIds?.remove(id);
  }

  static EditPatch _decode(String patch) {
    try {
      final json = jsonDecode(patch);
      return json is Map<String, Object?>
          ? EditPatch.fromJson(json)
          : const EditPatch({});
    } catch (_) {
      return const EditPatch({});
    }
  }

  /// [entry] with the change waiting for its item, if there is one, over
  /// what its message says. Albums merge the way they merge on Telegram.
  Future<IndexEntry?> _withWaitingChange(IndexEntry? entry) async {
    final (target, id) = switch (entry) {
      FilePartEntry(:final part) => (EditTarget.file, part.fileId.value),
      FolderEntry(:final folder) => (EditTarget.folder, folder.id.value),
      AlbumEntry(:final album) => (EditTarget.album, album.id.value),
      null => (null, ''),
    };
    if (target == null ||
        _settling.contains(id) ||
        !(await _pending()).contains(id)) {
      return entry;
    }
    final row = await _db.pendingEditOf(target, id);
    if (row == null) return entry;
    final patch = _decode(row.patch);
    switch (entry) {
      case FilePartEntry(:final file, :final part, :final albums):
        final shown = patch.over({
          'n': file.name.value,
          'f': file.folderId.value,
          'st': file.starred.value,
          'tr': EditPatch.trashedValue(file.trashedAt.value),
          'al': albums,
        });
        final name = shown['n']! as String;
        return FilePartEntry(
          file.copyWith(
            name: Value(name),
            kind: Value(
              FileKind.detect(fileName: name, mimeType: file.mimeType.value),
            ),
            folderId: Value(shown['f'] as String?),
            starred: Value(shown['st']! as bool),
            trashedAt: Value(_time(shown['tr'])),
          ),
          part,
          albums: (shown['al']! as List).cast<String>(),
        );
      case FolderEntry(:final folder):
        final shown = patch.over({
          'n': folder.name.value,
          'p': folder.parentId.value,
          'st': folder.starred.value,
          'tr': EditPatch.trashedValue(folder.trashedAt.value),
        });
        return FolderEntry(
          folder.copyWith(
            name: Value(shown['n']! as String),
            parentId: Value(shown['p'] as String?),
            starred: Value(shown['st']! as bool),
            trashedAt: Value(_time(shown['tr'])),
          ),
        );
      case AlbumEntry(:final album):
        final shown = patch.over({'n': album.name.value});
        return AlbumEntry(album.copyWith(name: Value(shown['n']! as String)));
      case null:
        return null;
    }
  }

  static DateTime? _time(Object? millis) =>
      millis is int ? DateTime.fromMillisecondsSinceEpoch(millis) : null;

  /// The message that holds what [id] is: a file's first part, or the
  /// folder's or album's own.
  Future<int?> _messageIdOf(EditTarget target, String id) async =>
      switch (target) {
        EditTarget.file => (await _db.partsOf(
          id,
        )).where((p) => p.partIndex == 0).firstOrNull?.messageId,
        EditTarget.folder => (await _db.folderById(id))?.messageId,
        EditTarget.album => (await _db.albumById(id))?.messageId,
      };

  /// Telegram has no such message, which went for good from another
  /// device.
  static bool _isGone(TelegramException e) =>
      e.code == 404 ||
      e.message.contains('MESSAGE_ID_INVALID') ||
      e.message.toLowerCase().contains('message not found');

  /// Sends the waiting change [row] to Telegram, onto what the channel
  /// holds now, read again first: a field another device changed meanwhile
  /// keeps that device's version, and the rest still goes. A split file has
  /// the result written to every part, so parts a rewrite cut short agree
  /// again. Returns what was left out, for the person to be told. A change
  /// whose item is gone from the channel is dropped. Telegram's refusals,
  /// flood waits included, come back as they are, for the outbox to settle.
  ///
  /// What Telegram hands back goes into the index as it is, since it is
  /// what the channel now holds, and so does the message read first when
  /// nothing needs writing; a change made while this one went is shown over
  /// it again once the row is settled.
  Future<EditNotice?> replay(PendingEditRow row) async {
    final patch = _decode(row.patch);
    final messageId = await _messageIdOf(row.target, row.itemId);
    if (messageId == null) {
      await _dropPending(row.target, row.itemId);
      return null;
    }
    _settling.add(row.itemId);
    try {
      final td.Message message;
      try {
        message = await _client.send<td.Message>(
          td.GetMessage(chatId: _chatId, messageId: messageId),
        );
      } on TelegramException catch (e) {
        if (!_isGone(e)) rethrow;
        await _dropPending(row.target, row.itemId);
        return null;
      }
      final Set<String> skipped;
      final String name;
      switch ((row.target, MessageIndexer.manifestOf(message))) {
        case (EditTarget.file, final FileManifest remote)
            when remote.id == row.itemId:
          final (:apply, skipped: left) = patch.resolve(
            EditPatch.fileValues(remote),
          );
          if (apply.isEmpty) await ingest(message);
          final parts = await _db.partsOf(row.itemId);
          if (apply.isNotEmpty || parts.length > 1) {
            final merged = EditPatch.applyToFile(remote, apply);
            await _writeFileManifest(
              parts,
              apply.isEmpty
                  ? merged
                  : merged.copyWith(modifiedAt: DateTime.now()),
              patient: false,
            );
          }
          skipped = left;
          name = remote.name;
        case (EditTarget.folder, final FolderManifest remote)
            when remote.id == row.itemId:
          final (:apply, skipped: left) = patch.resolve(
            EditPatch.folderValues(remote),
          );
          if (apply.isEmpty) {
            await ingest(message);
          } else {
            await _writeFolderManifest(
              messageId,
              EditPatch.applyToFolder(
                remote,
                apply,
                modifiedAt: DateTime.now(),
              ),
              patient: false,
            );
          }
          skipped = left;
          name = remote.name;
        case (EditTarget.album, final AlbumManifest remote)
            when remote.id == row.itemId:
          final (:apply, skipped: left) = patch.resolve({'n': remote.name});
          if (apply['n'] case final String wanted) {
            await _writeAlbumManifest(
              messageId,
              AlbumManifest(
                id: remote.id,
                name: wanted,
                createdAt: remote.createdAt,
                modifiedAt: DateTime.now(),
              ),
              patient: false,
            );
          } else {
            await ingest(message);
          }
          skipped = left;
          name = remote.name;
        default:
          // The message holds something else now, so nothing of this item
          // is left to change.
          await _dropPending(row.target, row.itemId);
          return null;
      }
      await _finishPending(row, patch);
      return _noticeFor(patch, skipped, name);
    } finally {
      _settling.remove(row.itemId);
      if (await _db.pendingEditOf(row.target, row.itemId) case final newer?) {
        await _applyLocally(row.target, row.itemId, _decode(newer.patch).over);
      }
    }
  }

  /// Settles the waiting change once [sent], what [row] held, has gone to
  /// Telegram. Nothing is left unless an edit came in meanwhile; then only
  /// what that edit changed stays, starting from what was sent.
  Future<void> _finishPending(PendingEditRow row, EditPatch sent) =>
      _db.transaction(() async {
        final current = await _db.pendingEditOf(row.target, row.itemId);
        if (current == null) return;
        final rest = _decode(current.patch).rebase(sent);
        if (rest.isEmpty) {
          await _dropPending(row.target, row.itemId);
          return;
        }
        await _db.savePendingEdit(
          current
              .toCompanion(false)
              .copyWith(
                patch: Value(jsonEncode(rest.toJson())),
                attempts: const Value(0),
                lastError: const Value(null),
              ),
        );
      });

  /// What to tell the person about the first of [skipped], the fields
  /// another device changed first, about the item called [current] in
  /// Telegram. It is named as it was before either change, when the change
  /// was a rename, so the name is one they know.
  static EditNotice? _noticeFor(
    EditPatch patch,
    Set<String> skipped,
    String current,
  ) {
    for (final key in const ['n', 'f', 'p', 'tr', 'st']) {
      if (!skipped.contains(key)) continue;
      return EditNotice(
        name: switch (patch.fields['n']?.base) {
          final String before => before,
          _ => current,
        },
        verb: switch (key) {
          'n' => 'rename',
          'f' || 'p' => 'move',
          'st' => 'star',
          _ => patch.fields[key]!.want == null ? 'restore' : 'trash',
        },
      );
    }
    return null;
  }

  /// Throws away the change waiting for [id], so the item goes back to how
  /// Telegram has it: read again from the channel when it can be reached,
  /// and otherwise put back the way it was when the change was made.
  Future<void> discardPending(EditTarget target, String id) async {
    final row = await _db.pendingEditOf(target, id);
    if (row == null) return;
    await _dropPending(target, id);
    final messageId = await _messageIdOf(target, id);
    if (_reachable && messageId != null) {
      try {
        await ingest(
          await _client.send<td.Message>(
            td.GetMessage(chatId: _chatId, messageId: messageId),
          ),
        );
        return;
      } on TelegramException catch (e) {
        debugPrint('[Drive] Reading a discarded change back: $e');
      }
    }
    final base = {
      for (final MapEntry(:key, value: field) in _decode(
        row.patch,
      ).fields.entries)
        key: field.base,
    };
    await _applyLocally(target, id, (_) => base);
  }

  /// Shows [values], worked out from what the index holds of the item now,
  /// in place of that, as if Telegram had taken them.
  Future<void> _applyLocally(
    EditTarget target,
    String id,
    Map<String, Object?> Function(Map<String, Object?> current) values,
  ) async {
    switch (target) {
      case EditTarget.file:
        final file = await _db.fileById(id);
        if (file == null) return;
        final current = await _fileManifest(file);
        await _applyFileLocally(
          file,
          EditPatch.applyToFile(current, values(EditPatch.fileValues(current))),
        );
      case EditTarget.folder:
        final folder = await _db.folderById(id);
        if (folder == null) return;
        final current = _folderManifest(folder);
        await _applyFolderLocally(
          folder,
          EditPatch.applyToFolder(
            current,
            values(EditPatch.folderValues(current)),
          ),
        );
      case EditTarget.album:
        final album = await _db.albumById(id);
        if (album == null) return;
        if (values({'n': album.name})['n'] case final String name) {
          await _applyAlbumLocally(album, name);
        }
    }
  }

  /// The changes waiting to reach Telegram, the one made first first, each
  /// with its item as the phone shows it and a sentence saying what
  /// changed. A change whose item has left the index is passed over.
  Stream<List<PendingEditView>> watchPendingEdits() =>
      _db.watchPendingEdits().asyncMap((rows) async {
        final folders = {
          for (final folder in await _db.allFolders()) folder.id: folder.name,
        };
        final albums = <String, String?>{};
        Future<String?> albumName(String id) async =>
            albums[id] ??= (await _db.albumById(id))?.name;
        final views = <PendingEditView>[];
        for (final row in rows) {
          final patch = _decode(row.patch);
          final description = await _describeChange(patch, folders, albumName);
          final error = row.attempts >= EditOutbox.maxAttempts
              ? row.lastError
              : null;
          switch (row.target) {
            case EditTarget.file:
              final file = await _db.fileById(row.itemId);
              if (file == null) continue;
              views.add(
                PendingEditView(
                  target: row.target,
                  id: row.itemId,
                  name: file.name,
                  file: DriveFile.fromRow(file),
                  description: description,
                  error: error,
                ),
              );
            case EditTarget.folder:
              final folder = await _db.folderById(row.itemId);
              if (folder == null) continue;
              views.add(
                PendingEditView(
                  target: row.target,
                  id: row.itemId,
                  name: folder.name,
                  folder: DriveFolder.fromRow(folder),
                  description: description,
                  error: error,
                ),
              );
            case EditTarget.album:
              final name = await albumName(row.itemId);
              if (name == null) continue;
              views.add(
                PendingEditView(
                  target: row.target,
                  id: row.itemId,
                  name: name,
                  description: description,
                  error: error,
                ),
              );
          }
        }
        return views;
      });

  /// What [patch] changes, one phrase per change joined with ' · ', as in
  /// 'Renamed from "Scan 12.pdf" · Moved to Work'. Folders are named from
  /// [folders], with the root as Files, and albums through [albumName].
  static Future<String> _describeChange(
    EditPatch patch,
    Map<String, String> folders,
    Future<String?> Function(String id) albumName,
  ) async {
    final fields = patch.fields;
    String place(Object? folderId) =>
        folderId is String ? folders[folderId] ?? 'a folder' : 'Files';
    Future<String> album(String id) async => switch (await albumName(id)) {
      final String name => '"$name"',
      null => 'an album',
    };
    List<String> ids(Object? value) => [
      if (value is List)
        for (final id in value)
          if (id is String) id,
    ];
    final phrases = [
      if (fields['n'] case final rename?) 'Renamed from "${rename.base}"',
      if (fields['f'] ?? fields['p'] case final move?)
        'Moved to ${place(move.want)}',
      if (fields['tr'] case final trash?)
        trash.want == null ? 'Restored from Trash' : 'Moved to Trash',
      if (fields['st'] case final star?)
        star.want == true ? 'Added to Starred' : 'Removed from Starred',
    ];
    if (fields['al'] case final albums?) {
      final before = ids(albums.base).toSet();
      final after = ids(albums.want).toSet();
      for (final id in after.difference(before)) {
        phrases.add('Added to ${await album(id)}');
      }
      for (final id in before.difference(after)) {
        phrases.add('Removed from ${await album(id)}');
      }
    }
    return phrases.join(' · ');
  }

  /// Longest flood wait an edit sits out. Anything longer fails with
  /// Telegram's own sentence, since holding a change for hours helps nobody.
  static const int _longestWaitSeconds = 15 * 60;

  /// Runs [action], sitting out Telegram's flood waits of up to 15 minutes
  /// instead of failing, so a long run of edits carries on by itself. The
  /// wait is announced through [telegramWaitProvider], whose Stop can cut
  /// it short when [stoppable].
  Future<T> _patiently<T>(
    Future<T> Function() action, {
    bool stoppable = true,
  }) => _messenger.patiently(
    action,
    longestWait: const Duration(seconds: _longestWaitSeconds),
    stoppable: stoppable,
  );

  Future<td.Message?> _ignoreUnchanged(
    Future<td.Message> Function() edit,
  ) async {
    try {
      return await edit();
    } on TelegramException catch (e) {
      if (e.message.contains('MESSAGE_NOT_MODIFIED')) return null;
      rethrow;
    }
  }

  void dispose() => _ingested.close();
}

final driveRepositoryProvider = Provider<DriveRepository>((ref) {
  final repository = DriveRepository(ref);
  ref.onDispose(repository.dispose);
  return repository;
});

// -----------------------------------------------------------------------------
// Query providers
// -----------------------------------------------------------------------------

final folderContentsProvider = StreamProvider.autoDispose
    .family<FolderContents, String?>(
      (ref, folderId) =>
          ref.watch(driveRepositoryProvider).watchFolder(folderId),
    );

final folderInfoProvider = StreamProvider.autoDispose
    .family<DriveFolder?, String>(
      (ref, id) => ref.watch(driveRepositoryProvider).watchFolderInfo(id),
    );

final fileInfoProvider = StreamProvider.autoDispose.family<DriveFile?, String>(
  (ref, id) => ref.watch(driveRepositoryProvider).watchFile(id),
);

final breadcrumbsProvider = FutureProvider.autoDispose
    .family<List<DriveFolder>, String?>((ref, folderId) {
      // Re-resolve when the folder itself is renamed or moved.
      if (folderId != null) ref.watch(folderInfoProvider(folderId));
      return ref.watch(driveRepositoryProvider).pathTo(folderId);
    });

/// Home's Recent: up to [limit] files opened or added lately.
final recentActivityProvider = StreamProvider.autoDispose
    .family<List<RecentEntry>, int>(
      (ref, limit) =>
          ref.watch(driveRepositoryProvider).watchRecentActivity(limit: limit),
    );

final starredFilesProvider = StreamProvider.autoDispose<List<DriveFile>>(
  (ref) => ref.watch(driveRepositoryProvider).watchStarred(),
);

/// Starred folders that aren't in the trash, in name order.
final starredFoldersProvider = StreamProvider.autoDispose<List<DriveFolder>>(
  (ref) => ref.watch(driveRepositoryProvider).watchStarredFolders(),
);

/// Each starred folder's id to what it holds, in it or below it. Alive only
/// while Home or Starred is on screen, since every change to a file
/// recounts it.
final starredFolderSizesProvider =
    StreamProvider.autoDispose<Map<String, FolderSize>>(
      (ref) => ref.watch(driveRepositoryProvider).watchStarredFolderSizes(),
    );

final trashProvider = StreamProvider.autoDispose<TrashContents>(
  (ref) => ref.watch(driveRepositoryProvider).watchTrash(),
);

final albumsProvider = StreamProvider.autoDispose<List<DriveAlbum>>(
  (ref) => ref.watch(driveRepositoryProvider).watchAlbums(),
);

final albumFilesProvider = StreamProvider.autoDispose
    .family<List<DriveFile>, String>(
      (ref, albumId) =>
          ref.watch(driveRepositoryProvider).watchAlbumFiles(albumId),
    );

final kindFilesProvider = StreamProvider.autoDispose
    .family<List<DriveFile>, FileKind>(
      (ref, kind) => ref.watch(driveRepositoryProvider).watchKind(kind),
    );

final storageSummaryProvider = StreamProvider.autoDispose<StorageSummary>(
  (ref) => ref.watch(driveRepositoryProvider).watchSummary(),
);

/// The 50 biggest files the drive shows, biggest first.
final largestFilesProvider = StreamProvider.autoDispose<List<DriveFile>>(
  (ref) => ref.watch(driveRepositoryProvider).watchLargestFiles(),
);

/// Each top-level folder's share of the drive, biggest first, then the
/// files in no folder.
final folderSizesProvider = StreamProvider.autoDispose<List<FolderSize>>(
  (ref) => ref.watch(driveRepositoryProvider).watchFolderSizes(),
);

/// How many files the trash holds, those in trashed folders included, and
/// their size.
final trashTotalsProvider = StreamProvider.autoDispose<(int count, int bytes)>(
  (ref) => ref.watch(driveRepositoryProvider).watchTrashTotals(),
);

/// Every photo and video in the drive, newest moment first.
final mediaTimelineProvider = StreamProvider.autoDispose<List<DriveFile>>(
  (ref) => ref.watch(driveRepositoryProvider).watchMedia(),
);
