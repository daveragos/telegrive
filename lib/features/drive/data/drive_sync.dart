import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;

import '../../../infrastructure/storage/preferences.dart';
import '../../../infrastructure/telegram/telegram_client.dart';
import '../../../infrastructure/telegram/telegram_exception.dart';
import 'drive_repository.dart';
import 'drive_session.dart';
import 'forward_filer.dart';
import 'message_indexer.dart';

@immutable
class SyncState {
  const SyncState({
    this.running = false,
    this.scanned = 0,
    this.error,
    this.lastSynced,
  });

  final bool running;

  /// Messages read so far in the current pass.
  final int scanned;

  /// Why the latest sync failed. It stays through the next try and clears
  /// only when one succeeds, so a retry that is still offline doesn't read
  /// as in sync while it runs.
  final String? error;
  final DateTime? lastSynced;

  SyncState copyWith({
    bool? running,
    int? scanned,
    String? error,
    bool clearError = false,
    DateTime? lastSynced,
  }) => SyncState(
    running: running ?? this.running,
    scanned: scanned ?? this.scanned,
    error: clearError ? null : (error ?? this.error),
    lastSynced: lastSynced ?? this.lastSynced,
  );
}

/// Keeps the local index in step with the channel.
///
/// * **Live** — while the drive is open, new, edited and deleted channel
///   messages flow straight into the index, so a file sent from Telegram on
///   another device appears within a second.
/// * **Incremental** — on open and on pull-to-refresh, reads back from the
///   newest message to the last one already indexed.
/// * **Full** — reads the whole channel and drops anything the index has
///   that the channel no longer does, then empties what has been in the
///   trash for 30 days. Runs on first open, daily, on the first open after
///   an update that changes [MessageIndexer.version], and from Settings →
///   Rebuild index.
///
/// Media that arrives without a manifest, a forward or a file sent from
/// another Telegram app, is handed to the [ForwardFiler] after each read,
/// which files it where its comment says.
class DriveSync extends Notifier<SyncState> {
  StreamSubscription<td.TdObject>? _live;
  int? _openChatId;
  Future<void>? _inFlight;

  /// Manifest-less media that arrived live, waiting for the burst it came
  /// with to finish before the filer looks at it.
  final List<td.Message> _arrived = [];
  Timer? _arrivedTimer;

  /// How long after the last forward arrived live the filer gets the burst;
  /// the files of one forward come in together, and the comment names a
  /// folder for all of them.
  @visibleForTesting
  static Duration burstSettle = const Duration(seconds: 3);

  static const Duration _fullSyncInterval = Duration(hours: 24);

  /// Kept from [build]: closing the chat happens while the provider is
  /// disposed, when reading other providers is no longer allowed.
  late TelegramClient _client;
  DriveRepository get _repository => ref.read(driveRepositoryProvider);
  Preferences get _prefs => ref.read(preferencesProvider);

  @override
  SyncState build() {
    _client = ref.watch(telegramClientProvider);
    ref.listen<DriveSession?>(driveSessionProvider, (previous, next) {
      if (previous?.chatId == next?.chatId) return;
      _stopLive();
      if (next != null) _startLive(next.chatId);
    }, fireImmediately: true);
    ref.onDispose(() {
      _stopLive();
      _retry?.cancel();
    });
    return const SyncState();
  }

  /// The sync that runs when the drive opens.
  Future<void> syncOnOpen() {
    final chatId = ref.read(driveSessionProvider)?.chatId;
    if (chatId == null) return Future.value();
    final lastFull = _prefs.lastFullSync(chatId);
    // An index an older indexer built may hold files it classified
    // differently or messages it skipped, so it is read again in full.
    final stale =
        lastFull == null ||
        DateTime.now().difference(lastFull) > _fullSyncInterval ||
        _prefs.indexedWith(chatId) < MessageIndexer.version;
    return stale ? fullSync() : refresh();
  }

  /// Completes once no sync is running. Photo backup waits on this so it
  /// judges "already in the drive" against a complete index.
  Future<void> whenIdle() async {
    while (_inFlight != null) {
      try {
        await _inFlight;
      } catch (_) {}
    }
  }

  /// Pulls in anything newer than the last sync.
  Future<void> refresh() => _run(full: false);

  /// Re-reads the whole channel.
  Future<void> fullSync() => _run(full: true);

  Future<void> _run({required bool full}) {
    final existing = _inFlight;
    if (existing != null) return existing;
    final future = _sync(full: full).whenComplete(() => _inFlight = null);
    _inFlight = future;
    return future;
  }

  Future<void> _sync({required bool full}) async {
    final chatId = ref.read(driveSessionProvider)?.chatId;
    if (chatId == null) return;
    state = state.copyWith(running: true, scanned: 0);

    try {
      final stopAt = full ? 0 : _prefs.lastSyncedMessageId(chatId);
      final seen = <int>{};
      final adopted = <td.Message>[];
      var newest = 0;
      var from = 0;

      // TDLib's history paging can return short pages (the first often has
      // a single message from its cache); only an empty page means the end.
      while (true) {
        final page = await _page(chatId, from);
        if (page.messages.isEmpty) break;

        var reachedKnown = false;
        for (final message in page.messages) {
          if (message.id <= stopAt) {
            reachedKnown = true;
            break;
          }
          if (message.sendingState != null) continue;
          seen.add(message.id);
          if (message.id > newest) newest = message.id;
          await _repository.ingest(message);
          if (MessageIndexer.isAdopted(message)) adopted.add(message);
        }
        state = state.copyWith(scanned: seen.length);
        if (reachedKnown) break;
        from = page.messages.last.id;
      }

      if (full) {
        // Anything indexed that the channel no longer has was deleted while
        // we weren't watching. Only messages older than the newest one read
        // are judged, so an upload finishing mid-sync is not mistaken for a
        // deletion.
        final known = await _repository.knownMessageIds();
        final gone = known.where((id) => id <= newest && !seen.contains(id));
        await _repository.forget(gone);
        await _prefs.setLastFullSync(chatId, DateTime.now());
        await _prefs.setIndexedWith(chatId, MessageIndexer.version);
        // Once a day, like the full read: what has sat in the trash for 30
        // days goes for good.
        try {
          await _repository.purgeTrash();
        } catch (e) {
          debugPrint('[DriveSync] Emptying old trash: $e');
        }
      }
      if (newest > 0) await _prefs.setLastSyncedMessageId(chatId, newest);

      // The first read with the filer sets its watermark at the channel's
      // end, so forwards from before it never move on their own; from then
      // on, what each read brings in is filed by its comment.
      if (_prefs.forwardFilingFrom(chatId) == null) {
        await _prefs.setForwardFilingFrom(chatId, math.max(newest, stopAt));
      } else if (adopted.isNotEmpty) {
        unawaited(ref.read(forwardFilerProvider.notifier).consider(adopted));
      }

      _failedFullSyncs = 0;
      state = state.copyWith(running: false, lastSynced: DateTime.now(), clearError: true);
    } on TelegramException catch (e) {
      state = state.copyWith(running: false, error: e.friendlyMessage);
      if (full) _retryFullSync();
    } catch (e) {
      debugPrint('[DriveSync] $e');
      state = state.copyWith(running: false, error: 'Sync failed: $e');
      if (full) _retryFullSync();
    }
  }

  /// One page of the channel's history. Reading thousands of messages after
  /// a reinstall is exactly when Telegram rate-limits, so waits it asks for
  /// are sat out and brief network trouble is retried, rather than leaving
  /// the index half built.
  Future<td.Messages> _page(int chatId, int from) async {
    for (var attempt = 1; ; attempt++) {
      try {
        return await _client.send<td.Messages>(
          td.GetChatHistory(
            chatId: chatId,
            fromMessageId: from,
            offset: 0,
            limit: 100,
            onlyLocal: false,
          ),
          timeout: const Duration(seconds: 60),
        );
      } on TelegramException catch (e) {
        final wait = e.retryAfterSeconds;
        if (e.isFloodWait && wait != null && wait <= 600) {
          await Future<void>.delayed(Duration(seconds: wait + 1));
          continue;
        }
        // Bad requests won't get better; anything else may.
        if (e.code == 400 || attempt >= 5) rethrow;
      }
      await Future<void>.delayed(Duration(seconds: 3 * attempt));
    }
  }

  int _failedFullSyncs = 0;
  Timer? _retry;

  /// A full sync that stopped short leaves the index missing older files,
  /// so it is tried again on its own, a little later each time.
  void _retryFullSync() {
    if (_failedFullSyncs >= 5) return;
    _failedFullSyncs++;
    _retry?.cancel();
    _retry = Timer(Duration(seconds: 30 * _failedFullSyncs), () => unawaited(fullSync()));
  }

  /// Forgets sync progress and reads everything again.
  Future<void> rebuildIndex() async {
    final chatId = ref.read(driveSessionProvider)?.chatId;
    if (chatId == null) return;
    await _prefs.clearSyncState(chatId);
    await fullSync();
  }

  void _startLive(int chatId) {
    // TDLib only receives a channel's updates — including edits and deletes
    // made on another device — while the chat is open. Opening it also makes
    // TDLib catch up on what changed while this device was away.
    _openChatId = chatId;
    unawaited(
      _client
          .send<td.Ok>(td.OpenChat(chatId: chatId))
          .then<void>((_) {}, onError: (Object e) => debugPrint('[DriveSync] openChat: $e')),
    );
    _live = _client.updates.listen((update) async {
      try {
        switch (update) {
          case td.UpdateNewMessage(:final message) when message.chatId == chatId:
            await _repository.ingest(message);
            _noteArrival(message);
          case td.UpdateMessageSendSucceeded(:final message)
              when message.chatId == chatId:
            await _repository.ingest(message);
            _noteArrival(message);
          case td.UpdateMessageContent(chatId: final id, :final messageId)
              when id == chatId:
            final message = await _client.send<td.Message>(
              td.GetMessage(chatId: chatId, messageId: messageId),
            );
            await _repository.ingest(message);
          case td.UpdateDeleteMessages(
                chatId: final id,
                :final messageIds,
                :final isPermanent,
                :final fromCache,
              )
              when id == chatId && isPermanent && !fromCache:
            await _repository.forget(messageIds);
          default:
            break;
        }
      } catch (e) {
        debugPrint('[DriveSync] live update failed: $e');
      }
    });
  }

  /// Keeps a manifest-less [message] for the filer, which gets the whole
  /// burst once [burstSettle] has passed with nothing more arriving.
  void _noteArrival(td.Message message) {
    if (!MessageIndexer.isAdopted(message)) return;
    _arrived.add(message);
    _arrivedTimer?.cancel();
    _arrivedTimer = Timer(burstSettle, () {
      final batch = [..._arrived];
      _arrived.clear();
      unawaited(ref.read(forwardFilerProvider.notifier).consider(batch));
    });
  }

  void _stopLive() {
    _live?.cancel();
    _live = null;
    _arrivedTimer?.cancel();
    _arrivedTimer = null;
    _arrived.clear();
    final open = _openChatId;
    _openChatId = null;
    if (open != null) {
      unawaited(
        _client
            .send<td.Ok>(td.CloseChat(chatId: open))
            .then<void>((_) {}, onError: (Object _) {}),
      );
    }
  }
}

final driveSyncProvider = NotifierProvider<DriveSync, SyncState>(DriveSync.new);
