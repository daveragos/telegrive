import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegrive/features/drive/data/drive_repository.dart';
import 'package:telegrive/features/drive/data/message_indexer.dart';
import 'package:telegrive/features/drive/data/preview_maker.dart';
import 'package:telegrive/features/drive/domain/drive_models.dart';
import 'package:telegrive/features/drive/domain/manifest.dart';
import 'package:telegrive/features/transfers/data/transfer_queue.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';
import 'package:telegrive/infrastructure/network/network_status.dart';
import 'package:telegrive/infrastructure/storage/device_storage.dart';
import 'package:telegrive/infrastructure/telegram/telegram_exception.dart';

import 'support/fake_telegram.dart';

class _MobileData extends NetworkStatus {
  @override
  NetworkState build() => const NetworkState(online: true, metered: true);
}

class _Wifi extends NetworkStatus {
  @override
  NetworkState build() => const NetworkState(online: true, metered: false);
}

class _Storage extends DeviceStorage {
  @override
  Future<int?> freeBytes() async => 64 << 30;
}

/// A queue that fetches every file but `gone.mp4`, whose download fails as
/// TDLib says when Telegram hands nothing over.
class _Queue extends TransferQueue {
  _Queue(this.into);

  final Directory into;

  @override
  TransfersState build() => TransfersState.empty;

  @override
  Future<String?> localPathIfAvailable(DriveFile file) async => null;

  @override
  Future<String> download(DriveFile file) async {
    if (file.name == 'gone.mp4') {
      throw const TelegramException(400, 'File download has failed or was canceled');
    }
    return (File('${into.path}/${file.name}')..writeAsBytesSync([1, 2, 3])).path;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');

  setUp(() {
    final temp = Directory.systemTemp.createTempSync('preview_maker_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      pathProvider,
      (call) async => temp.path,
    );
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        pathProvider,
        null,
      );
      temp.deleteSync(recursive: true);
    });
  });

  test('a file Telegram doesn\'t send is passed over, and the rest still go', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final at = DateTime(2026, 8, 19);
    // Smallest first, so the one that fails comes before the other.
    for (final (number, name) in [(1, 'gone.mp4'), (2, 'fine.mp4')]) {
      final entry =
          MessageIndexer.entryFor(
                documentMessage(
                  number << 20,
                  ManifestCodec.encodeFile(
                    FileManifest(
                      id: name,
                      name: name,
                      folderId: null,
                      mimeType: 'video/mp4',
                      size: number * 1000,
                      createdAt: at,
                      modifiedAt: at,
                    ),
                  ).text,
                  fileName: name,
                ),
              )!
              as FilePartEntry;
      await db.upsertFilePart(entry.file, entry.part);
    }
    final rows = [(await db.fileById('gone.mp4'))!, (await db.fileById('fine.mp4'))!];
    final fetched = Directory.systemTemp.createTempSync('preview_maker_fetched');
    addTearDown(() => fetched.deleteSync(recursive: true));
    final container = ProviderContainer(
      overrides: [
        networkStatusProvider.overrideWith(_Wifi.new),
        appDatabaseProvider.overrideWithValue(db),
        deviceStorageProvider.overrideWithValue(_Storage()),
        transferQueueProvider.overrideWith(() => _Queue(fetched)),
      ],
    );
    addTearDown(container.dispose);
    final maker = container.read(previewMakerProvider);

    final result = await maker.make(rows);

    expect(result.outcome.complete, isTrue);
    expect(result.outcome.done, 2);
    expect(result.notFetched, 1);
    // No picture is made here, away from a phone, but the second file was
    // fetched and tried.
    expect(result.noPicture, 1);
    // Passed over for the rest of this run, not waited on again.
    expect(maker.worthTrying(rows), isEmpty);
  });

  test('a bigger file gets longer to arrive', () {
    expect(PreviewMaker.fetchWithin(0), const Duration(minutes: 1));
    expect(PreviewMaker.fetchWithin(4000000), const Duration(seconds: 140));
  });

  ProviderContainer onMobileData() {
    final container = ProviderContainer(
      overrides: [networkStatusProvider.overrideWith(_MobileData.new)],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('on mobile data, previews wait for Wi-Fi unless the person agreed', () async {
    final maker = onMobileData().read(previewMakerProvider);

    await expectLater(maker.make(const []), throwsA(isA<DriveException>()));
  });

  test('on mobile data the person agreed to, previews go ahead', () async {
    final maker = onMobileData().read(previewMakerProvider);

    final result = await maker.make(const [], onMobileData: true);

    expect(result.outcome.complete, isTrue);
    expect(result.noPicture, 0);
  });
}
