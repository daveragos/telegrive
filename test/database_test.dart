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
    expect(await db.mediaFingerprints(), {'IMG_1.jpg|4242'});

    await db.markAssetBackedUp('asset-1', 'p');
    await db.markAssetFailed('asset-2', 2);
    final records = await db.backupAssetMap();
    expect(records['asset-1']!.state, BackupAssetState.done);
    expect(records['asset-2']!.failures, 2);
    expect(await db.watchBackedUpCount().first, 1);

    await db.clearBackupFailures();
    expect((await db.backupAssetMap()).keys, ['asset-1']);
  });
}
