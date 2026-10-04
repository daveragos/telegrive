import 'dart:async';
import 'dart:io';

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
import 'package:telegrive/features/transfers/domain/transfer_wait.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';
import 'package:telegrive/infrastructure/network/network_status.dart';
import 'package:telegrive/infrastructure/storage/preferences.dart';

import 'support/fake_telegram.dart';

const _mb = 1024 * 1024;
const _wifi = NetworkState(online: true, metered: false);
const _hotspot = NetworkState(online: true, metered: true);

/// photo_manager hands out files only on Android and Apple platforms.
final _readsFiles = Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

/// Backup switched on and up to date, whose passes the test runs itself.
class _Backup extends BackupController {
  int scheduled = 0;

  @override
  BackupState build() {
    super.build();
    return const BackupState(phase: BackupPhase.upToDate);
  }

  @override
  void schedule({bool immediate = false}) => scheduled++;
}

class _Sync extends DriveSync {
  @override
  SyncState build() => const SyncState();

  @override
  Future<void> whenIdle() async {}
}

/// A drive whose backup folders are there already, holding nothing yet.
class _Repository extends DriveRepository {
  _Repository(super.ref);

  @override
  Future<String> ensureFolderPath(List<String> names) async => names.join('/');

  @override
  Future<Map<String, ({String fileId, bool smallCopy})>> mediaFingerprints() async => {};
}

/// A phone whose connection the test moves.
class _Network extends NetworkStatus {
  _Network(this._initial);

  final NetworkState _initial;

  @override
  NetworkState build() => _initial;

  void set(NetworkState next) => state = next;
}

/// A queue that sends nothing. Uploads run until [finish], unless [finishesAtOnce]
/// lets them finish at once, and follow the network the way the real
/// queue does: Wi-Fi-only ones wait on mobile data, stepping back if they
/// are under way, and run again on Wi-Fi.
class _Queue extends TransferQueue {
  final uploads = <UploadRequest>[];
  final Map<String, TransferRow> _byId = {};
  final Map<String, Completer<TransferRow>> _ends = {};

  /// Whether an upload of this name finishes as soon as it starts.
  bool Function(String name) finishesAtOnce = (_) => true;

  @override
  TransfersState build() {
    ref.listen<NetworkState>(networkStatusProvider, (_, next) => _follow(next));
    return TransfersState.empty;
  }

  @override
  Future<List<String>> enqueueUploads(List<UploadRequest> requests, {String? folderId}) async {
    final ids = <String>[];
    for (final request in requests) {
      uploads.add(request);
      final id = 'u${uploads.length}';
      _byId[id] = TransferRow(
        id: id,
        kind: TransferKind.upload,
        status: TransferStatus.running,
        name: request.name,
        mimeType: mimeTypeFor(request.name),
        fileId: 'file-$id',
        ownsSource: request.ownsSource,
        wifiOnly: request.wifiOnly,
        totalBytes: request.size ?? 0,
        doneBytes: 0,
        partCount: 1,
        completedParts: 0,
        createdAt: DateTime.now(),
        origin: request.origin,
        assetId: request.assetId,
      );
      ids.add(id);
    }
    _follow(ref.read(networkStatusProvider));
    for (final id in ids) {
      if (_byId[id]!.status == TransferStatus.running && finishesAtOnce(_byId[id]!.name)) {
        scheduleMicrotask(() => finish(id));
      }
    }
    return ids;
  }

  @override
  Future<TransferRow> whenFinished(String id) => (_ends[id] ??= Completer()).future;

  TransferRow row(String id) => _byId[id]!;

  void finish(String id) {
    final row = _byId[id] = _byId[id]!.copyWith(status: TransferStatus.completed);
    _follow(ref.read(networkStatusProvider));
    (_ends[id] ??= Completer()).complete(row);
  }

  @override
  Future<void> waitForWifi(Iterable<String> ids) async {
    for (final id in ids) {
      _byId[id] = _byId[id]!.copyWith(wifiOnly: true);
    }
    _follow(ref.read(networkStatusProvider));
  }

  @override
  Future<void> useMobileData(Iterable<String> ids) async {
    for (final id in ids) {
      _byId[id] = _byId[id]!.copyWith(wifiOnly: false);
    }
    _follow(ref.read(networkStatusProvider));
  }

  void _follow(NetworkState network) {
    for (final row in _byId.values.toList()) {
      if (!row.status.isPending) continue;
      final waits = row.wifiOnly && network.metered;
      _byId[row.id] = row.copyWith(status: waits ? TransferStatus.queued : TransferStatus.running);
    }
    state = TransfersState([
      for (final row in _byId.values.toList().reversed)
        TransferItem(
          row,
          wait: row.status == TransferStatus.queued ? const WaitingForWifi() : null,
        ),
    ]);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const photos = MethodChannel('com.fluttercandies/photo_manager');
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  late Directory dir;

  /// The phone's photos and videos, newest first, as photo_manager lists
  /// them, and the files behind them.
  late List<Map<String, Object>> library;
  late Map<String, String> files;

  /// Adds a photo or video of [megabytes] to the library, older than what
  /// is there already.
  Future<void> add(String id, {required int megabytes, bool video = false}) async {
    final name = video ? 'VID_$id.mp4' : 'IMG_$id.jpg';
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
    dir = await Directory.systemTemp.createTemp('telegrive_backup_data');
    library = [];
    files = {};
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      photos,
      (call) async => switch (call.method) {
        'getPermissionState' => PermissionState.authorized.index,
        'getAssetPathList' => {
          'data': [
            if (library.isNotEmpty)
              {'id': 'all', 'name': 'Recent', 'isAll': true, 'assetCount': library.length},
          ],
        },
        'getAssetCountFromPath' => library.length,
        'getAssetListRange' => {'data': library},
        'getFullFile' => files[(call.arguments as Map)['id']],
        _ => null,
      },
    );
    // A cache of its own, so the library's files never count as copies to
    // delete.
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
    required BackupMobileData mobileData,
    Map<String, Object> prefs = const {},
  }) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({
      BackupPrefKeys.enabled: true,
      BackupPrefKeys.mobileData: mobileData.name,
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

  test('with mobile data for photos only, photos go up and videos wait for Wi-Fi', () async {
    await add('v1', megabytes: 40, video: true);
    await add('p1', megabytes: 3);
    await add('p2', megabytes: 3);
    final container = await open(network: _hotspot, mobileData: BackupMobileData.photos);
    final queue = container.read(transferQueueProvider.notifier) as _Queue;

    await container.read(backupControllerProvider.notifier).run();

    expect([
      for (final upload in queue.uploads) upload.name,
    ], unorderedEquals(['IMG_p1.jpg', 'IMG_p2.jpg']));
    expect(queue.uploads.every((upload) => !upload.wifiOnly), isTrue);
    final backup = container.read(backupControllerProvider);
    expect(backup.phase, BackupPhase.waitingForWifi);
    expect(backup.heldVideos, 1);
    expect(backup.done, 2);
    expect(describeBackup(backup).title, 'Videos wait for Wi-Fi');
  }, skip: _readsFiles ? false : 'photo_manager reads files on Android and Apple platforms only');

  test('a video too big for the monthly limit waits while the photos behind it go', () async {
    await add('v1', megabytes: 30, video: true);
    await add('p1', megabytes: 3);
    await add('p2', megabytes: 3);
    // 240 MB of a 250 MB limit used this period.
    final container = await open(
      network: _hotspot,
      mobileData: BackupMobileData.all,
      prefs: {
        'data_limit_bytes': 250 * _mb,
        'data_limit_renew_day': 3,
        'data_period_start': DataPeriod.startFor(DateTime.now(), 3).millisecondsSinceEpoch,
        'data_mobile_baseline': 0,
        'data_wifi_baseline': 0,
        'data_mobile_carry': 240 * _mb,
        'data_wifi_carry': 0,
        'data_stats_since': 0,
      },
    );
    final controller = container.read(backupControllerProvider.notifier) as _Backup;
    final queue = container.read(transferQueueProvider.notifier) as _Queue;

    await controller.run();

    expect([
      for (final upload in queue.uploads) upload.name,
    ], unorderedEquals(['IMG_p1.jpg', 'IMG_p2.jpg']));
    var backup = container.read(backupControllerProvider);
    expect(backup.phase, BackupPhase.waitingForBudget);
    expect(backup.heldForBudget, 1);
    expect(
      describeBackup(backup, renewDay: 3).detail,
      '1 item left. Backup carries on over Wi-Fi, or on the 3rd.',
    );

    controller.useDataAnyway();
    expect(controller.scheduled, 1);
    await controller.run();

    expect(queue.uploads.map((upload) => upload.name), contains('VID_v1.mp4'));
    backup = container.read(backupControllerProvider);
    expect(backup.phase, BackupPhase.upToDate);
    expect(backup.done, 3);
  }, skip: _readsFiles ? false : 'photo_manager reads files on Android and Apple platforms only');

  test(
    'leaving Wi-Fi with photos only steps a video back, and Wi-Fi carries the same upload on',
    () async {
      await add('v1', megabytes: 40, video: true);
      final container = await open(network: _wifi, mobileData: BackupMobileData.photos);
      final controller = container.read(backupControllerProvider.notifier) as _Backup;
      final queue = container.read(transferQueueProvider.notifier) as _Queue;
      final network = container.read(networkStatusProvider.notifier) as _Network;
      queue.finishesAtOnce = (_) => false;

      final first = controller.run();
      while (queue.uploads.isEmpty) {
        await pumpEventQueue();
      }
      expect(queue.uploads.single.wifiOnly, isTrue);
      network.set(_hotspot);
      await first;

      expect(queue.row('u1').status, TransferStatus.queued);
      var backup = container.read(backupControllerProvider);
      expect(backup.phase, BackupPhase.waitingForWifi);
      expect(backup.heldVideos, 1);

      network.set(_wifi);
      expect(controller.scheduled, 1);
      expect(queue.row('u1').status, TransferStatus.running);
      final second = controller.run();
      await pumpEventQueue();
      queue.finish('u1');
      await second;

      expect(queue.uploads, hasLength(1));
      backup = container.read(backupControllerProvider);
      expect(backup.phase, BackupPhase.upToDate);
      expect(backup.done, 1);
    },
    skip: _readsFiles ? false : 'photo_manager reads files on Android and Apple platforms only',
  );
}
