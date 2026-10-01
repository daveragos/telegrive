import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegrive/features/backup/data/backup_controller.dart';
import 'package:telegrive/features/drive/data/drive_session.dart';
import 'package:telegrive/features/drive/data/drive_sync.dart';
import 'package:telegrive/features/transfers/data/transfer_queue.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';
import 'package:telegrive/infrastructure/network/network_status.dart';
import 'package:telegrive/infrastructure/storage/preferences.dart';

import 'support/fake_telegram.dart';

const _wifi = NetworkState(online: true, metered: false);
const _hotspot = NetworkState(online: true, metered: true);

/// Backup switched on, up to date and listening to the network, counting
/// the passes it is asked to schedule rather than running them.
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

/// A phone whose connection the test moves.
class _Network extends NetworkStatus {
  _Network(this._initial);

  final NetworkState _initial;

  @override
  NetworkState build() => _initial;

  void set(NetworkState next) => state = next;
}

/// A queue holding [items], remembering what was let onto mobile data.
class _Queue extends TransferQueue {
  _Queue(this.items);

  final List<TransferItem> items;
  final List<String> released = [];

  @override
  TransfersState build() => TransfersState(items);

  @override
  Future<void> useMobileData(Iterable<String> ids) async => released.addAll(ids);
}

TransferItem _upload(String id, {required TransferOrigin origin, required bool wifiOnly}) =>
    TransferItem(
      TransferRow(
        id: id,
        kind: TransferKind.upload,
        status: TransferStatus.queued,
        name: '$id.jpg',
        mimeType: 'image/jpeg',
        fileId: id,
        ownsSource: false,
        wifiOnly: wifiOnly,
        totalBytes: 10,
        doneBytes: 0,
        partCount: 1,
        completedParts: 0,
        createdAt: DateTime(2026, 10, 2),
        origin: origin,
      ),
    );

/// A photo in the phone's Camera folder.
Map<String, Object> _photo(String id) => {
  'id': id,
  'type': 1,
  'width': 4000,
  'height': 3000,
  'createDt': DateTime(2026, 9, 25).millisecondsSinceEpoch ~/ 1000,
  'relativePath': 'DCIM/Camera/',
  'title': 'IMG_$id.jpg',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const photos = MethodChannel('com.fluttercandies/photo_manager');
  late List<String> libraryCalls;

  /// Runs while the library is being read.
  void Function()? onScan;

  /// The phone's photos, none until a test adds some.
  late List<Map<String, Object>> library;

  setUp(() {
    libraryCalls = [];
    onScan = null;
    library = [];
    // Photo access granted, and the photos in [library].
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      photos,
      (call) async {
        libraryCalls.add(call.method);
        if (call.method == 'getAssetPathList') onScan?.call();
        return switch (call.method) {
          'getPermissionState' => PermissionState.authorized.index,
          'getAssetPathList' => {
            'data': [
              if (library.isNotEmpty)
                {'id': 'all', 'name': 'Recent', 'isAll': true, 'assetCount': library.length},
            ],
          },
          'getAssetCountFromPath' => library.length,
          'getAssetListRange' => {'data': library},
          _ => null,
        };
      },
    );
  });

  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(photos, null),
  );

  Future<ProviderContainer> open({
    required NetworkState network,
    required bool wifiOnly,
    List<TransferItem> transfers = const [],
  }) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({
      BackupPrefKeys.enabled: true,
      'backup_wifi_only': wifiOnly,
      'full_sync_$testChatId': DateTime.now().millisecondsSinceEpoch,
    });
    final shared = await SharedPreferences.getInstance();
    final db = AppDatabase(NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(shared),
        appDatabaseProvider.overrideWithValue(db),
        driveSessionProvider.overrideWith(TestSession.new),
        driveSyncProvider.overrideWith(_Sync.new),
        networkStatusProvider.overrideWith(() => _Network(network)),
        transferQueueProvider.overrideWith(() => _Queue(transfers)),
        backupControllerProvider.overrideWith(_Backup.new),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    return container;
  }

  test('on a hotspot, Wi-Fi-only backup counts the library and waits for Wi-Fi', () async {
    library = [_photo('p1')];
    final container = await open(network: _hotspot, wifiOnly: true);

    await container.read(backupControllerProvider.notifier).run();

    expect(libraryCalls, contains('getAssetPathList'));
    expect(container.read(backupControllerProvider).phase, BackupPhase.waitingForWifi);
  });

  test('on a hotspot with nothing new, Wi-Fi-only backup is up to date', () async {
    final container = await open(network: _hotspot, wifiOnly: true);

    await container.read(backupControllerProvider.notifier).run();

    expect(container.read(backupControllerProvider).phase, BackupPhase.upToDate);
  });

  test('moving onto mobile data while the library is read waits for Wi-Fi', () async {
    library = [_photo('p1')];
    final container = await open(network: _wifi, wifiOnly: true);
    final controller = container.read(backupControllerProvider.notifier) as _Backup;
    final network = container.read(networkStatusProvider.notifier) as _Network;
    onScan = () => network.set(_hotspot);

    await controller.run();

    expect(libraryCalls, contains('getAssetPathList'));
    expect(container.read(backupControllerProvider).phase, BackupPhase.waitingForWifi);
    expect(controller.scheduled, 0);

    network.set(_wifi);
    expect(controller.scheduled, 1);
  });

  test('with mobile data allowed, a hotspot does not hold backup up', () async {
    final container = await open(network: _hotspot, wifiOnly: false);

    await container.read(backupControllerProvider.notifier).run();

    expect(container.read(backupControllerProvider).phase, BackupPhase.upToDate);
  });

  test('allowing mobile data lets backup uploads waiting for Wi-Fi go', () async {
    final container = await open(
      network: _hotspot,
      wifiOnly: true,
      transfers: [
        _upload('photo', origin: TransferOrigin.backup, wifiOnly: true),
        _upload('mine', origin: TransferOrigin.manual, wifiOnly: true),
      ],
    );
    final controller = container.read(backupControllerProvider.notifier) as _Backup;

    await controller.setWifiOnly(false);

    final queue = container.read(transferQueueProvider.notifier) as _Queue;
    expect(queue.released, ['photo']);
    expect(controller.scheduled, 1);
  });
}
