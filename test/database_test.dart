import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegrive/core/files/file_kind.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';

void main() {
  late AppDatabase db;
  final now = DateTime(2026, 9, 25);

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  DriveFilesCompanion file(String id, {String? folderId, int partCount = 1}) =>
      DriveFilesCompanion.insert(
        id: id,
        folderId: Value(folderId),
        name: '$id.bin',
        mimeType: 'application/octet-stream',
        kind: FileKind.other,
        size: 100,
        createdAt: now,
        modifiedAt: now,
        partCount: Value(partCount),
      );

  FilePartsCompanion part(String fileId, int index, int messageId) =>
      FilePartsCompanion.insert(
        fileId: fileId,
        partIndex: index,
        messageId: messageId,
        tdFileId: messageId + 1,
        size: 50,
      );

  FoldersCompanion folder(String id, int messageId, {String? parentId}) =>
      FoldersCompanion.insert(
        id: id,
        parentId: Value(parentId),
        name: id,
        messageId: messageId,
        createdAt: now,
        modifiedAt: now,
      );

  test('a split file only appears once every part has arrived', () async {
    await db.upsertFilePart(file('big', partCount: 2), part('big', 0, 10));
    expect(await db.watchFilesIn(null).first, isEmpty);

    await db.upsertFilePart(file('big', partCount: 2), part('big', 1, 11));
    final files = await db.watchFilesIn(null).first;
    expect(files.single.id, 'big');
    expect(files.single.partsPresent, 2);
  });

  test('deleting any part hides the file; deleting all removes it', () async {
    await db.upsertFilePart(file('big', partCount: 2), part('big', 0, 10));
    await db.upsertFilePart(file('big', partCount: 2), part('big', 1, 11));

    await db.removeMessages([11]);
    expect(await db.watchFilesIn(null).first, isEmpty);
    expect(await db.fileById('big'), isNotNull);

    await db.removeMessages([10]);
    expect(await db.fileById('big'), isNull);
  });

  test('re-ingesting the same message is idempotent', () async {
    await db.upsertFilePart(file('a'), part('a', 0, 10));
    await db.upsertFilePart(file('a'), part('a', 0, 10));
    expect((await db.watchFilesIn(null).first).single.partsPresent, 1);
  });

  test('a caption edit that re-homes a message drops the old file', () async {
    await db.upsertFilePart(file('tg10'), part('tg10', 0, 10));
    // The same message now carries a real manifest with a new id.
    await db.upsertFilePart(file('uuid-1'), part('uuid-1', 0, 10));

    expect(await db.fileById('tg10'), isNull);
    expect((await db.watchFilesIn(null).first).single.id, 'uuid-1');
  });

  test('items whose folder is gone surface at the root', () async {
    await db.upsertFolder(folder('docs', 1));
    await db.upsertFolder(folder('inner', 2, parentId: 'docs'));
    await db.upsertFilePart(file('a', folderId: 'docs'), part('a', 0, 10));

    expect(await db.watchFilesIn(null).first, isEmpty);
    expect((await db.watchChildFolders(null).first).map((f) => f.id), ['docs']);

    await db.removeMessages([1]); // the "docs" folder message is deleted

    expect((await db.watchFilesIn(null).first).single.id, 'a');
    expect((await db.watchChildFolders(null).first).map((f) => f.id), ['inner']);
  });

  test('opens follow their file, outlast a rebuilt index and go on sign-out', () async {
    await db.upsertFilePart(file('a'), part('a', 0, 10));
    await db.upsertFilePart(file('b'), part('b', 0, 11));
    for (final id in ['a', 'b']) {
      await db.into(db.fileOpens).insert(
        FileOpensCompanion.insert(fileId: id, openedAt: now),
      );
    }
    Future<List<String>> opened() async =>
        [for (final row in await db.select(db.fileOpens).get()) row.fileId];

    await db.removeMessages([10]);
    expect(await opened(), ['b']);

    await db.clearIndex();
    expect(await opened(), ['b']);

    await db.clearAll();
    expect(await opened(), isEmpty);
  });

  test('totals group by kind and skip incomplete files', () async {
    await db.upsertFilePart(file('a'), part('a', 0, 10));
    await db.upsertFilePart(file('b', partCount: 2), part('b', 0, 11));
    final totals = await db.watchTotals().first;
    expect(totals.single.count, 1);
    expect(totals.single.bytes, 100);
  });

  test('search escapes wildcards', () async {
    await db.upsertFilePart(file('100%'), part('100%', 0, 10));
    await db.upsertFilePart(file('1000'), part('1000', 0, 11));
    final hits = await db.watchSearch('100%').first;
    expect(hits.map((f) => f.id), ['100%']);
  });

  test('the photo timeline orders by capture time, falling back to upload', () async {
    DriveFilesCompanion media(String id, FileKind kind, {DateTime? taken, required DateTime added}) =>
        DriveFilesCompanion.insert(
          id: id,
          name: '$id.jpg',
          mimeType: 'image/jpeg',
          kind: kind,
          size: 100,
          createdAt: added,
          modifiedAt: added,
          takenAt: Value(taken),
        );

    await db.upsertFilePart(
      media('old-photo', FileKind.image, taken: DateTime(2019), added: DateTime(2026, 9)),
      part('old-photo', 0, 1),
    );
    await db.upsertFilePart(
      media('new-upload', FileKind.image, added: DateTime(2026, 8)),
      part('new-upload', 0, 2),
    );
    await db.upsertFilePart(
      media('clip', FileKind.video, taken: DateTime(2026, 9, 20), added: DateTime(2026, 9)),
      part('clip', 0, 3),
    );
    await db.upsertFilePart(file('report'), part('report', 0, 4));

    final timeline = await db.watchMedia().first;
    expect(timeline.map((f) => f.id), ['clip', 'new-upload', 'old-photo']);
  });

  test('media fingerprints and backup records', () async {
    await db.upsertFilePart(
      DriveFilesCompanion.insert(
        id: 'p',
        name: 'IMG_1.jpg',
        mimeType: 'image/jpeg',
        kind: FileKind.image,
        size: 4242,
        createdAt: now,
        modifiedAt: now,
      ),
      part('p', 0, 1),
    );
    expect(await db.mediaFingerprints(), {'IMG_1.jpg|4242': 'p'});

    await db.markAssetBackedUp('asset-1', 'p');
    await db.markAssetFailed('asset-2', 2);
    final records = await db.backupAssetMap();
    expect(records['asset-1']!.state, BackupAssetState.done);
    expect(records['asset-2']!.failures, 2);
    expect(await db.watchBackedUpCount().first, 1);
    expect(await db.watchLocalAssets().first, {'p': 'asset-1'});

    await db.clearBackupFailures();
    expect((await db.backupAssetMap()).keys, ['asset-1']);
  });

  test('the phone copy of a backed-up file is found by file id', () async {
    await db.markAssetBackedUp('asset-1', 'p');
    await db.markAssetFailed('asset-2', 1);
    expect(await db.localAssetOf('p'), 'asset-1');
    expect(await db.localAssetOf('q'), isNull);
  });

  test('the phone copies of several files, only for finished backups', () async {
    await db.markAssetBackedUp('asset-1', 'p');
    // Backup matched a second photo to the same drive file.
    await db.markAssetBackedUp('asset-1b', 'p');
    await db.markAssetBackedUp('asset-2', 'q');
    await db.markAssetBackedUp('asset-3', 'not-asked');
    await db.into(db.backupAssets).insert(
      BackupAssetsCompanion.insert(
        assetId: 'asset-4',
        state: BackupAssetState.failed,
        fileId: const Value('r'),
        updatedAt: now,
      ),
    );

    final found = await db.localAssetsOf(['p', 'q', 'r', 'unknown']);
    expect(found.keys, unorderedEquals(['p', 'q']));
    expect(found['p'], unorderedEquals(['asset-1', 'asset-1b']));
    expect(found['q'], ['asset-2']);
    expect(await db.localAssetsOf(const []), isEmpty);
  });

  test('the phone copies of more files than SQLite takes in one statement', () async {
    await db.batch(
      (b) => b.insertAll(db.backupAssets, [
        for (var i = 0; i < 1200; i++)
          BackupAssetsCompanion.insert(
            assetId: 'asset-$i',
            state: BackupAssetState.done,
            fileId: Value('f$i'),
            updatedAt: now,
          ),
      ]),
    );

    final found = await db.localAssetsOf([for (var i = 0; i < 1200; i++) 'f$i']);
    expect(found, hasLength(1200));
    expect(found['f0'], ['asset-0']);
    expect(found['f1199'], ['asset-1199']);
  });

  test('complete files, everywhere or in given folders', () async {
    await db.upsertFilePart(file('root'), part('root', 0, 10));
    await db.upsertFilePart(file('in-a', folderId: 'a'), part('in-a', 0, 11));
    await db.upsertFilePart(file('in-b', folderId: 'b'), part('in-b', 0, 12));
    await db.upsertFilePart(file('half', folderId: 'a', partCount: 2), part('half', 0, 13));

    expect((await db.completeFiles()).map((f) => f.id), unorderedEquals(['root', 'in-a', 'in-b']));
    expect((await db.completeFiles(['a'])).map((f) => f.id), ['in-a']);
  });

  test('deleting more transfers than SQLite takes in one statement', () async {
    final rows = [
      for (var i = 0; i < 1200; i++)
        TransferRow(
          id: 't$i',
          kind: TransferKind.download,
          status: TransferStatus.queued,
          name: 'f$i',
          mimeType: 'application/octet-stream',
          fileId: 'f$i',
          ownsSource: false,
          totalBytes: 1,
          doneBytes: 0,
          partCount: 1,
          completedParts: 0,
          createdAt: now,
          origin: TransferOrigin.save,
          saveTo: SaveTarget.files,
          saveFolder: 'Work/Reports',
        ),
    ];
    await db.saveTransfers(rows);
    expect((await db.allTransfers()).first.saveFolder, 'Work/Reports');

    await db.deleteTransfers(rows.take(1100).map((r) => r.id));
    expect(await db.allTransfers(), hasLength(100));
  });

  group('trash', () {
    Future<void> trashFolder(String id, int messageId, {String? parentId}) =>
        db.upsertFolder(folder(id, messageId, parentId: parentId).copyWith(trashedAt: Value(now)));

    test('a trashed folder hides everything inside it, and only it is listed', () async {
      await db.upsertFolder(folder('docs', 1));
      await db.upsertFolder(folder('inner', 2, parentId: 'docs'));
      await db.upsertFilePart(file('a', folderId: 'inner'), part('a', 0, 10));
      await db.upsertFilePart(file('b'), part('b', 0, 11));

      await trashFolder('docs', 1);

      expect((await db.watchChildFolders(null).first).map((f) => f.id), isEmpty);
      expect((await db.watchRecent().first).map((f) => f.id), ['b']);
      expect((await db.watchTotals().first).single.count, 1);
      expect((await db.watchTrashedFolders().first).map((f) => f.id), ['docs']);
      expect(await db.watchTrashedFiles().first, isEmpty);
      expect(await db.completeFiles(), hasLength(1));

      // Restoring the folder brings its contents back.
      await db.upsertFolder(folder('docs', 1).copyWith(trashedAt: const Value(null)));
      expect((await db.watchRecent().first).map((f) => f.id), unorderedEquals(['a', 'b']));
      expect(await db.watchTrashedFolders().first, isEmpty);
    });

    test('a trashed file is listed unless its folder is trashed too', () async {
      await db.upsertFolder(folder('docs', 1));
      await db.upsertFilePart(
        file('a', folderId: 'docs').copyWith(trashedAt: Value(now)),
        part('a', 0, 10),
      );
      expect((await db.watchTrashedFiles().first).map((f) => f.id), ['a']);
      expect(await db.watchFilesIn('docs').first, isEmpty);

      await trashFolder('docs', 1);
      expect(await db.watchTrashedFiles().first, isEmpty);
      expect((await db.watchTrashedFolders().first).map((f) => f.id), ['docs']);
    });

    test('a file arriving inside a trashed folder is hidden straight away', () async {
      await trashFolder('docs', 1);
      await db.upsertFilePart(file('late', folderId: 'docs'), part('late', 0, 10));
      expect(await db.watchRecent().first, isEmpty);
    });

    test('every folder is watched, trashed ones too', () async {
      await db.upsertFolder(folder('pb', 1));
      await db.upsertFolder(folder('scr', 2, parentId: 'pb'));
      await trashFolder('old', 3);

      final all = await db.watchAllFolders().first;
      expect(all.map((f) => f.id), unorderedEquals(['pb', 'scr', 'old']));
      expect(all.firstWhere((f) => f.id == 'scr').parentId, 'pb');
    });

    test('trashed photos are not safe to delete from the phone', () async {
      await db.upsertFilePart(file('p'), part('p', 0, 10));
      await db.upsertFilePart(file('q').copyWith(trashedAt: Value(now)), part('q', 0, 11));
      await db.markAssetBackedUp('asset-p', 'p');
      await db.markAssetBackedUp('asset-q', 'q');
      expect(await db.safelyBackedUp(), {'asset-p': 100});
    });
  });

  test('albums count and cover their shown files', () async {
    await db.upsertAlbum(
      AlbumsCompanion.insert(id: 'al', name: 'Trip', messageId: 50, createdAt: now, modifiedAt: now),
    );
    await db.upsertFilePart(
      file('old').copyWith(takenAt: Value(DateTime(2020))),
      part('old', 0, 10),
    );
    await db.upsertFilePart(
      file('new').copyWith(takenAt: Value(DateTime(2024))),
      part('new', 0, 11),
    );
    await db.upsertFilePart(file('gone').copyWith(trashedAt: Value(now)), part('gone', 0, 12));
    for (final id in ['old', 'new', 'gone']) {
      await db.setFileAlbums(id, ['al']);
    }

    final album = (await db.watchAlbums().first).single;
    expect(album.album.name, 'Trip');
    expect(album.count, 2);
    expect(album.coverFileId, 'new');
    expect((await db.watchAlbumFiles('al').first).map((f) => f.id), ['new', 'old']);

    await db.setFileAlbums('new', []);
    expect((await db.watchAlbums().first).single.count, 1);

    await db.removeMessages([50]);
    expect(await db.watchAlbums().first, isEmpty);
  });

  test('search finds recognised content and dates', () async {
    await db.upsertFilePart(
      file('receipt').copyWith(takenAt: Value(DateTime(2024, 3, 5))),
      part('receipt', 0, 10),
    );
    await db.upsertFilePart(file('other'), part('other', 0, 11));
    await db.saveContent('receipt', 'total due 42 birr · receipt · paper', 1);

    expect((await db.watchSearch('birr').first).map((f) => f.id), ['receipt']);
    final march = (DateTime(2024, 3), DateTime(2024, 4));
    expect((await db.watchSearch('march', range: march).first).map((f) => f.id), ['receipt']);
    expect(await db.indexedFileIds(1), {'receipt'});
    expect(await db.indexedFileIds(2), isEmpty);
  });

  test('offline pins and copies', () async {
    await db.pinOffline('docs', isFolder: true);
    await db.saveOfflineCopy('a', '/x/a.pdf', 10);
    expect(await db.watchOfflinePins().first, {'docs'});
    expect(await db.watchOfflineCopies().first, {'a': '/x/a.pdf'});
    await db.unpinOffline('docs');
    await db.deleteOfflineCopy('a');
    expect(await db.offlinePinList(), isEmpty);
    expect(await db.offlineCopyList(), isEmpty);
  });
}
