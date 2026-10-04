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

  test('play positions outlast a rebuilt index and go on sign-out', () async {
    await db.upsertFilePart(file('a'), part('a', 0, 10));
    await db.into(db.playPositions).insert(
      PlayPositionsCompanion.insert(
        fileId: 'a',
        positionMs: 42 * 60 * 1000,
        durationMs: 90 * 60 * 1000,
        updatedAt: now,
      ),
    );
    Future<List<PlayPositionRow>> positions() => db.select(db.playPositions).get();

    expect((await positions()).single.positionMs, 42 * 60 * 1000);

    await db.clearIndex();
    expect(await positions(), hasLength(1));

    await db.clearAll();
    expect(await positions(), isEmpty);
  });

  test('watched folders outlast a rebuilt index and go on sign-out', () async {
    await db.into(db.watchedFolders).insert(
      WatchedFoldersCompanion.insert(
        id: 'bank',
        treeUri: 'content://com.android.externalstorage.documents/tree/'
            'primary%3ADownload%2FBank',
        label: 'Bank',
        filter: WatchFilter.documents,
        createdAt: now,
      ),
    );
    await db.into(db.watchedFiles).insert(
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
    Future<List<WatchedFolderRow>> rules() => db.select(db.watchedFolders).get();
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

  test('waiting changes outlast a rebuilt index and go on sign-out', () async {
    await db.upsertFilePart(file('a'), part('a', 0, 10));
    // A file and an album may share an id: the target tells them apart.
    await db.into(db.pendingEdits).insert(
      PendingEditsCompanion.insert(
        target: EditTarget.file,
        itemId: 'a',
        patch: '{"n":{"b":"a.bin","w":"Lease.pdf"}}',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await db.into(db.pendingEdits).insert(
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

  test('a photo with only a small copy in the drive is never safe to free', () async {
    await db.upsertFilePart(file('p'), part('p', 0, 1));
    await db.updateFile('p', const DriveFilesCompanion(originalSize: Value(6100000)));
    await db.into(db.backupAssets).insert(
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
    await db.updateFile('p', const DriveFilesCompanion(originalSize: Value(null)));
    expect(await db.safelyBackedUp(), {'asset-1': 100});
    expect(await db.localAssetsOf(['p']), {'p': ['asset-1']});
    expect(await db.watchBackedUpCount().first, 1);
  });

  test('a length learned on this phone survives a caption without one', () async {
    await db.upsertFilePart(file('clip'), part('clip', 0, 10));
    await db.updateFile('clip', const DriveFilesCompanion(durationSeconds: Value(84)));
    expect((await db.watchMediaLite().first), isEmpty, reason: 'not a media kind');
    expect((await db.fileById('clip'))!.durationSeconds, 84);

    // The indexer leaves the column alone when the caption carries no du.
    await db.upsertFilePart(file('clip'), part('clip', 0, 10));
    expect((await db.fileById('clip'))!.durationSeconds, 84);

    await db.upsertFilePart(
      file('clip').copyWith(durationSeconds: const Value(90)),
      part('clip', 0, 10),
    );
    expect((await db.fileById('clip'))!.durationSeconds, 90);
  });

  test('opens are remembered, pruned and follow the file', () async {
    await db.upsertFilePart(file('a'), part('a', 0, 10));
    await db.upsertFilePart(file('b'), part('b', 0, 11));
    await db.upsertFilePart(
      file('c').copyWith(takenAt: Value(DateTime(2026, 9, 20))),
      part('c', 0, 12),
    );
    expect(db.schemaVersion, 10);

    await db.recordOpen('a');
    expect((await db.watchRecentOpens().first).map((o) => o.$1.id), ['a']);

    // Camera-roll backups are the only files with a capture time.
    expect(
      (await db.watchRecent(excludeCameraRoll: true).first).map((f) => f.id),
      unorderedEquals(['a', 'b']),
    );
    expect((await db.watchRecent().first).map((f) => f.id), unorderedEquals(['a', 'b', 'c']));

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
    final kept = {for (final row in await db.select(db.fileOpens).get()) row.fileId};
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
    Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));
    await settle();

    await db.recordOpens(['a', 'b', 'c']);
    await settle();
    expect(seen, [<String>{}, {'a', 'b', 'c'}]);
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
      media('old-photo', FileKind.image, taken: DateTime(2019), added: DateTime(2026, 9), mini: 'AQID'),
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

    final timeline = await db.watchMediaLite().first;
    expect(timeline.map((f) => f.row.id), ['clip', 'new-upload', 'old-photo']);
    // Every column but the preview comes back as stored.
    for (final lite in timeline) {
      final full = (await db.fileById(lite.row.id))!;
      expect(lite.row, full.copyWith(minithumbnail: const Value(null)));
      expect(lite.hasMinithumbnail, full.minithumbnail != null);
    }
    expect(timeline.last.hasMinithumbnail, isTrue);
    expect(await db.minithumbnailOf('old-photo'), 'AQID');
    expect(await db.minithumbnailOf('new-upload'), isNull);
  });

  test('lite album and kind lists hold the files the album and kind hold', () async {
    await db.upsertAlbum(
      AlbumsCompanion.insert(id: 'al', name: 'Trip', messageId: 50, createdAt: now, modifiedAt: now),
    );
    DriveFilesCompanion photo(String id, {required DateTime added, DateTime? taken}) =>
        file(id).copyWith(
          kind: const Value(FileKind.image),
          createdAt: Value(added),
          takenAt: Value(taken),
          minithumbnail: const Value('AQID'),
        );
    await db.upsertFilePart(photo('old', added: DateTime(2026, 9), taken: DateTime(2020)), part('old', 0, 10));
    await db.upsertFilePart(photo('new', added: DateTime(2026, 8)), part('new', 0, 11));
    await db.upsertFilePart(
      photo('gone', added: DateTime(2026, 7)).copyWith(trashedAt: Value(now)),
      part('gone', 0, 12),
    );
    // Half of a split photo isn't shown until its other part arrives.
    await db.upsertFilePart(
      photo('half', added: DateTime(2026, 6)).copyWith(partCount: const Value(2)),
      part('half', 0, 13),
    );
    await db.upsertFilePart(photo('outside', added: DateTime(2026, 5)), part('outside', 0, 14));
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
    final subscription = db.watchAlbumFilesLite('al').listen((rows) => counts.add(rows.length));
    addTearDown(subscription.cancel);
    while (counts.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    await db.setFileAlbums('old', []);
    while (counts.length < 2) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(counts, [3, 2]);
  });

  test('media thumbnails come newest first, for shown photos and videos', () async {
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
      media('clip', FileKind.video, thumbnail: 12, taken: DateTime(2026, 9, 20)),
      part('clip', 0, 2),
    );
    await db.upsertFilePart(
      media('upload', FileKind.image, thumbnail: 13, added: DateTime(2026, 8)),
      part('upload', 0, 3),
    );
    // No thumbnail, not a photo or video, in the trash, or still arriving.
    await db.upsertFilePart(media('bare', FileKind.image), part('bare', 0, 4));
    await db.upsertFilePart(
      media('report', FileKind.document, thumbnail: 15),
      part('report', 0, 5),
    );
    await db.upsertFilePart(
      media('binned', FileKind.image, thumbnail: 16).copyWith(trashedAt: Value(now)),
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

    // Photos out of tries are listed with the reason, and can be skipped.
    await db.markAssetFailed('asset-2', 3, reason: 'Telegram took too long to answer.');
    await db.markAssetFailed('asset-3', 2, reason: 'Couldn\'t start the upload.');
    await db.markAssetFailed('asset-4', 4);

    final failed = await db.watchFailedAssets(minFailures: 3).first;
    expect(failed.map((r) => r.assetId), unorderedEquals(['asset-2', 'asset-4']));
    expect(
      failed.singleWhere((r) => r.assetId == 'asset-2').reason,
      'Telegram took too long to answer.',
    );

    expect(await db.markAssetSkipped('asset-2'), 1);
    expect(await db.markAssetSkipped('asset-2'), 0);
    expect(await db.markAssetSkipped('asset-1'), 0);
    expect((await db.watchFailedAssets(minFailures: 3).first).map((r) => r.assetId), [
      'asset-4',
    ]);
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
    expect((await db.backupAssetMap()).keys, unorderedEquals(['asset-1', 'asset-3']));
    expect(await db.watchBackedUpCount().first, 1);
    expect(await db.watchLocalAssets().first, {'p': 'asset-1'});
    expect(await db.safelyBackedUp(), {'asset-1': 4242});
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
    DriveFilesCompanion sized(String id, int size, {String? folderId, int partCount = 1}) =>
        file(id, folderId: folderId, partCount: partCount).copyWith(size: Value(size));

    test('largest files skip trashed and incomplete files, biggest first', () async {
      await db.upsertFilePart(sized('small', 10), part('small', 0, 10));
      await db.upsertFilePart(sized('big', 900), part('big', 0, 11));
      await db.upsertFilePart(sized('middle', 500, folderId: 'docs'), part('middle', 0, 12));
      await db.upsertFilePart(
        sized('trashed', 5000).copyWith(trashedAt: Value(now)),
        part('trashed', 0, 13),
      );
      // One of two parts, so it isn't in the drive yet.
      await db.upsertFilePart(sized('half', 8000, partCount: 2), part('half', 0, 14));

      expect(
        (await db.watchLargestFiles().first).map((f) => f.id),
        ['big', 'middle', 'small'],
      );
      expect((await db.watchLargestFiles(limit: 2).first).map((f) => f.id), ['big', 'middle']);
    });

    test('folder sizes roll nested folders into their top-level folder and list root '
        'files once', () async {
      await db.upsertFolder(folder('a', 1));
      await db.upsertFolder(folder('b', 2, parentId: 'a'));
      await db.upsertFolder(folder('old', 3).copyWith(trashedAt: Value(now)));
      await db.upsertFolder(folder('orphan', 4, parentId: 'missing'));
      await db.upsertFolder(folder('empty', 5));
      await db.upsertFilePart(sized('in-a', 200, folderId: 'a'), part('in-a', 0, 10));
      await db.upsertFilePart(sized('in-b', 300, folderId: 'b'), part('in-b', 0, 11));
      await db.upsertFilePart(sized('in-old', 1000, folderId: 'old'), part('in-old', 0, 12));
      await db.upsertFilePart(sized('in-orphan', 400, folderId: 'orphan'), part('in-orphan', 0, 13));
      await db.upsertFilePart(sized('root', 50), part('root', 0, 14));
      // Its folder is gone, so Files shows it at the root.
      await db.upsertFilePart(sized('lost', 25, folderId: 'gone'), part('lost', 0, 15));

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

    test('trash totals include files inside trashed folders', () async {
      await db.upsertFolder(folder('old', 1).copyWith(trashedAt: Value(now)));
      await db.upsertFolder(folder('inner', 2, parentId: 'old'));
      await db.upsertFilePart(sized('in-old', 100, folderId: 'old'), part('in-old', 0, 10));
      await db.upsertFilePart(sized('in-inner', 200, folderId: 'inner'), part('in-inner', 0, 11));
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
    expect((await db.watchSearch('', range: march).first).map((f) => f.id), ['receipt']);
    // Words and a date both have to hold.
    expect((await db.watchSearch('receipt', range: march).first).map((f) => f.id), ['receipt']);
    expect(await db.watchSearch('other', range: march).first, isEmpty);
    expect(await db.indexedFileIds(1), {'receipt'});
    expect(await db.indexedFileIds(2), isEmpty);
  });

  test('content is searched with the commas typed', () async {
    await db.upsertFilePart(file('receipt'), part('receipt', 0, 10));
    await db.saveContent('receipt', 'total 1,250 birr', 1);

    expect((await db.watchSearch('1,250').first).map((f) => f.id), ['receipt']);
  });

  test('a date alone leaves out files only their content would match', () async {
    await db.upsertFilePart(
      file('receipt').copyWith(takenAt: Value(DateTime(2024, 3, 5))),
      part('receipt', 0, 10),
    );
    await db.upsertFilePart(file('notes'), part('notes', 0, 11));
    await db.saveContent('notes', 'minutes from march 2024', 1);

    final march = (DateTime(2024, 3), DateTime(2024, 4));
    expect((await db.watchSearch('', range: march).first).map((f) => f.id), ['receipt']);
  });

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

  test('the folders below one leave out the trash and survive a loop', () async {
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
  });

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
      (await db.watchSearch('', kinds: {FileKind.video}).first).map((f) => f.id),
      ['clip'],
    );
  });

  test('a name holding the whole query matches when part of it was a date', () async {
    await db.upsertFilePart(
      file('report').copyWith(name: const Value('report 2024.pdf')),
      part('report', 0, 10),
    );

    final year2024 = (DateTime(2024), DateTime(2025));
    expect(await db.watchSearch('report', range: year2024).first, isEmpty);
    expect(
      (await db.watchSearch('report', range: year2024, literal: 'report 2024').first)
          .map((f) => f.id),
      ['report'],
    );
  });

  test('names match in the case they were typed, content in any', () async {
    await db.upsertFolder(folder('Über', 1));
    await db.upsertFolder(folder('Работа', 2));
    await db.upsertFilePart(
      file('notes').copyWith(name: const Value('Ärzte.pdf')),
      part('notes', 0, 10),
    );
    await db.upsertFilePart(file('letter'), part('letter', 0, 11));
    await db.saveContent('letter', 'grüße aus über', 1);

    expect((await db.watchFolderSearch('Über').first).map((f) => f.id), ['Über']);
    expect((await db.watchFolderSearch('Работа').first).map((f) => f.id), ['Работа']);
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
    expect(
      (await db.watchSearch('', byMoment: true).first).map((f) => f.id),
      ['new', 'old'],
    );
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

  test('the Offline screen reads every pin with when it was made, and every copy', () async {
    final before = DateTime.now().subtract(const Duration(seconds: 1));
    await db.pinOffline('trips', isFolder: true);
    await db.pinOffline('report', isFolder: false);
    await db.saveOfflineCopy('a', '/x/a.jpg', 10);
    await db.saveOfflineCopy('b', '/x/b.jpg', 20);
    await db.saveOfflineCopy('report', '/x/report.pdf', 30);

    final pins = {for (final pin in await db.offlinePinList()) pin.itemId: pin};
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
  });
}
