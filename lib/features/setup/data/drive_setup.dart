import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../infrastructure/database/app_database.dart';
import '../../../infrastructure/storage/preferences.dart';
import '../../../infrastructure/telegram/telegram_client.dart';
import '../../../infrastructure/telegram/telegram_exception.dart';
import '../../auth/data/auth_controller.dart';
import '../../drive/data/channel_messenger.dart';
import '../../drive/data/drive_session.dart';
import '../../drive/data/drive_sync.dart';
import '../../drive/domain/manifest.dart';

enum SetupStep { account, channel, indexing, done }

@immutable
class SetupState {
  const SetupState({
    this.step = SetupStep.account,
    this.createdChannel = false,
    this.error,
    this.timedOut = false,
  });

  final SetupStep step;

  /// True when this run made a brand new channel rather than finding one.
  final bool createdChannel;
  final String? error;

  /// The [error] is Telegram not answering in time, which on a network
  /// that blocks Telegram is all there is to see.
  final bool timedOut;

  SetupState copyWith({
    SetupStep? step,
    bool? createdChannel,
    String? error,
    bool? timedOut,
    bool clearError = false,
  }) => SetupState(
    step: step ?? this.step,
    createdChannel: createdChannel ?? this.createdChannel,
    error: clearError ? null : (error ?? this.error),
    timedOut: clearError ? false : (timedOut ?? this.timedOut),
  );
}

/// Opens the drive after sign-in: identifies the account, finds its storage
/// channel (or creates one), then builds the local index.
///
/// Finding comes first on purpose. Someone signing in on a new phone, or
/// after a reinstall, gets their existing drive back without doing anything.
/// A channel is the drive when it is one this account created and the drive
/// message ([ManifestCodec.encodeDrive]) is pinned in it, or, for drives
/// made before that message, when its description carries the drive tag.
///
/// The setup screen runs it after sign-in. For someone whose drive this
/// phone has opened before, the drive opener runs it behind Home instead,
/// once Telegram has started, and Home says how it is going.
class DriveSetup extends Notifier<SetupState> {
  static const String channelTitle = 'Telegrive';

  /// What the app was called before; drives created then are adopted.
  static const String _legacyTitle = 'Gramrive';

  /// Tags in the description of a drive made before the drive message,
  /// which still mark it as one.
  static const List<String> _descriptionTags = ['#telegrive', '#gramrive'];

  /// The description a drive channel gets. It is for people only.
  static const String _channelDescription =
      'Storage for the Telegrive app. Every file here is part of your drive, '
      'so deleting or editing these messages changes it.';

  Future<void>? _running;

  TelegramClient get _client => ref.read(telegramClientProvider);
  Preferences get _prefs => ref.read(preferencesProvider);

  @override
  SetupState build() => const SetupState();

  Future<void> run() => _running ??= _run().whenComplete(() => _running = null);

  Future<void> _run() async {
    state = const SetupState();
    try {
      final me = await _client.send<td.User>(const td.GetMe());

      // Another account's drive on this phone goes before this one's
      // opens, so its files never show, not even for a moment.
      final last = _prefs.lastUserId;
      if (last != null && last != me.id) {
        await ref.read(authControllerProvider.notifier).wipeDeviceState();
      }
      await _prefs.setLastUserId(me.id);

      // Read before the channel is looked up, since a channel found anew
      // no longer matches it.
      final snapshot = ref.read(driveSnapshotProvider);
      state = state.copyWith(step: SetupStep.channel);
      final (chat, created) = await _locateOrCreate(me.id);
      if (snapshot != null && chat.id != snapshot.chatId) {
        // The drive channel was replaced. The index read from the old one
        // goes before the new one is read in full, so the two never mix,
        // and Home stops showing it while that runs.
        await ref.read(driveSnapshotProvider.notifier).clear();
        await ref.read(appDatabaseProvider).clearIndex();
        await _prefs.clearSyncState(snapshot.chatId);
      }
      await _prefs.setDriveChatId(me.id, chat.id);

      final session = DriveSession(
        userId: me.id,
        chatId: chat.id,
        channelTitle: chat.title,
        firstName: me.firstName,
        lastName: me.lastName,
        phoneNumber: me.phoneNumber,
        username: me.usernames?.activeUsernames.firstOrNull,
        isPremium: me.isPremium,
      );
      final sync = ref.read(driveSyncProvider.notifier);
      ref.read(driveSessionProvider.notifier).open(session);
      await ref.read(driveSnapshotProvider.notifier).save(session);

      if (_prefs.lastFullSync(chat.id) == null) {
        // First time on this device: build the index before showing an
        // empty-looking drive.
        state = state.copyWith(step: SetupStep.indexing, createdChannel: created);
        await sync.syncOnOpen();
      } else {
        // The index is already here; open straight away and catch up in the
        // background.
        unawaited(sync.syncOnOpen());
      }

      state = state.copyWith(step: SetupStep.done);
    } on TelegramException catch (e) {
      state = state.copyWith(error: e.friendlyMessage, timedOut: e.code == 408);
    } catch (e) {
      debugPrint('[DriveSetup] $e');
      state = state.copyWith(error: 'Something went wrong: $e');
    }
  }

  /// Opens the drive this phone last opened, for the background job, and
  /// catches the index up with an incremental read. It changes nothing in
  /// Telegram: it never searches for a channel, makes one or changes how
  /// one looks. It answers null, opening nothing, unless Telegram's account
  /// is the one whose index this phone holds and the saved channel is still
  /// a channel it created; the saved drive counts only once the index has
  /// been read from it in full, which backup needs.
  Future<DriveSession?> openExisting() async {
    final saved = ref.read(driveSnapshotProvider);
    if (saved == null) return null;
    final me = await _client.send<td.User>(const td.GetMe());
    if (me.id != saved.userId || _prefs.lastUserId != me.id) return null;
    final channel = await _ownedDriveChannel(saved.chatId, requireMark: false);
    if (channel == null) return null;
    final session = DriveSession(
      userId: me.id,
      chatId: channel.chat.id,
      channelTitle: channel.chat.title,
      firstName: me.firstName,
      lastName: me.lastName,
      phoneNumber: me.phoneNumber,
      username: me.usernames?.activeUsernames.firstOrNull,
      isPremium: me.isPremium,
    );
    ref.read(driveSessionProvider.notifier).open(session);
    await ref.read(driveSyncProvider.notifier).refresh();
    return session;
  }

  Future<(td.Chat, bool)> _locateOrCreate(int userId) async {
    final saved = _prefs.driveChatId(userId);
    if (saved != null) {
      final channel = await _ownedDriveChannel(saved, requireMark: false);
      if (channel != null) return (await _brand(channel), false);
    }

    final found = await _search();
    if (found != null) return (await _brand(found), false);

    final chat = await _client.send<td.Chat>(
      const td.CreateNewSupergroupChat(
        title: channelTitle,
        isForum: false,
        isChannel: true,
        description: _channelDescription,
        messageAutoDeleteTime: 0,
        forImport: false,
      ),
    );
    // Keep the storage channel out of the way in Telegram's chat list.
    try {
      await _client.send<td.Ok>(
        td.AddChatToList(chatId: chat.id, chatList: const td.ChatListArchive()),
      );
    } catch (e) {
      debugPrint('[DriveSetup] Could not archive the channel: $e');
    }
    return (
      await _brand((chat: chat, description: _channelDescription, card: null)),
      true,
    );
  }

  /// Brings a channel in line with how Telegrive presents it: the app icon as
  /// its photo, the drive message pinned at the top and, for drives made
  /// while the app was still called Gramrive, the new title. A title the
  /// owner chose themselves is left alone, and so is a description they
  /// wrote. Best-effort — none of this is needed for the drive to work.
  Future<td.Chat> _brand(_DriveChannel channel) async {
    var chat = channel.chat;
    try {
      if (chat.title == _legacyTitle) {
        await _client.send<td.Ok>(
          td.SetChatTitle(chatId: chat.id, title: channelTitle),
        );
      }
      final description = channel.description;
      if (description != _channelDescription &&
          (description.isEmpty || _descriptionTags.any(description.contains))) {
        await _client.send<td.Ok>(
          td.SetChatDescription(chatId: chat.id, description: _channelDescription),
        );
      }
      if (chat.photo == null) {
        await _client.send<td.Ok>(
          td.SetChatPhoto(
            chatId: chat.id,
            photo: td.InputChatPhotoStatic(
              photo: td.InputFileLocal(path: await _channelPhotoFile()),
            ),
          ),
          timeout: const Duration(minutes: 1),
        );
      }
      chat = await _client.send<td.Chat>(td.GetChat(chatId: chat.id));
    } catch (e) {
      debugPrint('[DriveSetup] Could not update the channel\'s look: $e');
    }
    await _pinDriveMessage(chat.id, channel.card);
    return chat;
  }

  /// Makes sure the drive message is pinned in [chatId]: [known] when the
  /// search already met it, else the one this phone last saw, else one
  /// Telegram finds, pinned again if it came unpinned. Only when Telegram
  /// answers that there is none is a new one sent and pinned, so a lookup
  /// that fails never leaves two.
  Future<void> _pinDriveMessage(int chatId, td.Message? known) async {
    try {
      var card = known;
      if (card == null) {
        if (_prefs.driveCardId(chatId) case final savedId?) {
          card = await _messageIfCard(chatId, savedId);
        }
      }
      if (card == null) {
        final found = await _findDriveMessage(chatId);
        if (!found.sure) return;
        card = found.card;
      }
      if (card == null) {
        final manifest = DriveManifest(id: const Uuid().v4(), createdAt: DateTime.now());
        card = await ref
            .read(channelMessengerProvider)
            .sendText(chatId, ManifestCodec.encodeDrive(manifest));
      }
      if (!card.isPinned) {
        await _client.send<td.Ok>(
          td.PinChatMessage(
            chatId: chatId,
            messageId: card.id,
            disableNotification: true,
            onlyForSelf: false,
          ),
        );
      }
      await _prefs.setDriveCardId(chatId, card.id);
    } catch (e) {
      debugPrint('[DriveSetup] Could not pin the drive message: $e');
    }
  }

  /// Message [messageId] of [chatId] if it is still the drive message, null
  /// when it is gone or something else. Any other failure is thrown.
  Future<td.Message?> _messageIfCard(int chatId, int messageId) async {
    try {
      final message = await _client.send<td.Message>(
        td.GetMessage(chatId: chatId, messageId: messageId),
      );
      return _isDriveMessage(message) ? message : null;
    } on TelegramException catch (e) {
      if (e.code == 404 || e.message.contains('MESSAGE_ID_INVALID')) return null;
      rethrow;
    }
  }

  /// The drive message in [chatId]: the message pinned last, or another
  /// pinned one, or failing those one Telegram's search finds by its kind,
  /// should it have come unpinned. [sure] is false when Telegram couldn't
  /// be asked, so a missing message is never assumed.
  Future<({td.Message? card, bool sure})> _findDriveMessage(int chatId) async {
    try {
      final pinned = await _client.send<td.Message>(
        td.GetChatPinnedMessage(chatId: chatId),
      );
      if (_isDriveMessage(pinned)) return (card: pinned, sure: true);
    } on TelegramException catch (e) {
      if (e.code != 404) return (card: null, sure: false);
    } catch (_) {
      return (card: null, sure: false);
    }
    for (final (query, filter) in const [
      ('', td.SearchMessagesFilterPinned()),
      (ManifestCodec.driveKind, null),
    ]) {
      try {
        final found = await _client.send<td.FoundChatMessages>(
          td.SearchChatMessages(
            chatId: chatId,
            query: query,
            fromMessageId: 0,
            offset: 0,
            limit: 50,
            filter: filter,
            messageThreadId: 0,
            savedMessagesTopicId: 0,
          ),
        );
        for (final message in found.messages) {
          if (_isDriveMessage(message)) return (card: message, sure: true);
        }
      } catch (_) {
        return (card: null, sure: false);
      }
    }
    return (card: null, sure: true);
  }

  static bool _isDriveMessage(td.Message message) =>
      message.content is td.MessageText &&
      ManifestCodec.decodeDrive((message.content as td.MessageText).text.text) != null;

  /// The bundled channel photo, copied to disk where TDLib can read it.
  static Future<String> _channelPhotoFile() async {
    final data = await rootBundle.load('assets/brand/channel_photo.jpg');
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/telegrive-channel-photo.jpg');
    await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
    return file.path;
  }

  /// Finds an existing drive — the reinstall and new-phone path.
  ///
  /// A fresh sign-in knows none of the account's chats yet, and the drive
  /// sits in the Archive, so a title search alone can miss it. If it does,
  /// the chat lists are loaded and every archived channel this account owns
  /// is checked for the drive message or tag — which also finds a drive
  /// someone renamed.
  Future<_DriveChannel?> _search() async {
    final byTitle = await _searchByTitle();
    if (byTitle != null) return byTitle;

    await _loadChatList(const td.ChatListArchive());
    await _loadChatList(const td.ChatListMain());

    final retry = await _searchByTitle();
    if (retry != null) return retry;

    try {
      final archived = await _client.send<td.Chats>(
        const td.GetChats(chatList: td.ChatListArchive(), limit: 500),
      );
      for (final chatId in archived.chatIds) {
        final channel = await _ownedDriveChannel(chatId, requireMark: true);
        if (channel != null) return channel;
      }
    } catch (e) {
      debugPrint('[DriveSetup] Archive scan failed: $e');
    }
    return null;
  }

  /// Pulls a chat list into TDLib, a page at a time, until it is complete
  /// (TDLib answers 404) or [maxPages] pages are in.
  Future<void> _loadChatList(td.ChatList list, {int maxPages = 10}) async {
    for (var page = 0; page < maxPages; page++) {
      try {
        await _client.send<td.Ok>(td.LoadChats(chatList: list, limit: 100));
      } on TelegramException catch (e) {
        if (e.code != 404) debugPrint('[DriveSetup] LoadChats: ${e.message}');
        return;
      }
    }
  }

  Future<_DriveChannel?> _searchByTitle() async {
    final candidates = <int>{};
    for (final query in const [channelTitle, _legacyTitle]) {
      for (final request in [
        td.SearchChatsOnServer(query: query, limit: 50),
        td.SearchChats(query: query, limit: 50),
      ]) {
        try {
          candidates.addAll((await _client.send<td.Chats>(request)).chatIds);
        } catch (e) {
          debugPrint('[DriveSetup] ${request.runtimeType} failed: $e');
        }
      }
    }
    for (final chatId in candidates) {
      final channel = await _ownedDriveChannel(chatId, requireMark: true);
      if (channel != null) return channel;
    }
    return null;
  }

  /// [chatId] if it is a channel this account created (and, when searching,
  /// one marked as a drive: by the drive message, or the tag in the
  /// description of a drive made before it).
  Future<_DriveChannel?> _ownedDriveChannel(
    int chatId, {
    required bool requireMark,
  }) async {
    try {
      final chat = await _client.send<td.Chat>(td.GetChat(chatId: chatId));
      final type = chat.type;
      if (type is! td.ChatTypeSupergroup || !type.isChannel) return null;

      final supergroup = await _client.send<td.Supergroup>(
        td.GetSupergroup(supergroupId: type.supergroupId),
      );
      if (supergroup.status is! td.ChatMemberStatusCreator) return null;

      final info = await _client.send<td.SupergroupFullInfo>(
        td.GetSupergroupFullInfo(supergroupId: type.supergroupId),
      );
      final tagged = _descriptionTags.any(info.description.contains);
      if (!requireMark || tagged) {
        return (chat: chat, description: info.description, card: null);
      }
      final found = await _findDriveMessage(chat.id);
      if (found.card == null) return null;
      return (chat: chat, description: info.description, card: found.card);
    } catch (_) {
      return null;
    }
  }
}

/// A channel taken for the drive, with its drive message when looking for
/// the channel already met it.
typedef _DriveChannel = ({td.Chat chat, String description, td.Message? card});

final driveSetupProvider = NotifierProvider<DriveSetup, SetupState>(
  DriveSetup.new,
);
