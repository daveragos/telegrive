import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegrive/core/files/file_kind.dart';
import 'package:telegrive/features/drive/data/drive_repository.dart';
import 'package:telegrive/features/drive/data/drive_session.dart';
import 'package:telegrive/features/transfers/data/transfer_queue.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';
import 'package:telegrive/infrastructure/storage/device_profile.dart';
import 'package:telegrive/infrastructure/telegram/telegram_client.dart';

import 'support/fake_telegram.dart';

/// A file split in two that went up as far as [parts] of its parts, its
/// messages numbered from [base], since a message holds one part only.
Future<void> _split(AppDatabase db, String id, {required int parts, required int base}) async {
  final now = DateTime(2026, 10, 9);
  for (var index = 0; index < parts; index++) {
    await db.upsertFilePart(
      DriveFilesCompanion.insert(
        id: id,
        name: '$id.mp4',
        mimeType: 'video/mp4',
        kind: FileKind.video,
        size: 3000,
        createdAt: now,
        modifiedAt: now,
        partCount: const Value(2),
      ),
      FilePartsCompanion.insert(
        fileId: id,
        partIndex: index,
        messageId: base + index,
        tdFileId: base + 50 + index,
        size: 1500,
      ),
    );
  }
}

/// An upload of [fileId] that was under way when the app stopped, one part
/// of two sent.
TransferRow _interrupted(String fileId) => TransferRow(
  id: 'upload-$fileId',
  kind: TransferKind.upload,
  status: TransferStatus.running,
  name: '$fileId.mp4',
  mimeType: 'video/mp4',
  fileId: fileId,
  sourcePath: '/gone/$fileId.mp4',
  ownsSource: false,
  wifiOnly: false,
  totalBytes: 3000,
  doneBytes: 1500,
  partCount: 2,
  completedParts: 1,
  createdAt: DateTime(2026, 10, 9),
  origin: TransferOrigin.manual,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late AppDatabase db;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('telegrive_half');
    db = AppDatabase(NativeDatabase.memory());
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => dir.path,
    );
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    await db.close();
    await dir.delete(recursive: true);
  });

  ProviderContainer open() {
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        telegramClientProvider.overrideWithValue(FakeTelegram()),
        driveSessionProvider.overrideWith(TestSession.new),
        saveMemoryProvider.overrideWithBuild((ref, notifier) => false),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('a split file with a part still to go is not whole, nor matched as already in the drive', () async {
    await _split(db, 'half', parts: 1, base: 100);
    await _split(db, 'whole', parts: 2, base: 200);
    final repository = open().read(driveRepositoryProvider);
    expect((await db.fileById('half'))!.partsPresent, 1);
    expect(await repository.isWhole('half'), isFalse);
    expect(await repository.isWhole('whole'), isTrue);
    expect(await repository.isWhole('nothing'), isFalse);
    expect([for (final file in await db.fileMatchRows()) file.id], ['whole']);
  });

  test('photos and videos without a preview are found, smallest first, others left out', () async {
    final now = DateTime(2026, 10, 9);
    Future<void> add(String id, FileKind kind, int size, {int? thumbnail, int parts = 1}) => db.upsertFilePart(
      DriveFilesCompanion.insert(
        id: id,
        name: id,
        mimeType: 'application/octet-stream',
        kind: kind,
        size: size,
        createdAt: now,
        modifiedAt: now,
        partCount: Value(parts),
        thumbnailFileId: Value(thumbnail),
      ),
      FilePartsCompanion.insert(fileId: id, partIndex: 0, messageId: 900 + size, tdFileId: 950 + size, size: size),
    );
    await add('big.mp4', FileKind.video, 300);
    await add('small.heic', FileKind.image, 10);
    await add('has-preview.jpg', FileKind.image, 20, thumbnail: 7);
    await add('notes.pdf', FileKind.document, 30);
    await add('split.mp4', FileKind.video, 40, parts: 2);
    final rows = await db.filesWithoutPreview(['big.mp4', 'small.heic', 'has-preview.jpg', 'notes.pdf', 'split.mp4']);
    expect([for (final row in rows) row.id], ['small.heic', 'big.mp4']);
  });

  test('after a restart, an upload whose file is only part there is not taken for done', () async {
    await _split(db, 'half', parts: 1, base: 100);
    await _split(db, 'whole', parts: 2, base: 200);
    await db.saveTransfers([_interrupted('half'), _interrupted('whole')]);
    final container = open();
    container.read(transferQueueProvider);
    final queue = container.read(transferQueueProvider.notifier);
    await queue.loaded;
    TransferStatus statusOf(String fileId) => container.read(transferQueueProvider).byId('upload-$fileId')!.status;
    // The whole one landed while the app was away.
    expect(statusOf('whole'), TransferStatus.completed);
    // The other still has its second part to send: it goes on, and with its
    // file gone from the phone it fails, saying so, rather than pass for done.
    expect(statusOf('half'), isNot(TransferStatus.completed));
    final ended = await queue.whenFinished('upload-half').timeout(const Duration(seconds: 5));
    expect(ended.status, TransferStatus.failed);
  });
}
