import 'dart:async';
import 'dart:io';

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

/// A download of file 7 that takes a moment, unless it is cancelled first.
/// The attempts from [finishFrom] on are allowed to finish.
class _FakeTelegram extends FakeTelegram {
  _FakeTelegram(this.path, {this.finishFrom = 2});

  final String path;
  final int finishFrom;
  bool done = false;
  int downloads = 0;
  int cancels = 0;
  Completer<td.File>? _inFlight;

  td.File _file() => tdFile(7, path: path, downloaded: done);

  @override
  Future<td.TdObject?> answer(td.TdFunction function) async {
    switch (function) {
      case td.GetFile():
        return _file();
      case td.DownloadFile():
        downloads++;
        final inFlight = _inFlight = Completer<td.File>();
        if (downloads >= finishFrom) {
          Timer(const Duration(milliseconds: 50), () {
            done = true;
            if (!inFlight.isCompleted) inFlight.complete(_file());
          });
        }
        return inFlight.future;
      case td.CancelDownloadFile():
        cancels++;
        final inFlight = _inFlight;
        if (inFlight != null && !inFlight.isCompleted) inFlight.complete(_file());
        return const td.Ok();
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
    FilePartsCompanion.insert(
      fileId: 'report',
      partIndex: 0,
      messageId: 1,
      tdFileId: 7,
      size: 10,
    ),
  );
}

void main() {
  test('a download asked for before the drive opens waits, then finishes once it does', () async {
    final dir = await Directory.systemTemp.createTemp('telegrive_late');
    addTearDown(() => dir.delete(recursive: true));
    final fetched = File('${dir.path}/report.pdf')..writeAsStringSync('0123456789');

    final db = AppDatabase(NativeDatabase.memory());
    final telegram = _FakeTelegram(fetched.path, finishFrom: 1);
    // No session yet: Home shows the drive from the index while Telegram
    // starts.
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        telegramClientProvider.overrideWithValue(telegram),
        saveMemoryProvider.overrideWithBuild((ref, notifier) => false),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    await _seed(db);

    container.listen(transferQueueProvider, (_, _) {});
    final queue = container.read(transferQueueProvider.notifier);
    final file = (await container.read(driveRepositoryProvider).fileById('report'))!;
    final result = queue.download(file);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(telegram.downloads, 0);
    final waiting = container.read(transferQueueProvider).items.single;
    expect(waiting.status, TransferStatus.queued);
    // Kept, so opening the drive finds it.
    expect((await db.allTransfers()).single.status, TransferStatus.queued);

    container.read(driveSessionProvider.notifier).open(testSession);

    expect(await result.timeout(const Duration(seconds: 5)), fetched.path);
    expect(telegram.downloads, 1);
    expect(
      container.read(transferQueueProvider).items.single.status,
      TransferStatus.completed,
    );
  });

  test('a paused download waits, then finishes when resumed', () async {
    final dir = await Directory.systemTemp.createTemp('telegrive_pause');
    addTearDown(() => dir.delete(recursive: true));
    final fetched = File('${dir.path}/report.pdf')..writeAsStringSync('0123456789');

    final db = AppDatabase(NativeDatabase.memory());
    final telegram = _FakeTelegram(fetched.path);
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        telegramClientProvider.overrideWithValue(telegram),
        driveSessionProvider.overrideWith(TestSession.new),
        saveMemoryProvider.overrideWithBuild((ref, notifier) => false),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
    });

    await _seed(db);

    container.listen(transferQueueProvider, (_, _) {});
    final queue = container.read(transferQueueProvider.notifier);
    TransferItem item() => container.read(transferQueueProvider).items.single;
    Future<void> until(bool Function() condition) async {
      for (var i = 0; i < 200 && !condition(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(condition(), isTrue);
    }

    final file = (await container.read(driveRepositoryProvider).fileById('report'))!;
    final result = queue.download(file);
    await until(() => telegram.downloads == 1);
    expect(item().status, TransferStatus.running);

    await queue.pause(item().id);
    await until(() => item().status == TransferStatus.paused);
    expect(telegram.cancels, 1);
    // Paused is neither running nor finished.
    expect(container.read(transferQueueProvider).active, isEmpty);
    expect(container.read(transferQueueProvider).finished, isEmpty);
    expect(container.read(transferQueueProvider).pending, hasLength(1));

    // Opening the file again resumes the same transfer rather than starting
    // another.
    final again = queue.download(file);
    expect(await result, fetched.path);
    expect(await again, fetched.path);
    expect(item().status, TransferStatus.completed);
    expect(container.read(transferQueueProvider).items, hasLength(1));
  });
}
