import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:path/path.dart' as p;
import 'package:telegrive/core/files/file_kind.dart';
import 'package:telegrive/features/drive/data/channel_messenger.dart';
import 'package:telegrive/features/drive/data/drive_repository.dart';
import 'package:telegrive/features/drive/data/drive_session.dart';
import 'package:telegrive/features/transfers/data/transfer_queue.dart';
import 'package:telegrive/features/transfers/domain/transfer_wait.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';
import 'package:telegrive/infrastructure/storage/device_profile.dart';
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
/// later as an update. The sends numbered in [floods], counting from 1, fail
/// with a flood wait of [floodSeconds] and leave the failed message behind;
/// the rest are delivered into the channel. The outcome for a file named in
/// [holding] waits for [release]. Downloads of TDLib file 7 finish at once
/// from [downloadPath].
class _UploadTelegram extends FakeTelegram {
  _UploadTelegram({
    this.floods = const {1},
    this.floodSeconds = 2,
    this.holding = const {},
    this.downloadPath = '',
  });

  final Set<int> floods;
  final int floodSeconds;
  final Set<String> holding;
  final String downloadPath;

  final _updates = StreamController<td.TdObject>.broadcast();
  final _released = Completer<void>();
  final List<int> deleted = [];

  /// The file names sent, in order.
  final List<String> sent = [];

  /// The messages TDLib kept after a failed send, and those delivered.
  final List<int> failedIds = [];
  final List<int> deliveredIds = [];

  int get sends => sent.length;

  /// Lets through the outcomes [holding] kept back.
  void release() => _released.complete();

  @override
  Stream<td.TdObject> get updates => _updates.stream;

  @override
  Future<td.TdObject?> answer(td.TdFunction function) async {
    switch (function) {
      case td.SendMessage(
        inputMessageContent: td.InputMessageDocument(
          document: td.InputFileLocal(:final path),
          :final caption?,
        ),
      ):
        sent.add(p.basename(path));
        final send = sent.length;
        td.Message message(int id) =>
            documentMessage(id, caption.text, fileName: p.basename(path), mimeType: 'text/plain');
        final pendingId = 1000 + send;
        final td.TdObject outcome;
        if (floods.contains(send)) {
          final failed = message(2000 + send);
          messages[failed.id] = failed;
          failedIds.add(failed.id);
          outcome = td.UpdateMessageSendFailed(
            message: failed,
            oldMessageId: pendingId,
            error: td.TdError(code: 429, message: 'Too Many Requests: retry after $floodSeconds'),
          );
        } else {
          final delivered = message(3000 + send);
          messages[delivered.id] = delivered;
          deliveredIds.add(delivered.id);
          outcome = td.UpdateMessageSendSucceeded(message: delivered, oldMessageId: pendingId);
        }
        if (holding.contains(p.basename(path))) {
          unawaited(_released.future.then((_) => _updates.add(outcome)));
        } else {
          Timer.run(() => _updates.add(outcome));
        }
        return message(pendingId).copyWith(
          sendingState: const td.MessageSendingStatePending(sendingId: 0),
        );
      case td.DeleteMessages(:final messageIds):
        deleted.addAll(messageIds);
        return null;
      case td.GetFile():
        return tdFile(7);
      case td.DownloadFile():
        return tdFile(7, path: downloadPath, downloaded: true);
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
        saveMemoryProvider.overrideWithBuild((ref, notifier) => false),
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
    wifiOnly: false,
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

  /// The queue for [telegram], once it has read its saved rows.
  Future<(ProviderContainer, TransferQueue)> openQueue(FakeTelegram telegram) async {
    final container = open(telegram);
    var loaded = false;
    container.listen<TransfersState>(transferQueueProvider, (_, _) => loaded = true);
    container.read(transferQueueProvider);
    await until(() => loaded);
    return (container, container.read(transferQueueProvider.notifier));
  }

  test('an upload turned away drops the failed message and goes again', () async {
    final source = File('${dir.path}/notes.txt')..writeAsStringSync('0123456789');
    final telegram = _UploadTelegram();
    final (_, queue) = await openQueue(telegram);

    final [id] = await queue.enqueueUploads([
      UploadRequest(name: 'notes.txt', path: source.path),
    ]);
    final finished = await queue.whenFinished(id);

    expect(finished.status, TransferStatus.completed);
    expect(telegram.sends, 2);
    expect(telegram.deleted, telegram.failedIds);
    expect(telegram.messages.keys, telegram.deliveredIds);
  });

  test('uploads queued behind one Telegram turned away wait with it', () async {
    // A wait of a second, long enough to see what happens while it lasts.
    TransferQueue.waitUnit = const Duration(milliseconds: 100);
    final fetched = File('${dir.path}/report.pdf')..writeAsStringSync('0123456789');
    await addFile('report');
    final telegram = _UploadTelegram(floodSeconds: 9, downloadPath: fetched.path);
    final (container, queue) = await openQueue(telegram);
    TransferItem item(String id) => container.read(transferQueueProvider).byId(id)!;

    final ids = await queue.enqueueUploads([
      for (final name in ['a.txt', 'b.txt', 'c.txt'])
        UploadRequest(
          name: name,
          path: (File('${dir.path}/$name')..writeAsStringSync(name)).path,
        ),
    ]);
    // Two go up at once. When the first is turned away, the third waits
    // too, rather than send all its bytes to be turned away at the end.
    await until(() => item(ids[2]).wait is WaitingForTelegram);
    expect(telegram.sent, unorderedEquals(['a.txt', 'b.txt']));
    expect(item(ids[2]).status, TransferStatus.queued);

    // Downloads don't wait on the uploads' pause.
    final file = (await container.read(driveRepositoryProvider).fileById('report'))!;
    expect(await queue.download(file), fetched.path);
    expect(telegram.sends, 2);

    for (final id in ids) {
      expect((await queue.whenFinished(id)).status, TransferStatus.completed);
    }
    // Once the wait is over, the one turned away goes again, and so does c.
    expect(telegram.sent.skip(2), unorderedEquals([telegram.sent.first, 'c.txt']));
  });

  test('a split upload under way sends no more parts while uploads wait', () async {
    // A wait of a second, long enough to see what happens while it lasts.
    TransferQueue.waitUnit = const Duration(milliseconds: 100);
    // As long as the row says, three parts of ten bytes.
    final source = File('${dir.path}/big.pdf')..writeAsStringSync('0123456789' * 3);
    await db.saveTransfers([
      row(
        'big',
        TransferStatus.queued,
        kind: TransferKind.upload,
        fileId: 'big',
        parts: 3,
        completedParts: 1,
      ).copyWith(sourcePath: Value(source.path)),
    ]);
    // The split upload's next part stays in flight until the upload sent
    // after it has been turned away.
    final telegram = _UploadTelegram(
      floods: const {2},
      floodSeconds: 9,
      holding: const {'big.pdf.002'},
    );
    final (container, queue) = await openQueue(telegram);
    TransferItem item(String id) => container.read(transferQueueProvider).byId(id)!;
    await until(() => telegram.sent.contains('big.pdf.002'));

    final [id] = await queue.enqueueUploads([
      UploadRequest(
        name: 'notes.txt',
        path: (File('${dir.path}/notes.txt')..writeAsStringSync('notes')).path,
      ),
    ]);
    await until(() => item(id).wait is WaitingForTelegram);
    // The part in flight lands, and the next one waits with the rest rather
    // than go up in full to be turned away at the end.
    telegram.release();
    await until(() => item('big').wait is WaitingForTelegram);
    expect(item('big').status, TransferStatus.queued);
    expect(item('big').row.completedParts, 2);
    expect(telegram.sent, ['big.pdf.002', 'notes.txt']);

    expect((await queue.whenFinished('big')).status, TransferStatus.completed);
    expect((await queue.whenFinished(id)).status, TransferStatus.completed);
    expect(telegram.sent.skip(2), unorderedEquals(['big.pdf.003', 'notes.txt']));
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

  test('an upload cancelled as it lands is taken back out of the channel', () async {
    final source = File('${dir.path}/notes.txt')..writeAsStringSync('0123456789');
    final telegram = _UploadTelegram(floods: const {});
    final (container, queue) = await openQueue(telegram);
    // The cancel comes just after the delivery reaches the drive's
    // messenger, which listens first, and before the part is indexed: there
    // is no send left to stop.
    container.read(channelMessengerProvider);
    Future<void>? cancelled;
    telegram.updates.listen((update) {
      if (update is td.UpdateMessageSendSucceeded) {
        cancelled ??= queue.cancel(container.read(transferQueueProvider).items.single.id);
      }
    });

    await queue.enqueueUploads([UploadRequest(name: 'notes.txt', path: source.path)]);
    await until(() => cancelled != null);
    await cancelled;
    final fileId = container.read(transferQueueProvider).items.single.row.fileId;
    await until(() => telegram.messages.isEmpty);

    expect(telegram.deleted, containsAll(telegram.deliveredIds));
    expect(await db.partsOf(fileId), isEmpty);
    expect(await db.fileById(fileId), isNull);
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
