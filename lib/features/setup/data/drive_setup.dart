import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:path_provider/path_provider.dart';

import '../../../infrastructure/storage/preferences.dart';
import '../../../infrastructure/telegram/telegram_client.dart';
import '../../../infrastructure/telegram/telegram_exception.dart';
import '../../drive/data/drive_session.dart';
import '../../drive/data/drive_sync.dart';

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
class DriveSetup extends Notifier<SetupState> {
  static const String channelTitle = 'Telegrive';

  /// Tag in the channel description that marks it as ours, so a search for
  /// the title never adopts some unrelated channel called "Telegrive".
  static const String channelTag = '#telegrive';

  /// What the app was called before; drives created then are adopted.
  static const String _legacyTitle = 'Gramrive';
  static const String _legacyTag = '#gramrive';

  static const String _channelDescription =
      'Storage for the Telegrive app. Every file here is part of your drive, '
      'so deleting or editing these messages changes it. $channelTag';

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

      state = state.copyWith(step: SetupStep.channel);
      final (chat, created) = await _locateOrCreate(me.id);
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

  Future<(td.Chat, bool)> _locateOrCreate(int userId) async {
    final saved = _prefs.driveChatId(userId);
    if (saved != null) {
      final channel = await _ownedDriveChannel(saved, requireTag: false);
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
    return (await _brand((chat: chat, description: _channelDescription)), true);
  }

  /// Brings a channel in line with how Telegrive presents it: the app icon as
  /// its photo and, for drives made while the app was still called Gramrive,
  /// the new title and description. A title the owner chose themselves is
  /// left alone. Best-effort — none of this is needed for the drive to work.
  Future<td.Chat> _brand(_DriveChannel channel) async {
    var chat = channel.chat;
    try {
      if (chat.title == _legacyTitle) {
        await _client.send<td.Ok>(
          td.SetChatTitle(chatId: chat.id, title: channelTitle),
        );
      }
      if (!channel.description.contains(channelTag)) {
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
    return chat;
  }

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
  /// is checked for the drive tag — which also finds a drive someone renamed.
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
        final channel = await _ownedDriveChannel(chatId, requireTag: true);
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
      final channel = await _ownedDriveChannel(chatId, requireTag: true);
      if (channel != null) return channel;
    }
    return null;
  }

  /// [chatId] if it is a channel this account created (and, when searching,
  /// one tagged as a Telegrive — or pre-rename Gramrive — drive).
  Future<_DriveChannel?> _ownedDriveChannel(
    int chatId, {
    required bool requireTag,
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
      final tagged =
          info.description.contains(channelTag) ||
          info.description.contains(_legacyTag);
      if (requireTag && !tagged) return null;
      return (chat: chat, description: info.description);
    } catch (_) {
      return null;
    }
  }
}

typedef _DriveChannel = ({td.Chat chat, String description});

final driveSetupProvider = NotifierProvider<DriveSetup, SetupState>(
  DriveSetup.new,
);
