import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegrive/core/files/file_kind.dart';
import 'package:telegrive/features/backup/data/backup_controller.dart';
import 'package:telegrive/features/drive/data/drive_repository.dart';
import 'package:telegrive/features/drive/data/drive_session.dart';
import 'package:telegrive/features/drive/domain/drive_models.dart';
import 'package:telegrive/features/transfers/data/transfer_keep_alive.dart';
import 'package:telegrive/features/transfers/data/transfer_queue.dart';
import 'package:telegrive/features/transfers/domain/transfer_wait.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';
import 'package:telegrive/infrastructure/network/network_status.dart';
import 'package:telegrive/infrastructure/storage/device_storage.dart';
import 'package:telegrive/infrastructure/storage/preferences.dart';
import 'package:telegrive/infrastructure/telegram/telegram_client.dart';

import 'support/fake_telegram.dart';

const _wifi = NetworkState(online: true, metered: false);
const _mobile = NetworkState(online: true, metered: true);

/// TDLib's files 7 and 8, fetched to [path]. A fetch of file 7 stays in
/// flight until [finish]; any other finishes at once.
class _FakeTelegram extends FakeTelegram {
  _FakeTelegram(this.path);

  final String path;
  final List<int> downloads = [];
  int cancels = 0;
  final Completer<td.File> _report = Completer<td.File>();

  /// Lets the fetch of file 7 land.
  void finish() => _report.complete(tdFile(7, path: path, downloaded: true));

  @override
  Future<td.TdObject?> answer(td.TdFunction function) async {
    switch (function) {
      case td.GetFile(:final fileId):
        return tdFile(fileId);
      case td.DownloadFile(:final fileId):
        downloads.add(fileId);
        if (fileId == 7) return _report.future;
        return tdFile(fileId, path: path, downloaded: true);
      case td.CancelDownloadFile():
        cancels++;
        return const td.Ok();
      case td.DeleteFile():
        return const td.Ok();
      default:
        return null;
    }
  }
}

/// A phone whose connection the test sets.
class _TestNetwork extends NetworkStatus {
  _TestNetwork(this._initial);

  final NetworkState _initial;

  @override
  NetworkState build() => _initial;
}

/// Saves a file where it already is, so a save finishes without a platform.
class _Storage extends DeviceStorage {
  @override
  Future<String> saveFile(
    String source, {
    required List<String> folders,
    required String name,
    required String mimeType,
  }) async => source;
}

TransferRow _row(String id, TransferStatus status) => TransferRow(
  id: id,
  kind: TransferKind.upload,
  status: status,
  name: '$id.jpg',
  mimeType: 'image/jpeg',
  fileId: id,
  ownsSource: false,
  wifiOnly: false,
  totalBytes: 10 << 20,
  doneBytes: 1 << 20,
  partCount: 1,
  completedParts: 0,
  createdAt: DateTime(2026, 10, 15),
  origin: TransferOrigin.manual,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> until(bool Function() condition) async {
    for (var i = 0; i < 300 && !condition(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(condition(), isTrue);
  }

  group('once Android ends the background time, the queue', () {
    late Directory dir;
    late AppDatabase db;
    late File fetched;
    final now = DateTime(2026, 10, 15);

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('telegrive_time_limit');
      db = AppDatabase(NativeDatabase.memory());
      fetched = File('${dir.path}/fetched.bin')..writeAsStringSync('0123456789');
      for (final (id, tdFileId) in [('report', 7), ('notes', 8)]) {
        await db.upsertFilePart(
          DriveFilesCompanion.insert(
            id: id,
            name: '$id.pdf',
            mimeType: 'application/pdf',
            kind: FileKind.document,
            size: 10,
            createdAt: now,
            modifiedAt: now,
            partCount: const Value(1),
          ),
          FilePartsCompanion.insert(
            fileId: id,
            partIndex: 0,
            messageId: tdFileId,
            tdFileId: tdFileId,
            size: 10,
          ),
        );
      }
    });

    tearDown(() async {
      await db.close();
      await dir.delete(recursive: true);
    });

    /// The queue on a phone on [network], once it has read its saved rows,
    /// with the drive files it moves.
    Future<(ProviderContainer, TransferQueue, Map<String, DriveFile>)> open(
      FakeTelegram telegram, {
      NetworkState network = _wifi,
    }) async {
      for (final part in await db.select(db.fileParts).get()) {
        telegram.holdsFile(part.messageId, part.tdFileId, size: part.size);
      }
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});
      final shared = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(shared),
          appDatabaseProvider.overrideWithValue(db),
          telegramClientProvider.overrideWithValue(telegram),
          driveSessionProvider.overrideWith(TestSession.new),
          deviceStorageProvider.overrideWithValue(_Storage()),
          networkStatusProvider.overrideWith(() => _TestNetwork(network)),
        ],
      );
      addTearDown(container.dispose);
      var loaded = false;
      container.listen<TransfersState>(transferQueueProvider, (_, _) => loaded = true);
      container.read(transferQueueProvider);
      await until(() => loaded);
      final repository = container.read(driveRepositoryProvider);
      return (
        container,
        container.read(transferQueueProvider.notifier),
        {
          for (final id in ['report', 'notes']) id: (await repository.fileById(id))!,
        },
      );
    }

    test('leaves a running transfer where it is, waiting, and carries on once the app is open', () async {
      final telegram = _FakeTelegram(fetched.path);
      final (container, queue, files) = await open(telegram);
      TransfersState state() => container.read(transferQueueProvider);

      final result = queue.download(files['report']!);
      await until(() => telegram.downloads.contains(7));
      expect(state().items.single.status, TransferStatus.running);

      queue.waitForApp();
      await until(() => state().items.single.wait is WaitingForApp);
      expect(state().items.single.status, TransferStatus.running);
      // Nothing is called off, so TDLib keeps what it has fetched.
      expect(telegram.cancels, 0);
      // Nor does it count as in flight, so nothing holds the phone awake.
      expect(state().active, isEmpty);
      expect(state().held.map((t) => t.id), [state().items.single.id]);

      queue.appOpened();
      await until(() => state().items.single.wait == null);
      expect(state().active, hasLength(1));
      telegram.finish();
      expect(await result, isNotEmpty);
      expect(telegram.downloads, [7]);
    });

    test('starts nothing new until the app is open', () async {
      final telegram = _FakeTelegram(fetched.path);
      final (container, queue, files) = await open(telegram);
      TransferItem item() => container.read(transferQueueProvider).items.single;

      queue.waitForApp();
      await queue.enqueueSaves([SaveRequest(files['notes']!, target: SaveTarget.files)]);
      await until(() => container.read(transferQueueProvider).items.isNotEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(telegram.downloads, isEmpty);
      expect(item().status, TransferStatus.queued);
      expect(item().wait, isA<WaitingForApp>());

      queue.appOpened();
      await until(() => item().status == TransferStatus.completed);
      expect(telegram.downloads, [8]);
      expect(item().wait, isNull);
    });

    test('lets a transfer that waits for Wi-Fi go on saying so', () async {
      final telegram = _FakeTelegram(fetched.path);
      final (container, queue, files) = await open(telegram, network: _mobile);
      TransferItem item() => container.read(transferQueueProvider).items.single;

      await queue.enqueueSaves([
        SaveRequest(files['notes']!, target: SaveTarget.files, wifiOnly: true),
      ]);
      await until(() => container.read(transferQueueProvider).items.isNotEmpty);
      queue.waitForApp();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(item().wait, isA<WaitingForWifi>());

      // Open, but still on mobile data.
      queue.appOpened();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(item().wait, isA<WaitingForWifi>());
      expect(telegram.downloads, isEmpty);
    });

    test('leaves a paused transfer for Resume', () async {
      final telegram = _FakeTelegram(fetched.path);
      final (container, queue, files) = await open(telegram);
      TransferItem item() => container.read(transferQueueProvider).items.single;

      queue.waitForApp();
      await queue.enqueueSaves([SaveRequest(files['notes']!, target: SaveTarget.files)]);
      await until(() => container.read(transferQueueProvider).items.isNotEmpty);
      await queue.pause(item().id);
      await until(() => item().status == TransferStatus.paused);
      expect(item().wait, isNull);

      queue.appOpened();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(item().status, TransferStatus.paused);
      expect(telegram.downloads, isEmpty);
    });
  });

  group('the service', () {
    test('tells the app when Android ends it at its time limit, and only then', () async {
      FlutterForegroundTask.initCommunicationPort();
      final received = <Object>[];
      void onData(Object data) => received.add(data);
      FlutterForegroundTask.addTaskDataCallback(onData);
      addTearDown(() => FlutterForegroundTask.removeTaskDataCallback(onData));

      final handler = TransferTaskHandler();
      await handler.onDestroy(DateTime.now(), false);
      await handler.onDestroy(DateTime.now(), true);
      await until(() => received.isNotEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(received, [TransferKeepAlive.timedOutSignal]);
    });
  });

  group('the keep-alive', () {
    const service = MethodChannel('flutter_foreground_task/methods');
    final calls = <String>[];
    var running = false;

    setUp(() {
      calls.clear();
      running = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(service, (
        call,
      ) async {
        calls.add(call.method);
        switch (call.method) {
          case 'isRunningService':
            return running;
          case 'startService':
            running = true;
          case 'stopService':
            running = false;
        }
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(service, null);
    });

    test('starts nothing after Android ends the service, until Telegrive is on screen', () async {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({'notifications_asked': true});
      final keeper = TransferKeepAlive(Preferences(await SharedPreferences.getInstance()));
      final busy = TransfersState([TransferItem(_row('photo', TransferStatus.running))]);
      const idle = BackupState(phase: BackupPhase.off);

      await keeper.update(busy, idle);
      expect(calls, contains('startService'));
      expect(keeper.timedOut, isFalse);

      // Android ends it, and the work is still there to do.
      running = false;
      keeper.stoppedAtTimeLimit();
      calls.clear();
      await keeper.update(busy, idle);
      await keeper.update(busy, const BackupState(phase: BackupPhase.uploading));
      expect(calls, isEmpty);
      expect(keeper.timedOut, isTrue);

      await keeper.onScreen();
      expect(calls, contains('startService'));
      expect(running, isTrue);
      expect(keeper.timedOut, isFalse);
    });

    test('on screen with nothing to do, starts nothing', () async {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({'notifications_asked': true});
      final keeper = TransferKeepAlive(Preferences(await SharedPreferences.getInstance()));
      const idle = BackupState(phase: BackupPhase.off);

      keeper.stoppedAtTimeLimit();
      await keeper.update(
        TransfersState([TransferItem(_row('photo', TransferStatus.completed))]),
        idle,
      );
      await keeper.onScreen();
      expect(calls, isEmpty);
      expect(keeper.timedOut, isFalse);
    });
  });
}
