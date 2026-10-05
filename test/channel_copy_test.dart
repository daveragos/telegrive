import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:telegrive/features/drive/data/channel_messenger.dart';
import 'package:telegrive/features/drive/data/telegram_wait.dart';
import 'package:telegrive/features/drive/domain/manifest.dart';
import 'package:telegrive/infrastructure/telegram/telegram_client.dart';
import 'package:telegrive/infrastructure/telegram/telegram_exception.dart';

import 'support/fake_telegram.dart';

/// A chat the drive sends files to.
const _chatId = 42;

/// The channel, keeping every request it is asked, and turning the forwards
/// numbered in [floods], counting from 1, away with a flood wait of
/// [seconds].
class _LoggingTelegram extends FakeTelegram {
  _LoggingTelegram({this.floods = const {}, this.seconds = 2});

  final Set<int> floods;
  final int seconds;
  final List<td.TdFunction> requests = [];

  List<td.ForwardMessages> get forwards => requests.whereType<td.ForwardMessages>().toList();

  @override
  Future<td.TdObject?> answer(td.TdFunction function) async {
    requests.add(function);
    if (function is td.ForwardMessages && floods.contains(forwards.length)) {
      throw TelegramException(420, 'FLOOD_WAIT_$seconds');
    }
    return null;
  }
}

/// A channel that copies the way TDLib sends: a pending message at once, and
/// the outcome later as an update. The copy is delivered as [copyId], or,
/// when [failing], turned away with a flood wait and kept under [failedId].
class _PendingTelegram extends FakeTelegram {
  _PendingTelegram({this.failing = false});

  static const pendingId = 600;
  static const failedId = 601;
  static const copyId = 602;

  final bool failing;
  final _updates = StreamController<td.TdObject>.broadcast();

  @override
  Stream<td.TdObject> get updates => _updates.stream;

  @override
  Future<td.TdObject?> answer(td.TdFunction function) async {
    if (function case td.SendMessage(
      inputMessageContent: td.InputMessageForwarded(
        copyOptions: td.MessageCopyOptions(:final newCaption?),
      ),
    )) {
      td.Message copy(int id) => documentMessage(id, newCaption.text);
      final td.TdObject outcome;
      if (failing) {
        messages[failedId] = copy(failedId);
        outcome = td.UpdateMessageSendFailed(
          message: copy(failedId),
          oldMessageId: pendingId,
          error: const td.TdError(code: 429, message: 'Too Many Requests: retry after 2'),
        );
      } else {
        messages[copyId] = copy(copyId);
        outcome = td.UpdateMessageSendSucceeded(message: copy(copyId), oldMessageId: pendingId);
      }
      Timer.run(() => _updates.add(outcome));
      return copy(pendingId).copyWith(
        sendingState: const td.MessageSendingStatePending(sendingId: 0),
      );
    }
    return null;
  }
}

void main() {
  late ProviderContainer container;

  ChannelMessenger open(FakeTelegram telegram) {
    container = ProviderContainer(
      overrides: [telegramClientProvider.overrideWithValue(telegram)],
    );
    addTearDown(container.dispose);
    return container.read(channelMessengerProvider);
  }

  final created = DateTime.utc(2026, 9, 1);
  final caption = ManifestCodec.encodeFile(
    FileManifest(
      id: 'a',
      name: 'a.jpg',
      folderId: 'trips',
      mimeType: 'image/jpeg',
      size: 9,
      createdAt: created,
      modifiedAt: created,
    ),
  );

  String captionOf(td.Message message) => (message.content as td.MessageDocument).caption.text;

  setUp(() => TelegramWait.unit = const Duration(milliseconds: 1));
  tearDown(() => TelegramWait.unit = const Duration(seconds: 1));

  group('sendCopy', () {
    test('copies a message with its new caption in one request', () async {
      final telegram = _LoggingTelegram()
        ..messages[10] = documentMessage(10, '', fileName: 'a.jpg', mimeType: 'image/jpeg');
      final messenger = open(telegram);

      final copy = await messenger.sendCopy(
        testChatId,
        fromChatId: testChatId,
        messageId: 10,
        caption: caption,
      );

      final request = telegram.requests.single as td.SendMessage;
      final content = request.inputMessageContent as td.InputMessageForwarded;
      final options = content.copyOptions!;
      expect(request.chatId, testChatId);
      expect(request.options?.disableNotification, isTrue);
      expect(content.fromChatId, testChatId);
      expect(content.messageId, 10);
      expect(options.sendCopy, isTrue);
      expect(options.replaceCaption, isTrue);
      expect(options.newShowCaptionAboveMedia, isFalse);
      expect(options.newCaption?.text, caption.text);
      expect(
        [
          for (final entity in options.newCaption!.entities)
            (entity.type.runtimeType, entity.offset, entity.length),
        ],
        [
          for (final range in caption.styles)
            (
              switch (range.style) {
                CaptionStyle.bold => td.TextEntityTypeBold,
                CaptionStyle.spoiler => td.TextEntityTypeSpoiler,
                CaptionStyle.expandableQuote => td.TextEntityTypeExpandableBlockQuote,
              },
              range.offset,
              range.length,
            ),
        ],
      );
      expect(copy.id, 1000);
      expect(copy.chatId, testChatId);
      expect(captionOf(copy), caption.text);
      expect(telegram.messages.keys, [10, 1000]);
    });

    test('waits for delivery, handing over the pending message first', () async {
      final telegram = _PendingTelegram()..messages[10] = documentMessage(10, '');
      final messenger = open(telegram);
      td.Message? pending;

      final copy = await messenger.sendCopy(
        testChatId,
        fromChatId: testChatId,
        messageId: 10,
        caption: caption,
        onPending: (message) => pending = message,
      );

      expect(pending?.id, _PendingTelegram.pendingId);
      expect(copy.id, _PendingTelegram.copyId);
      expect(captionOf(copy), caption.text);
    });

    test('a copy turned away while sending fails with the message TDLib kept', () async {
      final telegram = _PendingTelegram(failing: true)..messages[10] = documentMessage(10, '');
      final messenger = open(telegram);

      await expectLater(
        messenger.sendCopy(testChatId, fromChatId: testChatId, messageId: 10, caption: caption),
        throwsA(
          isA<SendFailed>()
              .having((e) => e.failedMessageId, 'failed message', _PendingTelegram.failedId)
              .having((e) => e.retryAfterSeconds, 'wait', 2),
        ),
      );
    });
  });

  group('forwardCopies', () {
    final ids = [for (var id = 1; id <= 230; id++) id];
    const allowed = Duration(minutes: 2);

    _LoggingTelegram channel({Set<int> floods = const {}, int seconds = 2}) {
      final telegram = _LoggingTelegram(floods: floods, seconds: seconds);
      for (final id in ids) {
        telegram.messages[id] = documentMessage(id, '$id.jpg\ntgr1:{"id":"$id"}');
      }
      return telegram;
    }

    Future<void> forward(ChannelMessenger messenger, {Duration longestWait = allowed}) =>
        messenger.forwardCopies(
          _chatId,
          fromChatId: testChatId,
          messageIds: ids,
          longestWait: longestWait,
        );

    List<td.Message> sentTo(FakeTelegram telegram) =>
        telegram.messages.values.where((m) => m.chatId == _chatId).toList();

    test('sends 100 messages to a request, in order and without captions', () async {
      final telegram = channel();
      final messenger = open(telegram);

      await forward(messenger);

      expect(telegram.forwards.map((f) => f.messageIds), [
        ids.sublist(0, 100),
        ids.sublist(100, 200),
        ids.sublist(200),
      ]);
      for (final request in telegram.forwards) {
        expect(request.chatId, _chatId);
        expect(request.fromChatId, testChatId);
        expect(request.sendCopy, isTrue);
        expect(request.removeCaption, isTrue);
      }
      final copies = sentTo(telegram);
      expect(copies, hasLength(230));
      expect(copies.map(captionOf), everyElement(isEmpty));
      expect(telegram.messages.keys.where(ids.contains), hasLength(230));
      expect(container.read(telegramWaitProvider), isNull);
    });

    test('a flood wait between requests is sat out, and only that slice goes again', () async {
      final telegram = channel(floods: {2});
      final messenger = open(telegram);
      final waits = <DateTime?>[];
      container.listen<DateTime?>(telegramWaitProvider, (_, next) => waits.add(next));

      await forward(messenger);

      expect(telegram.forwards.map((f) => f.messageIds.length), [100, 100, 100, 30]);
      expect(telegram.forwards[2].messageIds, telegram.forwards[1].messageIds);
      expect(sentTo(telegram), hasLength(230));
      expect(waits.whereType<DateTime>(), isNotEmpty);
      expect(container.read(telegramWaitProvider), isNull);
    });

    test('a wait longer than the caller allows fails, and what went stays sent', () async {
      final telegram = channel(floods: {2}, seconds: 600);
      final messenger = open(telegram);

      await expectLater(
        forward(messenger),
        throwsA(isA<TelegramException>().having((e) => e.retryAfterSeconds, 'wait', 600)),
      );

      expect(telegram.forwards, hasLength(2));
      expect(sentTo(telegram), hasLength(100));
      expect(container.read(telegramWaitProvider), isNull);
    });

    test('a third refusal in a row is thrown', () async {
      final telegram = channel(floods: {1, 2, 3});
      final messenger = open(telegram);

      await expectLater(forward(messenger), throwsA(isA<TelegramException>()));

      expect(telegram.forwards, hasLength(3));
      expect(sentTo(telegram), isEmpty);
    });
  });
}
