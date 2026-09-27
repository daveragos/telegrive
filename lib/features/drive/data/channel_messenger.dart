import 'dart:async';
import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;

import '../../../infrastructure/telegram/telegram_client.dart';
import '../../../infrastructure/telegram/telegram_exception.dart';
import '../domain/manifest.dart';

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
class ChannelMessenger {
  ChannelMessenger(this._client) {
    _subscription = _client.updates.listen(_onUpdate);
  }

  final TelegramClient _client;
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
    for (var i = 0; i < messageIds.length; i += 100) {
      final batch = messageIds.sublist(
        i,
        i + 100 > messageIds.length ? messageIds.length : i + 100,
      );
      await _client.send<td.Ok>(
        td.DeleteMessages(chatId: chatId, messageIds: batch, revoke: true),
      );
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
  final messenger = ChannelMessenger(ref.watch(telegramClientProvider));
  ref.onDispose(messenger.dispose);
  return messenger;
});
