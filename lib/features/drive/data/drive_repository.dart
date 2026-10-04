import 'dart:async';

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
import '../domain/manifest.dart';
import 'channel_messenger.dart';
import 'drive_session.dart';
import 'message_indexer.dart';
import 'telegram_wait.dart';

/// A request the drive cannot carry out, phrased for a person.
class DriveException implements Exception {
  const DriveException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Reads the local index and changes the drive.
///
/// Every change goes to Telegram first and is written to the index from the
/// message Telegram hands back, so the index never claims something the
/// channel does not hold.
class DriveRepository {
  DriveRepository(this._ref);

  final Ref _ref;
  final _uuid = const Uuid();
  final _ingested = StreamController<String>.broadcast();

  AppDatabase get _db => _ref.read(appDatabaseProvider);
  ChannelMessenger get _messenger => _ref.read(channelMessengerProvider);

  int get _chatId {
    final session = _ref.read(driveSessionProvider);
    if (session == null) throw const DriveException('Your drive is not open.');
    return session.chatId;
  }

  String newId() => _uuid.v4();

  /// Ids of files that just gained a part — how the transfer queue notices
  /// an upload TDLib finished on its own after a restart.
  Stream<String> get ingestedFileIds => _ingested.stream;

  // ---------------------------------------------------------------------------
  // Index maintenance
  // ---------------------------------------------------------------------------

  Future<void> ingest(td.Message message) async {
    switch (MessageIndexer.entryFor(message)) {
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

  Stream<List<DriveFile>> watchAlbumFiles(String albumId) =>
      _db.watchAlbumFiles(albumId).map(_files);

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

  Stream<List<(DriveFile, DateTime)>> watchRecentOpens({int limit = 20}) =>
      _db.watchRecentOpens(limit: limit).map(
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

  Stream<List<DriveFile>> watchMedia() => _db.watchMedia().map(_files);

  Future<Map<String, String>> mediaFingerprints() => _db.mediaFingerprints();

  Stream<List<DriveFile>> watchKind(FileKind kind) =>
      _db.watchKind(kind).map(_files);

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
  /// the message and remembered.
  Future<td.File> resolveTdFile(PartRow part) async {
    final client = _ref.read(telegramClientProvider);
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

  Future<void> _rewriteFolder(
    DriveFolder folder, {
    required String name,
    required String? parentId,
    DateTime? trashedAt,
    bool restore = false,
  }) async {
    final row = await _db.folderById(folder.id);
    if (row == null) return;
    final manifest = FolderManifest(
      id: folder.id,
      name: name,
      parentId: parentId,
      createdAt: folder.createdAt,
      modifiedAt: DateTime.now(),
      trashedAt: restore ? null : (trashedAt ?? row.trashedAt),
      starred: row.starred,
      extra: ManifestCodec.decodeExtra(row.manifestExtra),
    );
    final message = await _ignoreUnchanged(
      () => _patiently(
        () => _messenger.editText(
          _chatId,
          row.messageId,
          ManifestCodec.encodeFolder(manifest),
        ),
      ),
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

  Future<void> renameFile(DriveFile file, String name) async {
    final clean = name.trim();
    if (clean.isEmpty) throw const DriveException('Give the file a name.');
    if (clean == file.name) return;
    await _rewriteFile(file, (m) => m.copyWith(name: clean));
  }

  Future<void> moveFiles(List<DriveFile> files, String? folderId) async {
    for (final file in files) {
      if (file.folderId == folderId) continue;
      await _rewriteFile(
        file,
        (m) => folderId == null
            ? m.copyWith(clearFolder: true)
            : m.copyWith(folderId: folderId),
      );
    }
  }

  Future<void> setStarred(List<DriveFile> files, {required bool starred}) async {
    for (final file in files) {
      if (file.starred == starred) continue;
      await _rewriteFile(file, (m) => m.copyWith(starred: starred));
    }
  }

  /// Rewrites the manifest on every part of [file], starting from what the
  /// index holds so nothing the caller doesn't touch is lost, including
  /// keys only a newer version knows.
  Future<void> _rewriteFile(
    DriveFile file,
    FileManifest Function(FileManifest current) change,
  ) async {
    final row = await _db.fileById(file.id);
    if (row == null) return;
    final parts = await _db.partsOf(file.id);
    final base = change(
      FileManifest(
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
      ),
    ).copyWith(modifiedAt: DateTime.now());

    // Once one part carries the change, Stop no longer cuts a wait short,
    // so a split file never ends up with parts that disagree.
    var stoppable = true;
    for (final part in parts) {
      final caption = ManifestCodec.encodeFile(base.copyWith(partIndex: part.partIndex));
      td.Message? message;
      try {
        message = await _ignoreUnchanged(
          () => _patiently(
            () => _messenger.editCaption(_chatId, part.messageId, caption),
            stoppable: stoppable,
          ),
        );
      } on TelegramException catch (e) {
        if (!e.isNotEditable) rethrow;
        message = await _replaceWithOwnCopy(part.messageId, caption, stoppable: stoppable);
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
  /// its id throughout.
  Future<td.Message> _replaceWithOwnCopy(
    int messageId,
    EncodedText caption, {
    bool stoppable = true,
  }) async {
    // Telegram usually turns a copy away only once it is being sent, so the
    // wait covers the delivery as well as the request.
    final copy = await _patiently(() async {
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
    }, stoppable: stoppable);
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
      await _rewriteFolder(folder, name: folder.name, parentId: folder.parentId, trashedAt: now);
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
      await _rewriteFolder(folder, name: folder.name, parentId: folder.parentId, restore: true);
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
    final all = [for (final f in await _db.allFolders()) if (!f.hidden) f];
    final roots = all
        .where((f) => f.parentId == null && f.name.toLowerCase() == rootName.toLowerCase())
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
          (await _db.watchFilesIn(sub.id).first).map(DriveFile.fromRow).toList(),
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
    final existing = (await _db.watchChildFolders(parentId).first)
        .where((f) => f.name.toLowerCase() == name.toLowerCase());
    if (existing.isNotEmpty) return existing.first.id;
    final now = DateTime.now();
    final manifest = FolderManifest(
      id: newId(),
      name: name,
      parentId: parentId,
      createdAt: now,
      modifiedAt: now,
    );
    await ingest(await _messenger.sendText(_chatId, ManifestCodec.encodeFolder(manifest)));
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

  Future<void> renameAlbum(String albumId, String name) async {
    final clean = name.trim();
    if (clean.isEmpty) throw const DriveException('Give the album a name.');
    final row = await _db.albumById(albumId);
    if (row == null || row.name == clean) return;
    final message = await _ignoreUnchanged(
      () => _patiently(
        () => _messenger.editText(
          _chatId,
          row.messageId,
          ManifestCodec.encodeAlbum(
            AlbumManifest(
              id: row.id,
              name: clean,
              createdAt: row.createdAt,
              modifiedAt: DateTime.now(),
            ),
          ),
        ),
      ),
    );
    if (message != null) await ingest(message);
  }

  /// Deletes the album; its photos stay in the drive.
  Future<void> deleteAlbum(String albumId) async {
    final row = await _db.albumById(albumId);
    if (row == null) return;
    final members = await _db.watchAlbumFiles(albumId).first;
    await removeFromAlbum(members.map(DriveFile.fromRow).toList(), albumId);
    await _messenger.deleteMessages(_chatId, [row.messageId]);
    await _db.removeMessages([row.messageId]);
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
      await _rewriteFile(file, (m) => m.copyWith(albums: [...current, albumId]));
    }
    if (touch) await touchAlbum(albumId);
  }

  Future<void> removeFromAlbum(List<DriveFile> files, String albumId) async {
    for (final file in files) {
      final current = await _db.albumIdsOf(file.id);
      if (!current.contains(albumId)) continue;
      await _rewriteFile(
        file,
        (m) => m.copyWith(albums: current.where((id) => id != albumId).toList()),
      );
    }
  }

  /// Albums sort by when they last changed, so adding photos lifts one to
  /// the top.
  Future<void> touchAlbum(String albumId) async {
    final row = await _db.albumById(albumId);
    if (row == null) return;
    await _ignoreUnchanged(
      () => _patiently(
        () => _messenger.editText(
          _chatId,
          row.messageId,
          ManifestCodec.encodeAlbum(
            AlbumManifest(
              id: row.id,
              name: row.name,
              createdAt: row.createdAt,
              modifiedAt: DateTime.now(),
            ),
          ),
        ),
      ),
    ).then((message) async {
      if (message != null) await ingest(message);
    });
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
      for (final id in fileIds) ...(await _db.partsOf(id)).map((p) => p.messageId),
      ...allFolders
          .where((f) => folderIds.contains(f.id))
          .map((f) => f.messageId),
    ];
    if (messageIds.isEmpty) return 0;

    await _messenger.deleteMessages(_chatId, messageIds);
    await _db.removeMessages(messageIds);
    return fileIds.length;
  }

  Future<void> deleteFileById(String fileId) async {
    final ids = (await _db.partsOf(fileId)).map((p) => p.messageId).toList();
    if (ids.isEmpty) return;
    await _messenger.deleteMessages(_chatId, ids);
    await _db.removeMessages(ids);
  }

  /// Longest flood wait an edit sits out. Anything longer fails with
  /// Telegram's own sentence, since holding a change for hours helps nobody.
  static const int _longestWaitSeconds = 15 * 60;

  /// Runs [action], sitting out Telegram's flood waits of up to 15 minutes
  /// instead of failing, so a long run of edits carries on by itself. The
  /// wait is announced through [telegramWaitProvider], whose Stop can cut
  /// it short when [stoppable].
  Future<T> _patiently<T>(Future<T> Function() action, {bool stoppable = true}) =>
      _messenger.patiently(
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

final trashProvider = StreamProvider.autoDispose<TrashContents>(
  (ref) => ref.watch(driveRepositoryProvider).watchTrash(),
);

final albumsProvider = StreamProvider.autoDispose<List<DriveAlbum>>(
  (ref) => ref.watch(driveRepositoryProvider).watchAlbums(),
);

final albumFilesProvider = StreamProvider.autoDispose
    .family<List<DriveFile>, String>(
      (ref, albumId) => ref.watch(driveRepositoryProvider).watchAlbumFiles(albumId),
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
