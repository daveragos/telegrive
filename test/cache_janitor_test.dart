import 'dart:async';

import 'package:drift/native.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegrive/features/drive/data/drive_session.dart';
import 'package:telegrive/features/space/data/cache_janitor.dart';
import 'package:telegrive/features/transfers/data/transfer_queue.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';
import 'package:telegrive/infrastructure/storage/device_storage.dart';
import 'package:telegrive/infrastructure/storage/preferences.dart';
import 'package:telegrive/infrastructure/telegram/telegram_client.dart';

import 'support/fake_telegram.dart';

const _mb = 1 << 20;
const _gb = 1 << 30;

/// A 64 GB phone whose free space a test sets.
class _Storage extends DeviceStorage {
  _Storage(this.free);

  int free;

  @override
  Future<int?> freeBytes() async => free;

  @override
  Future<int?> totalBytes() async => 64 * _gb;
}

/// Telegram that records each trim it is asked for and says one file went.
class _Telegram extends FakeTelegram {
  final List<td.OptimizeStorage> trims = [];

  @override
  Future<td.TdObject?> answer(td.TdFunction function) async {
    if (function is td.OptimizeStorage) {
      trims.add(function);
      return const td.StorageStatistics(size: 4 * _mb, count: 1, byChat: []);
    }
    return null;
  }
}

/// A queue holding [items] that counts its leftover sweeps and notes how
/// old the joined split files it is asked to clear must be.
class _Queue extends TransferQueue {
  _Queue(this.items);

  final List<TransferItem> items;
  int sweeps = 0;
  final List<Duration> oldDownloads = [];

  @override
  TransfersState build() => TransfersState(items);

  @override
  Future<int> clearLeftovers() async {
    sweeps++;
    return 0;
  }

  @override
  Future<int> clearOldDownloads({required Duration olderThan, DateTime? now}) async {
    oldDownloads.add(olderThan);
    return 0;
  }

  @override
  Future<void> recheckRoom() async {}
}

void main() {
  late AppDatabase db;
  late _Telegram telegram;
  late _Storage storage;
  late _Queue queue;
  late Preferences prefs;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<CacheJanitor> janitor({
    required int free,
    DateTime? sweptAt,
    List<TransferItem> transfers = const [],
  }) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({
      if (sweptAt != null) 'cache_swept_at': sweptAt.millisecondsSinceEpoch,
    });
    final shared = await SharedPreferences.getInstance();
    telegram = _Telegram();
    queue = _Queue(transfers);
    storage = _Storage(free);
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(shared),
        appDatabaseProvider.overrideWithValue(db),
        telegramClientProvider.overrideWithValue(telegram),
        driveSessionProvider.overrideWith(TestSession.new),
        deviceStorageProvider.overrideWithValue(storage),
        transferQueueProvider.overrideWith(() => queue),
      ],
    );
    addTearDown(container.dispose);
    prefs = container.read(preferencesProvider);
    container.read(cacheJanitorProvider);
    return container.read(cacheJanitorProvider.notifier);
  }

  TransferItem running() => TransferItem(
    TransferRow(
      id: 't1',
      kind: TransferKind.download,
      status: TransferStatus.running,
      name: 'film.mkv',
      mimeType: 'video/x-matroska',
      fileId: 'film',
      ownsSource: false,
      wifiOnly: false,
      totalBytes: 1,
      doneBytes: 0,
      partCount: 1,
      completedParts: 0,
      createdAt: DateTime.now(),
      origin: TransferOrigin.manual,
    ),
  );

  test('a nearly full phone is trimmed to 100 MB straight away', () async {
    final now = DateTime.now();
    await (await janitor(free: 250 * _mb, sweptAt: now)).run();

    final trim = telegram.trims.single;
    expect(trim.size, 100 * _mb);
    expect(trim.ttl, const Duration(days: 1).inSeconds);
    expect(trim.immunityDelay, const Duration(hours: 1).inSeconds);
    expect(trim.fileTypes, isEmpty);
    expect(queue.oldDownloads, [const Duration(days: 1)]);
    // The daily pass is still to come.
    expect(queue.sweeps, 0);
    expect(prefs.cacheSweptAt, DateTime.fromMillisecondsSinceEpoch(now.millisecondsSinceEpoch));
  });

  test('nothing is trimmed while a transfer runs', () async {
    await (await janitor(free: 100 * _mb, transfers: [running()])).run();

    expect(telegram.trims, isEmpty);
    expect(queue.oldDownloads, isEmpty);
    expect(queue.sweeps, 0);
    expect(prefs.cacheSweptAt, isNull);
  });

  test('a day after the last pass, opened files are trimmed to the budget and '
      'leftovers swept', () async {
    await (await janitor(
      free: 20 * _gb,
      sweptAt: DateTime.now().subtract(const Duration(days: 2)),
    )).run();

    final trim = telegram.trims.single;
    expect(trim.size, _gb);
    expect(trim.ttl, const Duration(days: 14).inSeconds);
    expect(trim.immunityDelay, const Duration(hours: 1).inSeconds);
    expect(queue.oldDownloads, [const Duration(days: 14)]);
    expect(queue.sweeps, 1);
    expect(
      DateTime.now().difference(prefs.cacheSweptAt!),
      lessThan(const Duration(minutes: 1)),
    );
  });

  test('within a day of the last pass, only a nearly full phone is trimmed', () async {
    final recently = DateTime.now().subtract(const Duration(hours: 3));
    await (await janitor(free: 20 * _gb, sweptAt: recently)).run();

    expect(telegram.trims, isEmpty);
    expect(queue.oldDownloads, isEmpty);
    expect(queue.sweeps, 0);

    await (await janitor(free: 200 * _mb, sweptAt: recently)).run();

    expect(telegram.trims.single.size, 100 * _mb);
    expect(queue.sweeps, 0);
  });

  test('a drive that stays open is looked at again a day after each pass', () async {
    final swept = await janitor(
      free: 20 * _gb,
      sweptAt: DateTime.now().subtract(const Duration(days: 2)),
    );

    fakeAsync((async) {
      unawaited(swept.run());
      async.flushMicrotasks();
      expect(telegram.trims, hasLength(1));

      // The phone fills up while the app stays alive.
      storage.free = 100 * _mb;
      async.elapse(const Duration(hours: 23));
      expect(telegram.trims, hasLength(1));

      async.elapse(const Duration(hours: 1));
      expect(telegram.trims, hasLength(2));
      expect(telegram.trims.last.size, 100 * _mb);

      // And again the day after.
      async.elapse(const Duration(days: 1));
      expect(telegram.trims, hasLength(3));
    });
  });
}
