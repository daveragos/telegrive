import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;

import '../../../infrastructure/storage/preferences.dart';
import '../../../infrastructure/telegram/telegram_client.dart';
import '../../drive/data/channel_messenger.dart';
import '../../drive/data/drive_repository.dart';
import '../../drive/data/drive_session.dart';
import 'send_bundle.dart';

/// A chat a file can be sent to, or saved from.
@immutable
class TelegramChat {
  const TelegramChat({
    required this.id,
    required this.title,
    this.photoFileId,
    this.minithumbnail,
    this.isSelf = false,
    this.isGroup = false,
    this.slowMode = false,
    this.canSave = true,
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

  /// A group in slow mode, where members send one message at a time and
  /// can't forward several at once. Its admins aren't held to it.
  final bool slowMode;

  /// Whether files may be copied out of it: false when the chat protects
  /// its content.
  final bool canSave;
}

/// The person's Telegram chats: sending drive files into them, and which
/// of them files can be saved from.
class TelegramChats {
  TelegramChats(this._ref);

  final Ref _ref;

  TelegramClient get _client => _ref.read(telegramClientProvider);
  int? get _driveChatId => _ref.read(driveSessionProvider)?.chatId;

  /// Saved Messages first, then the chats this phone last sent files to,
  /// then the chat list in Telegram's own order. With [forImport], the
  /// chats files can be saved from, channels the person only reads
  /// included, in Telegram's order after Saved Messages.
  Future<List<TelegramChat>> recent({int limit = 40, bool forImport = false}) async {
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
    final ids = {
      saved.id,
      if (!forImport) ..._ref.read(preferencesProvider).recentSendChats,
      ...list.chatIds,
    };
    return _resolve(ids.toList(), selfId: saved.id, forImport: forImport);
  }

  Future<List<TelegramChat>> search(String query, {bool forImport = false}) async {
    final local = await _client.send<td.Chats>(td.SearchChats(query: query, limit: 30));
    td.Chats? remote;
    try {
      remote = await _client.send<td.Chats>(
        td.SearchChatsOnServer(query: query, limit: 30),
      );
    } catch (_) {}
    return _resolve({...local.chatIds, ...?remote?.chatIds}.toList(), forImport: forImport);
  }

  /// The chats behind [ids] that files can go into, or with [forImport],
  /// come from. Secret chats are never listed, nor the drive itself.
  Future<List<TelegramChat>> _resolve(
    List<int> ids, {
    int? selfId,
    bool forImport = false,
  }) async {
    final chats = <TelegramChat>[];
    for (final id in ids) {
      if (id == _driveChatId) continue;
      try {
        final chat = await _client.send<td.Chat>(td.GetChat(chatId: id));
        // Sending needs a chat files can go into: not a channel one merely
        // reads, not a secret chat (which can't take forwarded files).
        // Saving reads from any chat but a secret one, whose messages
        // can't be copied.
        final listed = switch (chat.type) {
          td.ChatTypePrivate() => true,
          td.ChatTypeBasicGroup() || td.ChatTypeSupergroup() when forImport => true,
          td.ChatTypeBasicGroup() => chat.permissions.canSendDocuments,
          td.ChatTypeSupergroup(isChannel: false) => chat.permissions.canSendDocuments,
          _ => false,
        };
        if (!listed) continue;
        final slowMode = switch (chat.type) {
          td.ChatTypeSupergroup(:final supergroupId) when !forImport => _slowFor(
            await _client.send<td.Supergroup>(
              td.GetSupergroup(supergroupId: supergroupId),
            ),
          ),
          _ => false,
        };
        chats.add(
          TelegramChat(
            id: chat.id,
            title: chat.id == selfId ? 'Saved Messages' : chat.title,
            photoFileId: chat.photo?.small.id,
            minithumbnail: chat.photo?.minithumbnail?.data,
            isSelf: chat.id == selfId,
            isGroup: chat.type is! td.ChatTypePrivate,
            slowMode: slowMode,
            canSave: !chat.hasProtectedContent,
          ),
        );
      } catch (e) {
        debugPrint('[Chats] $id: $e');
      }
    }
    return chats;
  }

  static bool _slowFor(td.Supergroup group) =>
      group.isSlowModeEnabled &&
      group.status is! td.ChatMemberStatusCreator &&
      group.status is! td.ChatMemberStatusAdministrator;

  /// The longest Telegram pause a send sits out before giving up.
  static const Duration longestWait = Duration(minutes: 2);

  /// Sends [bundle] to each of [chats] straight from the drive channel:
  /// [message] first when there is one, then each group's header line and
  /// copies of its files. Telegram already has the files, so nothing is
  /// uploaded again, and the drive's own captions stay behind. Pauses
  /// Telegram asks for, up to [longestWait], are sat out.
  ///
  /// A group in slow mode takes one message at a time and no forward of
  /// several, so it gets the first file alone, without the message or
  /// headers. That is reported as a [DriveException] once every other chat
  /// has had its files.
  Future<void> sendBundle(
    SendBundle bundle,
    List<TelegramChat> chats, {
    String message = '',
  }) async {
    final drive = _driveChatId;
    if (drive == null) throw driveNotOpen(_ref.read(driveSnapshotProvider));
    final repository = _ref.read(driveRepositoryProvider);
    final messenger = _ref.read(channelMessengerProvider);
    final groups = [
      for (final group in bundle.groups)
        (
          header: group.header,
          messageIds: [
            for (final file in group.files)
              ...(await repository.partsOf(file.id))
                  .map((part) => part.messageId),
          ],
        ),
    ];
    final messageIds = [for (final group in groups) ...group.messageIds];
    if (messageIds.isEmpty) return;

    Future<void> forward(int chatId, List<int> ids) => messenger.forwardCopies(
      chatId,
      fromChatId: drive,
      messageIds: ids,
      longestWait: longestWait,
    );

    var leftOut = false;
    for (final chat in chats) {
      if (chat.slowMode) {
        await forward(chat.id, messageIds.sublist(0, 1));
        leftOut |= messageIds.length > 1;
        continue;
      }
      if (message.isNotEmpty) await _sendLine(messenger, chat.id, message);
      for (final group in groups) {
        if (group.header case final header?) {
          await _sendLine(messenger, chat.id, header);
        }
        await forward(chat.id, group.messageIds);
      }
    }
    if (leftOut) {
      throw const DriveException(
        'This group lets members send one message at a time, so only the first file went.',
      );
    }
  }

  /// Sends one line of text, sitting out Telegram's pauses. TDLib keeps a
  /// line Telegram turned away in the chat under a new id; it never reached
  /// anyone, so it is dropped before the next try, which would otherwise
  /// leave it showing as failed.
  Future<void> _sendLine(ChannelMessenger messenger, int chatId, String text) =>
      messenger.patiently(() async {
        try {
          await messenger.sendPlainText(chatId, text);
        } on SendFailed catch (e) {
          try {
            await messenger.deleteMessages(chatId, [e.failedMessageId]);
          } catch (error) {
            debugPrint('[Chats] Could not drop a failed line: $error');
          }
          rethrow;
        }
      }, longestWait: longestWait);
}

final telegramChatsProvider = Provider<TelegramChats>(TelegramChats.new);

final recentChatsProvider = FutureProvider.autoDispose<List<TelegramChat>>(
  (ref) => ref.watch(telegramChatsProvider).recent(),
);

/// Saved Messages and the chats files can be saved from.
final importChatsProvider = FutureProvider.autoDispose<List<TelegramChat>>(
  (ref) => ref.watch(telegramChatsProvider).recent(forImport: true),
);

/// Chats matching a query, among those files can be sent to or, with
/// forImport, saved from.
final chatSearchProvider = FutureProvider.autoDispose
    .family<List<TelegramChat>, ({String query, bool forImport})>(
      (ref, search) => ref
          .watch(telegramChatsProvider)
          .search(search.query, forImport: search.forImport),
    );
