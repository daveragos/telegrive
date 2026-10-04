import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;

import '../../../core/files/file_kind.dart';
import '../../../infrastructure/telegram/telegram_client.dart';
import '../../drive/data/drive_repository.dart';
import '../../drive/data/message_indexer.dart';
import '../../drive/domain/drive_models.dart';
import '../../transfers/domain/transfer_error.dart';
import 'import_naming.dart';

/// Which of a chat's files are listed for saving.
enum ImportFilter {
  documents('Documents', 'document', 'documents', 'No documents in this chat'),
  media(
    'Photos and videos',
    'photo or video',
    'photos and videos',
    'No photos or videos in this chat',
  ),
  audio('Audio', 'track', 'tracks', 'No audio in this chat');

  const ImportFilter(this.label, this.noun, this.nouns, this.emptyTitle);

  final String label;

  /// One of them, and several, for counts.
  final String noun;
  final String nouns;

  /// What the list says when the chat has none.
  final String emptyTitle;

  td.SearchMessagesFilter get _search => switch (this) {
    documents => const td.SearchMessagesFilterDocument(),
    media => const td.SearchMessagesFilterPhotoAndVideo(),
    audio => const td.SearchMessagesFilterAudio(),
  };
}

/// One file in a chat that can be copied into the drive.
@immutable
class ChatItem {
  const ChatItem({
    required this.messageId,
    required this.preview,
    required this.size,
    required this.date,
  });

  /// [message] as the list shows it, or null when it carries no file the
  /// drive keeps.
  static ChatItem? fromMessage(td.Message message) {
    final media = MessageIndexer.describe(message);
    if (media == null) return null;
    final date = DateTime.fromMillisecondsSinceEpoch(message.date * 1000);
    final guessed = FileKind.detect(
      fileName: media.fileName,
      mimeType: media.mimeType,
    );
    final name = ImportNaming.nameFor(
      fileName: media.fileName,
      hasOwnName: media.hasOwnName,
      kind: guessed,
      mimeType: media.mimeType,
      date: date,
    );
    final mimeType = media.mimeType.isEmpty
        ? mimeTypeFor(name)
        : media.mimeType;
    final size = media.file.size != 0
        ? media.file.size
        : media.file.expectedSize;
    return ChatItem(
      messageId: message.id,
      size: size,
      date: date,
      preview: DriveFile(
        id: previewId(message.id),
        folderId: null,
        name: name,
        mimeType: mimeType,
        kind: FileKind.detect(fileName: name, mimeType: mimeType),
        size: size,
        createdAt: date,
        modifiedAt: date,
        partCount: 1,
        starred: false,
        minithumbnail: _bytes(media.minithumbnail?.data),
        thumbnailFileId: media.thumbnailFileId,
        takenAt: date,
        durationSeconds: media.duration,
      ),
    );
  }

  /// The id [preview] goes by, which no drive file has.
  static String previewId(int messageId) => 'chat:$messageId';

  final int messageId;

  /// The file as the drive's rows and tiles draw it, so the list looks like
  /// the drive. It is in no folder and is never saved as it is.
  final DriveFile preview;
  final int size;

  /// When the message was sent: the copy's date in the drive.
  final DateTime date;

  String get name => preview.name;
  String get mimeType => preview.mimeType;

  /// How the drive recognises the file once saved.
  String get fingerprint => '$name|$size';

  static Uint8List? _bytes(String? base64) {
    if (base64 == null || base64.isEmpty) return null;
    try {
      return base64Decode(base64);
    } catch (_) {
      return null;
    }
  }
}

/// A chat's files of one kind, newest first, as far as they have been read.
@immutable
class ChatMediaState {
  const ChatMediaState({
    this.items = const [],
    this.totalCount = 0,
    this.hiddenSaved = 0,
    this.hiddenProtected = 0,
    this.nextFrom = 0,
    this.loadingMore = false,
    this.pageError,
  });

  final List<ChatItem> items;

  /// How many Telegram says the chat holds, hidden ones included; at least
  /// as many as were read.
  final int totalCount;

  /// Read, but left out because the drive already has them.
  final int hiddenSaved;

  /// Read, but left out because the chat doesn't let them be saved.
  final int hiddenProtected;

  /// The message the next page starts from; 0 once every page is in.
  final int nextFrom;
  final bool loadingMore;

  /// Why the last page didn't load, until one does.
  final String? pageError;

  bool get complete => nextFrom == 0;

  /// This state with [loadingMore] when given, and [pageError] in place of
  /// the current one.
  ChatMediaState copyWith({bool? loadingMore, String? pageError}) =>
      ChatMediaState(
        items: items,
        totalCount: totalCount,
        hiddenSaved: hiddenSaved,
        hiddenProtected: hiddenProtected,
        nextFrom: nextFrom,
        loadingMore: loadingMore ?? this.loadingMore,
        pageError: pageError,
      );
}

/// Pages through one chat's documents, photos and videos, or audio, a
/// hundred messages at a time. Files the drive already has (by name and
/// size) and files the chat protects are counted and left out.
class ChatMedia extends AsyncNotifier<ChatMediaState> {
  ChatMedia(this.source);

  final ({int chatId, ImportFilter filter}) source;

  /// The most a Select all reads and picks.
  static const int selectAllCap = 2000;

  /// What the drive holds, as `name|size`, read once when the list opens.
  Set<String> _inDrive = const {};
  Future<void>? _loading;

  @override
  Future<ChatMediaState> build() async {
    _inDrive = (await ref.read(driveRepositoryProvider).mediaFingerprints()).keys.toSet();
    return _page(const ChatMediaState(), from: 0);
  }

  /// Reads the next page, unless every page is in or one is on its way.
  /// A page that fails leaves what was read and says why in
  /// [ChatMediaState.pageError].
  Future<void> loadMore() =>
      _loading ??= _next().whenComplete(() => _loading = null);

  /// Reads pages until every one is in or [cap] files are listed, and
  /// returns where that left the list.
  Future<ChatMediaState?> loadAll({int cap = selectAllCap}) async {
    while (ref.mounted) {
      final current = state.value;
      if (current == null || current.complete || current.items.length >= cap) {
        break;
      }
      await loadMore();
      if (state.value?.pageError != null) break;
    }
    return ref.mounted ? state.value : null;
  }

  Future<void> _next() async {
    final current = state.value;
    if (current == null || current.complete) return;
    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final next = await _page(current, from: current.nextFrom);
      if (ref.mounted) state = AsyncData(next);
    } catch (e) {
      debugPrint('[Import] ${source.chatId}: $e');
      if (ref.mounted) {
        state = AsyncData(
          current.copyWith(pageError: describeTransferError(e)),
        );
      }
    }
  }

  /// The page of messages from [from] added to [current].
  Future<ChatMediaState> _page(
    ChatMediaState current, {
    required int from,
  }) async {
    final found = await ref
        .read(telegramClientProvider)
        .send<td.FoundChatMessages>(
          td.SearchChatMessages(
            chatId: source.chatId,
            query: '',
            senderId: null,
            fromMessageId: from,
            offset: 0,
            limit: 100,
            filter: source.filter._search,
            messageThreadId: 0,
            savedMessagesTopicId: 0,
          ),
        );
    final items = [...current.items];
    var saved = current.hiddenSaved;
    var protected = current.hiddenProtected;
    for (final message in found.messages) {
      final item = ChatItem.fromMessage(message);
      if (item == null) continue;
      if (!message.canBeSaved) {
        protected++;
      } else if (_inDrive.contains(item.fingerprint)) {
        saved++;
      } else {
        items.add(item);
      }
    }
    return ChatMediaState(
      items: items,
      // Telegram's count is approximate, and -1 when it doesn't know.
      totalCount: math.max(found.totalCount, items.length + saved + protected),
      hiddenSaved: saved,
      hiddenProtected: protected,
      // An empty page ends the list even if Telegram offers another.
      nextFrom: found.messages.isEmpty ? 0 : found.nextFromMessageId,
    );
  }
}

final chatMediaProvider = AsyncNotifierProvider.autoDispose
    .family<ChatMedia, ChatMediaState, ({int chatId, ImportFilter filter})>(
      ChatMedia.new,
    );
