import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegrive/core/files/file_kind.dart';
import 'package:telegrive/features/drive/data/drive_repository.dart';
import 'package:telegrive/features/drive/domain/drive_models.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';
import 'package:telegrive/infrastructure/storage/device_storage.dart';

void main() {
  group('collectForSaving', () {
    late AppDatabase db;
    late ProviderContainer container;
    final now = DateTime(2026, 9, 26);
    var messageId = 0;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
      );

      Future<void> folder(String id, {String? parentId}) => db.upsertFolder(
        FoldersCompanion.insert(
          id: id,
          parentId: Value(parentId),
          name: id,
          messageId: ++messageId,
          createdAt: now,
          modifiedAt: now,
        ),
      );
      Future<void> file(String name, {String? folderId, int partCount = 1}) =>
          db.upsertFilePart(
            DriveFilesCompanion.insert(
              id: name,
              folderId: Value(folderId),
              name: name,
              mimeType: 'application/octet-stream',
              kind: FileKind.other,
              size: 10,
              createdAt: now,
              modifiedAt: now,
              partCount: Value(partCount),
            ),
            FilePartsCompanion.insert(
              fileId: name,
              partIndex: 0,
              messageId: ++messageId,
              tdFileId: messageId,
              size: 10,
            ),
          );

      // Work/Reports/q3.pdf, Work/plan.txt, Photo backup/Camera/IMG_1.jpg,
      // loose.txt at the root, and orphan.txt whose folder is gone.
      await folder('Work');
      await folder('Reports', parentId: 'Work');
      await folder('Photo backup');
      await folder('Camera', parentId: 'Photo backup');
      await file('q3.pdf', folderId: 'Reports');
      await file('plan.txt', folderId: 'Work');
      await file('draft.bin', folderId: 'Work', partCount: 2);
      await file('IMG_1.jpg', folderId: 'Camera');
      await file('loose.txt');
      await file('orphan.txt', folderId: 'gone');
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    DriveRepository repository() => container.read(driveRepositoryProvider);

    Map<String, List<String>> foldersOf(List<SaveItem> items) => {
      for (final item in items) item.file.name: item.folders,
    };

    test('the whole drive keeps its layout from the root', () async {
      final items = await repository().collectForSaving(everything: true);
      expect(foldersOf(items), {
        'q3.pdf': ['Work', 'Reports'],
        'plan.txt': ['Work'],
        'IMG_1.jpg': ['Photo backup', 'Camera'],
        'loose.txt': <String>[],
        'orphan.txt': <String>[],
      });
    });

    test('a folder brings everything inside it, starting from itself', () async {
      final work = DriveFolder.fromRow((await db.folderById('Work'))!);
      final loose = (await repository().fileById('loose.txt'))!;
      final items = await repository().collectForSaving(
        files: [loose],
        folders: [work],
      );
      expect(foldersOf(items), {
        'loose.txt': <String>[],
        'q3.pdf': ['Work', 'Reports'],
        'plan.txt': ['Work'],
      });
    });

    test('a nested folder starts at itself but knows its full path', () async {
      final camera = DriveFolder.fromRow((await db.folderById('Camera'))!);
      final item = (await repository().collectForSaving(folders: [camera])).single;
      expect(item.folders, ['Camera']);
      expect(item.path, ['Photo backup', 'Camera']);
    });
  });

  test('a version 1 database upgrades to the current schema', () async {
    final dir = await Directory.systemTemp.createTemp('telegrive_migration');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/telegrive.sqlite');

    // Version 1 is today's schema without what versions 2 to 10 added.
    var db = AppDatabase(NativeDatabase(file));
    await db.allTransfers();
    for (final statement in [
      'ALTER TABLE transfers DROP COLUMN save_to',
      'ALTER TABLE transfers DROP COLUMN save_folder',
      'ALTER TABLE folders DROP COLUMN trashed_at',
      'ALTER TABLE folders DROP COLUMN hidden',
      'ALTER TABLE drive_files DROP COLUMN trashed_at',
      'ALTER TABLE drive_files DROP COLUMN hidden',
      'DROP TABLE albums',
      'DROP TABLE album_files',
      'DROP TABLE offline_pins',
      'DROP TABLE offline_copies',
      'DROP TABLE file_contents',
      'ALTER TABLE folders DROP COLUMN manifest_extra',
      'ALTER TABLE drive_files DROP COLUMN manifest_extra',
      'DROP TABLE file_opens',
      'ALTER TABLE transfers DROP COLUMN wifi_only',
      'ALTER TABLE backup_assets DROP COLUMN reason',
      'ALTER TABLE drive_files DROP COLUMN duration_seconds',
      'ALTER TABLE transfers DROP COLUMN duration_seconds',
      'ALTER TABLE folders DROP COLUMN starred',
      'ALTER TABLE drive_files DROP COLUMN replaced_by',
      'ALTER TABLE transfers DROP COLUMN replaces_file_id',
      'DROP TABLE play_positions',
      'ALTER TABLE transfers DROP COLUMN source_chat_id',
      'ALTER TABLE transfers DROP COLUMN source_message_id',
      'ALTER TABLE drive_files DROP COLUMN adopted',
      'DROP TABLE watched_folders',
      'DROP TABLE watched_files',
      'DROP TABLE pending_edits',
      'ALTER TABLE drive_files DROP COLUMN original_size',
      'PRAGMA user_version = 1',
    ]) {
      await db.customStatement(statement);
    }
    await db.close();

    db = AppDatabase(NativeDatabase(file));
    addTearDown(db.close);
    await db.saveTransfer(
      TransferRow(
        id: 't',
        kind: TransferKind.download,
        status: TransferStatus.queued,
        name: 'IMG_1.jpg',
        mimeType: 'image/jpeg',
        fileId: 'f',
        ownsSource: false,
        wifiOnly: false,
        totalBytes: 1,
        doneBytes: 0,
        partCount: 1,
        completedParts: 0,
        createdAt: DateTime(2026, 9, 26),
        origin: TransferOrigin.save,
        saveTo: SaveTarget.gallery,
        saveFolder: 'Camera',
      ),
    );
    final row = (await db.allTransfers()).single;
    expect(row.saveTo, SaveTarget.gallery);
    expect(row.saveFolder, 'Camera');
    expect(await db.watchTrashedFiles().first, isEmpty);
    expect(await db.watchAlbums().first, isEmpty);
    expect(await db.select(db.fileOpens).get(), isEmpty);
    expect(await db.select(db.playPositions).get(), isEmpty);
    expect(await db.watchWatchedFolders().first, isEmpty);
    expect(await db.select(db.watchedFiles).get(), isEmpty);
    expect(await db.select(db.pendingEdits).get(), isEmpty);
    await db.saveWatchedFolder(
      WatchedFoldersCompanion.insert(
        id: 'bank',
        treeUri: 'content://com.android.externalstorage.documents/tree/primary%3ADownload%2FBank',
        label: 'Bank',
        filter: WatchFilter.documents,
        createdAt: DateTime(2026, 9, 26),
      ),
    );
    expect([for (final rule in await db.watchWatchedFolders().first) rule.label], ['Bank']);

    await db.saveTransfer(
      TransferRow(
        id: 'c',
        kind: TransferKind.upload,
        status: TransferStatus.queued,
        name: 'Contract.pdf',
        mimeType: 'application/pdf',
        fileId: 'g',
        ownsSource: false,
        wifiOnly: false,
        totalBytes: 1,
        doneBytes: 0,
        partCount: 1,
        completedParts: 0,
        createdAt: DateTime(2026, 9, 26),
        origin: TransferOrigin.fromChat,
        sourceChatId: 777000,
        sourceMessageId: 42,
      ),
    );
    final copy = (await db.allTransfers()).firstWhere((r) => r.id == 'c');
    expect(copy.origin, TransferOrigin.fromChat);
    expect(copy.sourceChatId, 777000);
    expect(copy.sourceMessageId, 42);

    await db.into(db.driveFiles).insert(
      DriveFilesCompanion.insert(
        id: 'g',
        name: 'Contract.pdf',
        mimeType: 'application/pdf',
        kind: FileKind.document,
        size: 1,
        createdAt: DateTime(2026, 9, 26),
        modifiedAt: DateTime(2026, 9, 26),
      ),
    );
    expect((await db.fileById('g'))!.adopted, isFalse);
  });

  group('DeviceStorage names', () {
    test('drive names become safe file names', () {
      expect(DeviceStorage.safeName('Q3/Q4: report'), 'Q3_Q4_ report');
      expect(DeviceStorage.safeName('  '), '_');
      expect(DeviceStorage.safeName('..'), '_');
      expect(DeviceStorage.safeName('Tizita — live.mp3'), 'Tizita — live.mp3');
    });

    test('clashes get a number before the extension', () {
      expect(DeviceStorage.numbered('photo.jpg', 2), 'photo (2).jpg');
      expect(DeviceStorage.numbered('README', 1), 'README (1)');
      expect(DeviceStorage.numbered('archive.tar.gz', 1), 'archive.tar (1).gz');
    });
  });
}
