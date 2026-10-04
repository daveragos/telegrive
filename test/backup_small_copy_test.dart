import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegrive/core/files/file_kind.dart';
import 'package:telegrive/features/backup/data/backup_controller.dart';
import 'package:telegrive/features/backup/presentation/backup_card.dart';
import 'package:telegrive/features/drive/data/drive_repository.dart';
import 'package:telegrive/features/drive/data/drive_session.dart';
import 'package:telegrive/features/drive/data/drive_sync.dart';
import 'package:telegrive/features/network/domain/data_period.dart';
import 'package:telegrive/features/transfers/data/transfer_queue.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';
import 'package:telegrive/infrastructure/network/network_status.dart';
import 'package:telegrive/infrastructure/storage/preferences.dart';

import 'support/fake_telegram.dart';

const _mb = 1024 * 1024;
const _wifi = NetworkState(online: true, metered: false);
const _hotspot = NetworkState(online: true, metered: true);

/// photo_manager hands out files only on Android and Apple platforms.
final _readsFiles = Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
final _skip = _readsFiles ? false : 'photo_manager reads files on Android and Apple platforms only';

/// Backup switched on, whose passes the test runs itself.
class _Backup extends BackupController {
  @override
  BackupState build() {
    super.build();
    return const BackupState(phase: BackupPhase.upToDate);
  }

  @override
  void schedule({bool immediate = false}) {}
}

class _Sync extends DriveSync {
  @override
  SyncState build() => const SyncState();

  @override
  Future<void> whenIdle() async {}
}

/// A drive whose backup folders are there already.
class _Repository extends DriveRepository {
  _Repository(super.ref);

  @override
  Future<String> ensureFolderPath(List<String> names) async => names.join('/');
}

/// A phone whose connection the test moves.
class _Network extends NetworkStatus {
  _Network(this._initial);

  final NetworkState _initial;

  @override
  NetworkState build() => _initial;

  void set(NetworkState next) => state = next;
}

/// A queue that sends nothing and finishes every upload at once, indexing
/// what it would have put in the drive: a small copy marked with its
/// original's size, and an original in its small copy's place. With
/// [failOriginals] an original ends failed and the small copy stays.
class _Queue extends TransferQueue {
  final uploads = <UploadRequest>[];
  final Set<String> _small = {};
  bool failOriginals = false;

  @override
  TransfersState build() => TransfersState.empty;

  @override
  bool sendsSmallCopy(String id) => _small.contains(id);

  @override
  Future<List<String>> enqueueUploads(List<UploadRequest> requests, {String? folderId}) async {
    final ids = <String>[];
    final db = ref.read(appDatabaseProvider);
    for (final request in requests) {
      uploads.add(request);
      final id = 'u${uploads.length}';
      final fileId = request.fileId ?? 'file-$id';
      final size = request.size ?? 0;
      if (request.smallCopyOf != null) _small.add(id);
      final failed = request.replacesSmallCopy && failOriginals;
      if (request.replacesSmallCopy) {
        if (!failed) {
          await db.updateFile(
            fileId,
            DriveFilesCompanion(size: Value(size), originalSize: const Value(null)),
          );
        }
      } else {
        await db.upsertFilePart(
          DriveFilesCompanion.insert(
            id: fileId,
            name: request.name,
            mimeType: request.smallCopyOf != null ? 'image/jpeg' : mimeTypeFor(request.name),
            kind: FileKind.image,
            size: size,
            createdAt: DateTime.now(),
            modifiedAt: DateTime.now(),
            originalSize: Value(request.smallCopyOf),
          ),
          FilePartsCompanion.insert(
            fileId: fileId,
            partIndex: 0,
            messageId: uploads.length,
            tdFileId: uploads.length,
            size: size,
          ),
        );
      }
      ids.add(id);
      _rows[id] = TransferRow(
        id: id,
        kind: TransferKind.upload,
        status: failed ? TransferStatus.failed : TransferStatus.completed,
        name: request.name,
        mimeType: mimeTypeFor(request.name),
        fileId: fileId,
        ownsSource: request.ownsSource,
        wifiOnly: request.wifiOnly,
        totalBytes: size,
        doneBytes: failed ? 0 : size,
        partCount: 1,
        completedParts: failed ? 0 : 1,
        createdAt: DateTime.now(),
        origin: request.origin,
        assetId: request.assetId,
        error: failed ? 'Message ID invalid' : null,
      );
    }
    return ids;
  }

  final Map<String, TransferRow> _rows = {};

  @override
  Future<TransferRow> whenFinished(String id) async => _rows[id]!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const photos = MethodChannel('com.fluttercandies/photo_manager');
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  late Directory dir;
  late List<Map<String, Object>> library;
  late Map<String, String> files;

  /// How many bytes the phone makes a small copy of, or null when it can't.
  int? smallCopyBytes;

  Future<void> add(String id, {required int megabytes, bool video = false}) async {
    final name = video ? 'VID_$id.mp4' : 'IMG_$id.HEIC';
    final file = File('${dir.path}/library/$name');
    await file.create(recursive: true);
    final open = await file.open(mode: FileMode.write);
    await open.truncate(megabytes * _mb);
    await open.close();
    files[id] = file.path;
    library.add({
      'id': id,
      'type': video ? 2 : 1,
      'width': 4000,
      'height': 3000,
      'duration': video ? 30 : 0,
      'createDt': DateTime(2026, 9, 25).millisecondsSinceEpoch ~/ 1000 - library.length,
      'relativePath': 'DCIM/Camera/',
      'title': name,
    });
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('telegrive_backup_small');
    library = [];
    files = {};
    smallCopyBytes = 300 * 1024;
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(photos, (call) async {
      switch (call.method) {
        case 'getPermissionState':
          return PermissionState.authorized.index;
        case 'getAssetPathList':
          return {
            'data': [
              if (library.isNotEmpty)
                {'id': 'all', 'name': 'Recent', 'isAll': true, 'assetCount': library.length},
            ],
          };
        case 'getAssetCountFromPath':
          return library.length;
        case 'getAssetListRange':
          return {'data': library};
        case 'getFullFile':
          return files[(call.arguments as Map)['id']];
        case 'getThumb':
          final option = (call.arguments as Map)['option'] as Map;
          // The 320 px preview is small; the small copy is what the test says.
          if (option['width'] != 1600) return Uint8List(20 * 1024);
          final bytes = smallCopyBytes;
          return bytes == null ? null : Uint8List(bytes);
        default:
          return null;
      }
    });
    messenger.setMockMethodCallHandler(paths, (call) async => '${dir.path}/cache');
  });

  tearDown(() async {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(photos, null);
    messenger.setMockMethodCallHandler(paths, null);
    await dir.delete(recursive: true);
  });

  Future<ProviderContainer> open({
    required NetworkState network,
    BackupMobileData mobileData = BackupMobileData.off,
    Map<String, Object> prefs = const {},
  }) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({
      BackupPrefKeys.enabled: true,
      BackupPrefKeys.mobileData: mobileData.name,
      'backup_small_copies': true,
      'full_sync_$testChatId': DateTime.now().millisecondsSinceEpoch,
      ...prefs,
    });
    final shared = await SharedPreferences.getInstance();
    final db = AppDatabase(NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(shared),
        appDatabaseProvider.overrideWithValue(db),
        driveSessionProvider.overrideWith(TestSession.new),
        driveSyncProvider.overrideWith(_Sync.new),
        driveRepositoryProvider.overrideWith(_Repository.new),
        networkStatusProvider.overrideWith(() => _Network(network)),
        transferQueueProvider.overrideWith(_Queue.new),
        backupControllerProvider.overrideWith(_Backup.new),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    return container;
  }

  test(
    'while small copies go up, what is left counts the photos with nothing in the drive yet',
    () {
      final status = describeBackup(
        const BackupState(
          phase: BackupPhase.uploading,
          total: 4530,
          done: 3080,
          smallCopies: 1410,
          sendingSmallCopies: true,
        ),
        speed: 1.1 * _mb,
      );
      expect(status.title, 'Backing up small copies');
      expect(status.detail, '40 left · 1.1 MB/s');
      expect(status.done, isFalse);
    },
  );

  test('on mobile data kept for other things, a photo goes up as a small copy and its original on Wi-Fi', () async {
    await add('v1', megabytes: 40, video: true);
    await add('p1', megabytes: 6);
    final container = await open(network: _hotspot);
    final controller = container.read(backupControllerProvider.notifier);
    final queue = container.read(transferQueueProvider.notifier) as _Queue;
    final db = container.read(appDatabaseProvider);

    await controller.run();

    final small = queue.uploads.single;
    expect(small.name, 'IMG_p1.HEIC');
    expect(small.smallCopyOf, 6 * _mb);
    expect(small.size, 300 * 1024);
    expect(small.wifiOnly, isFalse);
    expect(small.path, contains('telegrive-small'));
    final record = (await db.backupAssetMap())['p1']!;
    expect(record.state, BackupAssetState.smallCopy);
    expect(await db.safelyBackedUp(), isEmpty);
    var backup = container.read(backupControllerProvider);
    expect(backup.phase, BackupPhase.waitingForWifi);
    expect(backup.smallCopies, 1);
    expect(backup.done, 0);
    expect(describeBackup(backup).title, 'Originals wait for Wi-Fi');
    expect(describeBackup(backup).detail, '2 still to send. Small copies are already safe.');
    expect(await db.watchPendingOriginals().first, (count: 1, bytes: 6 * _mb));

    // A pass on mobile data again sends nothing more.
    await controller.run();
    expect(queue.uploads, hasLength(1));

    (container.read(networkStatusProvider.notifier) as _Network).set(_wifi);
    await controller.run();

    final original = queue.uploads.firstWhere(
      (u) => u.name == 'IMG_p1.HEIC' && u.replacesSmallCopy,
    );
    expect(original.fileId, record.fileId);
    expect(original.size, 6 * _mb);
    expect(original.smallCopyOf, isNull);
    expect(queue.uploads.map((u) => u.name), contains('VID_v1.mp4'));
    expect((await db.backupAssetMap())['p1']!.state, BackupAssetState.done);
    expect((await db.backupAssetMap())['p1']!.fileId, record.fileId);
    expect((await db.safelyBackedUp()).keys, containsAll(['p1', 'v1']));
    backup = container.read(backupControllerProvider);
    expect(backup.phase, BackupPhase.upToDate);
    expect(backup.smallCopies, 0);
    expect(backup.done, 2);
  }, skip: _skip);

  test('with the switch off, mobile data kept for other things sends nothing', () async {
    await add('p1', megabytes: 6);
    final container = await open(network: _hotspot, prefs: {'backup_small_copies': false});

    await container.read(backupControllerProvider.notifier).run();

    expect((container.read(transferQueueProvider.notifier) as _Queue).uploads, isEmpty);
    expect(container.read(backupControllerProvider).phase, BackupPhase.waitingForWifi);
  }, skip: _skip);

  test('past the monthly limit, a small copy goes only when the limit has room for it', () async {
    await add('p1', megabytes: 6);
    await add('p2', megabytes: 6);
    // All but 200 KB of a 250 MB limit used this period: too little for
    // even a small copy.
    final container = await open(
      network: _hotspot,
      mobileData: BackupMobileData.photos,
      prefs: {
        'data_limit_bytes': 250 * _mb,
        'data_limit_renew_day': 3,
        'data_period_start': DataPeriod.startFor(DateTime.now(), 3).millisecondsSinceEpoch,
        'data_mobile_baseline': 0,
        'data_wifi_baseline': 0,
        'data_mobile_carry': 250 * _mb - 200 * 1024,
        'data_wifi_carry': 0,
        'data_stats_since': 0,
      },
    );
    final queue = container.read(transferQueueProvider.notifier) as _Queue;

    await container.read(backupControllerProvider.notifier).run();

    expect(queue.uploads, isEmpty);
    expect(Directory('${dir.path}/cache/telegrive-small').listSync(), isEmpty);
    final backup = container.read(backupControllerProvider);
    expect(backup.phase, BackupPhase.waitingForBudget);
    expect(backup.heldForBudget, 2);
    expect(backup.smallCopies, 0);
  }, skip: _skip);

  test('a photo the phone can\'t make a small copy of waits for Wi-Fi', () async {
    await add('p1', megabytes: 6);
    smallCopyBytes = 2 * _mb;
    final container = await open(network: _hotspot);

    await container.read(backupControllerProvider.notifier).run();

    expect((container.read(transferQueueProvider.notifier) as _Queue).uploads, isEmpty);
    final backup = container.read(backupControllerProvider);
    expect(backup.phase, BackupPhase.waitingForWifi);
    expect(backup.smallCopies, 0);
    expect(describeBackup(backup).title, 'Waiting for Wi-Fi');
  }, skip: _skip);

  /// IMG_p1.HEIC's small copy, in the drive as file 'small'.
  Future<void> addSmallCopy(AppDatabase db) => db.upsertFilePart(
    DriveFilesCompanion.insert(
      id: 'small',
      name: 'IMG_p1.HEIC',
      mimeType: 'image/jpeg',
      kind: FileKind.image,
      size: 300 * 1024,
      createdAt: DateTime(2026, 9, 25),
      modifiedAt: DateTime(2026, 9, 25),
      originalSize: const Value(6 * _mb),
    ),
    FilePartsCompanion.insert(
      fileId: 'small',
      partIndex: 0,
      messageId: 70,
      tdFileId: 70,
      size: 300 * 1024,
    ),
  );

  test(
    'after a reinstall, a small copy in the drive is known and its original replaces it',
    () async {
      await add('p1', megabytes: 6);
      final container = await open(network: _wifi);
      final db = container.read(appDatabaseProvider);
      await addSmallCopy(db);
      final queue = container.read(transferQueueProvider.notifier) as _Queue;

      await container.read(backupControllerProvider.notifier).run();

      final original = queue.uploads.single;
      expect(original.replacesSmallCopy, isTrue);
      expect(original.fileId, 'small');
      final record = (await db.backupAssetMap())['p1']!;
      expect(record.state, BackupAssetState.done);
      expect(record.fileId, 'small');
      expect(container.read(backupControllerProvider).phase, BackupPhase.upToDate);
    },
    skip: _skip,
  );

  test('an original that keeps failing runs out of tries instead of starting over', () async {
    await add('p1', megabytes: 6);
    final container = await open(network: _wifi);
    final db = container.read(appDatabaseProvider);
    await addSmallCopy(db);
    final controller = container.read(backupControllerProvider.notifier);
    final queue = container.read(transferQueueProvider.notifier) as _Queue..failOriginals = true;

    for (var tries = 1; tries <= BackupController.maxFailures; tries++) {
      await controller.run();
      final record = (await db.backupAssetMap())['p1']!;
      expect(record.state, BackupAssetState.failed);
      expect(record.failures, tries);
      expect(record.reason, 'Message ID invalid');
    }
    expect(queue.uploads, hasLength(BackupController.maxFailures));
    expect(container.read(backupControllerProvider).failedIds, {'p1'});
    expect((await db.fileById('small'))!.originalSize, 6 * _mb);

    // Out of tries, the photo is left alone until Retry.
    await controller.run();
    expect(queue.uploads, hasLength(BackupController.maxFailures));

    // Retry gives the original fresh tries, and it goes in the small copy's place.
    queue.failOriginals = false;
    await controller.retryOne('p1');
    await controller.run();
    expect(queue.uploads, hasLength(BackupController.maxFailures + 1));
    final record = (await db.backupAssetMap())['p1']!;
    expect(record.state, BackupAssetState.done);
    expect(record.fileId, 'small');
  }, skip: _skip);

  test('a small copy deleted from the drive elsewhere isn\'t sent again', () async {
    await add('p1', megabytes: 6);
    final container = await open(network: _wifi);
    final db = container.read(appDatabaseProvider);
    await db.markAssetSmallCopy('p1', 'gone');

    await container.read(backupControllerProvider.notifier).run();

    expect((container.read(transferQueueProvider.notifier) as _Queue).uploads, isEmpty);
    final record = (await db.backupAssetMap())['p1']!;
    expect(record.state, BackupAssetState.done);
    expect(record.fileId, isNull);
  }, skip: _skip);
}
