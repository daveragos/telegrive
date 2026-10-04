import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;

import '../../../infrastructure/telegram/telegram_client.dart';
import 'drive_repository.dart';
import 'drive_session.dart';

/// Where a file that came in without a manifest is from: [forwarded] when
/// someone forwarded it into the channel, with the [name] of who sent it
/// first when Telegram says, and not forwarded when the account posted it
/// itself from another Telegram app.
typedef ForwardOrigin = ({bool forwarded, String? name});

/// The origin of the file [fileId], or null when it can't be read. The
/// sender's name is the user's, the hidden user's, or the group's or
/// channel's title. TDLib answers from its cache, so this costs no network
/// for messages it has seen; an answer is kept for as long as the drive is
/// open, since where a message came from never changes, so a row scrolled
/// back into view asks nothing again.
final forwardOriginProvider = FutureProvider.autoDispose.family<ForwardOrigin?, String>((
  ref,
  fileId,
) async {
  final chatId = ref.watch(driveSessionProvider)?.chatId;
  if (chatId == null) return null;
  final client = ref.watch(telegramClientProvider);
  try {
    final parts = await ref.watch(driveRepositoryProvider).partsOf(fileId);
    if (parts.isEmpty) return null;
    final message = await client.send<td.Message>(
      td.GetMessage(chatId: chatId, messageId: parts.first.messageId),
    );
    final origin = message.forwardInfo?.origin;
    if (origin == null) {
      ref.keepAlive();
      return (forwarded: false, name: null);
    }
    final name = switch (origin) {
      td.MessageOriginUser(:final senderUserId) => await _userName(client, senderUserId),
      td.MessageOriginHiddenUser(:final senderName) => senderName,
      td.MessageOriginChat(:final senderChatId) => await _chatTitle(client, senderChatId),
      td.MessageOriginChannel(:final chatId) => await _chatTitle(client, chatId),
    };
    ref.keepAlive();
    return (forwarded: true, name: name == null || name.isEmpty ? null : name);
  } catch (e) {
    debugPrint('[ForwardOrigin] $e');
    return null;
  }
});

Future<String?> _userName(TelegramClient client, int userId) async {
  final user = await client.send<td.User>(td.GetUser(userId: userId));
  return '${user.firstName} ${user.lastName}'.trim();
}

Future<String?> _chatTitle(TelegramClient client, int chatId) async =>
    (await client.send<td.Chat>(td.GetChat(chatId: chatId))).title;
