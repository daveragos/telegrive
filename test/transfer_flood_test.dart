import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:telegrive/core/files/file_kind.dart';
import 'package:telegrive/features/drive/data/channel_messenger.dart';
import 'package:telegrive/features/drive/data/drive_repository.dart';
import 'package:telegrive/features/drive/data/drive_session.dart';
import 'package:telegrive/features/transfers/data/transfer_queue.dart';
import 'package:telegrive/features/transfers/domain/transfer_wait.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';
import 'package:telegrive/infrastructure/telegram/telegram_client.dart';
import 'package:telegrive/infrastructure/telegram/telegram_exception.dart';

import 'support/fake_telegram.dart';

/// Downloads of TDLib file 7. The first try is turned away with a flood
/// wait of [floodSeconds] when [flood] is set; later ones finish at once.
/// [onDownload] runs as each one is answered.
class _FakeTelegram extends FakeTelegram {
  _FakeTelegram(this.path, {this.flood = false, this.floodSeconds = 2, this.onDownload});

  final String path;
  final bool flood;
  final int floodSeconds;
  final void Function()? onDownload;
  int downloads = 0;

  @override
  Future<td.TdObject?> answer(td.TdFunction function) async {
    switch (function) {
      case td.GetFile():
        return tdFile(7);
      case td.DownloadFile():
        downloads++;
        onDownload?.call();
        if (flood && downloads == 1) {
          throw TelegramException(429, 'Too Many Requests: retry after $floodSeconds');
        }
        return tdFile(7, path: path, downloaded: true);
      default:
        return null;
    }
  }
}

/// Sends the way TDLib does: a pending message at once, and the outcome
/// later as an update. The first send fails with a flood wait and leaves
/// the failed message behind under [failedId]; the next one is delivered.
class _UploadTelegram extends FakeTelegram {
  static const pendingId = 500;
  static const failedId = 501;
  static const deliveredId = 502;

  final _updates = StreamController<td.TdObject>.broadcast();
  final List<int> deleted = [];
  int sends = 0;

  @override
  Stream<td.TdObject> get updates => _updates.stream;

  @override
  Future<td.TdObject?> answer(td.TdFunction function) async {
    switch (function) {
      case td.SendMessage(inputMessageContent: td.InputMessageDocument(:final caption?)):
        sends++;
        td.Message message(int id) =>
            documentMessage(id, caption.text, fileName: 'notes.txt', mimeType: 'text/plain');
        final td.TdObject outcome;
        if (sends == 1) {
          messages[failedId] = message(failedId);
          outcome = td.UpdateMessageSendFailed(
            message: message(failedId),
            oldMessageId: pendingId,
            error: const td.TdError(code: 429, message: 'Too Many Requests: retry after 2'),
          );
        } else {
          outcome = td.UpdateMessageSendSucceeded(
            message: message(deliveredId),
            oldMessageId: pendingId,
          );
        }
        Timer.run(() => _updates.add(outcome));
        return message(pendingId).copyWith(
          sendingState: const td.MessageSendingStatePending(sendingId: 0),
        );
      case td.DeleteMessages(:final messageIds):
        deleted.addAll(messageIds);
        return null;
      default:
        return null;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late AppDatabase db;
  final now = DateTime(2026, 9, 26);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('telegrive_flood');
    db = AppDatabase(NativeDatabase.memory());
    TransferQueue.waitUnit = const Duration(milliseconds: 1);
    // Where finished downloads and stitched split files go.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => dir.path,
    );
  });

  tearDown(() async {
    TransferQueue.waitUnit = const Duration(seconds: 1);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    await db.close();
    await dir.delete(recursive: true);
  });

  ProviderContainer open(FakeTelegram telegram) {
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        telegramClientProvider.overrideWithValue(telegram),
        driveSessionProvider.overrideWith(TestSession.new),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<void> until(bool Function() condition) async {
    for (var i = 0; i < 200 && !condition(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(condition(), isTrue);
  }

  Future<void> addFile(String id, {int parts = 1, int messageId = 1}) async {
    for (var index = 0; index < parts; index++) {
      await db.upsertFilePart(
        DriveFilesCompanion.insert(
          id: id,
          name: '$id.pdf',
          mimeType: 'application/pdf',
          kind: FileKind.document,
          size: 10 * parts,
          createdAt: now,
          modifiedAt: now,
          partCount: Value(parts),
        ),
        FilePartsCompanion.insert(
          fileId: id,
          partIndex: index,
          messageId: messageId + index,
          tdFileId: 7,
          size: 10,
        ),
      );
    }
  }

  TransferRow row(
    String id,
    TransferStatus status, {
    TransferKind kind = TransferKind.download,
    TransferOrigin origin = TransferOrigin.manual,
    String fileId = 'report',
    int parts = 1,
    int completedParts = 0,
    String? error,
  }) => TransferRow(
    id: id,
    kind: kind,
    status: status,
    name: '$fileId.pdf',
    mimeType: 'application/pdf',
    fileId: fileId,
    ownsSource: false,
    origin: origin,
    totalBytes: 10 * parts,
    doneBytes: 10 * completedParts,
    partCount: parts,
    completedParts: completedParts,
    error: error,
    createdAt: now,
    finishedAt: status.isFinished ? now : null,
  );

  test('a flood wait puts the download back in the queue, then it finishes', () async {
    final fetched = File('${dir.path}/report.pdf')..writeAsStringSync('0123456789');
    await addFile('report');
    final telegram = _FakeTelegram(fetched.path, flood: true);
    final container = open(telegram);
    final seen = <TransferItem>[];
    container.listen<TransfersState>(
      transferQueueProvider,
      (_, next) => seen.addAll(next.items),
    );

    final file = (await container.read(driveRepositoryProvider).fileById('report'))!;
    final path = await container.read(transferQueueProvider.notifier).download(file);

    expect(path, fetched.path);
    expect(telegram.downloads, 2);
    expect(
      seen.where((t) => t.status == TransferStatus.queued && t.wait is WaitingForTelegram),
      isNotEmpty,
    );
    expect(seen.where((t) => t.status == TransferStatus.failed), isEmpty);
    final item = container.read(transferQueueProvider).items.single;
    expect(item.status, TransferStatus.completed);
    expect(item.wait, isNull);
  });

  test('pausing a transfer on a long wait leaves it paused, not waiting', () async {
    // Long enough for the wait to hold the transfer.
    TransferQueue.waitUnit = const Duration(seconds: 1);
    final fetched = File('${dir.path}/report.pdf')..writeAsStringSync('0123456789');
    await addFile('report');
    final container = open(_FakeTelegram(fetched.path, flood: true, floodSeconds: 600));
    container.listen<TransfersState>(transferQueueProvider, (_, _) {});
    final queue = container.read(transferQueueProvider.notifier);
    TransfersState state() => container.read(transferQueueProvider);

    final file = (await container.read(driveRepositoryProvider).fileById('report'))!;
    queue.download(file).ignore();
    await until(() => state().items.firstOrNull?.wait != null);
    expect(state().held, hasLength(1));

    await queue.pause(state().items.single.id);

    final item = state().items.single;
    expect(item.status, TransferStatus.paused);
    expect(item.wait, isNull);
    expect(state().held, isEmpty);
  });

  test('an upload turned away drops the failed message and goes again', () async {
    final source = File('${dir.path}/notes.txt')..writeAsStringSync('0123456789');
    final telegram = _UploadTelegram();
    final container = open(telegram);
    // The queue reads its saved rows first; this waits for that.
    var loaded = false;
    container.listen<TransfersState>(transferQueueProvider, (_, _) => loaded = true);
    container.read(transferQueueProvider);
    await until(() => loaded);
    final queue = container.read(transferQueueProvider.notifier);

    final [id] = await queue.enqueueUploads([
      UploadRequest(name: 'notes.txt', path: source.path),
    ]);
    final finished = await queue.whenFinished(id);

    expect(finished.status, TransferStatus.completed);
    expect(telegram.sends, 2);
    expect(telegram.deleted, [_UploadTelegram.failedId]);
    expect(telegram.messages, isEmpty);
  });

  test('retryAll queues again only the failed transfers it picks', () async {
    final fetched = File('${dir.path}/report.pdf')..writeAsStringSync('0123456789');
    await addFile('report');
    await db.saveTransfers([
      row('mine', TransferStatus.failed, error: 'Lost the connection to Telegram.'),
      row('saved', TransferStatus.failed, origin: TransferOrigin.save, error: 'Not enough space.'),
      row('done', TransferStatus.completed),
    ]);
    final container = open(_FakeTelegram(fetched.path));
    container.listen<TransfersState>(transferQueueProvider, (_, _) {});
    TransferItem item(String id) => container.read(transferQueueProvider).byId(id)!;
    await until(() => container.read(transferQueueProvider).items.length == 3);

    await container
        .read(transferQueueProvider.notifier)
        .retryAll((r) => r.origin == TransferOrigin.manual);

    await until(() => item('mine').status == TransferStatus.completed);
    expect(item('mine').row.error, isNull);
    expect(item('saved').status, TransferStatus.failed);
    expect(item('saved').row.error, 'Not enough space.');
    expect(item('done').status, TransferStatus.completed);
  });

  test('removing a paused split download deletes what was stitched', () async {
    await addFile('movie', parts: 2);
    await db.saveTransfers([
      row('paused', TransferStatus.paused, fileId: 'movie', parts: 2, completedParts: 1),
    ]);
    final stitched = Directory('${dir.path}/downloads/movie');
    File('${stitched.path}/movie.pdf')
      ..createSync(recursive: true)
      ..writeAsStringSync('0123456789');
    final container = open(_FakeTelegram(''));
    container.listen<TransfersState>(transferQueueProvider, (_, _) {});
    await until(() => container.read(transferQueueProvider).items.length == 1);

    await container.read(transferQueueProvider.notifier).remove('paused');

    expect(stitched.existsSync(), isFalse);
    expect(container.read(transferQueueProvider).items, isEmpty);
    expect(await db.allTransfers(), isEmpty);
  });

  test('removing a split download while a part is stitched in keeps it gone', () async {
    final fetched = File('${dir.path}/part.bin')..writeAsStringSync('0123456789');
    await addFile('movie', parts: 2);
    late ProviderContainer container;
    Future<void>? removed;
    // Removed straight after the first part arrives, while it is being
    // appended to the stitched copy.
    final telegram = _FakeTelegram(
      fetched.path,
      onDownload: () => Timer.run(() {
        final id = container.read(transferQueueProvider).items.single.id;
        removed ??= container.read(transferQueueProvider.notifier).remove(id);
      }),
    );
    container = open(telegram);
    container.listen<TransfersState>(transferQueueProvider, (_, _) {});
    final stitched = Directory('${dir.path}/downloads/movie');

    final file = (await container.read(driveRepositoryProvider).fileById('movie'))!;
    await expectLater(
      container.read(transferQueueProvider.notifier).download(file),
      throwsA(isA<SendCancelled>()),
    );
    await until(() => removed != null);
    await removed;
    await until(() => !stitched.existsSync());
    // Whatever the work had in hand when it stopped has run its course.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(telegram.downloads, 1);
    expect(container.read(transferQueueProvider).items, isEmpty);
    expect(await db.allTransfers(), isEmpty);
  });

  test('removing a paused split upload deletes the parts already sent', () async {
    final telegram = _FakeTelegram('');
    final container = open(telegram);
    final repository = container.read(driveRepositoryProvider);
    final part = documentMessage(
      21,
      'big.bin.001\ntgr1:{"id":"big","n":"big.bin","s":20,"ct":1700000000000,'
      '"pc":2}',
      fileName: 'big.bin.001',
    );
    telegram.messages[part.id] = part;
    await repository.ingest(part);
    expect(await repository.fileById('big'), isNotNull);
    await db.saveTransfers([
      row(
        'upload',
        TransferStatus.paused,
        kind: TransferKind.upload,
        fileId: 'big',
        parts: 2,
        completedParts: 1,
      ),
    ]);
    container.listen<TransfersState>(transferQueueProvider, (_, _) {});
    await until(() => container.read(transferQueueProvider).items.length == 1);

    await container.read(transferQueueProvider.notifier).remove('upload');

    expect(telegram.messages, isEmpty);
    expect(await db.partsOf('big'), isEmpty);
    expect(container.read(transferQueueProvider).items, isEmpty);
  });
}
