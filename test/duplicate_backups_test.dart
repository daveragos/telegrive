import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegrive/core/files/file_kind.dart';
import 'package:telegrive/features/drive/data/drive_repository.dart';
import 'package:telegrive/features/drive/data/drive_session.dart';
import 'package:telegrive/features/drive/domain/drive_models.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';
import 'package:telegrive/infrastructure/telegram/telegram_client.dart';

import 'support/fake_telegram.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  var messageId = 0;

  Future<void> folder(String id, String name, DateTime at, {String? parentId}) =>
      db.upsertFolder(
        FoldersCompanion.insert(
          id: id,
          parentId: Value(parentId),
          name: name,
          messageId: ++messageId,
          createdAt: at,
          modifiedAt: at,
        ),
      );

  Future<void> photo(String id, String name, int size, String folderId, DateTime at) =>
      db.upsertFilePart(
        DriveFilesCompanion.insert(
          id: id,
          folderId: Value(folderId),
          name: name,
          mimeType: 'image/jpeg',
          kind: FileKind.image,
          size: size,
          createdAt: at,
          modifiedAt: at,
        ),
        FilePartsCompanion.insert(
          fileId: id,
          partIndex: 0,
          messageId: ++messageId,
          tdFileId: messageId,
          size: size,
        ),
      );

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        telegramClientProvider.overrideWithValue(FakeTelegram()),
        driveSessionProvider.overrideWith(TestSession.new),
      ],
    );
    final before = DateTime(2025, 6);
    final after = DateTime(2026, 9);

    // The first backup, and a second one made after a reinstall.
    await folder('pb1', 'Photo backup', before);
    await folder('cam1', 'Camera', before, parentId: 'pb1');
    await folder('pb2', 'Photo backup', after);
    await folder('cam2', 'Camera', after, parentId: 'pb2');
    await folder('mine', 'Holidays', before);

    await photo('a1', 'IMG_1.jpg', 100, 'cam1', before);
    await photo('b1', 'IMG_2.jpg', 200, 'cam1', before);
    await photo('a2', 'IMG_1.jpg', 100, 'cam2', after);
    await photo('b2', 'IMG_2.jpg', 200, 'cam1', after);
    // Same name, different size: a different photo.
    await photo('c1', 'IMG_3.jpg', 300, 'cam1', before);
    await photo('c2', 'IMG_3.jpg', 301, 'cam2', after);
    // Copies outside backup are the person's own business.
    await photo('m1', 'IMG_1.jpg', 100, 'mine', after);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('later copies under either backup folder are extras; the first stays', () async {
    final found = await container
        .read(driveRepositoryProvider)
        .findDuplicateBackups('Photo backup');

    expect(found.extras.map((f) => f.id), unorderedEquals(['a2', 'b2']));
    expect(found.keptFor, {'a2': 'a1', 'b2': 'b1'});
    expect(found.bytes, 300);
    expect(found.primary?.id, 'pb1');
    expect(found.extraRoots.map((f) => f.id), ['pb2']);
  });

  test('backup records follow the copy that stays', () async {
    await db.markAssetBackedUp('asset-1', 'a2');
    await db.repointBackupAssets({'a2': 'a1'});
    expect(await db.watchLocalAssets().first, {'a1': 'asset-1'});
  });

  test('deleting for good marks backup rows removed', () async {
    await db.markAssetBackedUp('asset-1', 'a1');
    await db.markAssetBackedUp('asset-2', 'b1');
    final a1 = DriveFile.fromRow((await db.fileById('a1'))!);

    await container.read(driveRepositoryProvider).delete(files: [a1]);

    expect(await db.fileById('a1'), isNull);
    expect((await db.backupAssetOf('asset-1'))!.state, BackupAssetState.removed);
    expect((await db.backupAssetOf('asset-2'))!.state, BackupAssetState.done);
    // What went on purpose is never a gap for backup to fill.
    expect(await db.backedUpButMissing(), isEmpty);
  });

  test('nothing to do when every photo went up once', () async {
    final fresh = AppDatabase(NativeDatabase.memory());
    addTearDown(fresh.close);
    final other = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(fresh)]);
    addTearDown(other.dispose);
    final found = await other.read(driveRepositoryProvider).findDuplicateBackups('Photo backup');
    expect(found.isEmpty, isTrue);
  });
}
