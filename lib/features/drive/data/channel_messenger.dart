import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;

import '../../../infrastructure/telegram/telegram_client.dart';
import '../../../infrastructure/telegram/telegram_exception.dart';
import '../domain/manifest.dart';
import 'telegram_wait.dart';

/// Thrown into a pending send when the person cancels it.
class SendCancelled implements Exception {
  const SendCancelled();
}

/// A send Telegram turned down. TDLib keeps the failed message in the chat
/// under a new id, [failedMessageId], so whoever gives up on the send can
/// delete it.
class SendFailed extends TelegramException {
  const SendFailed(super.code, super.message, {required this.failedMessageId});

  final int failedMessageId;
}

/// Everything the drive does to messages in its channel.
///
/// The awkward part of sending through TDLib is that `sendMessage` returns a
/// *temporary* message immediately, and the real one — with its permanent id —
/// only arrives later as `updateMessageSendSucceeded`. [send] hides that: it
/// resolves with the delivered message, or fails with Telegram's error.
///
/// Copies are Telegram's own work, with nothing uploaded: [sendCopy] turns a
/// message anywhere into one of the drive's own, manifest and all, and
/// [forwardCopies] sends files on to any chat without the drive's captions.
class ChannelMessenger {
  ChannelMessenger(this._client, this._ref) {
    _subscription = _client.updates.listen(_onUpdate);
  }

  final TelegramClient _client;
  final Ref _ref;
  late final StreamSubscription<td.TdObject> _subscription;

  final Map<int, Completer<td.Message>> _waiters = {};

  /// Deliveries that landed before anyone waited for them — a small file can
  /// finish before the caller has even registered interest.
  final LinkedHashMap<int, Object> _early = LinkedHashMap();

  static const td.MessageSendOptions _silent = td.MessageSendOptions(
    disableNotification: true,
    fromBackground: true,
    protectContent: false,
    updateOrderOfInstalledStickerSets: false,
    effectId: 0,
    sendingId: 0,
    onlyPreview: false,
  );

  static td.FormattedText formatted(EncodedText encoded) => td.FormattedText(
    text: encoded.text,
    entities: [
      td.TextEntity(
        offset: encoded.spoilerOffset,
        length: encoded.spoilerLength,
        type: const td.TextEntityTypeSpoiler(),
      ),
    ],
  );

  /// Sends a document; [onPending] receives the temporary message as soon as
  /// TDLib accepts it, which is when upload progress can start being tracked.
  Future<td.Message> sendDocument(
    int chatId, {
    required String path,
    required EncodedText caption,
    String? thumbnailPath,
    void Function(td.Message pending)? onPending,
  }) {
    return _send(
      chatId,
      td.InputMessageDocument(
        document: td.InputFileLocal(path: path),
        // Telegram makes previews for image documents itself, but not for
        // video; a client-made JPEG (≤ 320 px) fills that gap.
        thumbnail: thumbnailPath == null
            ? null
            : td.InputThumbnail(
                thumbnail: td.InputFileLocal(path: thumbnailPath),
                width: 0,
                height: 0,
              ),
        // Keep photos and videos as untouched documents — Telegram would
        // otherwise recompress them.
        disableContentTypeDetection: true,
        caption: formatted(caption),
      ),
      onPending: onPending,
    );
  }

  /// Has Telegram copy [messageId] of [fromChatId] into [chatId] with
  /// [caption] in place of the original's, in one request: a photo stays a
  /// photo, a document a document, and the copy never sits in the channel
  /// without its manifest. A flood wait is the caller's to sit out, since
  /// the transfer queue shows it on the row and the drive's edits go
  /// through [patiently].
  Future<td.Message> sendCopy(
    int chatId, {
    required int fromChatId,
    required int messageId,
    required EncodedText caption,
    void Function(td.Message pending)? onPending,
  }) {
    return _send(
      chatId,
      td.InputMessageForwarded(
        fromChatId: fromChatId,
        messageId: messageId,
        inGameShare: false,
        copyOptions: td.MessageCopyOptions(
          sendCopy: true,
          replaceCaption: true,
          newCaption: formatted(caption),
          newShowCaptionAboveMedia: false,
        ),
      ),
      onPending: onPending,
    );
  }

  /// Sends copies of [messageIds] from [fromChatId] to [chatId], the way
  /// files leave the drive for a chat: Telegram already has them, so nothing
  /// is uploaded, and the drive's captions stay behind. Telegram forwards at
  /// most 100 messages at a time, and a flood wait of up to [longestWait]
  /// between requests is sat out before the same slice goes again, so
  /// nothing already sent is sent twice.
  Future<void> forwardCopies(
    int chatId, {
    required int fromChatId,
    required List<int> messageIds,
    required Duration longestWait,
  }) async {
    for (final batch in _batches(messageIds)) {
      await patiently(
        () => _client.send<td.Messages>(
          td.ForwardMessages(
            chatId: chatId,
            messageThreadId: 0,
            fromChatId: fromChatId,
            messageIds: batch,
            sendCopy: true,
            removeCaption: true,
          ),
        ),
        longestWait: longestWait,
      );
    }
  }

  /// Runs [action], sitting out Telegram's flood waits of up to
  /// [longestWait] through [TelegramWait] instead of failing, so a long run
  /// of requests carries on by itself; a longer wait, or a third refusal in
  /// a row, is thrown as it came. The wait shows above the bar, where Stop
  /// can cut it short when [stoppable].
  Future<T> patiently<T>(
    Future<T> Function() action, {
    required Duration longestWait,
    bool stoppable = true,
  }) async {
    for (var attempt = 1; ; attempt++) {
      try {
        return await action();
      } on TelegramException catch (e) {
        final wait = Duration(seconds: e.retryAfterSeconds ?? 30);
        if (!e.isFloodWait || wait > longestWait || attempt >= 3) rethrow;
        await _ref.read(telegramWaitProvider.notifier).sleep(wait, stoppable: stoppable);
      }
    }
  }

  Future<td.Message> sendText(int chatId, EncodedText text) {
    return _send(
      chatId,
      td.InputMessageText(
        text: formatted(text),
        linkPreviewOptions: const td.LinkPreviewOptions(
          isDisabled: true,
          url: '',
          forceSmallMedia: false,
          forceLargeMedia: false,
          showAboveText: false,
        ),
        clearDraft: false,
      ),
    );
  }

  Future<td.Message> _send(
    int chatId,
    td.InputMessageContent content, {
    void Function(td.Message pending)? onPending,
  }) async {
    final pending = await _client.send<td.Message>(
      td.SendMessage(
        chatId: chatId,
        messageThreadId: 0,
        options: _silent,
        inputMessageContent: content,
      ),
    );
    if (pending.sendingState == null) return pending;
    onPending?.call(pending);
    return awaitDelivery(pending.id);
  }

  /// Waits for a message TDLib is still sending — including one it resumed
  /// on its own after the app restarted.
  Future<td.Message> awaitDelivery(int pendingId) {
    final early = _early.remove(pendingId);
    if (early is td.Message) return Future.value(early);
    if (early is TelegramException) return Future.error(early);
    return (_waiters[pendingId] ??= Completer<td.Message>()).future;
  }

  /// Stops a send in flight. Deleting the pending message is how TDLib is
  /// told to abandon the upload.
  Future<void> cancel(int chatId, int pendingId) async {
    _waiters.remove(pendingId)?.completeError(const SendCancelled());
    await deleteMessages(chatId, [pendingId]);
  }

  /// Messages TDLib is still sending in [chatId], from its local database.
  Future<List<td.Message>> pendingMessages(int chatId) async {
    final result = <td.Message>[];
    var from = 0;
    for (var page = 0; page < 20; page++) {
      final history = await _client.send<td.Messages>(
        td.GetChatHistory(
          chatId: chatId,
          fromMessageId: from,
          offset: 0,
          limit: 100,
          onlyLocal: true,
        ),
      );
      if (history.messages.isEmpty) break;
      result.addAll(history.messages.where((m) => m.sendingState != null));
      from = history.messages.last.id;
    }
    return result;
  }

  Future<td.Message> editCaption(
    int chatId,
    int messageId,
    EncodedText caption,
  ) {
    return _client.send<td.Message>(
      td.EditMessageCaption(
        chatId: chatId,
        messageId: messageId,
        caption: formatted(caption),
        showCaptionAboveMedia: false,
      ),
    );
  }

  Future<td.Message> editText(int chatId, int messageId, EncodedText text) {
    return _client.send<td.Message>(
      td.EditMessageText(
        chatId: chatId,
        messageId: messageId,
        inputMessageContent: td.InputMessageText(
          text: formatted(text),
          clearDraft: false,
        ),
      ),
    );
  }

  /// Deletes for everyone, in the batches Telegram accepts.
  Future<void> deleteMessages(int chatId, List<int> messageIds) async {
    for (final batch in _batches(messageIds)) {
      await _client.send<td.Ok>(
        td.DeleteMessages(chatId: chatId, messageIds: batch, revoke: true),
      );
    }
  }

  /// Telegram takes at most 100 messages in one forward or delete.
  static Iterable<List<int>> _batches(List<int> ids) sync* {
    for (var i = 0; i < ids.length; i += 100) {
      yield ids.sublist(i, math.min(i + 100, ids.length));
    }
  }

  void _onUpdate(td.TdObject update) {
    switch (update) {
      case td.UpdateMessageSendSucceeded(:final oldMessageId, :final message):
        _resolve(oldMessageId, message);
      case td.UpdateMessageSendFailed(:final oldMessageId, :final message, :final error):
        _resolve(
          oldMessageId,
          SendFailed(error.code, error.message, failedMessageId: message.id),
        );
      default:
        break;
    }
  }

  void _resolve(int pendingId, Object outcome) {
    final waiter = _waiters.remove(pendingId);
    if (waiter == null) {
      _early[pendingId] = outcome;
      while (_early.length > 64) {
        _early.remove(_early.keys.first);
      }
      return;
    }
    if (outcome is td.Message) {
      waiter.complete(outcome);
    } else {
      waiter.completeError(outcome);
    }
  }

  void dispose() {
    _subscription.cancel();
    for (final waiter in _waiters.values) {
      waiter.completeError(const SendCancelled());
    }
    _waiters.clear();
  }
}

final channelMessengerProvider = Provider<ChannelMessenger>((ref) {
  final messenger = ChannelMessenger(ref.watch(telegramClientProvider), ref);
  ref.onDispose(messenger.dispose);
  return messenger;
});
