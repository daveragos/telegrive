import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:telegrive/core/files/file_kind.dart';
import 'package:telegrive/features/backup/data/backup_run_mode.dart';
import 'package:telegrive/features/drive/data/drive_repository.dart';
import 'package:telegrive/features/drive/data/drive_session.dart';
import 'package:telegrive/features/transfers/data/transfer_queue.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';
import 'package:telegrive/infrastructure/storage/device_profile.dart';
import 'package:telegrive/infrastructure/telegram/telegram_client.dart';

import 'support/fake_telegram.dart';

/// Telegram that counts the downloads it is asked for.
class _FakeTelegram extends FakeTelegram {
  int downloads = 0;

  @override
  Future<td.TdObject?> answer(td.TdFunction function) async {
    switch (function) {
      case td.GetFile():
        return tdFile(7, path: '/files/report.pdf', downloaded: false);
      case td.DownloadFile():
        downloads++;
        return Completer<td.File>().future;
      default:
        return null;
    }
  }
}

/// A file of ten bytes in one part, on TDLib's file 7.
Future<void> _seed(AppDatabase db) async {
  final now = DateTime(2026, 9, 26);
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
    FilePartsCompanion.insert(fileId: 'report', partIndex: 0, messageId: 1, tdFileId: 7, size: 10),
  );
}

void main() {
  late AppDatabase db;
  late _FakeTelegram telegram;
  late ProviderContainer container;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    telegram = _FakeTelegram();
    await _seed(db);
    // The background backup job's queue, before its drive opens.
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        telegramClientProvider.overrideWithValue(telegram),
        saveMemoryProvider.overrideWithBuild((ref, notifier) => false),
        backupRunModeProvider.overrideWithValue(BackupRunMode.background),
      ],
    );
    container.listen(transferQueueProvider, (_, _) {});
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('a download someone queued waits for the app, untouched', () async {
    await db.saveTransfer(
      TransferRow(
        id: 'mine',
        kind: TransferKind.download,
        status: TransferStatus.queued,
        name: 'report.pdf',
        mimeType: 'application/pdf',
        fileId: 'report',
        ownsSource: false,
        wifiOnly: false,
        origin: TransferOrigin.manual,
        totalBytes: 10,
        doneBytes: 0,
        partCount: 1,
        completedParts: 0,
        createdAt: DateTime(2026, 10, 4),
      ),
    );

    container.read(driveSessionProvider.notifier).open(testSession);
    await container.read(transferQueueProvider.notifier).loaded;
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(telegram.downloads, 0);
    expect(container.read(transferQueueProvider).items, isEmpty);
    final kept = (await db.allTransfers()).single;
    expect((kept.id, kept.status), ('mine', TransferStatus.queued));
  });

  test('a download asked for in the job is kept for the app', () async {
    container.read(driveSessionProvider.notifier).open(testSession);
    final queue = container.read(transferQueueProvider.notifier);
    await queue.loaded;

    final file = (await container.read(driveRepositoryProvider).fileById('report'))!;
    unawaited(queue.download(file).then<void>((_) {}, onError: (Object _) {}));
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(telegram.downloads, 0);
    expect((await db.allTransfers()).single.status, TransferStatus.queued);
  });
}
