import 'package:handy_tdlib/api.dart' as td;
import 'package:telegrive/features/drive/data/drive_session.dart';
import 'package:telegrive/infrastructure/telegram/secure_store.dart';
import 'package:telegrive/infrastructure/telegram/telegram_client.dart';
import 'package:telegrive/infrastructure/telegram/telegram_exception.dart';

/// The drive channel every test opens.
const testChatId = -100;

/// The drive on [testChatId] of account 1, without Premium.
const testSession = DriveSession(
  userId: 1,
  chatId: testChatId,
  channelTitle: 'Telegrive',
  firstName: 'A',
  lastName: '',
  phoneNumber: '',
  username: null,
  isPremium: false,
);

/// [testSession], open from the start.
class TestSession extends DriveSessionNotifier {
  @override
  DriveSession? build() => testSession;
}

/// Telegram for tests: a channel that holds [messages], applies caption and
/// text edits to them the way Telegram hands the edited message back and
/// refuses to edit a forwarded message, copies them under new ids when asked
/// to, delivers text sent to any chat at once, hands single messages back,
/// and deletes them. Anything else goes to [answer], which a test overrides
/// for what it needs (downloads, failures).
class FakeTelegram extends TelegramClient {
  FakeTelegram({this.signedIn = true}) : super(SecureStore());

  /// Whether an account counts as signed in from the start, so work that
  /// waits for [ready] goes ahead at once. Without it, [ready] waits for an
  /// authorization update, as the real client's does.
  final bool signedIn;

  @override
  Future<void> get ready => signedIn ? Future<void>.value() : super.ready;

  final Map<int, td.Message> messages = {};

  /// Ids the fake gives the messages it makes, counting up from 1000.
  int nextId = 1000;

  /// Puts message [messageId] in the channel holding TDLib file [fileId],
  /// with Telegram's thumbnail [thumbnailId] when given: the message behind
  /// a part the index stored. The app reads a file's id for this run from
  /// its message, so a test that answers for [fileId] seeds the message too.
  void holdsFile(int messageId, int fileId, {int size = 10, int? thumbnailId}) =>
      messages[messageId] = channelMessage(
        messageId,
        td.MessageDocument(
          document: td.Document(
            fileName: 'file.bin',
            mimeType: 'application/octet-stream',
            thumbnail: thumbnailId == null
                ? null
                : td.Thumbnail(
                    format: const td.ThumbnailFormatJpeg(),
                    width: 320,
                    height: 320,
                    file: tdFile(thumbnailId),
                  ),
            document: tdFile(fileId, size: size),
          ),
          caption: const td.FormattedText(text: '', entities: []),
        ),
      );

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
        final old = messages[messageId];
        if (old == null) throw const TelegramException(400, 'MESSAGE_ID_INVALID');
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
        final old = messages[messageId];
        if (old == null) throw const TelegramException(400, 'MESSAGE_ID_INVALID');
        return (messages[messageId] = old.copyWith(content: td.MessageText(text: text))) as T;
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

/// The supergroup id behind [testChatId], as TDLib hands it out.
const testSupergroupId = 7;

/// The drive channel as TDLib describes it: a private channel of the
/// account's own, with Telegram's auto-delete timer at [autoDeleteSeconds]
/// (0 for off).
td.Chat channelChat({int autoDeleteSeconds = 0}) => td.Chat(
  id: testChatId,
  type: const td.ChatTypeSupergroup(supergroupId: testSupergroupId, isChannel: true),
  title: 'Telegrive',
  accentColorId: 0,
  backgroundCustomEmojiId: 0,
  profileAccentColorId: -1,
  profileBackgroundCustomEmojiId: 0,
  permissions: const td.ChatPermissions(
    canSendBasicMessages: false,
    canSendAudios: false,
    canSendDocuments: false,
    canSendPhotos: false,
    canSendVideos: false,
    canSendVideoNotes: false,
    canSendVoiceNotes: false,
    canSendPolls: false,
    canSendOtherMessages: false,
    canAddLinkPreviews: false,
    canChangeInfo: false,
    canInviteUsers: false,
    canPinMessages: false,
    canCreateTopics: false,
  ),
  positions: const [],
  chatLists: const [],
  hasProtectedContent: false,
  isTranslatable: false,
  isMarkedAsUnread: false,
  viewAsTopics: false,
  hasScheduledMessages: false,
  canBeDeletedOnlyForSelf: false,
  canBeDeletedForAllUsers: true,
  canBeReported: false,
  defaultDisableNotification: true,
  unreadCount: 0,
  lastReadInboxMessageId: 0,
  lastReadOutboxMessageId: 0,
  unreadMentionCount: 0,
  unreadReactionCount: 0,
  notificationSettings: const td.ChatNotificationSettings(
    useDefaultMuteFor: true,
    muteFor: 0,
    useDefaultSound: true,
    soundId: 0,
    useDefaultShowPreview: true,
    showPreview: true,
    useDefaultMuteStories: true,
    muteStories: false,
    useDefaultStorySound: true,
    storySoundId: 0,
    useDefaultShowStorySender: true,
    showStorySender: true,
    useDefaultDisablePinnedMessageNotifications: true,
    disablePinnedMessageNotifications: false,
    useDefaultDisableMentionNotifications: true,
    disableMentionNotifications: false,
  ),
  availableReactions: const td.ChatAvailableReactionsAll(maxReactionCount: 11),
  messageAutoDeleteTime: autoDeleteSeconds,
  themeName: '',
  videoChat: const td.VideoChat(groupCallId: 0, hasParticipants: false),
  replyMarkupMessageId: 0,
  clientData: '',
);

/// The channel's supergroup record: created by this account, with the
/// public [usernames] it has, none for a private channel.
td.Supergroup ownedSupergroup({List<String> usernames = const []}) => td.Supergroup(
  id: testSupergroupId,
  usernames: usernames.isEmpty
      ? null
      : td.Usernames(
          activeUsernames: usernames,
          disabledUsernames: const [],
          editableUsername: usernames.first,
        ),
  date: 1_700_000_000,
  status: const td.ChatMemberStatusCreator(customTitle: '', isAnonymous: false, isMember: true),
  memberCount: 1,
  boostLevel: 0,
  hasLinkedChat: false,
  hasLocation: false,
  signMessages: false,
  showMessageSender: false,
  joinToSendMessages: false,
  joinByRequest: false,
  isSlowModeEnabled: false,
  isChannel: true,
  isBroadcastGroup: false,
  isForum: false,
  isVerified: false,
  hasSensitiveContent: false,
  restrictionReason: '',
  isScam: false,
  isFake: false,
  hasActiveStories: false,
  hasUnreadActiveStories: false,
);

/// The account's two-step verification, on or off.
td.PasswordState passwordState({required bool hasPassword}) => td.PasswordState(
  hasPassword: hasPassword,
  passwordHint: '',
  hasRecoveryEmailAddress: false,
  hasPassportData: false,
  loginEmailAddressPattern: '',
  pendingResetDate: 0,
);

/// A text message, the way folders and albums are kept, or a comment typed
/// when forwarding.
td.Message textMessage(int id, String text, {int date = 1_700_000_000}) => channelMessage(
  id,
  td.MessageText(text: td.FormattedText(text: text, entities: const [])),
  date: date,
);

/// Account 1 as TDLib describes it.
td.User testUser() => const td.User(
  id: 1,
  firstName: 'A',
  lastName: '',
  phoneNumber: '251911000000',
  status: td.UserStatusEmpty(),
  accentColorId: 0,
  backgroundCustomEmojiId: 0,
  profileAccentColorId: -1,
  profileBackgroundCustomEmojiId: 0,
  isContact: false,
  isMutualContact: false,
  isCloseFriend: false,
  isVerified: false,
  isPremium: false,
  isSupport: false,
  restrictionReason: '',
  isScam: false,
  isFake: false,
  hasActiveStories: false,
  hasUnreadActiveStories: false,
  restrictsNewChats: false,
  haveAccess: true,
  type: td.UserTypeRegular(),
  languageCode: 'en',
  addedToAttachmentMenu: false,
);

/// The drive channel's full record, its description carrying the tag that
/// marks a Telegrive drive.
td.SupergroupFullInfo channelInfo() => const td.SupergroupFullInfo(
  description: 'Storage for the Telegrive app. #telegrive',
  memberCount: 1,
  administratorCount: 1,
  restrictedCount: 0,
  bannedCount: 0,
  linkedChatId: 0,
  slowModeDelay: 0,
  slowModeDelayExpiresIn: 0,
  canEnablePaidReaction: false,
  canGetMembers: true,
  hasHiddenMembers: false,
  canHideMembers: false,
  canSetStickerSet: false,
  canSetLocation: false,
  canGetStatistics: false,
  canGetRevenueStatistics: false,
  canGetStarRevenueStatistics: false,
  canToggleAggressiveAntiSpam: false,
  isAllHistoryAvailable: true,
  canHaveSponsoredMessages: false,
  hasAggressiveAntiSpamEnabled: false,
  hasPaidMediaAllowed: false,
  hasPinnedStories: false,
  myBoostCount: 0,
  unrestrictBoostCount: 0,
  stickerSetId: 0,
  customEmojiStickerSetId: 0,
  botCommands: [],
  upgradedFromBasicGroupId: 0,
  upgradedFromMaxMessageId: 0,
);
