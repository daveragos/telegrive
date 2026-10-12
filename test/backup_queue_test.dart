import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegrive/app/theme/app_theme.dart';
import 'package:telegrive/core/files/file_kind.dart';
import 'package:telegrive/features/backup/data/backup_controller.dart';
import 'package:telegrive/features/backup/presentation/backup_queue_screen.dart';
import 'package:telegrive/features/backup/presentation/not_backed_up_screen.dart';
import 'package:telegrive/features/backup/presentation/phone_media_viewer.dart';
import 'package:telegrive/features/drive/data/drive_repository.dart';
import 'package:telegrive/features/drive/data/drive_session.dart';
import 'package:telegrive/features/drive/data/drive_sync.dart';
import 'package:telegrive/features/drive/domain/drive_models.dart';
import 'package:telegrive/features/transfers/data/transfer_queue.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';
import 'package:telegrive/infrastructure/network/network_status.dart';
import 'package:telegrive/infrastructure/storage/preferences.dart';

import 'support/fake_telegram.dart';

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

class _Network extends NetworkStatus {
  _Network(this._initial);

  final NetworkState _initial;

  @override
  NetworkState build() => _initial;
}

/// A queue that sends nothing. Uploads of the photos in [held] stay under
/// way until [land] or [remove]; the rest land at once, put in the drive
/// as the upload would.
class _Queue extends TransferQueue {
  final held = <String>{};
  final uploads = <UploadRequest>[];
  final removed = <String>[];
  final _rows = <String, TransferRow>{};
  final _ended = <String, Completer<TransferRow>>{};

  @override
  TransfersState build() => TransfersState.empty;

  /// The upload of [assetId].
  String idOf(String assetId) => _rows.values.firstWhere((r) => r.assetId == assetId).id;

  @override
  Future<List<String>> enqueueUploads(List<UploadRequest> requests, {String? folderId}) async {
    final ids = <String>[];
    for (final request in requests) {
      uploads.add(request);
      final id = 'u${uploads.length}';
      ids.add(id);
      _rows[id] = TransferRow(
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
      _ended[id] = Completer();
      _emit();
      if (!held.contains(request.assetId)) await land(id);
    }
    return ids;
  }

  /// Puts upload [id] in the drive and ends it.
  Future<void> land(String id) async {
    final row = _rows[id]!;
    final now = DateTime.now();
    await ref
        .read(appDatabaseProvider)
        .upsertFilePart(
          DriveFilesCompanion.insert(
            id: row.fileId,
            name: row.name,
            mimeType: row.mimeType,
            kind: FileKind.image,
            size: row.totalBytes,
            createdAt: now,
            modifiedAt: now,
          ),
          FilePartsCompanion.insert(
            fileId: row.fileId,
            partIndex: 0,
            messageId: int.parse(id.substring(1)),
            tdFileId: int.parse(id.substring(1)),
            size: row.totalBytes,
          ),
        );
    _end(row.copyWith(status: TransferStatus.completed, doneBytes: row.totalBytes, completedParts: 1));
  }

  @override
  Future<void> remove(String id) async {
    removed.add(id);
    final row = _rows[id];
    if (row != null && row.status.isPending) _end(row.copyWith(status: TransferStatus.cancelled));
    _rows.remove(id);
    _emit();
  }

  void _end(TransferRow row) {
    _rows[row.id] = row;
    _emit();
    _ended[row.id]!.complete(row);
  }

  void _emit() => state = TransfersState([
    for (final row in _rows.values.toList().reversed) TransferItem(row),
  ]);

  @override
  Future<TransferRow> whenFinished(String id) => _ended[id]!.future;
}

/// A backup in a fixed state that records what the screens ask of it.
class _Recording extends BackupController {
  _Recording(this._state);

  final BackupState _state;
  final calls = <String>[];

  @override
  BackupState build() => _state;

  @override
  Future<SkippedWaiting?> skipWaiting(String assetId) async {
    calls.add('skip $assetId');
    return SkippedWaiting(assetId, null, wasGoingUp: false);
  }

  @override
  Future<void> undoSkip(SkippedWaiting skipped) async => calls.add('undo ${skipped.assetId}');

  @override
  void backUpNow(String assetId) => calls.add('now $assetId');
}

class _EmptyQueue extends TransferQueue {
  @override
  TransfersState build() => TransfersState.empty;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const photos = MethodChannel('com.fluttercandies/photo_manager');
  const paths = MethodChannel('plugins.flutter.io/path_provider');

  group('taking photos out of the queue', () {
    late Directory dir;
    late List<Map<String, Object>> library;
    late Map<String, String> files;

    Future<void> add(String id) async {
      final file = File('${dir.path}/library/IMG_$id.jpg');
      await file.create(recursive: true);
      await file.writeAsBytes(List.filled(1024, 1));
      files[id] = file.path;
      library.add({
        'id': id,
        'type': 1,
        'width': 4000,
        'height': 3000,
        'createDt': DateTime(2026, 9, 25).millisecondsSinceEpoch ~/ 1000 - library.length,
        'relativePath': 'DCIM/Camera/',
        'title': 'IMG_$id.jpg',
      });
    }

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('telegrive_backup_queue');
      library = [];
      files = {};
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
            return Uint8List(1024);
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

    /// Backup over the photos added, sending on [network] by [mobileData];
    /// with [oneAtATime] a pass works on one photo at a time.
    Future<ProviderContainer> open({
      NetworkState network = _wifi,
      BackupMobileData mobileData = BackupMobileData.all,
      bool oneAtATime = false,
    }) async {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({
        BackupPrefKeys.enabled: true,
        BackupPrefKeys.mobileData: mobileData.name,
        'save_memory': oneAtATime,
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

    /// Waits for [queue] to have been handed [count] uploads.
    Future<void> handed(_Queue queue, int count) async {
      for (var i = 0; i < 500 && queue.uploads.length < count; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(queue.uploads, hasLength(count));
    }

    test(
      'a photo going up is called off and skipped, and Undo sends it after all',
      () async {
        for (final id in ['p1', 'p2', 'p3']) {
          await add(id);
        }
        final container = await open();
        final controller = container.read(backupControllerProvider.notifier);
        final queue = container.read(transferQueueProvider.notifier) as _Queue;
        final db = container.read(appDatabaseProvider);
        BackupState state() => container.read(backupControllerProvider);
        queue.held.addAll(['p1', 'p2', 'p3']);

        final pass = controller.run();
        await handed(queue, 3);
        expect(state().waiting.map((a) => a.assetId), ['p1', 'p2', 'p3']);
        expect(
          container.read(backupUploadsProvider).map((t) => t.row.assetId),
          unorderedEquals(['p1', 'p2', 'p3']),
        );

        final going = queue.idOf('p2');
        final skipped = await controller.skipWaiting('p2');
        expect(skipped?.wasGoingUp, isTrue);
        expect(skipped?.previous, isNull);
        expect(queue.removed, [going]);
        expect((await db.backupAssetOf('p2'))?.state, BackupAssetState.skipped);
        expect(state().waiting.map((a) => a.assetId), ['p1', 'p3']);
        expect((state().total, state().remaining), (2, 2));
        expect(state().skippedIds, {'p2'});

        await queue.land(queue.idOf('p1'));
        await queue.land(queue.idOf('p3'));
        await pass;
        expect(state().phase, BackupPhase.upToDate);
        expect((state().total, state().done), (2, 2));
        expect(state().waiting, isEmpty);
        expect(state().recent.map((r) => r.assetId), ['p3', 'p1']);
        container.listen(recentBackupsProvider, (_, _) {});
        final backedUp = await container.read(recentBackupsProvider.future);
        expect(backedUp.map((f) => f.name), unorderedEquals(['IMG_p1.jpg', 'IMG_p3.jpg']));

        await controller.undoSkip(skipped!);
        expect(await db.backupAssetOf('p2'), isNull);
        expect(state().skippedIds, isEmpty);
        expect((state().total, state().remaining), (3, 1));
        expect(state().waiting.map((a) => a.assetId), ['p2']);

        queue.held.clear();
        await controller.run();
        expect((state().total, state().done), (3, 3));
        expect(state().recent.map((r) => r.assetId), ['p2', 'p3', 'p1']);
        expect(queue.uploads.where((u) => u.assetId == 'p2'), hasLength(2));
      },
      skip: _skip,
    );

    test(
      'a photo still in line is passed over, and a second tap does nothing',
      () async {
        for (final id in ['p1', 'p2', 'p3']) {
          await add(id);
        }
        final container = await open(oneAtATime: true);
        final controller = container.read(backupControllerProvider.notifier);
        final queue = container.read(transferQueueProvider.notifier) as _Queue;
        BackupState state() => container.read(backupControllerProvider);
        queue.held.add('p1');

        final pass = controller.run();
        await handed(queue, 1);
        final taps = await Future.wait([controller.skipWaiting('p2'), controller.skipWaiting('p2')]);
        expect(taps.nonNulls.single.wasGoingUp, isFalse);
        expect(queue.removed, isEmpty);
        expect(state().waiting.map((a) => a.assetId), ['p1', 'p3']);

        await queue.land(queue.idOf('p1'));
        await pass;
        expect(queue.uploads.map((u) => u.assetId), ['p1', 'p3']);
        expect((state().total, state().done, state().remaining), (2, 2, 0));
        // In the drive already, so there is nothing to take out.
        expect(await controller.skipWaiting('p1'), isNull);
      },
      skip: _skip,
    );

    test('Undo puts back the failures and the small copy a photo had', () async {
      for (final id in ['p1', 'p2']) {
        await add(id);
      }
      // Mobile data is off for backup, so the pass counts and waits.
      final container = await open(network: _hotspot, mobileData: BackupMobileData.off);
      final controller = container.read(backupControllerProvider.notifier);
      final db = container.read(appDatabaseProvider);
      BackupState state() => container.read(backupControllerProvider);
      await db.markAssetFailed('p1', 1, reason: 'Telegram took too long to answer.');
      await db.markAssetSmallCopy('p2', 'file-small');

      await controller.run();
      expect(state().phase, BackupPhase.waitingForWifi);
      expect((state().total, state().remaining, state().smallCopies), (2, 2, 1));

      final failed = (await controller.skipWaiting('p1'))!;
      final small = (await controller.skipWaiting('p2'))!;
      expect((state().total, state().remaining, state().smallCopies), (0, 0, 0));
      expect(state().waiting, isEmpty);
      final kept = await db.backupAssetOf('p2');
      expect((kept?.state, kept?.fileId), (BackupAssetState.skipped, 'file-small'));

      await controller.undoSkip(failed);
      await controller.undoSkip(small);
      final p1 = await db.backupAssetOf('p1');
      expect((p1?.state, p1?.failures, p1?.reason), (BackupAssetState.failed, 1, 'Telegram took too long to answer.'));
      final p2 = await db.backupAssetOf('p2');
      expect((p2?.state, p2?.fileId), (BackupAssetState.smallCopy, 'file-small'));
      expect((state().total, state().remaining, state().smallCopies), (2, 2, 1));
      expect(state().waiting.map((a) => a.assetId), ['p1', 'p2']);

      // Bring back ran meanwhile: a late Undo leaves the photo as it is.
      final again = (await controller.skipWaiting('p1'))!;
      await db.clearSkipped();
      await controller.undoSkip(again);
      expect(await db.backupAssetOf('p1'), isNull);
    }, skip: _skip);
  });

  group('the queue screen', () {
    final now = DateTime.now();
    TransferItem going(String assetId, {int done = 0}) => TransferItem(
      TransferRow(
        id: 'u-$assetId',
        kind: TransferKind.upload,
        status: TransferStatus.running,
        name: 'IMG_$assetId.jpg',
        mimeType: 'image/jpeg',
        fileId: 'file-$assetId',
        ownsSource: false,
        wifiOnly: false,
        totalBytes: 4 * 1024 * 1024,
        doneBytes: done,
        partCount: 1,
        completedParts: 0,
        createdAt: now,
        origin: TransferOrigin.backup,
        assetId: assetId,
      ),
    );
    DriveFile file(String id) => DriveFile(
      id: id,
      folderId: null,
      name: 'IMG_$id.jpg',
      mimeType: 'image/jpeg',
      kind: FileKind.image,
      size: 1000,
      createdAt: now,
      modifiedAt: now,
      partCount: 1,
      starred: false,
      takenAt: now,
    );
    final waiting = [
      for (final id in ['w0', 'w1', 'w2'])
        PendingAsset(assetId: id, takenAt: DateTime(2025, 9, 25), folder: 'Camera'),
    ];

    Future<_Recording> pump(
      WidgetTester tester, {
      required BackupState backup,
      List<TransferItem> uploads = const [],
      List<DriveFile> backedUp = const [],
    }) async {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({BackupPrefKeys.enabled: true});
      final shared = await SharedPreferences.getInstance();
      final controller = _Recording(backup);
      final router = GoRouter(
        initialLocation: '/backup/queue',
        routes: [
          GoRoute(
            path: '/backup',
            builder: (_, _) => const SizedBox.shrink(),
            routes: [
              GoRoute(path: 'queue', builder: (_, _) => const BackupQueueScreen()),
              GoRoute(path: 'not-backed-up', builder: (_, _) => const NotBackedUpScreen()),
            ],
          ),
          GoRoute(
            path: '/phone-media',
            builder: (_, state) => PhoneMediaViewer(args: state.extra! as PhoneMediaArgs),
          ),
          GoRoute(path: '/viewer/:fileId', builder: (_, state) => Text('viewer ${state.uri}')),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(shared),
            backupControllerProvider.overrideWith(() => controller),
            transferQueueProvider.overrideWith(_EmptyQueue.new),
            backupUploadsProvider.overrideWith((ref) => uploads),
            recentBackupsProvider.overrideWith((ref) => Stream.value(backedUp)),
            failedBackupAssetsProvider.overrideWith((ref) => Stream.value(const [])),
            skippedBackupCountProvider.overrideWith((ref) => Stream.value(0)),
          ],
          child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
        ),
      );
      await tester.pump();
      await tester.pump();
      return controller;
    }

    testWidgets('lists what is going up, then what is left, each with a way out', (tester) async {
      final controller = await pump(
        tester,
        backup: BackupState(
          phase: BackupPhase.uploading,
          total: 30,
          done: 27,
          failed: 1,
          waiting: waiting,
        ),
        uploads: [going('w0', done: 1024 * 1024)],
      );

      expect(find.text('Now · 1'), findsOneWidget);
      expect(find.text('Up next · 2'), findsOneWidget);
      expect(find.text('1.0 MB of 4.0 MB'), findsOneWidget);
      expect(find.text('Camera · Sep 25, 2025'), findsNWidgets(2));
      expect(find.text('1 item didn\'t back up'), findsOneWidget);

      await tester.tap(find.byTooltip('Don\'t back up').at(1));
      await tester.pump();
      expect(controller.calls, ['skip w1']);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Skipped 1 item'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await tester.pump();
      expect(controller.calls.last, 'undo w1');

      await tester.tap(find.byTooltip('Don\'t back up').first);
      await tester.pump();
      expect(controller.calls.last, 'skip w0');

      await tester.tap(find.text('1 item didn\'t back up'));
      await tester.pumpAndSettle();
      expect(find.byType(NotBackedUpScreen), findsOneWidget);
    });

    testWidgets('a photo opens full screen, with Back up now while backup is moving', (tester) async {
      final controller = await pump(
        tester,
        backup: BackupState(phase: BackupPhase.uploading, total: 3, waiting: waiting),
      );

      await tester.tap(find.text('Camera · Sep 25, 2025').at(1));
      await tester.pumpAndSettle();
      expect(find.byType(PhoneMediaViewer), findsOneWidget);
      // The phone in a test has no photos to say when this one was taken.
      expect(find.text('Waiting · 2 of 3'), findsOneWidget);

      await tester.tap(find.byTooltip('Back up now'));
      await tester.pump();
      expect(controller.calls, ['now w1']);
      await tester.tap(find.byTooltip('Don\'t back up'));
      await tester.pump();
      expect(controller.calls.last, 'skip w1');
    });

    testWidgets('while backup waits for Wi-Fi, no photo can go first', (tester) async {
      final controller = await pump(
        tester,
        backup: BackupState(phase: BackupPhase.waitingForWifi, total: 3, waiting: waiting),
      );

      await tester.tap(find.text('Camera · Sep 25, 2025').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Back up now'));
      await tester.pump();
      expect(controller.calls, isEmpty);
    });

    testWidgets('Backed up shows what went up since the app opened', (tester) async {
      await pump(
        tester,
        backup: const BackupState(
          phase: BackupPhase.upToDate,
          total: 2,
          done: 2,
          recent: [
            RecentBackup(assetId: 'a', fileId: 'f1'),
            RecentBackup(assetId: 'b', fileId: 'f2'),
          ],
        ),
        backedUp: [file('f1'), file('f2')],
      );

      expect(find.text('Nothing waiting'), findsOneWidget);
      expect(find.text('Backed up · 2'), findsOneWidget);
      await tester.tap(find.text('Backed up · 2'));
      await tester.pumpAndSettle();
      expect(find.text('2 items backed up since Telegrive opened'), findsOneWidget);
    });
  });

  test('one photo can go first only while backup can send', () {
    expect(
      {for (final phase in BackupPhase.values) phase: canBackUpNow(phase)},
      {
        BackupPhase.off: false,
        BackupPhase.needsPermission: false,
        BackupPhase.waitingForDrive: false,
        BackupPhase.waitingForWifi: false,
        BackupPhase.waitingForBudget: false,
        BackupPhase.scanning: true,
        BackupPhase.uploading: true,
        BackupPhase.upToDate: true,
        BackupPhase.stopped: true,
      },
    );
  });
}
