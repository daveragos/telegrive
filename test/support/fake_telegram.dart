import 'package:handy_tdlib/api.dart' as td;
import 'package:telegrive/features/drive/data/drive_session.dart';
import 'package:telegrive/infrastructure/telegram/secure_store.dart';
import 'package:telegrive/infrastructure/telegram/telegram_client.dart';

/// The drive channel every test opens.
const testChatId = -100;

/// An open drive on [testChatId], without Premium.
class TestSession extends DriveSessionNotifier {
  @override
  DriveSession? build() => const DriveSession(
    userId: 1,
    chatId: testChatId,
    channelTitle: 'Telegrive',
    firstName: 'A',
    lastName: '',
    phoneNumber: '',
    username: null,
    isPremium: false,
  );
}

/// Telegram for tests: a channel that holds [messages], applies caption and
/// text edits to them the way Telegram hands the edited message back, copies
/// them under new ids when asked to, and deletes them. Anything else goes to
/// [answer], which a test overrides for what it needs (downloads, failures).
class FakeTelegram extends TelegramClient {
  FakeTelegram() : super(SecureStore());

  final Map<int, td.Message> messages = {};

  /// Ids the fake gives the copies it makes, counting up from 1000.
  int nextId = 1000;

  /// Answers [function] when a test cares about it; null leaves it to the
  /// channel.
  Future<td.TdObject?> answer(td.TdFunction function) async => null;

  @override
  Future<T> send<T extends td.TdObject>(
    td.TdFunction function, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final answered = await answer(function);
    if (answered != null) return answered as T;
    switch (function) {
      case td.GetChatHistory():
        return const td.Messages(totalCount: 0, messages: []) as T;
      case td.EditMessageCaption(:final messageId, :final caption?):
        final old = messages[messageId]!;
        final content = old.content as td.MessageDocument;
        return (messages[messageId] = old.copyWith(
              content: content.copyWith(caption: caption),
            ))
            as T;
      case td.EditMessageText(
        :final messageId,
        inputMessageContent: td.InputMessageText(:final text),
      ):
        return (messages[messageId] = messages[messageId]!.copyWith(
              content: td.MessageText(text: text),
            ))
            as T;
      case td.DeleteMessages(:final messageIds):
        messageIds.forEach(messages.remove);
        return const td.Ok() as T;
      case td.ForwardMessages(
        :final chatId,
        :final messageIds,
        sendCopy: true,
        removeCaption: true,
      ):
        const none = td.FormattedText(text: '', entities: []);
        return td.Messages(
          totalCount: messageIds.length,
          messages: [for (final id in messageIds) _copy(messages[id]!, chatId, none)],
        ) as T;
      case td.SendMessage(
        :final chatId,
        inputMessageContent: td.InputMessageForwarded(
          :final messageId,
          copyOptions: td.MessageCopyOptions(
            sendCopy: true,
            replaceCaption: true,
            :final newCaption?,
          ),
        ),
      ):
        return _copy(messages[messageId]!, chatId, newCaption) as T;
      default:
        throw UnsupportedError('$function');
    }
  }

  /// A copy of [source] in [chatId] the way Telegram makes one: a new
  /// message with [caption] in place of the original's, delivered at once
  /// and kept in [messages].
  td.Message _copy(td.Message source, int chatId, td.FormattedText caption) {
    final id = nextId++;
    final content = source.content;
    return messages[id] = source.copyWith(
      id: id,
      chatId: chatId,
      content: switch (content) {
        td.MessageDocument() => content.copyWith(caption: caption),
        td.MessagePhoto() => content.copyWith(caption: caption),
        td.MessageVideo() => content.copyWith(caption: caption),
        td.MessageAudio() => content.copyWith(caption: caption),
        _ => content,
      },
    );
  }
}

/// TDLib's file [id], fetched to [path] once [downloaded].
td.File tdFile(int id, {int size = 10, String path = '', bool downloaded = false}) =>
    td.File(
      id: id,
      size: size,
      expectedSize: size,
      local: td.LocalFile(
        path: downloaded ? path : '',
        canBeDownloaded: true,
        canBeDeleted: true,
        isDownloadingActive: false,
        isDownloadingCompleted: downloaded,
        downloadOffset: 0,
        downloadedPrefixSize: downloaded ? size : 0,
        downloadedSize: downloaded ? size : 0,
      ),
      remote: td.RemoteFile(
        id: 'r$id',
        uniqueId: 'u$id',
        isUploadingActive: false,
        isUploadingCompleted: true,
        uploadedSize: size,
      ),
    );

/// A message the drive account posted in [testChatId], at [date] and last
/// edited at [editDate] (Unix seconds, 0 for never).
td.Message channelMessage(
  int id,
  td.MessageContent content, {
  int date = 1_700_000_000,
  int editDate = 0,
}) => td.Message(
  id: id,
  senderId: const td.MessageSenderChat(chatId: testChatId),
  chatId: testChatId,
  isOutgoing: true,
  isPinned: false,
  isFromOffline: false,
  canBeSaved: true,
  hasTimestampedMedia: false,
  isChannelPost: true,
  isTopicMessage: false,
  containsUnreadMention: false,
  date: date,
  editDate: editDate,
  unreadReactions: const [],
  messageThreadId: 0,
  savedMessagesTopicId: 0,
  selfDestructIn: 0,
  autoDeleteIn: 0,
  viaBotUserId: 0,
  senderBusinessBotUserId: 0,
  senderBoostCount: 0,
  authorSignature: '',
  mediaAlbumId: 0,
  effectId: 0,
  hasSensitiveContent: false,
  restrictionReason: '',
  content: content,
);

/// A document message whose caption carries a file manifest.
td.Message documentMessage(
  int id,
  String caption, {
  String fileName = 'clip.mp4',
  String mimeType = 'video/mp4',
  int size = 9,
}) => channelMessage(
  id,
  td.MessageDocument(
    document: td.Document(
      fileName: fileName,
      mimeType: mimeType,
      document: tdFile(id, size: size),
    ),
    caption: td.FormattedText(text: caption, entities: const []),
  ),
);

/// A text message, the way folders and albums are kept.
td.Message textMessage(int id, String text) => channelMessage(
  id,
  td.MessageText(text: td.FormattedText(text: text, entities: const [])),
);
