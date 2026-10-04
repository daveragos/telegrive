import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;

import '../../../infrastructure/storage/preferences.dart';
import '../../../infrastructure/telegram/telegram_client.dart';
import '../domain/folder_address.dart';
import 'drive_repository.dart';
import 'drive_session.dart';
import 'message_indexer.dart';

/// One channel message as the filer reads it. [text] is a text message's
/// text when it isn't a folder or album manifest, else null; [manifest]
/// says whether the message carries any of the drive's manifests; [caption]
/// is the media's own caption, empty for text; [albumId] is Telegram's
/// media album, 0 for none.
typedef ChannelPost = ({
  int id,
  int date,
  String? text,
  bool media,
  bool manifest,
  bool forwarded,
  String caption,
  int albumId,
});

/// Where a forward asked to go: the folder [text], the comment it came from
/// when it was a comment rather than the media's own caption, and the other
/// forwards of the burst that sit between that comment and the forward,
/// which the comment covers too.
@immutable
class CommentAddress {
  const CommentAddress(this.text, {this.commentId, this.burst = const []});

  final String text;
  final int? commentId;
  final List<int> burst;
}

/// What the filer moved in one go, for Home: how many files, the folders
/// they went into, and the one folder when there was only one.
@immutable
class FilingSummary {
  const FilingSummary({required this.count, required this.folderNames, this.folderId});

  final int count;
  final List<String> folderNames;
  final String? folderId;

  /// This summary with [count] more files filed into [folders] (id to name).
  FilingSummary plus(int count, Map<String, String> folders) {
    final names = {...folderNames, ...folders.values}.toList();
    final ids = {?folderId, ...folders.keys};
    return FilingSummary(
      count: this.count + count,
      folderNames: names,
      folderId: ids.length == 1 ? ids.single : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FilingSummary &&
      other.count == count &&
      other.folderId == folderId &&
      listEquals(other.folderNames, folderNames);

  @override
  int get hashCode => Object.hash(count, folderId, Object.hashAll(folderNames));
}

/// Files media that came into the channel without a manifest into the
/// folder its comment or caption names.
///
/// A forward's folder is the plain text message sent just before it, the
/// comment Telegram's forward dialog adds; one comment covers the whole
/// burst sent with it. Media the account sent itself, from another Telegram
/// app or a bot, names its folder in its own caption, or in the caption of
/// any item of the same media album. Only messages newer than the channel's
/// watermark ([Preferences.forwardFilingFrom]) are looked at, so nothing
/// that was in the channel before the filer first ran moves on its own.
/// Filing goes through [DriveRepository.moveFiles], which copies a forward
/// into the drive's own message, and the comment is deleted once every file
/// it covered has gone where it said. The state is what the last passes
/// filed, until Home dismisses it.
class ForwardFiler extends Notifier<FilingSummary?> {
  Future<void> _chain = Future.value();

  /// The bursts whose comment went lately: what it named and when the
  /// burst's last forward was sent. A forward of the same burst that
  /// Telegram delivers after the comment has gone still goes with the rest.
  final List<_ClosedBurst> _closed = [];

  /// How far apart in time a comment and its forwards, or two forwards of
  /// one burst, may be.
  static const int burstGapSeconds = 10;

  /// How far back past a burst its comment is looked for, in messages.
  static const int _lookBack = 20;

  /// The most forwards one history read covers, so that read, with the
  /// look-back behind it, stays within what Telegram hands out at once.
  static const int _runLimit = 100 - _lookBack;

  @override
  FilingSummary? build() => null;

  /// Looks at [messages], manifest-less media just read or just arrived,
  /// and files what names a folder. Passes run one after another, so two
  /// arriving together never file the same message twice.
  Future<void> consider(List<td.Message> messages) {
    final run = _chain.then((_) => _consider(messages));
    _chain = run.catchError((Object e) => debugPrint('[ForwardFiler] $e'));
    return _chain;
  }

  /// Completes once no pass is running.
  Future<void> whenIdle() => _chain;

  /// Takes the report off Home.
  void clear() => state = null;

  Future<void> _consider(List<td.Message> messages) async {
    final chatId = ref.read(driveSessionProvider)?.chatId;
    if (chatId == null) return;
    final prefs = ref.read(preferencesProvider);
    final from = prefs.forwardFilingFrom(chatId);
    if (from == null) return;
    // Everything a pass has dealt with sits at or below the watermark, so
    // the same message handed over twice, once by the catch-up sync and
    // once live, is filed once.
    final byId = <int, td.Message>{
      for (final m in messages)
        if (m.id > from && MessageIndexer.isAdopted(m)) m.id: m,
    };
    final pending = byId.values.toList()..sort((a, b) => a.id.compareTo(b.id));
    if (pending.isEmpty) return;
    _closed.removeWhere((b) => pending.first.date - b.lastDate > burstGapSeconds);

    final repository = ref.read(driveRepositoryProvider);
    final client = ref.read(telegramClientProvider);

    var watermark = from;
    // The watermark as the current burst began. A comment that can't be
    // deleted puts it back there, so the next pass comes back for it.
    var beforeBurst = from;
    var filed = 0;
    final folders = <String, String>{};
    // The folder each text named, resolved once per pass rather than once
    // per file of a burst; null is a text that names none.
    final resolved = <String, _Destination?>{};
    // Forwards known to wait no longer: filed in this pass, or already
    // moved or gone when looked at.
    final settled = <int>{};
    _History? history;
    // The comment the current burst answers to, what it named, when the
    // burst's last forward was sent, and whether every file it covers went
    // where it said; the comment goes only then.
    int? commentId;
    var burstText = '';
    var burstDate = 0;
    var complete = true;

    Future<void> closeBurst() async {
      if (commentId != null && complete) {
        try {
          await repository.deleteComment(commentId!);
        } catch (_) {
          watermark = beforeBurst;
          rethrow;
        }
        _closed.add(_ClosedBurst(burstText, burstDate));
      }
      commentId = null;
      complete = true;
      beforeBurst = watermark;
    }

    try {
      for (var i = 0; i < pending.length; i++) {
        final message = pending[i];
        final CommentAddress? address;
        if (message.forwardInfo == null) {
          address = _ownAddress(message, pending);
        } else {
          if (history == null || message.id > history.from) {
            history = await _readBack(pending, i, chatId, client);
          }
          final post = MessageIndexer.postOf(message);
          var walk = _walk(post, history.posts);
          // TDLib may hand back fewer messages than asked for, so a walk
          // that runs out of posts before anything ends it reads further
          // back rather than giving the forward up.
          while (walk.address == null && walk.ranOut && !history.atStart) {
            await _readMore(history, _lookBack, chatId, client);
            walk = _walk(post, history.posts);
          }
          address = walk.address ?? _lately(message.date);
        }
        if (address?.commentId != commentId) {
          await closeBurst();
          commentId = address?.commentId;
          burstText = address?.text ?? '';
        }
        if (commentId != null) burstDate = message.date;
        // A comment also covers the forwards between it and this one. One
        // that still waits, from before the filer first ran or left by a
        // pass that stopped, keeps the comment in place for it.
        if (address != null && complete) {
          for (final id in address.burst) {
            if (settled.contains(id)) continue;
            final file = await repository.fileById(MessageIndexer.adoptedId(id));
            if (file != null && file.adopted) {
              complete = false;
              break;
            }
            settled.add(id);
          }
        }
        final outcome = await _file(message, address, repository, folders, resolved);
        switch (outcome) {
          case _Outcome.filed:
            filed++;
            settled.add(message.id);
          case _Outcome.unmatched:
            complete = false;
          case _Outcome.gone:
            settled.add(message.id);
        }
        watermark = message.id;
      }
      await closeBurst();
    } catch (e) {
      // The pass stops here; the watermark stays below the message that
      // failed, or below the burst whose comment wouldn't go, so the next
      // pass takes it up again.
      debugPrint('[ForwardFiler] $e');
    } finally {
      if (watermark > from) await prefs.setForwardFilingFrom(chatId, watermark);
      if (filed > 0) {
        state = (state ?? const FilingSummary(count: 0, folderNames: [])).plus(filed, folders);
      }
    }
  }

  /// Where media the account sent itself asks to go: its own caption, or
  /// the caption of another item of its album among [batch].
  CommentAddress? _ownAddress(td.Message message, List<td.Message> batch) {
    final album = [
      for (final other in batch)
        if (other.id != message.id &&
            message.mediaAlbumId != 0 &&
            other.mediaAlbumId == message.mediaAlbumId)
          MessageIndexer.postOf(other),
    ];
    return addressFor(MessageIndexer.postOf(message), const [], sameAlbum: album);
  }

  /// Where a forward sent at [date] goes when its comment has gone already:
  /// the folder a burst closed lately named, when the forward is within
  /// [burstGapSeconds] of that burst's last one, as it would be had the
  /// comment still stood. The burst then reaches to this forward.
  CommentAddress? _lately(int date) {
    for (final burst in _closed) {
      if ((date - burst.lastDate).abs() <= burstGapSeconds) {
        burst.lastDate = math.max(burst.lastDate, date);
        return CommentAddress(burst.text);
      }
    }
    return null;
  }

  /// The channel before the run of forwards that starts at [pending][first]:
  /// the forwards that follow it within [burstGapSeconds] of each other, up
  /// to [_runLimit], and [_lookBack] messages behind them, newest first. One
  /// read serves every forward of the run, and each finds its own comment
  /// in it, so two bursts sent close together each go where their comment
  /// says.
  Future<_History> _readBack(
    List<td.Message> pending,
    int first,
    int chatId,
    TelegramClient client,
  ) async {
    var last = first;
    while (last + 1 < pending.length &&
        last - first + 1 < _runLimit &&
        pending[last + 1].forwardInfo != null &&
        (pending[last + 1].date - pending[last].date).abs() <= burstGapSeconds) {
      last++;
    }
    final history = _History(pending[last].id);
    await _readMore(history, _lookBack + last - first, chatId, client);
    return history;
  }

  /// Reads up to [limit] more messages behind what [history] holds, and
  /// notes when there is nothing older.
  Future<void> _readMore(_History history, int limit, int chatId, TelegramClient client) async {
    final page = await client.send<td.Messages>(
      td.GetChatHistory(
        chatId: chatId,
        fromMessageId: history.posts.lastOrNull?.id ?? history.from,
        offset: 0,
        limit: limit,
        onlyLocal: false,
      ),
    );
    if (page.messages.isEmpty) history.atStart = true;
    history.posts.addAll(page.messages.map(MessageIndexer.postOf));
  }

  /// Moves the file [message] became into the folder [address] names, read
  /// from [resolved] when the same text was looked up earlier in the pass.
  Future<_Outcome> _file(
    td.Message message,
    CommentAddress? address,
    DriveRepository repository,
    Map<String, String> folders,
    Map<String, _Destination?> resolved,
  ) async {
    if (address == null) return _Outcome.unmatched;
    if (!resolved.containsKey(address.text)) {
      resolved[address.text] = await _destinationOf(address.text, repository);
    }
    final destination = resolved[address.text];
    if (destination == null) return _Outcome.unmatched;
    // Another phone may have filed it first, or it may have been moved by
    // hand in the meantime; either way it is no longer waiting.
    final file = await repository.fileById(MessageIndexer.adoptedId(message.id));
    if (file == null || !file.adopted) return _Outcome.gone;
    await repository.moveFiles([file], destination.id);
    folders[destination.id] ??= destination.name;
    return _Outcome.filed;
  }

  /// The folder [text] names among the drive's visible folders, made on the
  /// way when the text asks for that, or null when it names none.
  Future<_Destination?> _destinationOf(String text, DriveRepository repository) async {
    final parsed = FolderAddress.parse(text);
    if (parsed == null) return null;
    var folderId = parsed.resolve(await repository.visibleFolders());
    if (folderId == null && parsed.create) {
      folderId = await repository.ensureFolderPath(parsed.segments);
    }
    if (folderId == null) return null;
    final name = (await repository.folderById(folderId))?.name ?? parsed.segments.last;
    return (id: folderId, name: name);
  }

  /// The folder text [target] asks for, from [olderNewestFirst], the
  /// messages before it, newest first.
  ///
  /// Media the account sent itself is read from its own caption, or from
  /// the one caption among [sameAlbum], the other items of its media album,
  /// since a caption on an album sits on one item. It never looks back, so
  /// a caption-less copy the drive made can't pick up a comment meant for
  /// something else.
  ///
  /// A forward's comment is the plain text message the account sent just
  /// before the burst: anything forwarded without a manifest within
  /// [burstGapSeconds] of the forward after it is part of the burst and
  /// passed over, a forwarded text among them too; the first text message
  /// of the account's own with no manifest within that time of the last one
  /// is the comment; anything else ends the search with nothing.
  static CommentAddress? addressFor(
    ChannelPost target,
    List<ChannelPost> olderNewestFirst, {
    List<ChannelPost> sameAlbum = const [],
  }) => _walk(target, olderNewestFirst, sameAlbum: sameAlbum).address;

  /// [addressFor], saying also when the walk back [ranOut] of posts with
  /// nothing ending it, so the caller can read further back.
  static ({CommentAddress? address, bool ranOut}) _walk(
    ChannelPost target,
    List<ChannelPost> olderNewestFirst, {
    List<ChannelPost> sameAlbum = const [],
  }) {
    if (!target.forwarded) {
      final own = target.caption.trim();
      if (own.isNotEmpty) return (address: CommentAddress(own), ranOut: false);
      final captions = [
        for (final item in sameAlbum)
          if (item.caption.trim() case final text when text.isNotEmpty) text,
      ];
      return (
        address: captions.length == 1 ? CommentAddress(captions.single) : null,
        ranOut: false,
      );
    }
    final burst = <int>[];
    var last = target;
    for (final post in olderNewestFirst) {
      if (post.id >= target.id) continue;
      final close = (last.date - post.date).abs() <= burstGapSeconds;
      if (!close) return (address: null, ranOut: false);
      if (post.forwarded && !post.manifest) {
        if (post.media) burst.add(post.id);
        last = post;
        continue;
      }
      if (post.text case final text? when !post.manifest) {
        return (address: CommentAddress(text, commentId: post.id, burst: burst), ranOut: false);
      }
      return (address: null, ranOut: false);
    }
    return (address: null, ranOut: true);
  }
}

/// The channel read back from the forward [from]: [posts] newest first, and
/// [atStart] once a read came back empty, so there is nothing older.
class _History {
  _History(this.from);

  final int from;
  final List<ChannelPost> posts = [];
  bool atStart = false;
}

/// A burst whose comment went: the folder [text] it named, and when the
/// burst's last forward was sent.
class _ClosedBurst {
  _ClosedBurst(this.text, this.lastDate);

  final String text;
  int lastDate;
}

/// A folder a text resolved to, by id and name.
typedef _Destination = ({String id, String name});

/// How one message came out of a pass.
enum _Outcome { filed, unmatched, gone }

final forwardFilerProvider = NotifierProvider<ForwardFiler, FilingSummary?>(ForwardFiler.new);
