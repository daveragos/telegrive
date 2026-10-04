import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:telegrive/core/files/file_kind.dart';
import 'package:telegrive/features/drive/data/drive_repository.dart';
import 'package:telegrive/features/drive/data/drive_session.dart';
import 'package:telegrive/features/transfers/data/transfer_queue.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';
import 'package:telegrive/infrastructure/storage/device_profile.dart';
import 'package:telegrive/infrastructure/telegram/telegram_client.dart';

import 'support/fake_telegram.dart';

/// Downloads that start and never finish, so every one started stays
/// running.
class _FakeTelegram extends FakeTelegram {
  final Set<int> downloading = {};

  @override
  Future<td.TdObject?> answer(td.TdFunction function) async {
    switch (function) {
      case td.GetFile(:final fileId):
        return tdFile(fileId);
      case td.DownloadFile(:final fileId):
        downloading.add(fileId);
        return Completer<td.File>().future;
      case td.CancelDownloadFile():
        return const td.Ok();
      default:
        return null;
    }
  }
}

void main() {
  /// How many of three queued downloads start at once.
  Future<int> started({required bool saveMemory}) async {
    final db = AppDatabase(NativeDatabase.memory());
    final telegram = _FakeTelegram();
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        telegramClientProvider.overrideWithValue(telegram),
        driveSessionProvider.overrideWith(TestSession.new),
        saveMemoryProvider.overrideWithBuild((ref, notifier) => saveMemory),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
    });

    final now = DateTime(2026, 10, 4);
    for (var i = 1; i <= 3; i++) {
      await db.upsertFilePart(
        DriveFilesCompanion.insert(
          id: 'doc$i',
          name: 'doc$i.pdf',
          mimeType: 'application/pdf',
          kind: FileKind.document,
          size: 10,
          createdAt: now,
          modifiedAt: now,
          partCount: const Value(1),
        ),
        FilePartsCompanion.insert(
          fileId: 'doc$i',
          partIndex: 0,
          messageId: i,
          tdFileId: 10 + i,
          size: 10,
        ),
      );
    }

    container.listen(transferQueueProvider, (_, _) {});
    final queue = container.read(transferQueueProvider.notifier);
    final repository = container.read(driveRepositoryProvider);
    for (var i = 1; i <= 3; i++) {
      unawaited(queue.download((await repository.fileById('doc$i'))!));
    }
    // Long enough for every download the queue lets go to reach Telegram.
    for (var i = 0; i < 50; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    return telegram.downloading.length;
  }

  test('three queued downloads all start on an ordinary phone', () async {
    expect(await started(saveMemory: false), 3);
  });

  test('two of them start while the phone saves memory', () async {
    expect(await started(saveMemory: true), 2);
  });
}
