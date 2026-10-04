import 'package:handy_tdlib/api.dart' as td;
import 'package:telegrive/features/drive/data/drive_session.dart';
import 'package:telegrive/infrastructure/telegram/secure_store.dart';
import 'package:telegrive/infrastructure/telegram/telegram_client.dart';
import 'package:telegrive/infrastructure/telegram/telegram_exception.dart';

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
/// text edits to them the way Telegram hands the edited message back and
/// refuses to edit a forwarded message, copies them under new ids when asked
/// to, delivers text sent to any chat at once, hands single messages back,
/// and deletes them. Anything else goes to [answer], which a test overrides
/// for what it needs (downloads, failures).
class FakeTelegram extends TelegramClient {
  FakeTelegram() : super(SecureStore());

  final Map<int, td.Message> messages = {};

  /// Ids the fake gives the messages it makes, counting up from 1000.
  int nextId = 1000;

  /// Answers [function] when a test cares about it; null leaves it to the
  /// channel.
  Future<td.TdObject?> answer(td.TdFunction function) async => null;

  /// Moves TDLib's connection to [state], the way its update would.
  void setConnectionState(td.ConnectionState state) =>
      receive(td.UpdateConnectionState(state: state).toJson());

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
      case td.GetMessage(:final messageId):
        final message = messages[messageId];
        if (message == null) throw const TelegramException(400, 'MESSAGE_ID_INVALID');
        return message as T;
      case td.EditMessageCaption(:final messageId, :final caption?):
        final old = messages[messageId]!;
        if (old.forwardInfo != null) {
          throw const TelegramException(400, "Message can't be edited");
        }
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
      case td.SendMessage(:final chatId, inputMessageContent: td.InputMessageText(:final text)):
        final id = nextId++;
        return (messages[id] = channelMessage(
              id,
              td.MessageText(text: text),
            ).copyWith(chatId: chatId))
            as T;
      default:
        throw UnsupportedError('$function');
    }
  }

  /// A copy of [source] in [chatId] the way Telegram makes one: a new
  /// message of the account's own, with [caption] in place of the original's
  /// and nothing of where the original was forwarded from, delivered at once
  /// and kept in [messages].
  td.Message _copy(td.Message source, int chatId, td.FormattedText caption) {
    final id = nextId++;
    final content = source.content;
    return messages[id] = channelMessage(
      id,
      switch (content) {
        td.MessageDocument() => content.copyWith(caption: caption),
        td.MessagePhoto() => content.copyWith(caption: caption),
        td.MessageVideo() => content.copyWith(caption: caption),
        td.MessageAudio() => content.copyWith(caption: caption),
        _ => content,
      },
      date: source.date,
    ).copyWith(chatId: chatId);
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
/// edited at [editDate] (Unix seconds, 0 for never), or forwarded there
/// from [forwardedFrom]. [albumId] groups it with the other items of a media
/// album, as Telegram does; 0 is none.
td.Message channelMessage(
  int id,
  td.MessageContent content, {
  int date = 1_700_000_000,
  int editDate = 0,
  td.MessageOrigin? forwardedFrom,
  int albumId = 0,
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
  mediaAlbumId: albumId,
  effectId: 0,
  hasSensitiveContent: false,
  restrictionReason: '',
  content: content,
  forwardInfo: forwardedFrom == null
      ? null
      : td.MessageForwardInfo(
          origin: forwardedFrom,
          date: date,
          publicServiceAnnouncementType: '',
        ),
);

/// A document message whose caption carries a file manifest, or, when
/// [forwardedFrom] someone, a plain document forwarded into the channel.
td.Message documentMessage(
  int id,
  String caption, {
  String fileName = 'clip.mp4',
  String mimeType = 'video/mp4',
  int size = 9,
  int date = 1_700_000_000,
  td.MessageOrigin? forwardedFrom,
  int albumId = 0,
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
  date: date,
  forwardedFrom: forwardedFrom,
  albumId: albumId,
);

/// A text message, the way folders and albums are kept, or a comment typed
/// when forwarding.
td.Message textMessage(int id, String text, {int date = 1_700_000_000}) => channelMessage(
  id,
  td.MessageText(text: td.FormattedText(text: text, entities: const [])),
  date: date,
);
