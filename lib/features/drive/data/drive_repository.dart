import 'dart:async';

import 'package:drift/drift.dart' show Value, BooleanExpressionOperators;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:uuid/uuid.dart';

import '../../../core/async/combine.dart';
import '../../../core/files/file_kind.dart';
import '../../../infrastructure/database/app_database.dart';
import '../../../infrastructure/telegram/telegram_client.dart';
import '../../../infrastructure/telegram/telegram_exception.dart';
import '../domain/drive_models.dart';
import '../domain/manifest.dart';
import 'channel_messenger.dart';
import 'drive_session.dart';
import 'message_indexer.dart';

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
      case FilePartEntry(:final file, :final part):
        await _db.upsertFilePart(file, part);
        _ingested.add(part.fileId.value);
      case FolderEntry(:final folder):
        await _db.upsertFolder(folder);
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

  Stream<DriveFolder?> watchFolderInfo(String id) =>
      _db.watchFolder(id).map((r) => r == null ? null : DriveFolder.fromRow(r));

  Stream<DriveFile?> watchFile(String id) =>
      _db.watchFile(id).map((r) => r == null ? null : DriveFile.fromRow(r));

  Stream<List<DriveFile>> watchRecent({int limit = 20}) =>
      _db.watchRecent(limit: limit).map(_files);

  Stream<List<DriveFile>> watchStarred() => _db.watchStarred().map(_files);

  Stream<List<DriveFile>> watchMedia() => _db.watchMedia().map(_files);

  Future<Map<String, String>> mediaFingerprints() => _db.mediaFingerprints();

  Stream<List<DriveFile>> watchKind(FileKind kind) =>
      _db.watchKind(kind).map(_files);

  Stream<List<DriveFile>> watchSearch(String query, {FileKind? kind}) =>
      _db.watchSearch(query, kind: kind).map(_files);

  Stream<List<DriveFolder>> watchFolderSearch(String query) => _db
      .watchFolderSearch(query)
      .map((rows) => rows.map(DriveFolder.fromRow).toList());

  Stream<StorageSummary> watchSummary() =>
      _db.watchTotals().map((totals) => StorageSummary(totals: totals));

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
  }) async {
    final row = await _db.folderById(folder.id);
    if (row == null) return;
    final manifest = FolderManifest(
      id: folder.id,
      name: name,
      parentId: parentId,
      createdAt: folder.createdAt,
      modifiedAt: DateTime.now(),
    );
    final message = await _ignoreUnchanged(
      () => _messenger.editText(
        _chatId,
        row.messageId,
        ManifestCodec.encodeFolder(manifest),
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

  /// Rewrites the manifest on every part of [file].
  Future<void> _rewriteFile(
    DriveFile file,
    FileManifest Function(FileManifest current) change,
  ) async {
    final parts = await _db.partsOf(file.id);
    final base = change(
      FileManifest(
        id: file.id,
        name: file.name,
        folderId: file.folderId,
        mimeType: file.mimeType,
        size: file.size,
        createdAt: file.createdAt,
        modifiedAt: file.modifiedAt,
        partCount: file.partCount,
        starred: file.starred,
        takenAt: file.takenAt,
      ),
    ).copyWith(modifiedAt: DateTime.now());

    for (final part in parts) {
      final message = await _ignoreUnchanged(
        () => _messenger.editCaption(
          _chatId,
          part.messageId,
          ManifestCodec.encodeFile(base.copyWith(partIndex: part.partIndex)),
        ),
      );
      if (message != null) await ingest(message);
    }
  }

  // ---------------------------------------------------------------------------
  // Deleting
  // ---------------------------------------------------------------------------

  /// Deletes [files] and [folders] (with everything inside them) from
  /// Telegram and the index. Returns how many files went.
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

final recentFilesProvider = StreamProvider.autoDispose<List<DriveFile>>(
  (ref) => ref.watch(driveRepositoryProvider).watchRecent(limit: 12),
);

final starredFilesProvider = StreamProvider.autoDispose<List<DriveFile>>(
  (ref) => ref.watch(driveRepositoryProvider).watchStarred(),
);

final kindFilesProvider = StreamProvider.autoDispose
    .family<List<DriveFile>, FileKind>(
      (ref, kind) => ref.watch(driveRepositoryProvider).watchKind(kind),
    );

final storageSummaryProvider = StreamProvider.autoDispose<StorageSummary>(
  (ref) => ref.watch(driveRepositoryProvider).watchSummary(),
);

/// Every photo and video in the drive, newest moment first.
final mediaTimelineProvider = StreamProvider.autoDispose<List<DriveFile>>(
  (ref) => ref.watch(driveRepositoryProvider).watchMedia(),
);
