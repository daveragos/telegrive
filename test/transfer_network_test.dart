import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegrive/core/files/file_kind.dart';
import 'package:telegrive/features/drive/data/drive_repository.dart';
import 'package:telegrive/features/drive/data/drive_session.dart';
import 'package:telegrive/features/drive/domain/drive_models.dart';
import 'package:telegrive/features/drive/domain/manifest.dart';
import 'package:telegrive/features/offline/data/offline_sync.dart';
import 'package:telegrive/features/transfers/data/transfer_policy.dart';
import 'package:telegrive/features/transfers/data/transfer_queue.dart';
import 'package:telegrive/features/transfers/domain/transfer_wait.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';
import 'package:telegrive/infrastructure/network/network_status.dart';
import 'package:telegrive/infrastructure/storage/device_storage.dart';
import 'package:telegrive/infrastructure/storage/preferences.dart';
import 'package:telegrive/infrastructure/telegram/telegram_client.dart';
import 'package:telegrive/infrastructure/telegram/telegram_exception.dart';

import 'support/fake_telegram.dart';

const _wifi = NetworkState(online: true, metered: false);
const _mobile = NetworkState(online: true, metered: true);

/// TDLib's file 7, fetched to [path]. The first [timeouts] fetches time out
/// the way a request does when the connection drops. With [holdFirst], the
/// first fetch that goes through stays in flight until it is cancelled;
/// with [stall], every fetch does. Otherwise a fetch finishes at once.
class _FakeTelegram extends FakeTelegram {
  _FakeTelegram(this.path, {this.timeouts = 0, this.holdFirst = false, this.stall = false});

  final String path;
  final int timeouts;
  final bool holdFirst;
  final bool stall;
  int downloads = 0;
  int cancels = 0;
  bool _done = false;
  Completer<td.File>? _inFlight;

  td.File _file() => tdFile(7, path: path, downloaded: _done);

  @override
  Future<td.TdObject?> answer(td.TdFunction function) async {
    switch (function) {
      case td.GetFile():
        return _file();
      case td.DownloadFile():
        downloads++;
        if (downloads <= timeouts) throw const TelegramException(408, 'Request timeout');
        if (stall || (holdFirst && downloads == timeouts + 1)) {
          return (_inFlight = Completer<td.File>()).future;
        }
        _done = true;
        return _file();
      case td.CancelDownloadFile():
        cancels++;
        final inFlight = _inFlight;
        // Cancelled before it finished: TDLib answers with what it has.
        if (inFlight != null && !inFlight.isCompleted) inFlight.complete(_file());
        return const td.Ok();
      case td.DeleteFile():
        return const td.Ok();
      default:
        return null;
    }
  }
}

/// Every fetch of TDLib file 7 lands at [path], except those numbered in
/// [timeOut], counting from 1, which time out the way a request does when
/// the connection drops.
class _FlakyTelegram extends FakeTelegram {
  _FlakyTelegram(this.path, this.timeOut);

  final String path;
  final Set<int> timeOut;
  int downloads = 0;

  @override
  Future<td.TdObject?> answer(td.TdFunction function) async {
    switch (function) {
      case td.GetFile():
        return tdFile(7);
      case td.DownloadFile():
        downloads++;
        if (timeOut.contains(downloads)) throw const TelegramException(408, 'Request timeout');
        return tdFile(7, path: path, downloaded: true);
      case td.DeleteFile():
        return const td.Ok();
      default:
        return null;
    }
  }
}

/// TDLib after a restart, still sending [pending] on its own, and noting
/// what is deleted and what is sent anew.
class _ResumingTelegram extends FakeTelegram {
  _ResumingTelegram(this.pending);

  final td.Message pending;
  final List<int> deleted = [];
  int sends = 0;

  @override
  Future<td.TdObject?> answer(td.TdFunction function) async {
    switch (function) {
      case td.GetChatHistory(fromMessageId: 0, onlyLocal: true):
        return td.Messages(totalCount: 1, messages: [pending]);
      case td.DeleteMessages(:final messageIds):
        deleted.addAll(messageIds);
        return const td.Ok();
      case td.SendMessage():
        sends++;
        return null;
      default:
        return null;
    }
  }
}

/// A phone whose connection the test moves.
class _TestNetwork extends NetworkStatus {
  _TestNetwork(this._initial);

  final NetworkState _initial;

  @override
  NetworkState build() => _initial;

  void set(NetworkState next) => state = next;
}

/// The queue under test, the phone's network, and the drive file it moves.
typedef _Opened = ({
  ProviderContainer container,
  TransferQueue queue,
  _TestNetwork network,
  DriveFile file,
});

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late AppDatabase db;
  late File fetched;
  final now = DateTime(2026, 10, 2);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('telegrive_network');
    db = AppDatabase(NativeDatabase.memory());
    fetched = File('${dir.path}/report.pdf')..writeAsStringSync('0123456789');
    TransferQueue.waitUnit = const Duration(milliseconds: 1);
    await db.upsertFilePart(
      DriveFilesCompanion.insert(
        id: 'report',
        name: 'report.pdf',
        mimeType: 'application/pdf',
        kind: FileKind.document,
        size: 10,
        createdAt: now,
        modifiedAt: now,
        partCount: const Value(1),
      ),
      FilePartsCompanion.insert(
        fileId: 'report',
        partIndex: 0,
        messageId: 1,
        tdFileId: 7,
        size: 10,
      ),
    );
  });

  tearDown(() async {
    TransferQueue.waitUnit = const Duration(seconds: 1);
    await db.close();
    await dir.delete(recursive: true);
  });

  Future<void> until(bool Function() condition) async {
    for (var i = 0; i < 300 && !condition(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(condition(), isTrue);
  }

  /// The queue on a phone that starts on [network], once it has read its
  /// saved rows. With [onlyOverWifi], files kept offline download only over
  /// Wi-Fi.
  Future<_Opened> open(
    FakeTelegram telegram,
    NetworkState network, {
    bool onlyOverWifi = false,
  }) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({'offline_wifi_only': onlyOverWifi});
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
    return (
      container: container,
      queue: container.read(transferQueueProvider.notifier),
      network: container.read(networkStatusProvider.notifier) as _TestNetwork,
      file: (await container.read(driveRepositoryProvider).fileById('report'))!,
    );
  }

  test('a save that waits for Wi-Fi fetches nothing on mobile data, then goes on Wi-Fi', () async {
    final telegram = _FakeTelegram(fetched.path);
    final (:container, :queue, :network, :file) = await open(telegram, _mobile);
    TransfersState state() => container.read(transferQueueProvider);

    await queue.enqueueSaves([SaveRequest(file, target: SaveTarget.files, wifiOnly: true)]);
    await until(() => state().items.isNotEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final item = state().items.single;
    expect(telegram.downloads, 0);
    expect(item.status, TransferStatus.queued);
    expect(item.wait, isA<WaitingForWifi>());
    expect(state().active, isEmpty);
    expect(state().waitingForWifi, [item]);

    network.set(_wifi);
    await until(() => state().items.single.status == TransferStatus.completed);
    expect(telegram.downloads, 1);
    expect(state().items.single.wait, isNull);
  });

  test('a running Wi-Fi-only save steps back on mobile data, and resumes on Wi-Fi', () async {
    final telegram = _FakeTelegram(fetched.path, holdFirst: true);
    final (:container, :queue, :network, :file) = await open(telegram, _wifi);
    TransferItem item() => container.read(transferQueueProvider).items.single;

    await queue.enqueueSaves([SaveRequest(file, target: SaveTarget.files, wifiOnly: true)]);
    await until(() => telegram.downloads == 1);
    expect(item().status, TransferStatus.running);

    network.set(_mobile);
    await until(() => item().status == TransferStatus.queued);
    expect(telegram.cancels, 1);
    expect(item().wait, isA<WaitingForWifi>());
    expect(item().row.error, isNull);
    // It stays back while the phone is on mobile data.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(telegram.downloads, 1);
    expect(item().status, TransferStatus.queued);

    network.set(_wifi);
    await until(() => item().status == TransferStatus.completed);
    expect(telegram.downloads, 2);
  });

  test('Use mobile data starts a save that waits for Wi-Fi', () async {
    final telegram = _FakeTelegram(fetched.path);
    final (:container, :queue, network: _, :file) = await open(telegram, _mobile);
    TransferItem item() => container.read(transferQueueProvider).items.single;

    await queue.enqueueSaves([SaveRequest(file, target: SaveTarget.files, wifiOnly: true)]);
    await until(() => item().wait is WaitingForWifi);

    await queue.useMobileData([item().id]);
    await until(() => item().status == TransferStatus.completed);
    expect(telegram.downloads, 1);
    expect(item().row.wifiOnly, isFalse);
  });

  test('without a network a running transfer says it waits, and keeps running', () async {
    final telegram = _FakeTelegram(fetched.path, holdFirst: true);
    final (:container, :queue, network: _, :file) = await open(telegram, _wifi);
    TransfersState state() => container.read(transferQueueProvider);

    final result = queue.download(file);
    await until(() => telegram.downloads == 1);

    telegram.setConnectionState(const td.ConnectionStateWaitingForNetwork());
    await until(() => state().items.single.wait is WaitingForNetwork);
    expect(state().items.single.status, TransferStatus.running);
    // Still in flight, so nothing lets the phone sleep on it.
    expect(state().active, hasLength(1));
    expect(telegram.cancels, 0);

    telegram.setConnectionState(const td.ConnectionStateReady());
    await until(() => state().items.single.wait == null);
    expect(state().items.single.status, TransferStatus.running);
    result.ignore();
  });

  test('a request that times out is tried again, and the tries are counted', () async {
    // Long enough to see the row wait between tries.
    TransferQueue.waitUnit = const Duration(milliseconds: 20);
    final telegram = _FakeTelegram(fetched.path, timeouts: 2);
    final (:container, :queue, network: _, :file) = await open(telegram, _wifi);
    final seen = <TransferItem>[];
    container.listen<TransfersState>(transferQueueProvider, (_, next) => seen.addAll(next.items));

    final path = await queue.download(file);

    expect(path, fetched.path);
    expect(telegram.downloads, 3);
    expect(
      seen.where((t) => t.status == TransferStatus.queued && t.wait is WaitingForNetwork),
      isNotEmpty,
    );
    expect(seen.where((t) => t.status == TransferStatus.failed), isEmpty);
    final item = container.read(transferQueueProvider).items.single;
    expect(item.status, TransferStatus.completed);
    expect(item.wait, isNull);
  });

  test('after three tries a timeout fails the transfer and says why', () async {
    final telegram = _FakeTelegram(fetched.path, timeouts: 4);
    final (:container, :queue, network: _, :file) = await open(telegram, _wifi);

    await expectLater(queue.download(file), throwsA(isA<TelegramException>()));

    expect(telegram.downloads, 4);
    final item = container.read(transferQueueProvider).items.single;
    expect(item.status, TransferStatus.failed);
    expect(item.row.error, 'Lost the connection to Telegram. Retry when you\'re back online.');
  });

  test('a try again waits for Telegram to have a network', () async {
    final telegram = _FakeTelegram(fetched.path, timeouts: 1);
    final (:container, :queue, network: _, :file) = await open(telegram, _wifi);
    TransferItem item() => container.read(transferQueueProvider).items.single;
    telegram.setConnectionState(const td.ConnectionStateWaitingForNetwork());

    final result = queue.download(file);
    await until(() => telegram.downloads == 1 && item().status == TransferStatus.queued);
    // Its wait before the next try is long over, and still nothing goes
    // without a network.
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(telegram.downloads, 1);
    expect(item().wait, isA<WaitingForNetwork>());

    telegram.setConnectionState(const td.ConnectionStateReady());
    expect(await result, fetched.path);
    expect(telegram.downloads, 2);
  });

  test('a try again goes once Telegram has a network, while it still connects', () async {
    final telegram = _FakeTelegram(fetched.path, timeouts: 1);
    final (:container, :queue, network: _, :file) = await open(telegram, _wifi);
    TransferItem item() => container.read(transferQueueProvider).items.single;
    telegram.setConnectionState(const td.ConnectionStateWaitingForNetwork());

    final result = queue.download(file);
    await until(() => telegram.downloads == 1 && item().status == TransferStatus.queued);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(telegram.downloads, 1);

    telegram.setConnectionState(const td.ConnectionStateConnecting());
    expect(await result, fetched.path);
    expect(telegram.downloads, 2);
  });

  test('a Wi-Fi-only save due another try waits for Wi-Fi on mobile data', () async {
    // Long enough to move the phone onto mobile data before the next try.
    TransferQueue.waitUnit = const Duration(milliseconds: 20);
    final telegram = _FakeTelegram(fetched.path, timeouts: 1);
    final (:container, :queue, :network, :file) = await open(telegram, _wifi);
    TransfersState state() => container.read(transferQueueProvider);

    await queue.enqueueSaves([SaveRequest(file, target: SaveTarget.files, wifiOnly: true)]);
    await until(
      () => telegram.downloads == 1 && state().items.single.status == TransferStatus.queued,
    );

    network.set(_mobile);
    await until(() => state().items.single.wait is WaitingForWifi);
    expect(state().active, isEmpty);
    expect(state().waitingForWifi, [state().items.single]);
    // Its wait before the next try is long over, and still nothing goes on
    // mobile data.
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(telegram.downloads, 1);
    expect(state().items.single.wait, isA<WaitingForWifi>());

    network.set(_wifi);
    await until(() => state().items.single.status == TransferStatus.completed);
    expect(telegram.downloads, 2);
    expect(state().items.single.wait, isNull);
  });

  test('a part that lands starts the tries afresh', () async {
    // Where the parts are stitched back together.
    const paths = MethodChannel('plugins.flutter.io/path_provider');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(paths, (call) async => dir.path);
    addTearDown(() => messenger.setMockMethodCallHandler(paths, null));
    for (final index in [0, 1]) {
      await db.upsertFilePart(
        DriveFilesCompanion.insert(
          id: 'movie',
          name: 'movie.mp4',
          mimeType: 'video/mp4',
          kind: FileKind.video,
          size: 20,
          createdAt: now,
          modifiedAt: now,
          partCount: const Value(2),
        ),
        FilePartsCompanion.insert(
          fileId: 'movie',
          partIndex: index,
          messageId: 30 + index,
          tdFileId: 7,
          size: 10,
        ),
      );
    }
    // Three timeouts before the first part lands, and one more before the
    // second: four in all, but never more than three in a row.
    final telegram = _FlakyTelegram(fetched.path, {1, 2, 3, 5});
    final (:container, :queue, network: _, file: _) = await open(telegram, _wifi);
    final movie = (await container.read(driveRepositoryProvider).fileById('movie'))!;

    final path = await queue.download(movie);

    expect(telegram.downloads, 6);
    expect(File(path).lengthSync(), 20);
    expect(container.read(transferQueueProvider).items.single.status, TransferStatus.completed);
  });

  group('a folder kept offline', () {
    const mb = 1 << 20;

    /// Trips holds a 10 MB and a 30 MB photo; pinning it queues both, and
    /// [starting] of them start fetching. With [talks], Talks is kept
    /// offline already and its 30 MB talk is still to come. With
    /// [alongside], a reconcile after a sync runs at the same time as the
    /// pin. With [onlyOverWifi], Only over Wi-Fi is on. Says which wait for
    /// Wi-Fi.
    Future<Map<String, bool>> pin(
      NetworkState network, {
      bool? wifiOnly,
      required int starting,
      bool talks = false,
      bool alongside = false,
      bool onlyOverWifi = false,
    }) async {
      for (final (index, (id, name)) in [('trips', 'Trips'), if (talks) ('talks', 'Talks')].indexed) {
        await db.upsertFolder(
          FoldersCompanion.insert(
            id: id,
            name: name,
            messageId: 10 + index,
            createdAt: now,
            modifiedAt: now,
          ),
        );
      }
      if (talks) await db.pinOffline('talks', isFolder: true);
      final files = [
        ('small.jpg', 10 * mb, 'trips'),
        ('big.jpg', 30 * mb, 'trips'),
        if (talks) ('talk.mp4', 30 * mb, 'talks'),
      ];
      for (final (index, (name, size, folderId)) in files.indexed) {
        await db.upsertFilePart(
          DriveFilesCompanion.insert(
            id: name,
            folderId: Value(folderId),
            name: name,
            mimeType: 'image/jpeg',
            kind: FileKind.image,
            size: size,
            createdAt: now,
            modifiedAt: now,
            partCount: const Value(1),
          ),
          FilePartsCompanion.insert(
            fileId: name,
            partIndex: 0,
            messageId: 20 + index,
            tdFileId: 20 + index,
            size: size,
          ),
        );
      }
      final telegram = _FakeTelegram(fetched.path, stall: true);
      final (:container, queue: _, network: _, file: _) = await open(
        telegram,
        network,
        onlyOverWifi: onlyOverWifi,
      );
      final folder = DriveFolder.fromRow((await db.folderById('trips'))!);
      final sync = container.read(offlineSyncProvider.notifier);
      final pinned = sync.pin(folder: folder, wifiOnly: wifiOnly);
      if (alongside) await sync.reconcile();
      await pinned;
      await until(() => telegram.downloads == starting);
      return {
        for (final item in container.read(transferQueueProvider).items)
          item.name: item.row.wifiOnly,
      };
    }

    test('from 20 MB, what nobody was asked about waits for Wi-Fi', () async {
      expect(await pin(_mobile, starting: 1), {'small.jpg': false, 'big.jpg': true});
    });

    test('Keep offline now brings everything over mobile data', () async {
      expect(
        await pin(_mobile, wifiOnly: false, starting: 2),
        {'small.jpg': false, 'big.jpg': false},
      );
    });

    test('Later, on Wi-Fi holds even the small ones', () async {
      expect(
        await pin(_mobile, wifiOnly: true, starting: 0),
        {'small.jpg': true, 'big.jpg': true},
      );
    });

    test('the choice is for what is being kept, not for other folders', () async {
      expect(
        await pin(_mobile, wifiOnly: false, starting: 2, talks: true),
        {'small.jpg': false, 'big.jpg': false, 'talk.mp4': true},
      );
    });

    test('the choice holds while a sync brings the copies in line too', () async {
      expect(
        await pin(_mobile, wifiOnly: false, starting: 2, alongside: true),
        {'small.jpg': false, 'big.jpg': false},
      );
    });

    test('with Only over Wi-Fi on, every copy waits, even after Keep', () async {
      expect(
        await pin(_mobile, wifiOnly: false, starting: 0, onlyOverWifi: true),
        {'small.jpg': true, 'big.jpg': true},
      );
    });
  });

  group('Only over Wi-Fi', () {
    /// Where the copy kept offline goes.
    void mockOfflineStore() {
      const paths = MethodChannel('plugins.flutter.io/path_provider');
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(paths, (call) async => dir.path);
      addTearDown(() => messenger.setMockMethodCallHandler(paths, null));
    }

    /// The report kept offline on mobile data, its copy on its way.
    Future<({ProviderContainer container, _FakeTelegram telegram})> keepReport() async {
      mockOfflineStore();
      final telegram = _FakeTelegram(fetched.path, holdFirst: true);
      final (:container, queue: _, network: _, :file) = await open(telegram, _mobile);
      await container.read(offlineSyncProvider.notifier).pin(file: file);
      await until(() => telegram.downloads == 1);
      return (container: container, telegram: telegram);
    }

    test('switched on, a copy on mobile data steps back until Wi-Fi', () async {
      final (:container, :telegram) = await keepReport();
      TransferItem item() => container.read(transferQueueProvider).items.single;
      expect(item().status, TransferStatus.running);

      await container.read(offlineSyncProvider.notifier).setWifiOnly(true);
      expect(container.read(offlineSyncProvider), isTrue);
      expect(container.read(preferencesProvider).offlineWifiOnly, isTrue);
      await until(() => item().status == TransferStatus.queued);
      expect(item().row.wifiOnly, isTrue);
      expect(item().wait, isA<WaitingForWifi>());
      expect(telegram.cancels, 1);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(telegram.downloads, 1);

      (container.read(networkStatusProvider.notifier) as _TestNetwork).set(_wifi);
      await until(() => container.read(transferQueueProvider).items.isEmpty);
      expect(telegram.downloads, 2);
      expect(await db.offlineCopyOf('report'), isNotNull);
    });

    test('Download now brings a copy that waits over mobile data', () async {
      final (:container, :telegram) = await keepReport();
      final queue = container.read(transferQueueProvider.notifier);
      await container.read(offlineSyncProvider.notifier).setWifiOnly(true);
      await until(
        () => container.read(transferQueueProvider).items.single.wait is WaitingForWifi,
      );

      await queue.useMobileData([container.read(transferQueueProvider).items.single.id]);
      await until(() => container.read(transferQueueProvider).items.isEmpty);
      expect(telegram.downloads, 2);
      expect(await db.offlineCopyOf('report'), isNotNull);
      // The switch stays on for what comes later.
      expect(container.read(offlineSyncProvider), isTrue);
    });

    test('switched off, small copies that wait go on mobile data', () async {
      final (:container, :telegram) = await keepReport();
      final sync = container.read(offlineSyncProvider.notifier);
      await sync.setWifiOnly(true);
      await until(
        () => container.read(transferQueueProvider).items.single.wait is WaitingForWifi,
      );

      await sync.setWifiOnly(false);
      await until(() => container.read(transferQueueProvider).items.isEmpty);
      expect(telegram.downloads, 2);
      expect(container.read(preferencesProvider).offlineWifiOnly, isFalse);
    });

    test('switched off, a copy of 20 MB or more keeps waiting until Download now', () async {
      mockOfflineStore();
      const size = TransferPolicy.followUpOnDataBelow;
      await db.upsertFilePart(
        DriveFilesCompanion.insert(
          id: 'film',
          name: 'film.mp4',
          mimeType: 'video/mp4',
          kind: FileKind.video,
          size: size,
          createdAt: now,
          modifiedAt: now,
          partCount: const Value(1),
        ),
        FilePartsCompanion.insert(
          fileId: 'film',
          partIndex: 0,
          messageId: 2,
          tdFileId: 7,
          size: size,
        ),
      );
      final telegram = _FakeTelegram(fetched.path, holdFirst: true);
      final (:container, :queue, network: _, file: _) = await open(telegram, _mobile);
      final film = (await container.read(driveRepositoryProvider).fileById('film'))!;
      final sync = container.read(offlineSyncProvider.notifier);
      TransferItem item() => container.read(transferQueueProvider).items.single;

      await sync.pin(file: film);
      await until(() => container.read(transferQueueProvider).items.isNotEmpty);
      await sync.setWifiOnly(true);
      await sync.setWifiOnly(false);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(container.read(preferencesProvider).offlineWifiOnly, isFalse);
      expect(item().row.wifiOnly, isTrue);
      expect(item().wait, isA<WaitingForWifi>());
      expect(telegram.downloads, 0);

      await queue.useMobileData([item().id]);
      await until(() => telegram.downloads == 1);
    });

    test('a copy still on its way stops when the file is no longer kept', () async {
      final (:container, :telegram) = await keepReport();
      final file = (await container.read(driveRepositoryProvider).fileById('report'))!;

      await container.read(offlineSyncProvider.notifier).unpin(file: file);
      await until(() => container.read(transferQueueProvider).items.isEmpty);
      expect(telegram.cancels, 1);
      expect(await db.offlineCopyList(), isEmpty);
    });
  });

  test('an upload TDLib took up again after a restart steps back on mobile data', () async {
    final source = File('${dir.path}/notes.txt')..writeAsStringSync('0123456789');
    final manifest = FileManifest(
      id: 'notes',
      name: 'notes.txt',
      folderId: null,
      mimeType: 'text/plain',
      size: 10,
      createdAt: now,
      modifiedAt: now,
    );
    final pending = documentMessage(
      500,
      ManifestCodec.encodeFile(manifest).text,
      fileName: 'notes.txt',
      mimeType: 'text/plain',
      size: 10,
    ).copyWith(sendingState: const td.MessageSendingStatePending(sendingId: 0));
    // Running when the app last stopped.
    await db.saveTransfers([
      TransferRow(
        id: 'up',
        kind: TransferKind.upload,
        status: TransferStatus.running,
        name: 'notes.txt',
        mimeType: 'text/plain',
        fileId: 'notes',
        sourcePath: source.path,
        ownsSource: false,
        wifiOnly: true,
        totalBytes: 10,
        doneBytes: 4,
        partCount: 1,
        completedParts: 0,
        createdAt: now,
        origin: TransferOrigin.manual,
      ),
    ]);
    final telegram = _ResumingTelegram(pending);
    final (:container, queue: _, network: _, file: _) = await open(telegram, _mobile);
    TransferItem item() => container.read(transferQueueProvider).byId('up')!;

    await until(() => item().status == TransferStatus.queued);
    expect(telegram.deleted, [500]);
    expect(telegram.sends, 0);
    expect(item().wait, isA<WaitingForWifi>());
  });
}
