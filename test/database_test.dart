import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:telegrive/core/files/file_kind.dart';
import 'package:telegrive/features/drive/data/message_indexer.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';

import 'generated_migrations/schema.dart';
import 'support/fake_telegram.dart';

void main() {
  late AppDatabase db;
  final now = DateTime(2026, 9, 25);

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  /// The photos safe to delete from the phone, each with its drive copy's
  /// size.
  Future<Map<String, int>> safeSizes() async =>
      (await db.safelyBackedUp()).map((id, row) => MapEntry(id, row.size));

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

  test('a file is adopted until its message carries a manifest', () async {
    await db.upsertFilePart(
      file('tg10').copyWith(adopted: const Value(true)),
      part('tg10', 0, 10),
    );
    expect((await db.fileById('tg10'))!.adopted, isTrue);

    // Keep here writes a manifest onto the same message, under the same id.
    await db.upsertFilePart(
      file('tg10').copyWith(adopted: const Value(false)),
      part('tg10', 0, 10),
    );
    expect((await db.fileById('tg10'))!.adopted, isFalse);
  });

  test('a one-off read of a folder shows what watching it does', () async {
    await db.upsertFolder(folder('docs', 1));
    await db.upsertFilePart(file('a', folderId: 'docs'), part('a', 0, 10));
    await db.upsertFilePart(file('b'), part('b', 0, 11));
    await db.upsertFilePart(
      file('lost', folderId: 'gone'),
      part('lost', 0, 12),
    );
    await db.upsertFilePart(
      file('half', partCount: 2, folderId: 'docs'),
      part('half', 0, 13),
    );
    await db.upsertFilePart(
      file('binned', folderId: 'docs').copyWith(trashedAt: Value(now)),
      part('binned', 0, 14),
    );
    await db.upsertFolder(folder('bin', 2).copyWith(trashedAt: Value(now)));
    await db.upsertFilePart(
      file('inside', folderId: 'bin'),
      part('inside', 0, 15),
    );

    for (final folderId in ['docs', 'bin', null]) {
      expect(
        (await db.filesIn(folderId)).map((f) => f.id),
        (await db.watchFilesIn(folderId).first).map((f) => f.id),
      );
    }
    expect((await db.filesIn('docs')).map((f) => f.id), ['a']);
    expect(await db.filesIn('bin'), isEmpty);
    expect(
      (await db.filesIn(null)).map((f) => f.id),
      unorderedEquals(['b', 'lost']),
    );
  });

  test('items whose folder is gone surface at the root', () async {
    await db.upsertFolder(folder('docs', 1));
    await db.upsertFolder(folder('inner', 2, parentId: 'docs'));
    await db.upsertFilePart(file('a', folderId: 'docs'), part('a', 0, 10));

    expect(await db.watchFilesIn(null).first, isEmpty);
    expect((await db.watchChildFolders(null).first).map((f) => f.id), ['docs']);

    await db.removeMessages([1]); // the "docs" folder message is deleted

    expect((await db.watchFilesIn(null).first).single.id, 'a');
    expect((await db.watchChildFolders(null).first).map((f) => f.id), [
      'inner',
    ]);
  });

  test(
    'opens follow their file, outlast a rebuilt index and go on sign-out',
    () async {
      await db.upsertFilePart(file('a'), part('a', 0, 10));
      await db.upsertFilePart(file('b'), part('b', 0, 11));
      for (final id in ['a', 'b']) {
        await db
            .into(db.fileOpens)
            .insert(FileOpensCompanion.insert(fileId: id, openedAt: now));
      }
      Future<List<String>> opened() async => [
        for (final row in await db.select(db.fileOpens).get()) row.fileId,
      ];

      await db.removeMessages([10]);
      expect(await opened(), ['b']);

      await db.clearIndex();
      expect(await opened(), ['b']);

      await db.clearAll();
      expect(await opened(), isEmpty);
    },
  );

  test('play positions outlast a rebuilt index and go on sign-out', () async {
    await db.upsertFilePart(file('a'), part('a', 0, 10));
    await db
        .into(db.playPositions)
        .insert(
          PlayPositionsCompanion.insert(
            fileId: 'a',
            positionMs: 42 * 60 * 1000,
            durationMs: 90 * 60 * 1000,
            updatedAt: now,
          ),
        );
    Future<List<PlayPositionRow>> positions() =>
        db.select(db.playPositions).get();

    expect((await positions()).single.positionMs, 42 * 60 * 1000);

    await db.clearIndex();
    expect(await positions(), hasLength(1));

    await db.clearAll();
    expect(await positions(), isEmpty);
  });

  test('watched folders outlast a rebuilt index and go on sign-out', () async {
    await db
        .into(db.watchedFolders)
        .insert(
          WatchedFoldersCompanion.insert(
            id: 'bank',
            treeUri:
                'content://com.android.externalstorage.documents/tree/'
                'primary%3ADownload%2FBank',
            label: 'Bank',
            filter: WatchFilter.documents,
            createdAt: now,
          ),
        );
    await db
        .into(db.watchedFiles)
        .insert(
          WatchedFilesCompanion.insert(
            ruleId: 'bank',
            documentId: 'primary:Download/Bank/statement.pdf',
            size: 3,
            modifiedAt: now,
            state: WatchedFileState.done,
            fileId: const Value('a'),
            updatedAt: now,
          ),
        );
    Future<List<WatchedFolderRow>> rules() =>
        db.select(db.watchedFolders).get();
    Future<List<WatchedFileRow>> ledger() => db.select(db.watchedFiles).get();

    final rule = (await rules()).single;
    expect(rule.filter, WatchFilter.documents);
    expect(rule.subfolders, isTrue);
    expect(rule.destinationId, isNull);
    expect(rule.checkedAt, isNull);
    final entry = (await ledger()).single;
    expect(entry.state, WatchedFileState.done);
    expect(entry.fileId, 'a');
    expect(entry.transferId, isNull);
    expect(entry.failures, 0);

    await db.clearIndex();
    expect(await rules(), hasLength(1));
    expect(await ledger(), hasLength(1));

    await db.clearAll();
    expect(await rules(), isEmpty);
    expect(await ledger(), isEmpty);
  });

  WatchedFoldersCompanion watchedFolder(String id, {required DateTime createdAt}) =>
      WatchedFoldersCompanion.insert(
        id: id,
        treeUri: 'content://com.android.externalstorage.documents/tree/primary%3A$id',
        label: id,
        filter: WatchFilter.documents,
        createdAt: createdAt,
      );

  WatchedFilesCompanion watchedFile(String ruleId, String documentId, WatchedFileState state) =>
      WatchedFilesCompanion.insert(
        ruleId: ruleId,
        documentId: documentId,
        size: 3,
        modifiedAt: now,
        state: state,
        updatedAt: now,
      );

  test('watched folders keep a ledger and lose it with the folder', () async {
    await db.saveWatchedFolder(watchedFolder('Recordings', createdAt: now));
    await db.saveWatchedFolder(
      watchedFolder('Bank', createdAt: now.subtract(const Duration(days: 1))),
    );
    await db.saveWatchedFiles([
      watchedFile('Bank', 'statement.pdf', WatchedFileState.pending),
      watchedFile('Bank', 'lease.pdf', WatchedFileState.skipped),
      watchedFile('Recordings', 'memo.m4a', WatchedFileState.done),
    ]);

    // Oldest first, in the stream and in the one-off read alike.
    expect([for (final rule in await db.watchWatchedFolders().first) rule.id], [
      'Bank',
      'Recordings',
    ]);
    expect([for (final rule in await db.watchedFolderList()) rule.id], ['Bank', 'Recordings']);

    // Saving a ledger row again replaces it.
    await db.saveWatchedFiles([watchedFile('Bank', 'statement.pdf', WatchedFileState.done)]);
    final ledger = await db.watchedLedger('Bank');
    expect(ledger.keys, unorderedEquals(['statement.pdf', 'lease.pdf']));
    expect(ledger['statement.pdf']!.state, WatchedFileState.done);

    // A change writes only the fields it holds, and so does saving the row
    // again.
    await db.updateWatchedFolder(
      'Bank',
      WatchedFoldersCompanion(checkedAt: Value(now), destinationId: const Value('auto-bank')),
    );
    var bank = (await db.watchedFolderList()).first;
    expect(bank.checkedAt, now);
    expect(bank.destinationId, 'auto-bank');
    expect(bank.filter, WatchFilter.documents);
    await db.saveWatchedFolder(
      watchedFolder(
        'Bank',
        createdAt: bank.createdAt,
      ).copyWith(filter: const Value(WatchFilter.everything)),
    );
    bank = (await db.watchedFolderList()).first;
    expect(bank.filter, WatchFilter.everything);
    expect(bank.checkedAt, now);

    await db.deleteWatchedFolder('Bank');
    expect([for (final rule in await db.watchedFolderList()) rule.id], ['Recordings']);
    expect(await db.watchedLedger('Bank'), isEmpty);
    expect((await db.watchedLedger('Recordings')).keys, ['memo.m4a']);
  });

  test('uploaded counts per folder', () async {
    await db.saveWatchedFolder(watchedFolder('Bank', createdAt: now));
    await db.saveWatchedFolder(watchedFolder('Recordings', createdAt: now));
    final counts = db.watchUploadedCounts();
    expect(await counts.first, isEmpty);

    await db.saveWatchedFiles([
      watchedFile('Bank', 'a.pdf', WatchedFileState.done),
      watchedFile('Bank', 'b.pdf', WatchedFileState.done),
      watchedFile('Bank', 'c.pdf', WatchedFileState.pending),
      watchedFile('Bank', 'd.pdf', WatchedFileState.failed),
      watchedFile('Recordings', 'memo.m4a', WatchedFileState.done),
      watchedFile('Recordings', 'old.m4a', WatchedFileState.skipped),
    ]);
    expect(await counts.first, {'Bank': 2, 'Recordings': 1});

    await db.deleteWatchedFolder('Recordings');
    expect(await counts.first, {'Bank': 2});
  });

  test('waiting changes outlast a rebuilt index and go on sign-out', () async {
    await db.upsertFilePart(file('a'), part('a', 0, 10));
    // A file and an album may share an id: the target tells them apart.
    await db
        .into(db.pendingEdits)
        .insert(
          PendingEditsCompanion.insert(
            target: EditTarget.file,
            itemId: 'a',
            patch: '{"n":{"b":"a.bin","w":"Lease.pdf"}}',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db
        .into(db.pendingEdits)
        .insert(
          PendingEditsCompanion.insert(
            target: EditTarget.album,
            itemId: 'a',
            patch: '{"n":{"b":"Trip","w":"Lalibela 2026"}}',
            createdAt: now,
            updatedAt: now,
            attempts: const Value(2),
            lastError: const Value('Telegram took too long to answer.'),
          ),
        );
    Future<List<PendingEditRow>> waiting() => db.select(db.pendingEdits).get();

    final rows = await waiting();
    expect(
      rows.map((r) => r.target),
      unorderedEquals([EditTarget.file, EditTarget.album]),
    );
    final rename = rows.singleWhere((r) => r.target == EditTarget.file);
    expect(rename.attempts, 0);
    expect(rename.lastError, isNull);

    await db.clearIndex();
    expect(await waiting(), hasLength(2));

    await db.clearAll();
    expect(await waiting(), isEmpty);
  });

  group('waiting changes', () {
    PendingEditsCompanion change(
      EditTarget target,
      String id, {
      required DateTime at,
      String patch = '{"st":{"b":false,"w":true}}',
    }) => PendingEditsCompanion.insert(
      target: target,
      itemId: id,
      patch: patch,
      createdAt: at,
      updatedAt: at,
    );

    test('are saved, read back, replaced and deleted one by one', () async {
      await db.savePendingEdit(change(EditTarget.file, 'a', at: now));
      expect((await db.pendingEditOf(EditTarget.file, 'a'))!.patch, contains('"st"'));
      expect(await db.pendingEditOf(EditTarget.folder, 'a'), isNull);

      // Saving again replaces the patch rather than adding a second row.
      await db.savePendingEdit(
        change(EditTarget.file, 'a', at: now, patch: '{"n":{"b":"a","w":"b"}}'),
      );
      expect(await db.pendingEditList(), hasLength(1));
      expect((await db.pendingEditOf(EditTarget.file, 'a'))!.patch, contains('"n"'));

      await db.deletePendingEdit(EditTarget.file, 'a');
      expect(await db.pendingEditOf(EditTarget.file, 'a'), isNull);
    });

    test('are listed the one made first first, and watched by id', () async {
      final ids = db.watchPendingItemIds();
      await db.savePendingEdit(
        change(EditTarget.album, 'late', at: now.add(const Duration(minutes: 2))),
      );
      await db.savePendingEdit(change(EditTarget.file, 'early', at: now));
      await db.savePendingEdit(
        change(EditTarget.folder, 'middle', at: now.add(const Duration(minutes: 1))),
      );

      expect([for (final row in await db.pendingEditList()) row.itemId], [
        'early',
        'middle',
        'late',
      ]);
      expect([for (final row in await db.watchPendingEdits().first) row.itemId], [
        'early',
        'middle',
        'late',
      ]);
      expect(await db.pendingEditIds(), {'early', 'middle', 'late'});
      expect(await ids.first, {'early', 'middle', 'late'});
    });

    test('made within the same second keep the order they were made in', () async {
      await db.savePendingEdit(change(EditTarget.file, 'first', at: now));
      await db.savePendingEdit(change(EditTarget.file, 'second', at: now));
      // A later edit of the first one leaves it first.
      await db.savePendingEdit(
        change(EditTarget.file, 'first', at: now, patch: '{"n":{"b":"a","w":"b"}}'),
      );

      expect([for (final row in await db.pendingEditList()) row.itemId], ['first', 'second']);
    });

    test('of files and folders deleted for good go with them, albums stay', () async {
      await db.savePendingEdit(change(EditTarget.file, 'a', at: now));
      await db.savePendingEdit(change(EditTarget.folder, 'b', at: now));
      await db.savePendingEdit(change(EditTarget.album, 'a', at: now));
      await db.savePendingEdit(change(EditTarget.file, 'c', at: now));

      await db.deletePendingEditsFor(['a', 'b']);

      expect(
        [for (final row in await db.pendingEditList()) (row.target, row.itemId)],
        unorderedEquals([(EditTarget.album, 'a'), (EditTarget.file, 'c')]),
      );
    });

    test('count failed tries and get them back on Try again', () async {
      await db.savePendingEdit(change(EditTarget.file, 'a', at: now));
      await db.failPendingEdit(EditTarget.file, 'a', 'Telegram won\'t let this file be changed.');
      await db.failPendingEdit(EditTarget.file, 'a', 'Nothing changed.');

      var row = (await db.pendingEditOf(EditTarget.file, 'a'))!;
      expect(row.attempts, 2);
      expect(row.lastError, 'Nothing changed.');
      expect(row.patch, contains('"st"'));

      await db.retryPendingEdits();
      row = (await db.pendingEditOf(EditTarget.file, 'a'))!;
      expect(row.attempts, 0);
      expect(row.lastError, isNull);
    });
  });

  test(
    'a photo with only a small copy in the drive is never safe to free',
    () async {
      await db.upsertFilePart(file('p'), part('p', 0, 1));
      await db.updateFile(
        'p',
        const DriveFilesCompanion(originalSize: Value(6100000)),
      );
      await db
          .into(db.backupAssets)
          .insert(
            BackupAssetsCompanion.insert(
              assetId: 'asset-1',
              state: BackupAssetState.smallCopy,
              fileId: const Value('p'),
              updatedAt: now,
            ),
          );

      expect((await db.fileById('p'))!.originalSize, 6100000);
      expect(await db.safelyBackedUp(), isEmpty);
      expect(await db.localAssetsOf(['p']), isEmpty);
      expect(await db.watchBackedUpCount().first, 0);

      await db.markAssetBackedUp('asset-1', 'p');
      await db.updateFile(
        'p',
        const DriveFilesCompanion(originalSize: Value(null)),
      );
      expect(await safeSizes(), {'asset-1': 100});
      expect(await db.localAssetsOf(['p']), {
        'p': ['asset-1'],
      });
      expect(await db.watchBackedUpCount().first, 1);
    },
  );

  group('small copies', () {
    /// What the indexer makes of [message], written into the index.
    Future<void> index(td.Message message) async {
      final entry = MessageIndexer.entryFor(message)! as FilePartEntry;
      await db.upsertFilePart(entry.file, entry.part);
    }

    /// The small copy of IMG_1.HEIC, a 312 KB JPEG standing for a 6.1 MB
    /// original, in message 7.
    final small = documentMessage(
      7,
      'tgfile2;id=p;name=IMG_1.HEIC;type=image/jpeg;size=312000;original=6100000;'
      'added=1700000000000',
      fileName: 'IMG_1.HEIC',
      mimeType: 'image/jpeg',
      size: 312000,
    );

    test('a small copy is indexed with its original\'s size', () async {
      await index(small);
      final row = (await db.fileById('p'))!;
      expect(row.size, 312000);
      expect(row.originalSize, 6100000);
      expect(row.manifestExtra, isNull);
    });

    test('the original arriving in the same message clears the mark and keeps the file', () async {
      await index(small);
      final content = small.content as td.MessageDocument;
      await index(
        small.copyWith(
          content: content.copyWith(
            document: content.document.copyWith(document: tdFile(9, size: 6100000)),
            caption: const td.FormattedText(
              text: 'tgfile2;id=p;name=IMG_1.HEIC;type=image/heic;size=6100000;'
                  'added=1700000000000',
              entities: [],
            ),
          ),
        ),
      );
      final row = (await db.fileById('p'))!;
      expect(row.originalSize, isNull);
      expect(row.size, 6100000);
      expect(row.mimeType, 'image/heic');
      final part = (await db.partsOf('p')).single;
      expect(part.messageId, 7);
      expect(part.tdFileId, 9);
      expect(part.size, 6100000);
    });

    test('backup knows a small copy by its original\'s size', () async {
      await index(small);
      expect(await db.mediaFingerprints(), {
        'IMG_1.HEIC|6100000': (fileId: 'p', smallCopy: true),
      });
    });

    test('a photo with only a small copy is on the phone but never freeable', () async {
      await index(small);
      await db.markAssetSmallCopy('asset-1', 'p');
      expect((await db.backupAssetMap())['asset-1']!.state, BackupAssetState.smallCopy);
      expect(await db.safelyBackedUp(), isEmpty);
      expect(await db.watchLocalAssets().first, {'p': 'asset-1'});
      expect(await db.localAssetOf('p'), 'asset-1');
    });

    test('a small copy starts its original with fresh tries', () async {
      await db.markAssetFailed('asset-1', 2, reason: 'Telegram took too long to answer.');
      await db.markAssetSmallCopy('asset-1', 'p');
      final record = (await db.backupAssetMap())['asset-1']!;
      expect(record.failures, 0);
      expect(record.reason, isNull);
      expect(record.fileId, 'p');
    });

    test('the originals still to send are this phone\'s small copies only', () async {
      await index(small);
      await db.markAssetSmallCopy('asset-1', 'p');
      // Another phone's small copy, which this one has no original of.
      await index(
        documentMessage(
          8,
          'tgfile2;id=q;name=IMG_2.HEIC;type=image/jpeg;size=290000;original=5000000;'
          'added=1700000000000',
          size: 290000,
        ),
      );
      // A small copy of this phone's that is in the trash.
      await index(
        documentMessage(
          9,
          'tgfile2;id=r;name=IMG_3.HEIC;type=image/jpeg;size=300000;'
          'trashed=1700000000000;original=4000000;added=1700000000000',
          size: 300000,
        ),
      );
      await db.markAssetSmallCopy('asset-3', 'r');
      expect(await db.watchPendingOriginals().first, (count: 1, bytes: 6100000));

      await db.markAssetBackedUp('asset-1', 'p');
      expect(await db.watchPendingOriginals().first, (count: 0, bytes: 0));
    });
  });

  test(
    'a length learned on this phone survives a caption without one',
    () async {
      await db.upsertFilePart(file('clip'), part('clip', 0, 10));
      await db.updateFile(
        'clip',
        const DriveFilesCompanion(durationSeconds: Value(84)),
      );
      expect(
        (await db.watchMediaLite().first),
        isEmpty,
        reason: 'not a media kind',
      );
      expect((await db.fileById('clip'))!.durationSeconds, 84);

      // The indexer leaves the column alone when the caption carries no du.
      await db.upsertFilePart(file('clip'), part('clip', 0, 10));
      expect((await db.fileById('clip'))!.durationSeconds, 84);

      await db.upsertFilePart(
        file('clip').copyWith(durationSeconds: const Value(90)),
        part('clip', 0, 10),
      );
      expect((await db.fileById('clip'))!.durationSeconds, 90);
    },
  );

  test('opens are remembered, pruned and follow the file', () async {
    await db.upsertFilePart(file('a'), part('a', 0, 10));
    await db.upsertFilePart(file('b'), part('b', 0, 11));
    await db.upsertFilePart(
      file('c').copyWith(takenAt: Value(DateTime(2026, 9, 20))),
      part('c', 0, 12),
    );
    expect(db.schemaVersion, 14);

    await db.recordOpen('a');
    expect((await db.watchRecentOpens().first).map((o) => o.$1.id), ['a']);

    // Camera-roll backups are the only files with a capture time.
    expect(
      (await db.watchRecent(excludeCameraRoll: true).first).map((f) => f.id),
      unorderedEquals(['a', 'b']),
    );
    expect(
      (await db.watchRecent().first).map((f) => f.id),
      unorderedEquals(['a', 'b', 'c']),
    );

    // A trashed file is not shown as opened.
    await db.updateFile('a', const DriveFilesCompanion(hidden: Value(true)));
    expect(await db.watchRecentOpens().first, isEmpty);
    await db.updateFile('a', const DriveFilesCompanion(hidden: Value(false)));

    await db.removeMessages([10]);
    expect(await db.watchRecentOpens().first, isEmpty);
    expect(await db.select(db.fileOpens).get(), isEmpty);

    // A full history drops the oldest open to make room for a new one.
    final earlier = DateTime.now().subtract(const Duration(days: 1));
    await db.batch(
      (b) => b.insertAll(db.fileOpens, [
        for (var i = 0; i < AppDatabase.keptOpens; i++)
          FileOpensCompanion.insert(
            fileId: 'old-$i',
            openedAt: earlier.subtract(Duration(minutes: i)),
          ),
      ]),
    );
    await db.recordOpen('b');
    final kept = {
      for (final row in await db.select(db.fileOpens).get()) row.fileId,
    };
    expect(kept, hasLength(AppDatabase.keptOpens));
    expect(kept, contains('b'));
    expect(kept, contains('old-0'));
    expect(kept, isNot(contains('old-${AppDatabase.keptOpens - 1}')));
    expect((await db.watchRecentOpens().first).map((o) => o.$1.id), ['b']);
  });

  test('files sent together are remembered in one update', () async {
    for (final (i, id) in ['a', 'b', 'c'].indexed) {
      await db.upsertFilePart(file(id), part(id, 0, 10 + i));
    }
    final seen = <Set<String>>[];
    final watching = db.watchRecentOpens().listen(
      (opens) => seen.add({for (final (row, _) in opens) row.id}),
    );
    addTearDown(watching.cancel);
    Future<void> settle() =>
        Future<void>.delayed(const Duration(milliseconds: 20));
    await settle();

    await db.recordOpens(['a', 'b', 'c']);
    await settle();
    expect(seen, [
      <String>{},
      {'a', 'b', 'c'},
    ]);
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

  test(
    'the photo timeline orders by capture time, falling back to upload',
    () async {
      DriveFilesCompanion media(
        String id,
        FileKind kind, {
        DateTime? taken,
        required DateTime added,
        String? mini,
      }) => DriveFilesCompanion.insert(
        id: id,
        name: '$id.jpg',
        mimeType: 'image/jpeg',
        kind: kind,
        size: 100,
        createdAt: added,
        modifiedAt: added,
        takenAt: Value(taken),
        minithumbnail: Value(mini),
        thumbnailFileId: const Value(9),
        durationSeconds: Value(kind == FileKind.video ? 12 : null),
      );

      await db.upsertFilePart(
        media(
          'old-photo',
          FileKind.image,
          taken: DateTime(2019),
          added: DateTime(2026, 9),
          mini: 'AQID',
        ),
        part('old-photo', 0, 1),
      );
      await db.upsertFilePart(
        media('new-upload', FileKind.image, added: DateTime(2026, 8)),
        part('new-upload', 0, 2),
      );
      await db.upsertFilePart(
        media(
          'clip',
          FileKind.video,
          taken: DateTime(2026, 9, 20),
          added: DateTime(2026, 9),
        ),
        part('clip', 0, 3),
      );
      await db.upsertFilePart(file('report'), part('report', 0, 4));

      final timeline = await db.watchMediaLite().first;
      expect(timeline.map((f) => f.row.id), [
        'clip',
        'new-upload',
        'old-photo',
      ]);
      // Every column but the preview comes back as stored.
      for (final lite in timeline) {
        final full = (await db.fileById(lite.row.id))!;
        expect(lite.row, full.copyWith(minithumbnail: const Value(null)));
        expect(lite.hasMinithumbnail, full.minithumbnail != null);
      }
      expect(timeline.last.hasMinithumbnail, isTrue);
      expect(await db.minithumbnailOf('old-photo'), 'AQID');
      expect(await db.minithumbnailOf('new-upload'), isNull);
    },
  );

  test(
    'lite album and kind lists hold the files the album and kind hold',
    () async {
      await db.upsertAlbum(
        AlbumsCompanion.insert(
          id: 'al',
          name: 'Trip',
          messageId: 50,
          createdAt: now,
          modifiedAt: now,
        ),
      );
      DriveFilesCompanion photo(
        String id, {
        required DateTime added,
        DateTime? taken,
      }) => file(id).copyWith(
        kind: const Value(FileKind.image),
        createdAt: Value(added),
        takenAt: Value(taken),
        minithumbnail: const Value('AQID'),
      );
      await db.upsertFilePart(
        photo('old', added: DateTime(2026, 9), taken: DateTime(2020)),
        part('old', 0, 10),
      );
      await db.upsertFilePart(
        photo('new', added: DateTime(2026, 8)),
        part('new', 0, 11),
      );
      await db.upsertFilePart(
        photo('gone', added: DateTime(2026, 7)).copyWith(trashedAt: Value(now)),
        part('gone', 0, 12),
      );
      // Half of a split photo isn't shown until its other part arrives.
      await db.upsertFilePart(
        photo(
          'half',
          added: DateTime(2026, 6),
        ).copyWith(partCount: const Value(2)),
        part('half', 0, 13),
      );
      await db.upsertFilePart(
        photo('outside', added: DateTime(2026, 5)),
        part('outside', 0, 14),
      );
      await db.upsertFilePart(file('notes'), part('notes', 0, 15));
      for (final id in ['old', 'new', 'gone', 'half', 'notes']) {
        await db.setFileAlbums(id, ['al']);
      }

      final album = await db.watchAlbumFilesLite('al').first;
      expect(album.map((f) => f.row.id), ['notes', 'new', 'old']);
      expect(
        album.map((f) => f.row.id),
        (await db.watchAlbumFiles('al').first).map((f) => f.id),
      );
      expect(album.map((f) => f.hasMinithumbnail), [false, true, true]);
      expect(album.every((f) => f.row.minithumbnail == null), isTrue);

      final images = await db.watchKindLite(FileKind.image).first;
      expect(images.map((f) => f.row.id), ['old', 'new', 'outside']);

      // Membership is read too, so leaving the album updates the list.
      final counts = <int>[];
      final subscription = db
          .watchAlbumFilesLite('al')
          .listen((rows) => counts.add(rows.length));
      addTearDown(subscription.cancel);
      while (counts.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await db.setFileAlbums('old', []);
      while (counts.length < 2) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(counts, [3, 2]);
    },
  );

  test(
    'media thumbnails come newest first, for shown photos and videos',
    () async {
      DriveFilesCompanion media(
        String id,
        FileKind kind, {
        int? thumbnail,
        DateTime? taken,
        DateTime? added,
        int partCount = 1,
      }) => DriveFilesCompanion.insert(
        id: id,
        name: '$id.bin',
        mimeType: 'application/octet-stream',
        kind: kind,
        size: 100,
        createdAt: added ?? now,
        modifiedAt: now,
        takenAt: Value(taken),
        thumbnailFileId: Value(thumbnail),
        partCount: Value(partCount),
      );

      await db.upsertFilePart(
        media('old', FileKind.image, thumbnail: 11, taken: DateTime(2019)),
        part('old', 0, 1),
      );
      await db.upsertFilePart(
        media(
          'clip',
          FileKind.video,
          thumbnail: 12,
          taken: DateTime(2026, 9, 20),
        ),
        part('clip', 0, 2),
      );
      await db.upsertFilePart(
        media(
          'upload',
          FileKind.image,
          thumbnail: 13,
          added: DateTime(2026, 8),
        ),
        part('upload', 0, 3),
      );
      // No thumbnail, not a photo or video, in the trash, or still arriving.
      await db.upsertFilePart(
        media('bare', FileKind.image),
        part('bare', 0, 4),
      );
      await db.upsertFilePart(
        media('report', FileKind.document, thumbnail: 15),
        part('report', 0, 5),
      );
      await db.upsertFilePart(
        media(
          'binned',
          FileKind.image,
          thumbnail: 16,
        ).copyWith(trashedAt: Value(now)),
        part('binned', 0, 6),
      );
      await db.upsertFilePart(
        media('half', FileKind.video, thumbnail: 17, partCount: 2),
        part('half', 0, 7),
      );

      expect(await db.mediaThumbnails(), [
        (fileId: 'clip', thumbnailFileId: 12),
        (fileId: 'upload', thumbnailFileId: 13),
        (fileId: 'old', thumbnailFileId: 11),
      ]);
    },
  );

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
    expect(await db.mediaFingerprints(), {
      'IMG_1.jpg|4242': (fileId: 'p', smallCopy: false),
    });

    await db.markAssetBackedUp('asset-1', 'p');
    await db.markAssetFailed('asset-2', 2);
    final records = await db.backupAssetMap();
    expect(records['asset-1']!.state, BackupAssetState.done);
    expect(records['asset-2']!.failures, 2);
    expect(await db.watchBackedUpCount().first, 1);
    expect(await db.watchLocalAssets().first, {'p': 'asset-1'});

    await db.clearBackupFailures();
    expect((await db.backupAssetMap()).keys, ['asset-1']);

    // Photos out of tries are listed with the reason, and can be skipped.
    await db.markAssetFailed(
      'asset-2',
      3,
      reason: 'Telegram took too long to answer.',
    );
    await db.markAssetFailed(
      'asset-3',
      2,
      reason: 'Couldn\'t start the upload.',
    );
    await db.markAssetFailed('asset-4', 4);

    final failed = await db.watchFailedAssets(minFailures: 3).first;
    expect(
      failed.map((r) => r.assetId),
      unorderedEquals(['asset-2', 'asset-4']),
    );
    expect(
      failed.singleWhere((r) => r.assetId == 'asset-2').reason,
      'Telegram took too long to answer.',
    );

    expect(await db.markAssetSkipped('asset-2'), 1);
    expect(await db.markAssetSkipped('asset-2'), 0);
    expect(await db.markAssetSkipped('asset-1'), 0);
    expect(
      (await db.watchFailedAssets(minFailures: 3).first).map((r) => r.assetId),
      ['asset-4'],
    );
    expect(await db.watchSkippedAssetIds().first, ['asset-2']);
    final skipped = (await db.backupAssetOf('asset-2'))!;
    expect(skipped.state, BackupAssetState.skipped);
    expect(skipped.failures, 3);
    expect(skipped.reason, 'Telegram took too long to answer.');
    expect(await db.backupAssetOf('asset-9'), isNull);

    // Undo puts a skipped photo back among the failed ones, once, and
    // leaves any other record alone.
    expect(await db.unmarkAssetSkipped('asset-2'), 1);
    expect(await db.unmarkAssetSkipped('asset-2'), 0);
    expect(await db.unmarkAssetSkipped('asset-1'), 0);
    final back = (await db.backupAssetOf('asset-2'))!;
    expect(
      (back.state, back.failures, back.reason),
      (BackupAssetState.failed, 3, 'Telegram took too long to answer.'),
    );
    expect((await db.backupAssetOf('asset-1'))?.state, BackupAssetState.done);
    expect(await db.markAssetSkipped('asset-2'), 1);

    // Retrying one forgets that photo's failures and no other row.
    expect(await db.clearBackupFailure('asset-4'), 1);
    expect(await db.clearBackupFailure('asset-4'), 0);
    expect(await db.clearBackupFailure('asset-1'), 0);
    expect(
      (await db.backupAssetMap()).keys,
      unorderedEquals(['asset-1', 'asset-2', 'asset-3']),
    );

    await db.clearSkipped();
    expect(await db.watchSkippedAssetIds().first, isEmpty);
    expect(
      (await db.backupAssetMap()).keys,
      unorderedEquals(['asset-1', 'asset-3']),
    );
    expect(await db.watchBackedUpCount().first, 1);
    expect(await db.watchLocalAssets().first, {'p': 'asset-1'});
    expect(await safeSizes(), {'asset-1': 4242});
  });

  test('backed-up photos whose file left the drive are found', () async {
    // Four photos went up: one is still there, one is in the trash, one
    // lost a part of its split file, and one's file is gone altogether. A
    // fifth record never pointed at a file.
    await db.upsertFilePart(file('kept'), part('kept', 0, 1));
    await db.upsertFilePart(file('binned'), part('binned', 0, 2));
    await db.updateFile('binned', DriveFilesCompanion(trashedAt: Value(now)));
    await db.refreshHidden();
    await db.upsertFilePart(file('split', partCount: 2), part('split', 0, 3));
    await db.upsertFilePart(file('split', partCount: 2), part('split', 1, 4));
    await db.removeMessages([4]);
    await db.markAssetBackedUp('a-kept', 'kept');
    await db.markAssetBackedUp('a-binned', 'binned');
    await db.markAssetBackedUp('a-split', 'split');
    await db.markAssetBackedUp('a-gone', 'gone');
    await db.markAssetBackedUp('a-none', null);

    expect(await db.backedUpButMissing(), unorderedEquals(['a-split', 'a-gone']));
    expect(await db.countBackedUpWithFile(), 4);

    await db.markAssetsMissing(['a-split', 'a-gone']);
    expect(await db.watchMissingCount().first, 2);
    expect(await db.countBackedUpWithFile(), 2);
    expect(await db.backedUpButMissing(), isEmpty);
    expect((await db.backupAssetOf('a-gone'))!.fileId, isNull);
    expect(await db.watchBackedUpCount().first, 3);

    // Leaving them out keeps the records as removed; backing up again
    // forgets only the missing ones.
    await db.markAssetsMissing(['a-kept']);
    await db.leaveOutMissing();
    expect(await db.watchMissingCount().first, 0);
    expect((await db.backupAssetOf('a-gone'))!.state, BackupAssetState.removed);
    await db.markAssetsMissing(['a-binned']);
    await db.backUpMissingAgain();
    expect(await db.backupAssetOf('a-binned'), isNull);
    expect(
      (await db.backupAssetMap()).keys,
      unorderedEquals(['a-kept', 'a-split', 'a-gone', 'a-none']),
    );
  });

  test('deleting a file for good marks its backup record removed', () async {
    await db.upsertFilePart(file('p'), part('p', 0, 1));
    await db.upsertFilePart(file('q'), part('q', 0, 2));
    await db.markAssetBackedUp('a-p', 'p');
    await db.markAssetBackedUp('a-q', 'q');

    await db.markFilesRemoved(['p']);
    expect((await db.backupAssetOf('a-p'))!.state, BackupAssetState.removed);
    expect((await db.backupAssetOf('a-q'))!.state, BackupAssetState.done);
    // Gone from the drive on purpose, so it isn't a gap.
    await db.removeMessages([1]);
    expect(await db.backedUpButMissing(), isEmpty);
  });

  test('split files missing a part are listed by name, trash left out', () async {
    await db.upsertFilePart(file('b', partCount: 3), part('b', 0, 10));
    await db.upsertFilePart(file('b', partCount: 3), part('b', 2, 12));
    await db.upsertFilePart(file('a', partCount: 2), part('a', 0, 20));
    await db.upsertFilePart(file('whole', partCount: 2), part('whole', 0, 30));
    await db.upsertFilePart(file('whole', partCount: 2), part('whole', 1, 31));
    await db.upsertFilePart(file('binned', partCount: 2), part('binned', 0, 40));
    await db.updateFile('binned', DriveFilesCompanion(trashedAt: Value(now)));
    await db.refreshHidden();
    await db.upsertFilePart(file('single'), part('single', 0, 50));

    expect((await db.incompleteFiles()).map((f) => f.id), ['a', 'b']);
    expect(await db.countSplitFiles(), 3);
  });

  test('the phone copy of a backed-up file is found by file id', () async {
    await db.markAssetBackedUp('asset-1', 'p');
    await db.markAssetFailed('asset-2', 1);
    expect(await db.localAssetOf('p'), 'asset-1');
    expect(await db.localAssetOf('q'), isNull);
  });

  test(
    'the phone copies of several files, only for finished backups',
    () async {
      await db.markAssetBackedUp('asset-1', 'p');
      // Backup matched a second photo to the same drive file.
      await db.markAssetBackedUp('asset-1b', 'p');
      await db.markAssetBackedUp('asset-2', 'q');
      await db.markAssetBackedUp('asset-3', 'not-asked');
      await db
          .into(db.backupAssets)
          .insert(
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
    },
  );

  test(
    'the phone copies of more files than SQLite takes in one statement',
    () async {
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

      final found = await db.localAssetsOf([
        for (var i = 0; i < 1200; i++) 'f$i',
      ]);
      expect(found, hasLength(1200));
      expect(found['f0'], ['asset-0']);
      expect(found['f1199'], ['asset-1199']);
    },
  );

  test('complete files, everywhere or in given folders', () async {
    await db.upsertFilePart(file('root'), part('root', 0, 10));
    await db.upsertFilePart(file('in-a', folderId: 'a'), part('in-a', 0, 11));
    await db.upsertFilePart(file('in-b', folderId: 'b'), part('in-b', 0, 12));
    await db.upsertFilePart(
      file('half', folderId: 'a', partCount: 2),
      part('half', 0, 13),
    );

    expect(
      (await db.completeFiles()).map((f) => f.id),
      unorderedEquals(['root', 'in-a', 'in-b']),
    );
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
          wifiOnly: false,
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

  test('paths in use come only from unfinished transfers', () async {
    TransferRow upload(String id, TransferStatus status) => TransferRow(
      id: id,
      kind: TransferKind.upload,
      status: status,
      name: '$id.mp4',
      mimeType: 'video/mp4',
      fileId: 'f-$id',
      sourcePath: '/cache/telegrive-staging/$id.mp4',
      thumbnailPath: '/cache/telegrive-thumbs/$id.jpg',
      ownsSource: true,
      wifiOnly: false,
      totalBytes: 1,
      doneBytes: 0,
      partCount: 1,
      completedParts: 0,
      createdAt: now,
      origin: TransferOrigin.manual,
    );
    await db.saveTransfers([
      upload('queued', TransferStatus.queued),
      upload('paused', TransferStatus.paused),
      upload('failed', TransferStatus.failed),
      upload('done', TransferStatus.completed),
      upload('gone', TransferStatus.cancelled),
      TransferRow(
        id: 'save',
        kind: TransferKind.download,
        status: TransferStatus.running,
        name: 'film.mkv',
        mimeType: 'video/x-matroska',
        fileId: 'film',
        resultPath: '/support/downloads/film/film.mkv',
        ownsSource: false,
        wifiOnly: false,
        totalBytes: 1,
        doneBytes: 0,
        partCount: 2,
        completedParts: 1,
        createdAt: now,
        origin: TransferOrigin.save,
      ),
    ]);

    expect(await db.pathsInUse(), {
      for (final id in ['queued', 'paused', 'failed']) ...[
        '/cache/telegrive-staging/$id.mp4',
        '/cache/telegrive-thumbs/$id.jpg',
      ],
      '/support/downloads/film/film.mkv',
    });
  });

  group('space', () {
    DriveFilesCompanion sized(
      String id,
      int size, {
      String? folderId,
      int partCount = 1,
    }) => file(
      id,
      folderId: folderId,
      partCount: partCount,
    ).copyWith(size: Value(size));

    test(
      'largest files skip trashed and incomplete files, biggest first',
      () async {
        await db.upsertFilePart(sized('small', 10), part('small', 0, 10));
        await db.upsertFilePart(sized('big', 900), part('big', 0, 11));
        await db.upsertFilePart(
          sized('middle', 500, folderId: 'docs'),
          part('middle', 0, 12),
        );
        await db.upsertFilePart(
          sized('trashed', 5000).copyWith(trashedAt: Value(now)),
          part('trashed', 0, 13),
        );
        // One of two parts, so it isn't in the drive yet.
        await db.upsertFilePart(
          sized('half', 8000, partCount: 2),
          part('half', 0, 14),
        );

        expect((await db.watchLargestFiles().first).map((f) => f.id), [
          'big',
          'middle',
          'small',
        ]);
        expect((await db.watchLargestFiles(limit: 2).first).map((f) => f.id), [
          'big',
          'middle',
        ]);
      },
    );

    test('folder sizes roll nested folders into their top-level folder and list root '
        'files once', () async {
      await db.upsertFolder(folder('a', 1));
      await db.upsertFolder(folder('b', 2, parentId: 'a'));
      await db.upsertFolder(folder('old', 3).copyWith(trashedAt: Value(now)));
      await db.upsertFolder(folder('orphan', 4, parentId: 'missing'));
      await db.upsertFolder(folder('empty', 5));
      await db.upsertFilePart(
        sized('in-a', 200, folderId: 'a'),
        part('in-a', 0, 10),
      );
      await db.upsertFilePart(
        sized('in-b', 300, folderId: 'b'),
        part('in-b', 0, 11),
      );
      await db.upsertFilePart(
        sized('in-old', 1000, folderId: 'old'),
        part('in-old', 0, 12),
      );
      await db.upsertFilePart(
        sized('in-orphan', 400, folderId: 'orphan'),
        part('in-orphan', 0, 13),
      );
      await db.upsertFilePart(sized('root', 50), part('root', 0, 14));
      // Its folder is gone, so Files shows it at the root.
      await db.upsertFilePart(
        sized('lost', 25, folderId: 'gone'),
        part('lost', 0, 15),
      );

      final sizes = await db.watchFolderSizes().first;
      expect(
        [for (final s in sizes) (s.folderId, s.name, s.count, s.bytes)],
        [('a', 'a', 2, 500), ('orphan', 'orphan', 1, 400), (null, '', 2, 75)],
      );
      final totals = await db.watchTotals().first;
      expect(
        sizes.fold(0, (sum, s) => sum + s.bytes),
        totals.fold(0, (sum, t) => sum + t.bytes),
      );
    });

    test(
      'starred folder sizes count each starred folder and what is below it',
      () async {
        await db.upsertFolder(
          folder('work', 1).copyWith(starred: const Value(true)),
        );
        await db.upsertFolder(folder('2026', 2, parentId: 'work'));
        await db.upsertFolder(
          folder(
            'invoices',
            3,
            parentId: '2026',
          ).copyWith(starred: const Value(true)),
        );
        await db.upsertFolder(
          folder('empty', 4).copyWith(starred: const Value(true)),
        );
        await db.upsertFolder(folder('plain', 5));
        await db.upsertFolder(
          folder('old', 6, parentId: 'work').copyWith(trashedAt: Value(now)),
        );
        await db.upsertFilePart(
          sized('in-work', 100, folderId: 'work'),
          part('in-work', 0, 10),
        );
        await db.upsertFilePart(
          sized('in-2026', 200, folderId: '2026'),
          part('in-2026', 0, 11),
        );
        await db.upsertFilePart(
          sized('in-invoices', 400, folderId: 'invoices'),
          part('in-invoices', 0, 12),
        );
        await db.upsertFilePart(
          sized('in-old', 1000, folderId: 'old'),
          part('in-old', 0, 13),
        );
        await db.upsertFilePart(
          sized('in-plain', 50, folderId: 'plain'),
          part('in-plain', 0, 14),
        );
        await db.upsertFilePart(
          sized(
            'trashed',
            5000,
            folderId: 'work',
          ).copyWith(trashedAt: Value(now)),
          part('trashed', 0, 15),
        );
        await db.upsertFilePart(
          sized('half', 8000, folderId: 'work', partCount: 2),
          part('half', 0, 16),
        );

        final sizes = await db.watchStarredFolderSizes().first;
        expect(
          [for (final s in sizes) (s.folderId, s.name, s.count, s.bytes)],
          [
            ('empty', 'empty', 0, 0),
            ('invoices', 'invoices', 1, 400),
            ('work', 'work', 3, 700),
          ],
        );
      },
    );

    test(
      'starred folder sizes leave out a trashed folder and survive a loop',
      () async {
        await db.upsertFolder(
          folder(
            'gone',
            1,
          ).copyWith(starred: const Value(true), trashedAt: Value(now)),
        );
        await db.upsertFolder(
          folder(
            'loop-a',
            2,
            parentId: 'loop-b',
          ).copyWith(starred: const Value(true)),
        );
        await db.upsertFolder(folder('loop-b', 3, parentId: 'loop-a'));
        await db.upsertFilePart(
          sized('in-b', 30, folderId: 'loop-b'),
          part('in-b', 0, 10),
        );

        final sizes = await db.watchStarredFolderSizes().first;
        expect(
          [for (final s in sizes) (s.folderId, s.count, s.bytes)],
          [('loop-a', 1, 30)],
        );
      },
    );

    test('trash totals include files inside trashed folders', () async {
      await db.upsertFolder(folder('old', 1).copyWith(trashedAt: Value(now)));
      await db.upsertFolder(folder('inner', 2, parentId: 'old'));
      await db.upsertFilePart(
        sized('in-old', 100, folderId: 'old'),
        part('in-old', 0, 10),
      );
      await db.upsertFilePart(
        sized('in-inner', 200, folderId: 'inner'),
        part('in-inner', 0, 11),
      );
      await db.upsertFilePart(
        sized('loose', 300).copyWith(trashedAt: Value(now)),
        part('loose', 0, 12),
      );
      await db.upsertFilePart(sized('kept', 400), part('kept', 0, 13));

      expect(await db.watchTrashTotals().first, (3, 600));
    });
  });

  group('trash', () {
    Future<void> trashFolder(String id, int messageId, {String? parentId}) =>
        db.upsertFolder(
          folder(
            id,
            messageId,
            parentId: parentId,
          ).copyWith(trashedAt: Value(now)),
        );

    test(
      'a trashed folder hides everything inside it, and only it is listed',
      () async {
        await db.upsertFolder(folder('docs', 1));
        await db.upsertFolder(folder('inner', 2, parentId: 'docs'));
        await db.upsertFilePart(file('a', folderId: 'inner'), part('a', 0, 10));
        await db.upsertFilePart(file('b'), part('b', 0, 11));

        await trashFolder('docs', 1);

        expect(
          (await db.watchChildFolders(null).first).map((f) => f.id),
          isEmpty,
        );
        expect((await db.watchRecent().first).map((f) => f.id), ['b']);
        expect((await db.watchTotals().first).single.count, 1);
        expect((await db.watchTrashedFolders().first).map((f) => f.id), [
          'docs',
        ]);
        expect(await db.watchTrashedFiles().first, isEmpty);
        expect(await db.completeFiles(), hasLength(1));

        // Restoring the folder brings its contents back.
        await db.upsertFolder(
          folder('docs', 1).copyWith(trashedAt: const Value(null)),
        );
        expect(
          (await db.watchRecent().first).map((f) => f.id),
          unorderedEquals(['a', 'b']),
        );
        expect(await db.watchTrashedFolders().first, isEmpty);
      },
    );

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

    test(
      'a file arriving inside a trashed folder is hidden straight away',
      () async {
        await trashFolder('docs', 1);
        await db.upsertFilePart(
          file('late', folderId: 'docs'),
          part('late', 0, 10),
        );
        expect(await db.watchRecent().first, isEmpty);
      },
    );

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
      await db.upsertFilePart(
        file('q').copyWith(trashedAt: Value(now)),
        part('q', 0, 11),
      );
      await db.markAssetBackedUp('asset-p', 'p');
      await db.markAssetBackedUp('asset-q', 'q');
      expect(await safeSizes(), {'asset-p': 100});
    });
  });

  test(
    'a photo safe to free comes with its drive copy and when it was taken',
    () async {
      final taken = DateTime(2021, 3, 14, 9, 30);
      await db.upsertFilePart(
        file('p').copyWith(takenAt: Value(taken)),
        part('p', 0, 10),
      );
      await db.upsertFilePart(file('q'), part('q', 0, 11));
      await db.markAssetBackedUp('asset-p', 'p');
      await db.markAssetBackedUp('asset-q', 'q');

      final safe = await db.safelyBackedUp();
      expect(safe.keys, unorderedEquals(['asset-p', 'asset-q']));
      final photo = safe['asset-p']!;
      expect((photo.id, photo.size, photo.takenAt), ('p', 100, taken));
      expect(safe['asset-q']!.takenAt, isNull);
      expect(safe['asset-q']!.createdAt, now);
    },
  );

  test('albums count and cover their shown files', () async {
    await db.upsertAlbum(
      AlbumsCompanion.insert(
        id: 'al',
        name: 'Trip',
        messageId: 50,
        createdAt: now,
        modifiedAt: now,
      ),
    );
    await db.upsertFilePart(
      file('old').copyWith(takenAt: Value(DateTime(2020))),
      part('old', 0, 10),
    );
    await db.upsertFilePart(
      file('new').copyWith(takenAt: Value(DateTime(2024))),
      part('new', 0, 11),
    );
    await db.upsertFilePart(
      file('gone').copyWith(trashedAt: Value(now)),
      part('gone', 0, 12),
    );
    for (final id in ['old', 'new', 'gone']) {
      await db.setFileAlbums(id, ['al']);
    }

    final album = (await db.watchAlbums().first).single;
    expect(album.album.name, 'Trip');
    expect(album.count, 2);
    expect(album.coverFileId, 'new');
    expect((await db.watchAlbumFiles('al').first).map((f) => f.id), [
      'new',
      'old',
    ]);

    await db.setFileAlbums('new', []);
    expect((await db.watchAlbums().first).single.count, 1);

    await db.removeMessages([50]);
    expect(await db.watchAlbums().first, isEmpty);
  });

  test('the albums a file is in are named in order', () async {
    for (final (id, name, messageId) in [
      ('t', 'Trip', 50),
      ('f', 'Family', 51),
      ('r', 'Receipts', 52),
    ]) {
      await db.upsertAlbum(
        AlbumsCompanion.insert(
          id: id,
          name: name,
          messageId: messageId,
          createdAt: now,
          modifiedAt: now,
        ),
      );
    }
    await db.upsertFilePart(file('p'), part('p', 0, 10));
    await db.upsertFilePart(file('q'), part('q', 0, 11));
    await db.setFileAlbums('p', ['t', 'f']);
    await db.setFileAlbums('q', ['r']);

    expect(await db.albumNamesOf('p'), ['Family', 'Trip']);
    expect(await db.albumNamesOf('loose'), isEmpty);

    // The album's message is gone; its links are not yet.
    await db.removeMessages([51]);
    expect(await db.albumNamesOf('p'), ['Trip']);
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
    expect((await db.watchSearch('', range: march).first).map((f) => f.id), [
      'receipt',
    ]);
    // Words and a date both have to hold.
    expect(
      (await db.watchSearch('receipt', range: march).first).map((f) => f.id),
      ['receipt'],
    );
    expect(await db.watchSearch('other', range: march).first, isEmpty);
    expect(await db.indexedFileIds(1), {'receipt'});
    expect(await db.indexedFileIds(2), isEmpty);
  });

  test('content is searched with the commas typed', () async {
    await db.upsertFilePart(file('receipt'), part('receipt', 0, 10));
    await db.saveContent('receipt', 'total 1,250 birr', 1);

    expect((await db.watchSearch('1,250').first).map((f) => f.id), ['receipt']);
  });

  test(
    'a date alone leaves out files only their content would match',
    () async {
      await db.upsertFilePart(
        file('receipt').copyWith(takenAt: Value(DateTime(2024, 3, 5))),
        part('receipt', 0, 10),
      );
      await db.upsertFilePart(file('notes'), part('notes', 0, 11));
      await db.saveContent('notes', 'minutes from march 2024', 1);

      final march = (DateTime(2024, 3), DateTime(2024, 4));
      expect((await db.watchSearch('', range: march).first).map((f) => f.id), [
        'receipt',
      ]);
    },
  );

  test('search within a folder and everything below it', () async {
    await db.upsertFolder(folder('docs', 1));
    await db.upsertFolder(folder('inner', 2, parentId: 'docs'));
    await db.upsertFolder(folder('sibling', 3));
    await db.upsertFilePart(file('a', folderId: 'docs'), part('a', 0, 10));
    await db.upsertFilePart(file('b', folderId: 'inner'), part('b', 0, 11));
    await db.upsertFilePart(file('c', folderId: 'sibling'), part('c', 0, 12));
    await db.upsertFilePart(file('d'), part('d', 0, 13));

    final subtree = await db.descendantFolderIds('docs');
    expect(subtree, {'docs', 'inner'});
    expect(
      (await db.watchSearch('', folderIds: subtree).first).map((f) => f.id),
      unorderedEquals(['a', 'b']),
    );
    expect(
      (await db.watchSearch('bin', folderIds: subtree).first).map((f) => f.id),
      unorderedEquals(['a', 'b']),
    );
    expect(
      (await db.watchFolderSearch('', within: subtree).first).map((f) => f.id),
      unorderedEquals(['docs', 'inner']),
    );
    expect(await db.descendantFolderIds('sibling'), {'sibling'});
  });

  test('starred folders are listed by name without the trashed ones', () async {
    await db.upsertFolder(
      folder('work', 1).copyWith(starred: const Value(true)),
    );
    await db.upsertFolder(
      folder('Archive', 2).copyWith(starred: const Value(true)),
    );
    await db.upsertFolder(folder('plain', 3));
    await db.upsertFolder(
      folder(
        'old',
        4,
      ).copyWith(starred: const Value(true), trashedAt: Value(now)),
    );
    await db.upsertFolder(
      folder(
        'under-old',
        5,
        parentId: 'old',
      ).copyWith(starred: const Value(true)),
    );

    expect((await db.watchStarredFolders().first).map((f) => f.id), [
      'Archive',
      'work',
    ]);

    await db.updateFolder(
      'work',
      const FoldersCompanion(starred: Value(false)),
    );
    expect((await db.watchStarredFolders().first).map((f) => f.id), [
      'Archive',
    ]);
  });

  test('a folder search puts starred folders first', () async {
    await db.upsertFolder(folder('a', 1));
    await db.upsertFolder(folder('b', 2));
    await db.upsertFolder(folder('z', 3).copyWith(starred: const Value(true)));

    expect((await db.watchFolderSearch('').first).map((f) => f.id), [
      'z',
      'a',
      'b',
    ]);
    expect((await db.watchFolderSearch('b').first).map((f) => f.id), ['b']);
  });

  test(
    'the folders below one leave out the trash and survive a loop',
    () async {
      await db.upsertFolder(folder('docs', 1));
      await db.upsertFolder(folder('inner', 2, parentId: 'docs'));
      await db.upsertFolder(
        folder('old', 3, parentId: 'docs').copyWith(trashedAt: Value(now)),
      );
      await db.upsertFolder(folder('under-old', 4, parentId: 'old'));
      expect(await db.descendantFolderIds('docs'), {'docs', 'inner'});

      await db.upsertFolder(folder('loop-a', 5, parentId: 'loop-b'));
      await db.upsertFolder(folder('loop-b', 6, parentId: 'loop-a'));
      expect(await db.descendantFolderIds('loop-a'), {'loop-a', 'loop-b'});
    },
  );

  test('search keeps to the kinds asked for', () async {
    await db.upsertFilePart(
      file('photo').copyWith(kind: const Value(FileKind.image)),
      part('photo', 0, 10),
    );
    await db.upsertFilePart(
      file('clip').copyWith(kind: const Value(FileKind.video)),
      part('clip', 0, 11),
    );
    await db.upsertFilePart(file('notes'), part('notes', 0, 12));

    expect(
      (await db.watchSearch('', kinds: {FileKind.image, FileKind.video}).first)
          .map((f) => f.id),
      unorderedEquals(['photo', 'clip']),
    );
    expect(
      (await db.watchSearch('', kinds: {FileKind.video}).first).map(
        (f) => f.id,
      ),
      ['clip'],
    );
  });

  test(
    'a name holding the whole query matches when part of it was a date',
    () async {
      await db.upsertFilePart(
        file('report').copyWith(name: const Value('report 2024.pdf')),
        part('report', 0, 10),
      );

      final year2024 = (DateTime(2024), DateTime(2025));
      expect(await db.watchSearch('report', range: year2024).first, isEmpty);
      expect(
        (await db
                .watchSearch('report', range: year2024, literal: 'report 2024')
                .first)
            .map((f) => f.id),
        ['report'],
      );
    },
  );

  test('names match in the case they were typed, content in any', () async {
    await db.upsertFolder(folder('Über', 1));
    await db.upsertFolder(folder('Работа', 2));
    await db.upsertFilePart(
      file('notes').copyWith(name: const Value('Ärzte.pdf')),
      part('notes', 0, 10),
    );
    await db.upsertFilePart(file('letter'), part('letter', 0, 11));
    await db.saveContent('letter', 'grüße aus über', 1);

    expect((await db.watchFolderSearch('Über').first).map((f) => f.id), [
      'Über',
    ]);
    expect((await db.watchFolderSearch('Работа').first).map((f) => f.id), [
      'Работа',
    ]);
    expect((await db.watchSearch('Ärzte').first).map((f) => f.id), ['notes']);
    // The indexer stores content in lower case.
    expect((await db.watchSearch('Über').first).map((f) => f.id), ['letter']);
  });

  test('a search by moment puts the newest capture first', () async {
    await db.upsertFilePart(
      file('old').copyWith(
        kind: const Value(FileKind.image),
        takenAt: Value(DateTime(2020)),
        modifiedAt: Value(DateTime(2026, 9, 30)),
      ),
      part('old', 0, 10),
    );
    await db.upsertFilePart(
      file('new').copyWith(
        kind: const Value(FileKind.image),
        takenAt: Value(DateTime(2026, 9)),
        modifiedAt: Value(DateTime(2026, 9, 1)),
      ),
      part('new', 0, 11),
    );

    expect((await db.watchSearch('').first).map((f) => f.id), ['old', 'new']);
    expect((await db.watchSearch('', byMoment: true).first).map((f) => f.id), [
      'new',
      'old',
    ]);
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

  test(
    'the Offline screen reads every pin with when it was made, and every copy',
    () async {
      final before = DateTime.now().subtract(const Duration(seconds: 1));
      await db.pinOffline('trips', isFolder: true);
      await db.pinOffline('report', isFolder: false);
      await db.saveOfflineCopy('a', '/x/a.jpg', 10);
      await db.saveOfflineCopy('b', '/x/b.jpg', 20);
      await db.saveOfflineCopy('report', '/x/report.pdf', 30);

      final pins = {
        for (final pin in await db.offlinePinList()) pin.itemId: pin,
      };
      expect(pins.keys, unorderedEquals(['trips', 'report']));
      expect(pins['trips']!.isFolder, isTrue);
      expect(pins['report']!.isFolder, isFalse);
      // Rows are newest first by this, which the screen sorts on.
      for (final pin in pins.values) {
        expect(pin.pinnedAt.isAfter(before), isTrue);
      }
      expect(
        {for (final copy in await db.offlineCopyList()) copy.fileId: copy.size},
        {'a': 10, 'b': 20, 'report': 30},
      );

      // Pinning again keeps one row, and Remove all leaves nothing.
      await db.pinOffline('trips', isFolder: true);
      expect(await db.offlinePinList(), hasLength(2));
      await db.clearOffline();
      expect(await db.offlinePinList(), isEmpty);
      expect(await db.offlineCopyList(), isEmpty);
    },
  );

  test('replaced files are found from their replacement', () async {
    await db.upsertFilePart(file('v2'), part('v2', 0, 10));
    await db.upsertFilePart(
      file('v1').copyWith(replacedBy: const Value('v2'), trashedAt: Value(now)),
      part('v1', 0, 11),
    );
    await db.upsertFilePart(
      file('v1b').copyWith(
        replacedBy: const Value('v2'),
        trashedAt: Value(now.add(const Duration(days: 1))),
      ),
      part('v1b', 0, 12),
    );
    // Marked but not in the trash, as a restore on a phone that doesn't
    // know the key leaves a file: not a previous version.
    await db.upsertFilePart(
      file('v0').copyWith(replacedBy: const Value('v2')),
      part('v0', 0, 13),
    );

    expect((await db.trashedReplacementsOf('v2')).map((f) => f.id), [
      'v1b',
      'v1',
    ]);
    expect(await db.trashedReplacementsOf('v1'), isEmpty);
    expect((await db.fileById('v1'))!.replacedBy, 'v2');
  });

  test('a version 3 database gains play positions', () async {
    final verifier = SchemaVerifier(GeneratedHelper());
    final upgraded = AppDatabase(await verifier.startAt(3));
    addTearDown(upgraded.close);
    await verifier.migrateAndValidate(upgraded, upgraded.schemaVersion);

    expect(await upgraded.playPositionOf('film'), isNull);
    await upgraded.savePlayPosition('film', 5 * 60 * 1000, 20 * 60 * 1000);
    final point = (await upgraded.playPositionOf('film'))!;
    expect(point.positionMs, 5 * 60 * 1000);
    expect(point.durationMs, 20 * 60 * 1000);
  });
}
