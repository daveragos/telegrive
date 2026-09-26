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
import 'package:telegrive/infrastructure/telegram/secure_store.dart';
import 'package:telegrive/infrastructure/telegram/telegram_client.dart';

class _Session extends DriveSessionNotifier {
  @override
  DriveSession? build() => const DriveSession(
    userId: 1,
    chatId: -100,
    channelTitle: 'Telegrive',
    firstName: 'A',
    lastName: '',
    phoneNumber: '',
    username: null,
    isPremium: false,
  );
}

/// A download of file 7 that takes a moment, unless it is cancelled first.
class _FakeTelegram extends TelegramClient {
  _FakeTelegram(this.path) : super(SecureStore());

  final String path;
  bool done = false;
  int downloads = 0;
  int cancels = 0;
  Completer<td.File>? _inFlight;

  td.File _file() => td.File(
    id: 7,
    size: 10,
    expectedSize: 10,
    local: td.LocalFile(
      path: done ? path : '',
      canBeDownloaded: true,
      canBeDeleted: true,
      isDownloadingActive: false,
      isDownloadingCompleted: done,
      downloadOffset: 0,
      downloadedPrefixSize: done ? 10 : 4,
      downloadedSize: done ? 10 : 4,
    ),
    remote: const td.RemoteFile(
      id: 'r',
      uniqueId: 'u',
      isUploadingActive: false,
      isUploadingCompleted: true,
      uploadedSize: 10,
    ),
  );

  @override
  Future<T> send<T extends td.TdObject>(
    td.TdFunction function, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    switch (function) {
      case td.GetChatHistory():
        return const td.Messages(totalCount: 0, messages: []) as T;
      case td.GetFile():
        return _file() as T;
      case td.DownloadFile():
        downloads++;
        final inFlight = _inFlight = Completer<td.File>();
        // The second attempt is allowed to finish.
        if (downloads > 1) {
          Timer(const Duration(milliseconds: 50), () {
            done = true;
            if (!inFlight.isCompleted) inFlight.complete(_file());
          });
        }
        return await inFlight.future as T;
      case td.CancelDownloadFile():
        cancels++;
        final inFlight = _inFlight;
        if (inFlight != null && !inFlight.isCompleted) inFlight.complete(_file());
        return const td.Ok() as T;
      default:
        throw UnsupportedError('$function');
    }
  }
}

void main() {
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
        driveSessionProvider.overrideWith(_Session.new),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
    });

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
