import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:telegrive/core/files/file_kind.dart';
import 'package:telegrive/features/drive/data/drive_session.dart';
import 'package:telegrive/features/drive/data/drive_sync.dart';
import 'package:telegrive/features/drive/data/thumbnail_prefetch.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';
import 'package:telegrive/infrastructure/network/network_status.dart';
import 'package:telegrive/infrastructure/storage/device_storage.dart';
import 'package:telegrive/infrastructure/telegram/telegram_client.dart';
import 'package:telegrive/infrastructure/telegram/telegram_exception.dart';

import 'support/fake_telegram.dart';

const _wifi = NetworkState(online: true, metered: false);
const _mobile = NetworkState(online: true, metered: true);
const _gb = 1 << 30;

/// Thumbnails Telegram hands over at once; [onPhone] are fetched already,
/// and asking about any in [refused] fails the way it says.
class _Telegram extends FakeTelegram {
  _Telegram({this.onPhone = const {}, this.refused = const {}});

  final Set<int> onPhone;
  final Map<int, TelegramException> refused;
  final asked = <int>[];
  final downloads = <int>[];

  @override
  Future<td.TdObject?> answer(td.TdFunction function) async {
    switch (function) {
      case td.GetFile(:final fileId):
        asked.add(fileId);
        if (refused[fileId] case final error?) throw error;
        return tdFile(fileId, downloaded: onPhone.contains(fileId));
      case td.DownloadFile(:final fileId):
        downloads.add(fileId);
        return tdFile(fileId, path: '/thumbs/$fileId.jpg', downloaded: true);
      default:
        return null;
    }
  }
}

/// A phone whose connection the test moves.
class _Network extends NetworkStatus {
  _Network(this._initial);

  final NetworkState _initial;

  @override
  NetworkState build() => _initial;

  void set(NetworkState next) => state = next;
}

class _Storage extends DeviceStorage {
  _Storage(this.free);

  final int free;

  @override
  Future<int?> freeBytes() async => free;
}

class _IdleSync extends DriveSync {
  @override
  SyncState build() => const SyncState();
}

void main() {
  late AppDatabase db;

  setUp(() async {
    ThumbnailPrefetch.enabled = true;
    ThumbnailPrefetch.unit = const Duration(milliseconds: 1);
    db = AppDatabase(NativeDatabase.memory());
    final now = DateTime(2026, 9, 30);
    for (final (index, id, kind, thumbnail, taken) in [
      (0, 'new', FileKind.image, 11, DateTime(2026, 9, 20)),
      (1, 'clip', FileKind.video, 12, DateTime(2026, 6)),
      (2, 'old', FileKind.image, 13, DateTime(2019)),
      (3, 'mine', FileKind.image, 14, DateTime(2026, 9, 25)),
    ]) {
      await db.upsertFilePart(
        DriveFilesCompanion.insert(
          id: id,
          name: '$id.jpg',
          mimeType: 'image/jpeg',
          kind: kind,
          size: 100,
          createdAt: now,
          modifiedAt: now,
          takenAt: Value(taken),
          thumbnailFileId: Value(thumbnail),
        ),
        FilePartsCompanion.insert(
          fileId: id,
          partIndex: 0,
          messageId: index + 1,
          tdFileId: index + 100,
          size: 100,
        ),
      );
    }
    // Backed up from this phone, so its tile shows the phone's copy.
    await db.markAssetBackedUp('asset-1', 'mine');
  });

  tearDown(() async {
    ThumbnailPrefetch.enabled = false;
    ThumbnailPrefetch.unit = const Duration(seconds: 1);
    await db.close();
  });

  ProviderContainer containerFor(
    _Telegram telegram, {
    NetworkState network = _wifi,
    int free = 20 * _gb,
  }) {
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        telegramClientProvider.overrideWithValue(telegram),
        driveSessionProvider.overrideWith(TestSession.new),
        driveSyncProvider.overrideWith(_IdleSync.new),
        networkStatusProvider.overrideWith(() => _Network(network)),
        deviceStorageProvider.overrideWithValue(_Storage(free)),
      ],
    );
    addTearDown(container.dispose);
    container.listen(thumbnailPrefetchProvider, (_, _) {});
    return container;
  }

  /// Long enough for a run that was going to happen to have finished.
  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 300));

  test('on Wi-Fi, the newest thumbnails come down, skipping what the phone has', () async {
    final telegram = _Telegram(onPhone: {12});
    final container = containerFor(telegram);

    await settle();
    // Not the photo backed up from this phone, nor the one already here.
    expect(telegram.asked, [11, 12, 13]);
    expect(telegram.downloads, [11, 13]);
    expect(container.read(thumbnailPrefetchProvider), 2);
  });

  test('a thumbnail TDLib has forgotten is passed over', () async {
    final telegram = _Telegram(
      refused: {11: const TelegramException(400, 'Invalid file identifier')},
    );
    containerFor(telegram);

    await settle();
    expect(telegram.downloads, [12, 13]);
  });

  test('when Telegram asks to slow down the run ends', () async {
    const flood = TelegramException(429, 'Too Many Requests: retry after 300');
    final telegram = _Telegram(refused: {11: flood, 12: flood, 13: flood});
    containerFor(telegram);

    await settle();
    expect(telegram.asked, [11]);
    expect(telegram.downloads, isEmpty);
  });

  test('on mobile data nothing comes down until the phone is on Wi-Fi', () async {
    final telegram = _Telegram();
    final container = containerFor(telegram, network: _mobile);

    await settle();
    expect(telegram.downloads, isEmpty);

    (container.read(networkStatusProvider.notifier) as _Network).set(_wifi);
    await settle();
    expect(telegram.downloads, [11, 12, 13]);
  });

  test('a phone short of space fetches nothing', () async {
    final telegram = _Telegram();
    containerFor(telegram, free: ThumbnailPrefetch.minFree - 1);

    await settle();
    expect(telegram.downloads, isEmpty);
  });
}
