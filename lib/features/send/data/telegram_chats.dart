import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;

import '../../../infrastructure/telegram/telegram_client.dart';
import '../../drive/data/drive_repository.dart';
import '../../drive/data/drive_session.dart';
import '../../drive/domain/drive_models.dart';

/// A chat a file can be sent to.
@immutable
class TelegramChat {
  const TelegramChat({
    required this.id,
    required this.title,
    this.photoFileId,
    this.minithumbnail,
    this.isSelf = false,
    this.isGroup = false,
  });

  final int id;
  final String title;

  /// TDLib id of the small chat photo.
  final int? photoFileId;

  /// Base64 JPEG of the photo's blurred preview.
  final String? minithumbnail;

  /// Saved Messages.
  final bool isSelf;
  final bool isGroup;
}

/// The person's Telegram chats, and sending drive files into them.
class TelegramChats {
  TelegramChats(this._ref);

  final Ref _ref;

  TelegramClient get _client => _ref.read(telegramClientProvider);
  int? get _driveChatId => _ref.read(driveSessionProvider)?.chatId;

  /// Saved Messages first, then the chat list in Telegram's own order.
  Future<List<TelegramChat>> recent({int limit = 40}) async {
    final me = await _client.send<td.User>(const td.GetMe());
    final saved = await _client.send<td.Chat>(
      td.CreatePrivateChat(userId: me.id, force: false),
    );
    try {
      await _client.send<td.Ok>(
        const td.LoadChats(chatList: td.ChatListMain(), limit: 50),
      );
    } catch (_) {
      // TDLib answers 404 once every chat is loaded.
    }
    final list = await _client.send<td.Chats>(
      td.GetChats(chatList: const td.ChatListMain(), limit: limit),
    );
    return _resolve([saved.id, ...list.chatIds], selfId: saved.id);
  }

  Future<List<TelegramChat>> search(String query) async {
    final local = await _client.send<td.Chats>(td.SearchChats(query: query, limit: 30));
    td.Chats? remote;
    try {
      remote = await _client.send<td.Chats>(
        td.SearchChatsOnServer(query: query, limit: 30),
      );
    } catch (_) {}
    return _resolve({...local.chatIds, ...?remote?.chatIds}.toList());
  }

  Future<List<TelegramChat>> _resolve(List<int> ids, {int? selfId}) async {
    final chats = <TelegramChat>[];
    for (final id in ids) {
      if (id == _driveChatId) continue;
      try {
        final chat = await _client.send<td.Chat>(td.GetChat(chatId: id));
        // Only chats files can go into: not channels one merely reads, not
        // secret chats (which can't take forwarded files).
        final sendable = switch (chat.type) {
          td.ChatTypePrivate() => true,
          td.ChatTypeBasicGroup() => chat.permissions.canSendDocuments,
          td.ChatTypeSupergroup(isChannel: false) => chat.permissions.canSendDocuments,
          _ => false,
        };
        if (!sendable) continue;
        chats.add(
          TelegramChat(
            id: chat.id,
            title: chat.id == selfId ? 'Saved Messages' : chat.title,
            photoFileId: chat.photo?.small.id,
            minithumbnail: chat.photo?.minithumbnail?.data,
            isSelf: chat.id == selfId,
            isGroup: chat.type is! td.ChatTypePrivate,
          ),
        );
      } catch (e) {
        debugPrint('[Chats] $id: $e');
      }
    }
    return chats;
  }

  /// Sends copies of [files] to each of [chatIds] straight from the drive
  /// channel: Telegram already has them, so nothing is uploaded again. The
  /// drive's own caption stays behind.
  Future<void> send(List<DriveFile> files, List<int> chatIds) async {
    final drive = _driveChatId;
    if (drive == null) throw const DriveException('Your drive is not open.');
    final repository = _ref.read(driveRepositoryProvider);
    final messageIds = <int>[
      for (final file in files) ...(await repository.partsOf(file.id)).map((p) => p.messageId),
    ];
    if (messageIds.isEmpty) return;
    for (final chatId in chatIds) {
      // Telegram forwards at most 100 messages at a time.
      for (var i = 0; i < messageIds.length; i += 100) {
        await _client.send<td.Messages>(
          td.ForwardMessages(
            chatId: chatId,
            messageThreadId: 0,
            fromChatId: drive,
            messageIds: messageIds.sublist(i, math.min(i + 100, messageIds.length)),
            sendCopy: true,
            removeCaption: true,
          ),
        );
      }
    }
  }
}

final telegramChatsProvider = Provider<TelegramChats>(TelegramChats.new);

final recentChatsProvider = FutureProvider.autoDispose<List<TelegramChat>>(
  (ref) => ref.watch(telegramChatsProvider).recent(),
);

final chatSearchProvider = FutureProvider.autoDispose
    .family<List<TelegramChat>, String>(
      (ref, query) => ref.watch(telegramChatsProvider).search(query),
    );
