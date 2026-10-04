import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegrive/core/files/file_kind.dart';
import 'package:telegrive/features/backup/data/backup_controller.dart';
import 'package:telegrive/features/drive/data/drive_session.dart';
import 'package:telegrive/features/drive/data/drive_sync.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';
import 'package:telegrive/infrastructure/storage/preferences.dart';

import 'support/fake_telegram.dart';

/// Backup switched on, without a pass running.
class _Backup extends BackupController {
  @override
  BackupState build() {
    super.build();
    return const BackupState(phase: BackupPhase.upToDate);
  }

  @override
  void schedule({bool immediate = false}) {}
}

/// A drive whose channel was read in full in this run, or not.
class _Sync extends DriveSync {
  _Sync({required this.readInFull});

  final bool readInFull;

  @override
  SyncState build() => SyncState(lastFull: readInFull ? DateTime.now() : null);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const photos = MethodChannel('com.fluttercandies/photo_manager');
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      photos,
      (call) async => null,
    );
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(photos, null),
  );

  final now = DateTime(2026, 9, 25);

  /// A drive with [total] backed-up photos, of which [gone] have lost their
  /// file, and backup on.
  Future<(ProviderContainer, AppDatabase)> open({
    required int total,
    required int gone,
    bool readInFull = true,
  }) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({
      BackupPrefKeys.enabled: true,
      'full_sync_$testChatId': now.millisecondsSinceEpoch,
    });
    final shared = await SharedPreferences.getInstance();
    final db = AppDatabase(NativeDatabase.memory());
    for (var i = 0; i < total; i++) {
      if (i >= gone) {
        await db.upsertFilePart(
          DriveFilesCompanion.insert(
            id: 'f$i',
            name: 'IMG_$i.jpg',
            mimeType: 'image/jpeg',
            kind: FileKind.image,
            size: 100,
            createdAt: now,
            modifiedAt: now,
          ),
          FilePartsCompanion.insert(
            fileId: 'f$i',
            partIndex: 0,
            messageId: i + 1,
            tdFileId: i + 1,
            size: 100,
          ),
        );
      }
      await db.markAssetBackedUp('a$i', 'f$i');
    }
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(shared),
        appDatabaseProvider.overrideWithValue(db),
        driveSessionProvider.overrideWith(TestSession.new),
        driveSyncProvider.overrideWith(() => _Sync(readInFull: readInFull)),
        backupControllerProvider.overrideWith(_Backup.new),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    return (container, db);
  }

  test('a few photos gone from the drive are marked missing', () async {
    final (container, db) = await open(total: 100, gone: 3);
    final outcome = await container.read(backupControllerProvider.notifier).verify();

    expect(outcome, VerifyOutcome.gaps);
    expect(await db.watchMissingCount().first, 3);
    for (final id in ['a0', 'a1', 'a2']) {
      final record = (await db.backupAssetOf(id))!;
      expect(record.state, BackupAssetState.missing);
      expect(record.fileId, isNull);
    }
    expect((await db.backupAssetOf('a3'))!.state, BackupAssetState.done);
    expect(container.read(preferencesProvider).backupVerifiedAt, isNotNull);
  });

  test('most photos gone means the index is doubted, and nothing is written', () async {
    final (container, db) = await open(total: 100, gone: 80);
    final outcome = await container.read(backupControllerProvider.notifier).verify();

    expect(outcome, VerifyOutcome.suspect);
    expect(await db.watchMissingCount().first, 0);
    expect(await db.watchBackedUpCount().first, 100);
    expect(container.read(preferencesProvider).backupVerifiedAt, isNull);
  });

  test('nothing is checked before a full read in this run', () async {
    final (container, db) = await open(total: 10, gone: 3, readInFull: false);
    final outcome = await container.read(backupControllerProvider.notifier).verify();

    expect(outcome, VerifyOutcome.skipped);
    expect(await db.watchMissingCount().first, 0);
  });

  test('everything in place is fine', () async {
    final (container, _) = await open(total: 5, gone: 0);
    expect(await container.read(backupControllerProvider.notifier).verify(), VerifyOutcome.ok);
  });

  test('a pass leaves missing and removed photos alone', () {
    BackupAssetRow record(BackupAssetState state, {int failures = 0}) =>
        BackupAssetRow(assetId: 'a', state: state, failures: failures, updatedAt: now);
    expect(BackupController.classify(null), BackupDisposition.pending);
    expect(BackupController.classify(record(BackupAssetState.done)), BackupDisposition.done);
    expect(
      BackupController.classify(record(BackupAssetState.failed, failures: 2)),
      BackupDisposition.pending,
    );
    expect(
      BackupController.classify(record(BackupAssetState.failed, failures: 3)),
      BackupDisposition.failed,
    );
    expect(BackupController.classify(record(BackupAssetState.skipped)), BackupDisposition.skip);
    expect(BackupController.classify(record(BackupAssetState.missing)), BackupDisposition.skip);
    expect(BackupController.classify(record(BackupAssetState.removed)), BackupDisposition.skip);
  });

  test('back up again forgets the missing records; leave them out keeps them', () async {
    final (container, db) = await open(total: 4, gone: 2);
    final controller = container.read(backupControllerProvider.notifier);
    await controller.verify();
    expect(await db.watchMissingCount().first, 2);

    await (db.update(db.backupAssets)..where((a) => a.assetId.equals('a0'))).write(
      const BackupAssetsCompanion(state: Value(BackupAssetState.removed)),
    );
    await controller.retryMissing();
    expect(await db.backupAssetOf('a1'), isNull);
    expect((await db.backupAssetOf('a0'))!.state, BackupAssetState.removed);

    await db.markAssetsMissing(['a2']);
    await controller.leaveOutMissing();
    expect((await db.backupAssetOf('a2'))!.state, BackupAssetState.removed);
    expect(await db.watchMissingCount().first, 0);
  });
}
