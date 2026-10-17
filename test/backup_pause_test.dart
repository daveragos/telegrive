import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegrive/core/format/formatters.dart';
import 'package:telegrive/features/backup/data/background_backup.dart';
import 'package:telegrive/features/backup/data/backup_controller.dart';
import 'package:telegrive/features/backup/presentation/backup_card.dart';
import 'package:telegrive/features/backup/presentation/backup_pause_sheet.dart';
import 'package:telegrive/features/drive/data/drive_session.dart';
import 'package:telegrive/features/drive/data/drive_sync.dart';
import 'package:telegrive/features/transfers/data/transfer_queue.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';
import 'package:telegrive/infrastructure/network/network_status.dart';
import 'package:telegrive/infrastructure/storage/preferences.dart';

import 'support/fake_telegram.dart';

/// Backup as the app runs it, counting the passes it is asked to schedule
/// rather than running them.
class _Backup extends BackupController {
  int scheduled = 0;

  @override
  void schedule({bool immediate = false}) => scheduled++;
}

class _Sync extends DriveSync {
  @override
  SyncState build() => const SyncState();

  @override
  Future<void> whenIdle() async {}
}

class _Wifi extends NetworkStatus {
  @override
  NetworkState build() => const NetworkState(online: true, metered: false);
}

/// A queue holding [_items] that pauses, resumes and cancels them in
/// place, and remembers what it was asked to send.
class _Queue extends TransferQueue {
  _Queue(this._items);

  final List<TransferItem> _items;
  final List<String> cancelled = [];
  final List<String> enqueued = [];

  @override
  TransfersState build() => TransfersState(_items);

  void _move(bool Function(TransferRow row) which, bool Function(TransferStatus s) from, TransferStatus to) {
    state = TransfersState([
      for (final item in state.items)
        if (which(item.row) && from(item.status))
          TransferItem(item.row.copyWith(status: to))
        else
          item,
    ]);
  }

  @override
  Future<void> pauseAll(bool Function(TransferRow row) which) async =>
      _move(which, (s) => s.isActive, TransferStatus.paused);

  @override
  Future<void> resumeAll(bool Function(TransferRow row) which) async =>
      _move(which, (s) => s == TransferStatus.paused, TransferStatus.queued);

  @override
  Future<void> cancel(String id) async => cancelled.add(id);

  @override
  Future<List<String>> enqueueUploads(List<UploadRequest> requests, {String? folderId}) async {
    enqueued.addAll(requests.map((r) => r.name));
    return const [];
  }
}

TransferItem _upload(String id, TransferOrigin origin) => TransferItem(
  TransferRow(
    id: id,
    kind: TransferKind.upload,
    status: TransferStatus.running,
    name: '$id.jpg',
    mimeType: 'image/jpeg',
    fileId: id,
    ownsSource: false,
    wifiOnly: false,
    totalBytes: 10,
    doneBytes: 4,
    partCount: 1,
    completedParts: 0,
    createdAt: DateTime(2026, 10, 2),
    origin: origin,
    assetId: origin == TransferOrigin.backup ? 'asset-$id' : null,
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
  late List<Map<String, Object>> library;
  void Function()? onScan;

  setUp(() {
    libraryCalls = [];
    library = [];
    onScan = null;
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
    Map<String, Object> prefs = const {},
    List<TransferItem> transfers = const [],
  }) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({
      BackupPrefKeys.enabled: true,
      BackupPrefKeys.mobileData: BackupMobileData.all.name,
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
        networkStatusProvider.overrideWith(_Wifi.new),
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

  group('pausing backup', () {
    test('holds its uploads where they are, leaves yours, and is saved', () async {
      final container = await open(
        transfers: [_upload('photo', TransferOrigin.backup), _upload('mine', TransferOrigin.manual)],
      );
      final until = DateTime.now().add(const Duration(hours: 1));

      await container.read(backupControllerProvider.notifier).pause(until);

      final backup = container.read(backupControllerProvider);
      expect(backup.phase, BackupPhase.paused);
      expect(backup.pauseEnds, until);
      final queue = container.read(transferQueueProvider);
      expect(queue.byId('photo')!.status, TransferStatus.paused);
      expect(queue.byId('mine')!.status, TransferStatus.running);
      final saved = container.read(preferencesProvider).backupPause;
      expect(saved?.until?.millisecondsSinceEpoch, until.millisecondsSinceEpoch);
    });

    test('starts no pass while it lasts', () async {
      library = [_photo('p1')];
      final container = await open();
      final controller = container.read(backupControllerProvider.notifier);

      await controller.pause();
      await controller.run();

      expect(libraryCalls, isNot(contains('getAssetPathList')));
      expect(container.read(backupControllerProvider).phase, BackupPhase.paused);
    });

    test('while the library is read keeps the counts, sends nothing, and never reads as '
        'backing up', () async {
      library = [_photo('p1')];
      final container = await open();
      final controller = container.read(backupControllerProvider.notifier);
      final phases = <BackupPhase>[];
      container.listen(
        backupControllerProvider.select((s) => s.phase),
        (_, next) => phases.add(next),
      );
      onScan = () => unawaited(controller.pause());

      await controller.run();
      await pumpEventQueue();

      final backup = container.read(backupControllerProvider);
      expect(backup.phase, BackupPhase.paused);
      expect(backup.total, 1);
      expect(phases.skipWhile((p) => p != BackupPhase.paused), everyElement(BackupPhase.paused));
      expect((container.read(transferQueueProvider.notifier) as _Queue).enqueued, isEmpty);
    });

    test('resuming lets its uploads go on and looks for what is left', () async {
      final container = await open(transfers: [_upload('photo', TransferOrigin.backup)]);
      final controller = container.read(backupControllerProvider.notifier) as _Backup;
      await controller.pause();

      await controller.resume();

      expect(container.read(transferQueueProvider).byId('photo')!.status, TransferStatus.queued);
      expect(container.read(preferencesProvider).backupPause, isNull);
      expect(container.read(backupControllerProvider).phase, BackupPhase.scanning);
      expect(controller.scheduled, 1);
    });

    test('ends by itself once its time is up', () async {
      final container = await open();
      final controller = container.read(backupControllerProvider.notifier) as _Backup;

      await controller.pause(DateTime.now().add(const Duration(milliseconds: 20)));
      expect(container.read(backupControllerProvider).phase, BackupPhase.paused);
      await Future<void>.delayed(const Duration(milliseconds: 1200));

      expect(container.read(preferencesProvider).backupPause, isNull);
      expect(container.read(backupControllerProvider).phase, BackupPhase.scanning);
      expect(controller.scheduled, 1);
    });

    test('turning backup off ends it and cancels the uploads it held', () async {
      final container = await open(transfers: [_upload('photo', TransferOrigin.backup)]);
      final controller = container.read(backupControllerProvider.notifier);
      await controller.pause();

      await controller.disable();

      expect(container.read(preferencesProvider).backupPause, isNull);
      expect((container.read(transferQueueProvider.notifier) as _Queue).cancelled, ['photo']);
      expect(container.read(backupControllerProvider).phase, BackupPhase.off);
    });
  });

  group('a pause when the app opens again', () {
    test('with time left still holds backup', () async {
      final until = DateTime.now().add(const Duration(hours: 2));
      final container = await open(
        prefs: {
          BackupPrefKeys.paused: true,
          BackupPrefKeys.pausedUntil: until.millisecondsSinceEpoch,
        },
      );

      final backup = container.read(backupControllerProvider);
      expect(backup.phase, BackupPhase.paused);
      expect(backup.pauseEnds?.millisecondsSinceEpoch, until.millisecondsSinceEpoch);
    });

    test('until resumed still holds backup', () async {
      final container = await open(prefs: {BackupPrefKeys.paused: true});

      final backup = container.read(backupControllerProvider);
      expect(backup.phase, BackupPhase.paused);
      expect(backup.pauseEnds, isNull);
    });

    test('whose time passed is over', () async {
      final container = await open(
        prefs: {
          BackupPrefKeys.paused: true,
          BackupPrefKeys.pausedUntil: DateTime.now()
              .subtract(const Duration(minutes: 1))
              .millisecondsSinceEpoch,
        },
      );

      expect(container.read(backupControllerProvider).phase, BackupPhase.waitingForDrive);
      await pumpEventQueue();
      expect(container.read(preferencesProvider).backupPause, isNull);
    });

    test('leaves the background job done with the pass', () {
      expect(
        BackgroundBackup.isDone(const BackupState(phase: BackupPhase.paused, total: 10, done: 2)),
        isTrue,
      );
    });
  });

  group('the words for a pause', () {
    final now = DateTime(2026, 10, 18, 22, 5);

    test('tomorrow morning is eight the next day, past a month\'s end too', () {
      expect(tomorrowMorning(now), DateTime(2026, 10, 19, 8));
      expect(tomorrowMorning(DateTime(2026, 10, 31, 23, 30)), DateTime(2026, 11, 1, 8));
    });

    test('later today, tomorrow, another day, another year', () {
      expect(Formatters.at(DateTime(2026, 10, 18, 23, 5), now: now), startsWith('at '));
      expect(Formatters.at(DateTime(2026, 10, 19, 8), now: now), startsWith('tomorrow at '));
      expect(Formatters.at(DateTime(2026, 10, 21, 8), now: now), startsWith('on Oct 21 at '));
      expect(Formatters.at(DateTime(2027, 1, 2, 8), now: now), startsWith('on Jan 2, 2027 at '));
    });

    test('say what waits and when backup carries on', () {
      final ends = DateTime(2026, 10, 19, 8);
      expect(
        pausedDetail(0, null, now: now),
        'New photos wait. Backup carries on when you resume it.',
      );
      expect(
        pausedDetail(5, null, now: now),
        '5 items left. Backup carries on when you resume it.',
      );
      expect(
        pausedDetail(1, ends, now: now),
        '1 item left. Backup carries on by itself ${Formatters.at(ends, now: now)}.',
      );
    });
  });
}
