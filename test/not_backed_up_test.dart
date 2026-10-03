import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegrive/app/theme/app_theme.dart';
import 'package:telegrive/features/backup/data/backup_controller.dart';
import 'package:telegrive/features/backup/presentation/backup_screen.dart';
import 'package:telegrive/features/backup/presentation/duplicates_sheet.dart';
import 'package:telegrive/features/backup/presentation/not_backed_up_screen.dart';
import 'package:telegrive/features/drive/data/drive_repository.dart';
import 'package:telegrive/features/drive/data/drive_session.dart';
import 'package:telegrive/features/drive/data/drive_sync.dart';
import 'package:telegrive/features/drive/domain/drive_models.dart';
import 'package:telegrive/features/photos/data/photos_visibility.dart';
import 'package:telegrive/features/photos/presentation/photos_screen.dart';
import 'package:telegrive/features/transfers/data/transfer_queue.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';
import 'package:telegrive/infrastructure/network/network_status.dart';
import 'package:telegrive/infrastructure/storage/preferences.dart';

import 'support/fake_telegram.dart';

/// Backup switched on and about to run its first pass, without the library
/// watchers, counting the passes it is asked for.
class _Starting extends BackupController {
  int passes = 0;

  @override
  BackupState build() => const BackupState(phase: BackupPhase.waitingForDrive);

  @override
  void schedule({bool immediate = false}) => passes++;
}

/// A drive that has been read in full and is never syncing.
class _Sync extends DriveSync {
  @override
  SyncState build() => const SyncState();

  @override
  Future<void> whenIdle() async {}
}

/// A backup with two photos out of tries, whose passes are only counted.
class _Counted extends BackupController {
  int passes = 0;

  @override
  BackupState build() => const BackupState(
    phase: BackupPhase.upToDate,
    total: 10,
    done: 8,
    failed: 2,
    failedIds: {'a', 'b'},
  );

  @override
  void schedule({bool immediate = false}) => passes++;
}

/// A backup in a fixed state that records what the screen asks of it.
class _Recording extends BackupController {
  _Recording(this._state, {this.skips = true});

  final BackupState _state;

  /// What [skip] answers: whether it set the photo aside.
  final bool skips;
  final calls = <String>[];

  @override
  BackupState build() => _state;

  @override
  Future<List<DeviceFolder>> deviceFolders() async => const [];

  @override
  Future<void> retryOne(String assetId) async => calls.add('retry $assetId');

  @override
  Future<bool> skip(String assetId) async {
    calls.add('skip $assetId');
    return skips;
  }

  @override
  Future<void> unskip(String assetId) async => calls.add('unskip $assetId');

  @override
  Future<void> retryFailed() async => calls.add('retry all');

  @override
  Future<void> unskipAll() async => calls.add('bring back');

  @override
  void backUpNow(String assetId) => calls.add('now $assetId');
}

class _Queue extends TransferQueue {
  @override
  TransfersState build() => TransfersState.empty;
}

BackupAssetRow _failed(String assetId, String reason) => BackupAssetRow(
  assetId: assetId,
  state: BackupAssetState.failed,
  failures: BackupController.maxFailures,
  updatedAt: DateTime(2026, 9, 25),
  reason: reason,
);

/// A phone on mobile data.
class _Metered extends NetworkStatus {
  @override
  NetworkState build() => const NetworkState(online: true, metered: true);
}

/// A photo in the phone's Camera folder, taken [daysAgo] days ago.
Map<String, Object> _photo(String id, int daysAgo) => {
  'id': id,
  'type': 1,
  'width': 4000,
  'height': 3000,
  'createDt': DateTime(2026, 9, 25).subtract(Duration(days: daysAgo)).millisecondsSinceEpoch ~/
      1000,
  'relativePath': 'DCIM/Camera/',
  'title': 'IMG_$id.jpg',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const photos = MethodChannel('com.fluttercandies/photo_manager');
  tearDown(() {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(photos, null);
  });

  /// A drive read in full, a phone whose library holds [library] (and
  /// whose files can't be read), and a backup about to run over them. With
  /// [wifiOnly] the phone is on mobile data, so a pass counts and waits.
  Future<(ProviderContainer, AppDatabase)> start(
    List<Map<String, Object>> library, {
    required bool wifiOnly,
  }) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({
      BackupPrefKeys.enabled: true,
      BackupPrefKeys.mobileData: (wifiOnly ? BackupMobileData.off : BackupMobileData.all).name,
      'full_sync_$testChatId': DateTime.now().millisecondsSinceEpoch,
    });
    final shared = await SharedPreferences.getInstance();
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      photos,
      (call) async => switch (call.method) {
        'getPermissionState' => PermissionState.authorized.index,
        'getAssetPathList' => {
          'data': [
            {'id': 'all', 'name': 'Recent', 'isAll': true, 'assetCount': library.length},
          ],
        },
        'getAssetCountFromPath' => library.length,
        'getAssetListRange' => {'data': library},
        _ => null,
      },
    );
    final db = AppDatabase(NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(shared),
        appDatabaseProvider.overrideWithValue(db),
        driveSessionProvider.overrideWith(TestSession.new),
        driveSyncProvider.overrideWith(_Sync.new),
        backupControllerProvider.overrideWith(_Starting.new),
        networkStatusProvider.overrideWith(_Metered.new),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    return (container, db);
  }

  test('waiting for Wi-Fi still counts what is left, newest first', () async {
    final (container, db) = await start([
      for (var i = 1; i <= 5; i++) _photo('p$i', i),
    ], wifiOnly: true);
    await db.markAssetBackedUp('p2', 'file-2');
    await db.markAssetFailed('p4', 3, reason: 'Telegram took too long to answer.');
    await db.markAssetFailed('p5', 3);
    await db.markAssetSkipped('p5');

    await container.read(backupControllerProvider.notifier).run();

    final state = container.read(backupControllerProvider);
    expect(state.phase, BackupPhase.waitingForWifi);
    // The skipped photo is out of scope; the failed one is not waiting.
    expect((state.total, state.done, state.failed, state.remaining), (4, 1, 1, 2));
    expect(state.failedIds, {'p4'});
    expect(state.waiting.map((a) => a.assetId), ['p1', 'p3']);
    expect(state.waiting.first.folder, 'Camera');
    expect(state.waiting.first.takenAt, DateTime(2026, 9, 24));
  });

  test('a failed photo the scan no longer finds is neither counted nor listed', () async {
    final (container, db) = await start([
      for (var i = 1; i <= 3; i++) _photo('p$i', i),
    ], wifiOnly: true);
    await db.markAssetFailed('p2', 3, reason: 'Telegram took too long to answer.');
    // Deleted from the phone after failing.
    await db.markAssetFailed('gone-1', 3, reason: 'Couldn\'t start the upload.');
    await db.markAssetFailed('gone-2', 3, reason: 'Couldn\'t start the upload.');
    final controller = container.read(backupControllerProvider.notifier) as _Starting;
    BackupState state() => container.read(backupControllerProvider);
    container.listen(failedBackupAssetsProvider, (_, _) {});

    await controller.run();
    expect((state().total, state().failed, state().remaining), (3, 1, 2));
    final listed = await container.read(failedBackupAssetsProvider.future);
    expect(listed.map((r) => r.assetId), ['p2']);

    // Retry and Skip on those records leave the counts alone.
    await controller.retryOne('gone-1');
    await controller.skip('gone-2');
    expect((state().total, state().failed, state().remaining), (3, 1, 2));
    expect(await db.backupAssetOf('gone-1'), isNull);
    expect((await db.backupAssetOf('gone-2'))?.state, BackupAssetState.skipped);
  });

  test('a second tap on Retry or Skip changes nothing', () async {
    final (container, db) = await start([
      for (var i = 1; i <= 3; i++) _photo('p$i', i),
    ], wifiOnly: true);
    await db.markAssetFailed('p1', 3, reason: 'Telegram took too long to answer.');
    await db.markAssetFailed('p2', 3, reason: 'Telegram took too long to answer.');
    final controller = container.read(backupControllerProvider.notifier) as _Starting;
    BackupState state() => container.read(backupControllerProvider);
    await controller.run();
    expect((state().total, state().failed), (3, 2));

    expect(
      await Future.wait([controller.skip('p2'), controller.skip('p2')]),
      unorderedEquals([true, false]),
    );
    expect((state().total, state().failed), (2, 1));
    await controller.unskip('p2');
    expect((state().total, state().failed), (3, 2));

    await Future.wait([controller.retryOne('p1'), controller.retryOne('p1')]);
    expect((state().total, state().failed, state().remaining), (3, 1, 2));
    expect(controller.passes, 1);
  });

  test('waiting for Wi-Fi, a pass never reads as backing up', () async {
    final (container, _) = await start([_photo('p1', 1)], wifiOnly: true);
    final phases = <BackupPhase>[];
    container.listen(
      backupControllerProvider.select((s) => s.phase),
      (_, phase) => phases.add(phase),
    );

    await container.read(backupControllerProvider.notifier).run();
    expect(phases, [BackupPhase.waitingForWifi]);
  });

  test('a request for a photo that went up meanwhile is dropped at the next scan', () async {
    final (container, db) = await start([_photo('p1', 1)], wifiOnly: true);
    final controller = container.read(backupControllerProvider.notifier);
    // Asked for while it was going up, and in the drive since.
    controller.backUpNow('p1');
    await db.markAssetBackedUp('p1', 'file-1');

    await controller.run();
    expect(container.read(backupControllerProvider).phase, BackupPhase.upToDate);
  });

  test('the skipped count covers only photos the scan found', () async {
    final (container, db) = await start([_photo('p1', 1), _photo('p2', 2)], wifiOnly: true);
    for (final id in ['p2', 'gone']) {
      await db.markAssetFailed(id, 3);
      await db.markAssetSkipped(id);
    }
    final controller = container.read(backupControllerProvider.notifier);
    container.listen(skippedBackupCountProvider, (_, _) {});

    await controller.run();
    expect(container.read(backupControllerProvider).skippedIds, {'p2'});
    expect(await container.read(skippedBackupCountProvider.future), 1);

    // Bring back clears the skipped records out of sight as well.
    await controller.unskipAll();
    await pumpEventQueue();
    expect(container.read(skippedBackupCountProvider).value, 0);
    expect(await db.watchSkippedAssetIds().first, isEmpty);
  });

  test('a photo that fails with tries left gets another pass soon after', () async {
    // Its file can't be read, so the upload fails before it starts.
    final (container, db) = await start([_photo('p1', 1)], wifiOnly: false);
    final controller = container.read(backupControllerProvider.notifier) as _Starting;

    await controller.run();

    final record = await db.backupAssetOf('p1');
    expect(record?.failures, 1);
    expect(record?.reason, 'This photo is no longer on this phone.');
    expect(controller.passes, 1);
    final state = container.read(backupControllerProvider);
    expect(state.phase, isNot(BackupPhase.upToDate));
    expect((state.failed, state.remaining), (0, 1));
  });

  /// [_Counted] over a database holding its two failed records.
  Future<(_Counted, AppDatabase, BackupState Function())> counted() async {
    final db = AppDatabase(NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        backupControllerProvider.overrideWith(_Counted.new),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    await db.markAssetFailed('a', 3, reason: 'Telegram took too long to answer.');
    await db.markAssetFailed('b', 3, reason: 'This photo is no longer on this phone.');
    final controller = container.read(backupControllerProvider.notifier) as _Counted;
    return (controller, db, () => container.read(backupControllerProvider));
  }

  test('retry, skip and undo keep the counts in step with the records', () async {
    final (controller, db, state) = await counted();

    await controller.retryOne('a');
    expect((state().failed, state().remaining), (1, 1));
    expect((await db.backupAssetMap()).keys, ['b']);
    expect(controller.passes, 1);

    expect(await controller.skip('b'), isTrue);
    expect((state().total, state().failed, state().remaining), (9, 0, 1));
    expect(state().skippedIds, {'b'});
    expect(await db.watchSkippedAssetIds().first, ['b']);
    expect(await db.watchFailedAssets(minFailures: 3).first, isEmpty);

    await controller.unskip('b');
    expect((state().total, state().failed), (10, 1));
    final back = (await db.watchFailedAssets(minFailures: 3).first).single;
    expect(back.assetId, 'b');
    expect(back.reason, 'This photo is no longer on this phone.');

    await controller.retryFailed();
    expect((state().failed, state().remaining), (0, 2));
    expect(controller.passes, 2);
  });

  test('Undo after Bring back leaves a photo that has moved on as it is', () async {
    final (controller, db, state) = await counted();
    expect(await controller.skip('b'), isTrue);
    await controller.unskipAll();
    // The next pass sent it up.
    await db.markAssetBackedUp('b', 'file-b');

    await controller.unskip('b');
    expect((await db.backupAssetOf('b'))?.state, BackupAssetState.done);
    expect((state().total, state().failed), (9, 1));
  });

  Future<_Recording> pump(
    WidgetTester tester, {
    required BackupState backup,
    List<BackupAssetRow> failed = const [],
    int skipped = 0,
    bool skips = true,
  }) async {
    final controller = _Recording(backup, skips: skips);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backupControllerProvider.overrideWith(() => controller),
          failedBackupAssetsProvider.overrideWith((ref) => Stream.value(failed)),
          skippedBackupCountProvider.overrideWith((ref) => Stream.value(skipped)),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: const NotBackedUpScreen()),
      ),
    );
    await tester.pump();
    return controller;
  }

  testWidgets('each photo out of tries shows why, with Retry and Skip', (tester) async {
    final controller = await pump(
      tester,
      backup: const BackupState(phase: BackupPhase.upToDate, total: 10, done: 8, failed: 2),
      failed: [
        _failed('a', 'Telegram took too long to answer.'),
        _failed('b', 'This photo is no longer on this phone.'),
      ],
      skipped: 1,
    );

    expect(find.text('Didn\'t back up · 2'), findsOneWidget);
    expect(find.text('Telegram took too long to answer.'), findsOneWidget);
    expect(find.text('This photo is no longer on this phone.'), findsOneWidget);
    expect(find.text('1 item skipped'), findsOneWidget);
    expect(find.textContaining('Waiting'), findsNothing);

    await tester.tap(find.widgetWithText(TextButton, 'Retry').first);
    await tester.tap(find.widgetWithText(TextButton, 'Skip').last);
    await tester.pump();
    expect(controller.calls, ['retry a', 'skip b']);

    // Skipping can be taken back from the snack.
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Skipped 1 item'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect(controller.calls.last, 'unskip b');

    await tester.tap(find.widgetWithText(TextButton, 'Retry all'));
    await tester.tap(find.widgetWithText(TextButton, 'Bring back'));
    await tester.pump();
    expect(controller.calls.skip(3), ['retry all', 'bring back']);
  });

  testWidgets('a Skip that sets nothing aside offers no Undo', (tester) async {
    final controller = await pump(
      tester,
      backup: const BackupState(phase: BackupPhase.upToDate, total: 10, done: 9, failed: 1),
      failed: [_failed('a', 'Telegram took too long to answer.')],
      skips: false,
    );

    await tester.tap(find.widgetWithText(TextButton, 'Skip'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(controller.calls, ['skip a']);
    expect(find.text('Skipped 1 item'), findsNothing);
    expect(find.text('Undo'), findsNothing);
  });

  testWidgets('waiting photos say what they wait for, and Back up now waits for Wi-Fi too', (
    tester,
  ) async {
    final waiting = [
      for (var i = 0; i < 3; i++)
        PendingAsset(assetId: 'w$i', takenAt: DateTime(2025, 9, 25), folder: 'Camera'),
    ];
    final controller = await pump(
      tester,
      backup: BackupState(
        phase: BackupPhase.waitingForWifi,
        total: 30,
        done: 3,
        waiting: waiting,
      ),
    );

    expect(find.text('Waiting · 27'), findsOneWidget);
    expect(find.text('27 items · waiting for Wi-Fi'), findsOneWidget);
    expect(find.text('and 24 more, newest first.'), findsOneWidget);
    expect(find.text('Camera · Sep 25, 2025'), findsNWidgets(3));
    final retryAll = tester.widget<TextButton>(find.widgetWithText(TextButton, 'Retry all'));
    expect(retryAll.onPressed, isNull);

    await tester.tap(find.widgetWithText(TextButton, 'Back up now').first);
    await tester.pump();
    expect(controller.calls, isEmpty);
  });

  testWidgets('Back up now queues the photo and says so', (tester) async {
    final controller = await pump(
      tester,
      backup: BackupState(
        phase: BackupPhase.uploading,
        total: 30,
        done: 28,
        waiting: [
          PendingAsset(assetId: 'w0', takenAt: DateTime(2025, 9, 25), folder: 'Camera'),
          PendingAsset(assetId: 'w1', takenAt: DateTime(2025, 9, 24), folder: 'Camera'),
        ],
      ),
    );

    expect(find.text('2 items · backing up now'), findsOneWidget);
    expect(find.textContaining('more, newest first'), findsNothing);
    await tester.tap(find.widgetWithText(TextButton, 'Back up now').last);
    await tester.pump();
    expect(controller.calls, ['now w1']);
    expect(find.text('Queued'), findsOneWidget);
    expect(find.text('Back up now'), findsOneWidget);
  });

  testWidgets('with nothing stuck, it says everything is backed up', (tester) async {
    await pump(
      tester,
      backup: const BackupState(phase: BackupPhase.upToDate, total: 10, done: 10),
    );
    expect(find.text('Everything is backed up'), findsOneWidget);
  });

  group('the way in', () {
    /// The screen at [location] with backup in [backup], in a router that
    /// knows the way to Not backed up.
    Future<void> open(WidgetTester tester, String location, BackupState backup) async {
      // A fresh tree, so each state gets its own overrides.
      await tester.pumpWidget(const SizedBox.shrink());
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({BackupPrefKeys.enabled: true});
      final shared = await SharedPreferences.getInstance();
      final router = GoRouter(
        initialLocation: location,
        routes: [
          GoRoute(path: '/photos', builder: (_, _) => const PhotosScreen()),
          GoRoute(
            path: '/backup',
            builder: (_, _) => const BackupScreen(),
            routes: [
              GoRoute(path: 'not-backed-up', builder: (_, _) => const NotBackedUpScreen()),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(shared),
            backupControllerProvider.overrideWith(() => _Recording(backup)),
            transferQueueProvider.overrideWith(_Queue.new),
            duplicateBackupsProvider.overrideWith((ref) async => DuplicateBackups.none),
            mediaTimelineProvider.overrideWith((ref) => Stream.value(const [])),
            hiddenBackupFoldersProvider.overrideWith((ref) => Stream.value(const {})),
            failedBackupAssetsProvider.overrideWith((ref) => Stream.value(const [])),
            skippedBackupCountProvider.overrideWith((ref) => Stream.value(0)),
          ],
          child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    /// Taps [line] and expects Not backed up to open.
    Future<void> follow(WidgetTester tester, String line) async {
      await tester.tap(find.text(line));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(NotBackedUpScreen), findsOneWidget);
    }

    const uploading = BackupState(phase: BackupPhase.uploading, total: 30, done: 3);
    const onMobileData = BackupState(phase: BackupPhase.waitingForWifi, total: 30, done: 3);
    const failing = BackupState(
      phase: BackupPhase.uploading,
      total: 30,
      done: 3,
      failed: 2,
    );
    const stuck = BackupState(
      phase: BackupPhase.waitingForWifi,
      total: 30,
      done: 3,
      failed: 2,
    );
    const allDone = BackupState(phase: BackupPhase.upToDate, total: 30, done: 30);

    testWidgets('Photos points to it only while something is stuck', (tester) async {
      final pointer = find.textContaining(RegExp(r"^[\d,]+ waiting|didn't back up"));
      for (final (backup, line) in [
        (uploading, null),
        (allDone, null),
        (onMobileData, '27 waiting'),
        // While backup is moving, the status line above counts what is left.
        (failing, '2 didn\'t back up'),
        (stuck, '25 waiting · 2 didn\'t back up'),
      ]) {
        await open(tester, '/photos', backup);
        if (line == null) {
          expect(pointer, findsNothing, reason: '${backup.phase}');
        } else {
          expect(find.text(line), findsOneWidget);
          await follow(tester, line);
        }
      }
    });

    testWidgets('the Backup screen has a row for it only while something is stuck', (
      tester,
    ) async {
      final row = find.textContaining(RegExp(r"^See (which ones and why|what's left)"));
      for (final (backup, line) in [
        (uploading, null),
        (allDone, null),
        (onMobileData, '27 items waiting'),
        (failing, '2 items didn\'t back up'),
        (stuck, '2 items didn\'t back up'),
      ]) {
        await open(tester, '/backup', backup);
        if (line == null) {
          expect(row, findsNothing, reason: '${backup.phase}');
        } else {
          expect(find.text(line), findsOneWidget);
          await follow(tester, line);
        }
      }
    });
  });
}
