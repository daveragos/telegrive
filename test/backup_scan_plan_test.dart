import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegrive/features/backup/data/backup_controller.dart';
import 'package:telegrive/features/backup/presentation/backup_card.dart';
import 'package:telegrive/features/drive/data/drive_repository.dart';
import 'package:telegrive/features/drive/data/drive_session.dart';
import 'package:telegrive/features/drive/data/drive_sync.dart';
import 'package:telegrive/features/transfers/data/transfer_queue.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';
import 'package:telegrive/infrastructure/network/network_status.dart';
import 'package:telegrive/infrastructure/storage/device_profile.dart';
import 'package:telegrive/infrastructure/storage/preferences.dart';
import 'package:telegrive/infrastructure/telegram/telegram_exception.dart';

import 'support/fake_telegram.dart';

/// photo_manager hands out files only on Android and Apple platforms.
final _readsFiles = Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

const _wifi = NetworkState(online: true, metered: false);
const _hotspot = NetworkState(online: true, metered: true);

/// Backup switched on, whose passes run only when the test runs them.
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

/// A drive whose backup folders are there already, holding nothing yet. The
/// read of what the drive holds waits for [gate] when there is one.
class _Repository extends DriveRepository {
  _Repository(super.ref, this.gate);

  final Future<void>? gate;

  @override
  Future<String> ensureFolderPath(List<String> names) async => names.join('/');

  @override
  Future<Map<String, ({String fileId, bool smallCopy})>> mediaFingerprints() async {
    await gate;
    return {};
  }
}

/// A phone whose connection the test sets.
class _Network extends NetworkStatus {
  _Network(this._initial);

  final NetworkState _initial;

  @override
  NetworkState build() => _initial;
}

/// A queue that sends nothing. An upload finishes as soon as it starts,
/// unless [holds] names it: it then stays under way until the test finishes
/// it or the pass cancels it. Queueing fails with [error] when that is set.
class _Queue extends TransferQueue {
  final uploads = <UploadRequest>[];
  final cancelled = <String>[];
  final Map<String, TransferRow> _rows = {};
  final Map<String, Completer<TransferRow>> _ends = {};

  bool Function(String name) holds = (_) => false;
  Object? error;

  @override
  TransfersState build() => TransfersState.empty;

  @override
  Future<List<String>> enqueueUploads(List<UploadRequest> requests, {String? folderId}) async {
    if (error case final error?) throw error;
    final ids = <String>[];
    for (final request in requests) {
      uploads.add(request);
      final id = 'u${uploads.length}';
      _rows[id] = TransferRow(
        id: id,
        kind: TransferKind.upload,
        status: TransferStatus.running,
        name: request.name,
        mimeType: 'image/jpeg',
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
    _publish();
    for (final id in ids) {
      if (!holds(_rows[id]!.name)) scheduleMicrotask(() => finish(id));
    }
    return ids;
  }

  @override
  Future<TransferRow> whenFinished(String id) => (_ends[id] ??= Completer()).future;

  @override
  Future<void> cancel(String id) async {
    cancelled.add(id);
    _end(id, TransferStatus.cancelled);
  }

  void finish(String id) => _end(id, TransferStatus.completed);

  void _end(String id, TransferStatus status) {
    final row = _rows[id] = _rows[id]!.copyWith(status: status);
    _publish();
    (_ends[id] ??= Completer()).complete(row);
  }

  void _publish() =>
      state = TransfersState([for (final row in _rows.values.toList().reversed) TransferItem(row)]);
}

/// A photo in the phone's Camera folder, added at [at].
Map<String, Object> _photo(String id, [DateTime? at]) => {
  'id': id,
  'type': 1,
  'width': 4000,
  'height': 3000,
  'createDt': (at ?? DateTime(2026, 9, 25)).millisecondsSinceEpoch ~/ 1000,
  'relativePath': 'DCIM/Camera/',
  'title': 'IMG_$id.jpg',
};

/// The earliest addition date [arguments] ask the library for.
int _since(Object? arguments) {
  final option = (arguments! as Map)['option'] as Map;
  return ((option['child'] as Map)['createDate'] as Map)['min'] as int;
}

/// The photo library telling the app it changed.
Future<void> _libraryChanges() =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      'com.fluttercandies/photo_manager/notify',
      const StandardMethodCodec().encodeMethodCall(const MethodCall('change', {'type': 'insert'})),
      (_) {},
    );

/// An opened container, with what the tests reach into.
class _Open {
  const _Open(this.container);

  final ProviderContainer container;

  _Backup get controller => container.read(backupControllerProvider.notifier) as _Backup;
  _Queue get queue => container.read(transferQueueProvider.notifier) as _Queue;
  Preferences get prefs => container.read(preferencesProvider);
  AppDatabase get db => container.read(appDatabaseProvider);
  BackupState get state => container.read(backupControllerProvider);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 10, 4, 9);
  final checkpoint = DateTime(2026, 10, 4, 2);

  group('a pass looks through the whole library', () {
    test('when it never has', () {
      expect(
        BackupController.fullScanDue(lastFullScan: null, checkpoint: checkpoint, now: now),
        isTrue,
      );
    });

    test('when it last did a day or more ago', () {
      expect(
        BackupController.fullScanDue(
          lastFullScan: now.subtract(const Duration(hours: 25)),
          checkpoint: checkpoint,
          now: now,
        ),
        isTrue,
      );
    });

    test('after a change to what is backed up, which forgets the last look', () {
      // Changing folders or videos removes when it last looked, which reads
      // the same as never having looked.
      expect(BackupController.fullScanDue(checkpoint: checkpoint, now: now), isTrue);
    });

    test('while no pass has dealt with everything yet', () {
      expect(
        BackupController.fullScanDue(
          lastFullScan: now.subtract(const Duration(hours: 2)),
          checkpoint: null,
          now: now,
        ),
        isTrue,
      );
    });

    test('when the clock says the last look is still to come', () {
      expect(
        BackupController.fullScanDue(
          lastFullScan: now.add(const Duration(hours: 3)),
          checkpoint: checkpoint,
          now: now,
        ),
        isTrue,
      );
    });

    test('but only at the newest photos within the day', () {
      expect(
        BackupController.fullScanDue(
          lastFullScan: now.subtract(const Duration(hours: 23)),
          checkpoint: checkpoint,
          now: now,
        ),
        isFalse,
      );
    });
  });

  group('after a look at the newest photos', () {
    test('the total is the records in scope plus the new photos', () {
      // 12,000 records, 3 of them for photos the last full look didn't
      // find, and 5 photos new since.
      final totals = BackupController.incrementalTotals(
        records: 12000,
        unfound: 3,
        unrecorded: 5,
        pending: 5,
        failed: 0,
      );
      expect(totals, (total: 12002, done: 11997));
    });

    test('photos still to be tried again and out of tries are not done', () {
      final totals = BackupController.incrementalTotals(
        records: 100,
        unfound: 0,
        unrecorded: 2,
        pending: 4,
        failed: 3,
      );
      expect(totals, (total: 102, done: 95));
    });

    test('photos sent up by passes since the full look count as done', () {
      // The full look found 40 photos with records; two passes since sent
      // up 6 more, so they have records too, and nothing is new now.
      final totals = BackupController.incrementalTotals(
        records: 46,
        unfound: 0,
        unrecorded: 0,
        pending: 0,
        failed: 0,
      );
      expect(totals, (total: 46, done: 46));
    });

    test('counts never go below nothing', () {
      final totals = BackupController.incrementalTotals(
        records: 2,
        unfound: 5,
        unrecorded: 1,
        pending: 3,
        failed: 1,
      );
      expect(totals, (total: 1, done: 0));
    });
  });

  group('coming back to the app', () {
    final lastPass = DateTime(2026, 10, 4, 8, 50);

    bool due({
      DateTime? lastPass,
      bool upToDate = true,
      bool libraryChanged = false,
      DateTime? at,
    }) => BackupController.resumeDue(
      lastPass: lastPass,
      upToDate: upToDate,
      libraryChanged: libraryChanged,
      now: at ?? now,
    );

    test('looks for new photos when no pass has run yet', () {
      expect(due(), isTrue);
    });

    test('leaves a pass that left everything up to date alone for 15 minutes', () {
      expect(due(lastPass: lastPass), isFalse);
      expect(due(lastPass: lastPass, at: lastPass.add(const Duration(minutes: 14))), isFalse);
    });

    test('looks again after 15 minutes', () {
      expect(due(lastPass: lastPass, at: lastPass.add(const Duration(minutes: 15))), isTrue);
    });

    test('looks again when the library changed since', () {
      expect(due(lastPass: lastPass, libraryChanged: true), isTrue);
    });

    test('looks again when the last pass left something to do', () {
      expect(due(lastPass: lastPass, upToDate: false), isTrue);
    });

    test('looks when the clock says the last pass is still to come', () {
      expect(due(lastPass: now.add(const Duration(hours: 3))), isTrue);
    });
  });

  group('a pass in the app', () {
    const photos = MethodChannel('com.fluttercandies/photo_manager');
    const paths = MethodChannel('plugins.flutter.io/path_provider');
    late Directory dir;

    /// The phone's photos, and the files behind the ones that have one.
    late List<Map<String, Object>> library;
    late Map<String, String> files;

    /// The earliest addition dates the library was asked for, in order.
    late List<int> asked;

    /// Runs while the library is being read, which waits for it.
    Future<void> Function()? onScan;

    var since = 0;

    /// Adds a photo with a file, newest last.
    Future<void> add(String id) async {
      final file = File('${dir.path}/library/IMG_$id.jpg');
      await file.create(recursive: true);
      await file.writeAsBytes(List.filled(1024, 7));
      files[id] = file.path;
      library.add(_photo(id));
    }

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('telegrive_scan_plan');
      library = [];
      files = {};
      asked = [];
      onScan = null;
      since = 0;
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      // The photos added at or after the earliest date asked for, as the
      // library answers.
      List<Map<String, Object>> visible() => [
        for (final photo in library)
          if ((photo['createDt']! as int) * 1000 >= since) photo,
      ];
      messenger.setMockMethodCallHandler(photos, (call) async {
        if (call.method == 'getAssetPathList') {
          since = _since(call.arguments);
          asked.add(since);
          await onScan?.call();
        }
        return switch (call.method) {
          'getPermissionState' => PermissionState.authorized.index,
          'getAssetPathList' => {
            'data': [
              if (visible().isNotEmpty)
                {'id': 'all', 'name': 'Recent', 'isAll': true, 'assetCount': visible().length},
            ],
          },
          'getAssetCountFromPath' => visible().length,
          'getAssetListRange' => {'data': visible()},
          'getFullFile' => files[(call.arguments as Map)['id']],
          _ => null,
        };
      });
      messenger.setMockMethodCallHandler(paths, (call) async => '${dir.path}/cache');
    });

    tearDown(() async {
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(photos, null);
      messenger.setMockMethodCallHandler(paths, null);
      await dir.delete(recursive: true);
    });

    Future<_Open> open({
      Map<String, Object> prefs = const {},
      NetworkState network = _wifi,
      bool saveMemory = false,
      Future<void>? gate,
    }) async {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({
        BackupPrefKeys.enabled: true,
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
          driveRepositoryProvider.overrideWith((ref) => _Repository(ref, gate)),
          networkStatusProvider.overrideWith(() => _Network(network)),
          saveMemoryProvider.overrideWithBuild((ref, notifier) => saveMemory),
          transferQueueProvider.overrideWith(_Queue.new),
          backupControllerProvider.overrideWith(_Backup.new),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await db.close();
      });
      return _Open(container);
    }

    test('looks only at the photos added since everything was dealt with', () async {
      final app = await open();
      final controller = app.controller;

      // Two photos backed up already, and one record for a photo that has
      // since left the phone.
      library = [_photo('p1'), _photo('p2')];
      await app.db.markAssetsBackedUp(['p1', 'p2', 'gone']);
      await controller.run();
      expect(asked.single, 0);
      expect((app.state.phase, app.state.total, app.state.done), (BackupPhase.upToDate, 2, 2));
      final dealtWith = app.prefs.backupCheckpoint!;

      // A photo arrived, and was recognised as already in the drive.
      library = [_photo('p3', DateTime.now())];
      await app.db.markAssetsBackedUp(['p3']);
      await controller.run();
      expect(asked.last, dealtWith.subtract(const Duration(hours: 1)).millisecondsSinceEpoch);
      expect((app.state.phase, app.state.total, app.state.done), (BackupPhase.upToDate, 3, 3));

      // Leaving videos out changes what is backed up, so the next pass
      // looks through everything again.
      await controller.setIncludeVideos(false);
      library = [_photo('p1'), _photo('p2'), _photo('p3')];
      await controller.run();
      expect(asked.last, 0);
      expect((app.state.total, app.state.done), (3, 3));
    });

    test(
      'a look through the library that ends early is still due, and finds the old photos',
      () async {
        // Everything up to five hours ago was dealt with, and a photo from
        // days before is still to go. Videos were just switched off, which
        // asks for a look through everything, and the phone is on mobile
        // data that backup may not use, so the pass ends waiting.
        library = [_photo('old', DateTime.now().subtract(const Duration(days: 3)))];
        final app = await open(
          network: _hotspot,
          prefs: {BackupPrefKeys.mobileData: BackupMobileData.off.name},
        );
        final earlier = DateTime.now().subtract(const Duration(hours: 5));
        await app.prefs.setBackupCompleted(earlier);
        await app.prefs.setBackupFullScan(earlier, unfound: 0);
        await app.controller.setIncludeVideos(false);

        await app.controller.run();
        expect(app.state.phase, BackupPhase.waitingForWifi);
        expect(app.state.total, 1);
        expect(app.prefs.backupLastFullScan, isNull);
        expect(
          BackupController.fullScanDue(
            lastFullScan: app.prefs.backupLastFullScan,
            checkpoint: app.prefs.backupCheckpoint,
            now: DateTime.now(),
          ),
          isTrue,
        );

        await app.controller.run();
        expect(asked.last, 0);
        expect(app.state.total, 1);
        expect([for (final photo in app.state.waiting) photo.assetId], ['old']);
      },
    );

    test('a look through the library that deals with everything is recorded', () async {
      library = [_photo('p1')];
      final app = await open();
      await app.db.markAssetsBackedUp(['p1', 'gone']);

      await app.controller.run();

      expect(app.state.phase, BackupPhase.upToDate);
      expect(app.prefs.backupLastFullScan, isNotNull);
      expect(app.prefs.backupUnfoundRecords, 1);
      expect(app.prefs.backupCheckpoint, isNotNull);
    });

    test('a change made while the library is read keeps the next pass a full one', () async {
      library = [_photo('p1')];
      final app = await open();
      await app.db.markAssetsBackedUp(['p1']);
      onScan = app.controller.unskipAll;

      await app.controller.run();
      expect(app.state.phase, BackupPhase.upToDate);
      expect(app.prefs.backupLastFullScan, isNull);

      onScan = null;
      await app.controller.run();
      expect(asked.last, 0);
    });

    test('coming back to the app leaves a recent pass alone until the library changes', () async {
      final app = await open();
      await app.controller.run();
      expect(app.state.phase, BackupPhase.upToDate);

      app.controller.scheduleOnResume();
      expect(app.controller.scheduled, 0);

      // The watcher is set up as the controller is built.
      await pumpEventQueue();
      await _libraryChanges();
      expect(app.controller.scheduled, 1);

      app.controller.scheduleOnResume();
      expect(app.controller.scheduled, 2);
    });

    test('a wait Telegram asks for pauses backup without counting a failure', () async {
      await add('p1');
      final app = await open();
      app.queue.error = const TelegramException(429, 'Too Many Requests: retry after 30');

      await app.controller.run();

      final state = app.state;
      expect(state.phase, BackupPhase.uploading);
      expect(state.pausedUntil, isNotNull);
      expect(state.pausedUntil!.isAfter(DateTime.now().add(const Duration(seconds: 20))), isTrue);
      expect(state.isWorking, isFalse);
      expect(state.failed, 0);
      expect(await app.db.backupAssetOf('p1'), isNull);
      expect(describeBackup(state).title, 'Telegram asked us to wait');
      expect(app.controller.scheduled, 0);
    }, skip: _readsFiles ? false : 'photo_manager reads files on Android and Apple platforms only');

    group('run for the background job', () {
      test(
        'stopping gives the uploads under way their grace, and starts no more',
        () async {
          await add('p1');
          await add('p2');
          await add('p3');
          final app = await open(saveMemory: true);
          app.queue.holds = (name) => name == 'IMG_p2.jpg';

          final pass = app.controller.runInBackground(const Duration(minutes: 8));
          while (app.queue.uploads.length < 2) {
            await pumpEventQueue();
          }
          app.controller.stop();
          var ended = false;
          unawaited(pass.whenComplete(() => ended = true));
          await pumpEventQueue();
          expect(ended, isFalse);
          expect(app.queue.cancelled, isEmpty);

          app.queue.finish('u2');
          expect(await pass, 2);
          expect(app.queue.uploads, hasLength(2));
          expect(app.queue.cancelled, isEmpty);
        },
        skip: _readsFiles ? false : 'photo_manager reads files on Android and Apple platforms only',
      );

      test(
        'stopping at once cancels the uploads under way',
        () async {
          await add('p1');
          await add('p2');
          final app = await open(saveMemory: true);
          app.queue.holds = (name) => name == 'IMG_p2.jpg';

          final pass = app.controller.runInBackground(const Duration(minutes: 8));
          while (app.queue.uploads.length < 2) {
            await pumpEventQueue();
          }
          app.controller.stop(now: true);

          expect(await pass, 1);
          expect(app.queue.cancelled, ['u2']);
        },
        skip: _readsFiles ? false : 'photo_manager reads files on Android and Apple platforms only',
      );

      test(
        'once its time is up, the pass sends nothing more',
        () async {
          await add('p1');
          final gate = Completer<void>();
          final app = await open(gate: gate.future);

          final pass = app.controller.runInBackground(const Duration(milliseconds: 20));
          await Future<void>.delayed(const Duration(milliseconds: 100));
          gate.complete();

          expect(await pass, 0);
          expect(app.queue.uploads, isEmpty);
        },
        skip: _readsFiles ? false : 'photo_manager reads files on Android and Apple platforms only',
      );
    });
  });
}
