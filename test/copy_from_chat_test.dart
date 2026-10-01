import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:telegrive/features/drive/data/drive_repository.dart';
import 'package:telegrive/features/drive/data/drive_session.dart';
import 'package:telegrive/features/drive/domain/manifest.dart';
import 'package:telegrive/features/transfers/data/transfer_queue.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';
import 'package:telegrive/infrastructure/telegram/telegram_client.dart';
import 'package:telegrive/infrastructure/telegram/telegram_exception.dart';

import 'support/fake_telegram.dart';

/// The chat files are saved from.
const _savedMessages = 777;

/// 3 March 2023, 18:04:12 UTC, when the lease was sent.
const _leaseSent = 1_677_866_652;

/// 1 July 2024, when the photo was sent.
const _photoSent = 1_719_835_200;

/// A PDF in [_savedMessages], as message 501.
td.Message _lease() => documentMessage(
  501,
  '',
  fileName: 'Lease.pdf',
  mimeType: 'application/pdf',
  size: 2400,
).copyWith(chatId: _savedMessages, date: _leaseSent);

/// A photo sent as a photo in [_savedMessages], as message 502.
td.Message _photo() => channelMessage(
  502,
  td.MessagePhoto(
    photo: td.Photo(
      hasStickers: false,
      sizes: [
        td.PhotoSize(
          type: 'y',
          photo: tdFile(502, size: 180000),
          width: 1280,
          height: 960,
          progressiveSizes: const [],
        ),
      ],
    ),
    caption: const td.FormattedText(text: '', entities: []),
    showCaptionAboveMedia: false,
    hasSpoiler: false,
    isSecret: false,
  ),
  date: _photoSent,
).copyWith(chatId: _savedMessages);

/// Telegram copying messages the way the shared fake does, keeping every
/// copy it is asked for and when. The copies numbered in [floods], counting
/// from 1, are turned away with a two-second flood wait. Those numbered in
/// [failsLater] are accepted, then fail with that wait as an update, the
/// way TDLib reports a flood on a message it has already taken. With
/// [pending], a copy is only accepted, and its outcome arrives as an update
/// when the test sends one.
class _CopyTelegram extends FakeTelegram {
  _CopyTelegram({
    this.floods = const {},
    this.failsLater = const {},
    this.pending = false,
    this.history = const [],
  });

  final Set<int> floods;
  final Set<int> failsLater;
  final bool pending;

  /// What TDLib still has to send in the channel, as it reads it locally.
  final List<td.Message> history;

  final _updates = StreamController<td.TdObject>.broadcast();
  final List<({int messageId, DateTime at})> copies = [];
  final List<int> deleted = [];
  int attempts = 0;

  static const pendingId = 900;

  /// The id TDLib gives a copy that failed to send, which it keeps.
  static const failedId = 901;

  @override
  Stream<td.TdObject> get updates => _updates.stream;

  void deliver(td.Message message) =>
      _updates.add(td.UpdateMessageSendSucceeded(message: message, oldMessageId: pendingId));

  @override
  Future<td.TdObject?> answer(td.TdFunction function) async {
    switch (function) {
      case td.SendMessage(
        inputMessageContent: td.InputMessageForwarded(:final messageId, :final copyOptions?),
      ):
        attempts++;
        if (floods.contains(attempts)) throw const TelegramException(420, 'FLOOD_WAIT_2');
        final accepted = documentMessage(pendingId, copyOptions.newCaption!.text).copyWith(
          sendingState: const td.MessageSendingStatePending(sendingId: 0),
        );
        if (failsLater.contains(attempts)) {
          final failed = documentMessage(failedId, copyOptions.newCaption!.text);
          Timer.run(
            () => _updates.add(
              td.UpdateMessageSendFailed(
                message: failed,
                oldMessageId: pendingId,
                error: const td.TdError(code: 429, message: 'Too Many Requests: retry after 2'),
              ),
            ),
          );
          return accepted;
        }
        copies.add((messageId: messageId, at: DateTime.now()));
        return pending ? accepted : null;
      case td.GetChatHistory(:final fromMessageId):
        return td.Messages(
          totalCount: history.length,
          messages: fromMessageId == 0 ? history : const [],
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
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    TransferQueue.waitUnit = const Duration(milliseconds: 1);
  });

  tearDown(() async {
    TransferQueue.waitUnit = const Duration(seconds: 1);
    await db.close();
  });

  ProviderContainer open(_CopyTelegram telegram) {
    telegram.messages[501] = _lease();
    telegram.messages[502] = _photo();
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        telegramClientProvider.overrideWithValue(telegram),
        driveSessionProvider.overrideWith(TestSession.new),
      ],
    );
    addTearDown(container.dispose);
    container.listen(transferQueueProvider, (_, _) {});
    return container;
  }

  Future<void> until(bool Function() condition) async {
    for (var i = 0; i < 300 && !condition(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(condition(), isTrue);
  }

  DateTime sent(int seconds) => DateTime.fromMillisecondsSinceEpoch(seconds * 1000);

  final requests = [
    CopyRequest(
      chatId: _savedMessages,
      messageId: 501,
      name: 'Lease.pdf',
      mimeType: 'application/pdf',
      size: 2400,
      date: sent(_leaseSent),
    ),
    CopyRequest(
      chatId: _savedMessages,
      messageId: 502,
      name: 'Photo 2024-07-01 12.00.00.jpg',
      mimeType: 'image/jpeg',
      size: 180000,
      date: sent(_photoSent),
    ),
  ];

  List<TransferItem> copiesIn(ProviderContainer container) =>
      container.read(transferQueueProvider).copies;

  test('copies land one after the other, in the folder, with their dates', () async {
    final telegram = _CopyTelegram();
    final container = open(telegram);
    final queue = container.read(transferQueueProvider.notifier);

    expect(await queue.enqueueCopies(requests, folderId: 'contracts'), 2);
    // Asking again while they are on their way queues nothing more.
    expect(await queue.enqueueCopies(requests, folderId: 'contracts'), 0);
    expect(copiesIn(container), hasLength(2));
    expect(copiesIn(container).every((t) => t.row.origin == TransferOrigin.fromChat), isTrue);

    await until(
      () => copiesIn(container).every((t) => t.status == TransferStatus.completed),
    );
    expect(telegram.copies.map((c) => c.messageId), [501, 502]);
    final lease = copiesIn(container).firstWhere((t) => t.row.sourceMessageId == 501).row;
    // The second copy starts only once the first is in, and a moment after.
    expect(
      telegram.copies[1].at.difference(lease.finishedAt!),
      greaterThanOrEqualTo(const Duration(milliseconds: 350)),
    );

    final repository = container.read(driveRepositoryProvider);
    for (final item in copiesIn(container)) {
      final file = await repository.fileById(item.row.fileId);
      expect(file, isNotNull, reason: item.name);
      expect(file!.folderId, 'contracts');
      expect(file.name, item.name);
      expect(file.size, item.row.totalBytes);
    }
    final pdf = (await repository.fileById(lease.fileId))!;
    expect(pdf.createdAt, sent(_leaseSent));
    expect(pdf.takenAt, isNull);
    final photo = (await repository.fileById(
      copiesIn(container).firstWhere((t) => t.row.sourceMessageId == 502).row.fileId,
    ))!;
    expect(photo.createdAt, sent(_photoSent));
    expect(photo.takenAt, sent(_photoSent));
  });

  test('a flood wait on a copy is waited out', () async {
    final telegram = _CopyTelegram(floods: {1});
    final container = open(telegram);
    final queue = container.read(transferQueueProvider.notifier);

    await queue.enqueueCopies(requests.take(1).toList());
    await until(() => copiesIn(container).single.status == TransferStatus.completed);
    expect(telegram.attempts, 2);
    expect(telegram.copies.map((c) => c.messageId), [501]);
    final row = copiesIn(container).single.row;
    expect(row.error, isNull);
    expect(await container.read(driveRepositoryProvider).fileById(row.fileId), isNotNull);
  });

  test('a copy that fails with a flood wait after it was accepted is made again', () async {
    final telegram = _CopyTelegram(failsLater: {1});
    final container = open(telegram);
    final queue = container.read(transferQueueProvider.notifier);

    await queue.enqueueCopies(requests.take(1).toList());
    await until(() => copiesIn(container).single.status == TransferStatus.completed);
    // TDLib keeps the failed copy under its own id; it never reached the
    // channel, so it is dropped.
    expect(telegram.deleted, [_CopyTelegram.failedId]);
    expect(telegram.attempts, 2);
    expect(telegram.copies.map((c) => c.messageId), [501]);
    final row = copiesIn(container).single.row;
    expect(row.error, isNull);
    expect(await container.read(driveRepositoryProvider).fileById(row.fileId), isNotNull);
  });

  test('cancelling a copy Telegram is still making takes it back', () async {
    final telegram = _CopyTelegram(pending: true);
    final container = open(telegram);
    final queue = container.read(transferQueueProvider.notifier);

    await queue.enqueueCopies(requests.take(1).toList());
    await until(() => telegram.copies.length == 1);
    final id = copiesIn(container).single.id;
    await queue.cancel(id);

    expect(telegram.deleted, [_CopyTelegram.pendingId]);
    expect(copiesIn(container).single.status, TransferStatus.cancelled);
    expect(await db.fileById(copiesIn(container).single.row.fileId), isNull);
  });

  test('Stop drops the copies still to come and keeps those made', () async {
    final telegram = _CopyTelegram();
    final container = open(telegram);
    final queue = container.read(transferQueueProvider.notifier);

    await queue.enqueueCopies(requests);
    await until(() => copiesIn(container).first.status == TransferStatus.completed ||
        copiesIn(container).last.status == TransferStatus.completed);
    await queue.cancelCopies();

    final left = copiesIn(container);
    expect(left.single.status, TransferStatus.completed);
    expect(await db.fileById(left.single.row.fileId), isNotNull);
    expect((await db.allTransfers()).single.id, left.single.id);
  });

  test('a copy TDLib was making when the app stopped is finished, not made again', () async {
    final manifest = FileManifest(
      id: 'lease',
      name: 'Lease.pdf',
      folderId: null,
      mimeType: 'application/pdf',
      size: 2400,
      createdAt: sent(_leaseSent),
      modifiedAt: sent(_leaseSent),
    );
    final caption = ManifestCodec.encodeFile(manifest).text;
    final inFlight = documentMessage(_CopyTelegram.pendingId, caption).copyWith(
      sendingState: const td.MessageSendingStatePending(sendingId: 0),
    );
    await db.saveTransfer(
      TransferRow(
        id: 'copy',
        kind: TransferKind.upload,
        status: TransferStatus.running,
        name: 'Lease.pdf',
        mimeType: 'application/pdf',
        fileId: 'lease',
        ownsSource: false,
        wifiOnly: false,
        totalBytes: 2400,
        doneBytes: 0,
        partCount: 1,
        completedParts: 0,
        createdAt: DateTime(2026, 10, 1),
        origin: TransferOrigin.fromChat,
        takenAt: sent(_leaseSent),
        sourceChatId: _savedMessages,
        sourceMessageId: 501,
      ),
    );
    final telegram = _CopyTelegram(history: [inFlight]);
    final container = open(telegram);

    await until(() => copiesIn(container).singleOrNull?.status == TransferStatus.running);
    telegram.deliver(documentMessage(950, caption, fileName: 'Lease.pdf', mimeType: 'application/pdf'));
    await until(() => copiesIn(container).single.status == TransferStatus.completed);

    expect(telegram.attempts, 0);
    expect(await container.read(driveRepositoryProvider).fileById('lease'), isNotNull);
  });
}
