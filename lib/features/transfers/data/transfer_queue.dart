import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/files/file_kind.dart';
import '../../../infrastructure/database/app_database.dart';
import '../../../infrastructure/media/media_probe.dart';
import '../../../infrastructure/network/network_status.dart';
import '../../../infrastructure/storage/device_profile.dart';
import '../../../infrastructure/storage/device_storage.dart';
import '../../../infrastructure/telegram/telegram_client.dart';
import '../../../infrastructure/telegram/telegram_exception.dart';
import '../../backup/data/backup_run_mode.dart';
import '../../drive/data/channel_messenger.dart';
import '../../drive/data/drive_repository.dart';
import '../../drive/data/drive_session.dart';
import '../../drive/data/message_indexer.dart';
import '../../drive/domain/drive_models.dart';
import '../../drive/domain/manifest.dart';
import '../../share/data/share_intake.dart';
import '../domain/transfer_error.dart';
import '../domain/transfer_wait.dart';
import 'leftovers.dart';
import 'room.dart';
import 'transfer_policy.dart';

/// A file on this device, about to go up.
///
/// Either a real [path], or — for pickers that hand back a content URI, as
/// Android's does — a way to [openRead] it. TDLib can only upload from a
/// path, so the latter is copied into staging when its turn comes.
@immutable
class UploadRequest {
  const UploadRequest({
    required this.name,
    this.path,
    this.openRead,
    this.size,
    this.ownsSource = false,
    this.origin = TransferOrigin.manual,
    this.assetId,
    this.takenAt,
    this.thumbnailPath,
    this.wifiOnly = false,
    this.replacesFileId,
    this.durationSeconds,
    this.fileId,
    this.smallCopyOf,
    this.replacesSmallCopy = false,
    this.albumIds = const [],
    this.starred = false,
  }) : assert(path != null || openRead != null);

  final String name;
  final String? path;
  final Stream<List<int>> Function()? openRead;
  final int? size;

  /// The path is our own temporary copy and can be deleted once uploaded.
  final bool ownsSource;
  final TransferOrigin origin;
  final String? assetId;
  final DateTime? takenAt;

  /// Temporary JPEG to attach as the document thumbnail; deleted after.
  final String? thumbnailPath;

  /// Waits for an unmetered network, and steps back to wait again if the
  /// phone moves onto mobile data while it runs.
  final bool wifiOnly;

  /// The drive file this upload replaces: once the upload has landed, that
  /// file goes to the trash marked as replaced by the new one.
  final String? replacesFileId;

  /// How long a video or audio file runs, in seconds, when the caller
  /// already knows; otherwise the queue reads it from the file before the
  /// upload starts.
  final int? durationSeconds;

  /// The drive file this upload goes up as, when it is one already in the
  /// drive; otherwise a new one.
  final String? fileId;

  /// Makes this upload a small copy of a photo whose original is this many
  /// bytes: a JPEG that goes up as a drive file of its own, marked as a
  /// small copy, until the original takes its place.
  final int? smallCopyOf;

  /// The original of the small copy [fileId], which goes into that file's
  /// message in its place rather than into a message of its own.
  final bool replacesSmallCopy;

  /// Albums the file goes into, written in its first caption.
  final List<String> albumIds;

  /// Goes up starred.
  final bool starred;

  /// This request under another [name] or [path], or replacing a file.
  UploadRequest copyWith({
    String? name,
    String? path,
    String? replacesFileId,
  }) => UploadRequest(
    name: name ?? this.name,
    path: path ?? this.path,
    openRead: openRead,
    size: size,
    ownsSource: ownsSource,
    origin: origin,
    assetId: assetId,
    takenAt: takenAt,
    thumbnailPath: thumbnailPath,
    wifiOnly: wifiOnly,
    replacesFileId: replacesFileId ?? this.replacesFileId,
    durationSeconds: durationSeconds,
    fileId: fileId,
    smallCopyOf: smallCopyOf,
    replacesSmallCopy: replacesSmallCopy,
    albumIds: albumIds,
    starred: starred,
  );
}

/// A drive file to download and keep on this phone.
@immutable
class SaveRequest {
  const SaveRequest(
    this.file, {
    required this.target,
    this.folders = const [],
    this.wifiOnly = false,
  });

  final DriveFile file;
  final SaveTarget target;

  /// Folders under the save location, so the drive's layout carries over.
  /// For the gallery, the phone folder the photo was backed up from.
  final List<String> folders;

  /// Waits for an unmetered network, as [UploadRequest.wifiOnly] does.
  final bool wifiOnly;
}

/// A file in a Telegram chat, to be copied into the drive by Telegram
/// itself, so nothing is downloaded or uploaded.
@immutable
class CopyRequest {
  const CopyRequest({
    required this.chatId,
    required this.messageId,
    required this.name,
    required this.mimeType,
    required this.size,
    required this.date,
  });

  final int chatId;
  final int messageId;

  /// What the copy is called in the drive.
  final String name;
  final String mimeType;
  final int size;

  /// When the message was sent, which the copy keeps.
  final DateTime date;
}

/// A transfer as the UI sees it: the persisted row plus live speed.
@immutable
class TransferItem {
  const TransferItem(
    this.row, {
    this.bytesPerSecond = 0,
    this.preparing = false,
    this.wait,
  });

  final TransferRow row;
  final double bytesPerSecond;

  /// Being copied into staging before the upload proper starts.
  final bool preparing;

  /// What the transfer is waiting for before it carries on by itself: a
  /// queued one before it starts, a running one for the network to return.
  final TransferWait? wait;

  String get id => row.id;
  String get name => row.name;
  TransferKind get kind => row.kind;
  TransferOrigin get origin => row.origin;
  TransferStatus get status => row.status;
  FileKind get fileKind =>
      FileKind.detect(fileName: row.name, mimeType: row.mimeType);

  /// Queued, or running while Telegrive waits to be opened, on a wait that,
  /// at [now], is long enough that it doesn't count as in flight. A paused
  /// transfer is never held: it waits for a person, not for the clock.
  bool heldAt(DateTime now) =>
      status.isActive && (wait?.holdsAt(now) ?? false);

  /// Running or queued, with nothing holding it back for long at [now]. A
  /// transfer on a long wait isn't counted, so nothing stays awake for it.
  bool inFlightAt(DateTime now) => status.isActive && !heldAt(now);

  double get progress => row.totalBytes <= 0
      ? 0
      : (row.doneBytes / row.totalBytes).clamp(0.0, 1.0);

  Duration? get eta {
    if (bytesPerSecond < 1 || status != TransferStatus.running) return null;
    final remaining = row.totalBytes - row.doneBytes;
    return Duration(seconds: (remaining / bytesPerSecond).ceil());
  }
}

@immutable
class TransfersState {
  const TransfersState(this.items);

  static const empty = TransfersState([]);

  /// Newest first.
  final List<TransferItem> items;

  List<TransferItem> get active => activeAt(DateTime.now());

  /// [active] as it stands at [now], for status worked out for a given time.
  List<TransferItem> activeAt(DateTime now) =>
      items.where((t) => t.inFlightAt(now)).toList();

  /// Photo-backup uploads in flight, shown as one group in the UI.
  List<TransferItem> get backupActive =>
      active.where((t) => t.origin == TransferOrigin.backup).toList();

  /// Waiting long enough that they don't count as in flight.
  List<TransferItem> get held => heldAt(DateTime.now());

  /// [held] as it stands at [now].
  List<TransferItem> heldAt(DateTime now) =>
      items.where((t) => t.heldAt(now)).toList();

  /// Queued until the phone is on Wi-Fi again.
  List<TransferItem> get waitingForWifi => items
      .where(
        (t) => t.status == TransferStatus.queued && t.wait is WaitingForWifi,
      )
      .toList();

  /// Queued until the phone has room for what they write.
  List<TransferItem> get waitingForRoom => items
      .where(
        (t) => t.status == TransferStatus.queued && t.wait is WaitingForRoom,
      )
      .toList();

  /// Downloads to this phone, which the UI also shows as one group.
  List<TransferItem> get saves =>
      items.where((t) => t.origin == TransferOrigin.save).toList();

  /// Copies from Telegram chats, which the UI also shows as one group.
  List<TransferItem> get copies =>
      items.where((t) => t.origin == TransferOrigin.fromChat).toList();

  /// How many [copies] are made, out of all of them but the cancelled ones,
  /// and how many are still to be made. Telegram makes each copy in one
  /// request, so copies are counted by file, never by byte.
  ({int saved, int total, int left}) get copyCount {
    var saved = 0;
    var total = 0;
    var left = 0;
    for (final item in copies) {
      if (item.status == TransferStatus.cancelled) continue;
      total++;
      if (item.status == TransferStatus.completed) saved++;
      if (item.status.isPending) left++;
    }
    return (saved: saved, total: total, left: left);
  }

  List<TransferItem> get finished =>
      items.where((t) => t.status.isFinished).toList();

  /// Running, waiting or paused: everything the Transfers list shows as in
  /// progress.
  List<TransferItem> get pending =>
      items.where((t) => t.status.isPending).toList();

  int get pausedCount =>
      items.where((t) => t.status == TransferStatus.paused).length;

  int get activeCount => active.length;

  /// Failed uploads and downloads the person can retry; backup retries its
  /// own.
  int get failedCount => items
      .where(
        (t) =>
            t.status == TransferStatus.failed &&
            t.origin != TransferOrigin.backup,
      )
      .length;

  /// Combined progress of everything in flight, for the global indicator.
  /// It covers bytes, so copies from chats are left out; see [copyCount].
  double get activeProgress => byteProgress(active);

  /// The share of bytes done across [items], leaving out copies from chats:
  /// Telegram makes a copy in one request, so it has no bytes to follow,
  /// and its size would only hold the share down.
  static double byteProgress(Iterable<TransferItem> items) {
    var total = 0;
    var done = 0;
    for (final item in items) {
      if (item.origin == TransferOrigin.fromChat) continue;
      total += item.row.totalBytes;
      done += item.row.doneBytes;
    }
    return total == 0 ? 0 : done / total;
  }

  TransferItem? byId(String id) {
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }
}

/// The phone lacks the room a transfer needs before it writes anything:
/// [needed] bytes free, with [free] there.
class _NeedsRoom implements Exception {
  const _NeedsRoom(this.needed, this.free);

  final int needed;
  final int free;
}

/// Which transfer a TDLib file's progress belongs to.
class _Tracked {
  const _Tracked(this.transferId, this.baseBytes, {required this.upload});

  final String transferId;

  /// Bytes already done in earlier parts of a split file.
  final int baseBytes;
  final bool upload;
}

/// The upload and download queue.
///
/// Runs a few transfers at a time, reports progress from TDLib's file
/// updates, and persists every state change so a restart picks up where the
/// last run stopped: queued work runs again, split uploads resume at the last
/// finished part, and a single upload TDLib is still sending on its own is
/// re-attached rather than sent twice. When Telegram asks for a pause, the
/// transfer waits in the queue and starts again by itself; when it asks an
/// upload, every other upload waits with it, a split one under way before
/// its next part. Whether a queued transfer may start is one question,
/// [TransferPolicy.mayRun], so every reason to wait is checked in one place.
///
/// A dropped connection never interrupts a transfer: TDLib picks it up again
/// by itself, and the row only says it is waiting for the network. A request
/// that times out on the way is tried again a few times before the row is
/// called failed. A row marked Wi-Fi only doesn't start on mobile data, and
/// steps back into the queue when the phone moves onto it mid-way. Once
/// Android ends the time it gives transfers in the background, nothing
/// starts and what runs waits until Telegrive is on screen again; see
/// [waitForApp].
///
/// Nothing big is written without room for it: a transfer that would fill
/// the phone waits in the queue, says how much it needs, and starts by
/// itself once [recheckRoom] finds the space. A copy made for an upload is
/// written under a temporary name and only sent when it is whole, and the
/// copies nothing needs any more are deleted with their transfer, or swept
/// up when the drive opens.
///
/// Copies from chats are uploads to the queue, waiting with them when
/// Telegram asks, but Telegram makes them in one request each, with nothing
/// sent from the phone. They go one at a time, a moment apart, and leave
/// the upload slots free.
///
/// In the background backup job ([BackupRunMode.background]) the queue
/// reads and sends only photo backup's uploads. The person's own transfers
/// stay in the database as they are, for the app to carry on with.
class TransferQueue extends Notifier<TransfersState> {
  static const int _maxCopies = 1;

  /// The pause after each copy, so a long run of them keeps under the rate
  /// at which Telegram starts asking for waits.
  static const Duration _copyGap = Duration(milliseconds: 400);

  /// A phone saving memory runs fewer transfers at once. Read each time the
  /// queue starts work, so turning it on or off applies from the next start
  /// and lets the transfers already running finish.
  bool get _saveMemory => ref.read(saveMemoryProvider);
  int get _maxUploads => _saveMemory ? 1 : 2;
  int get _maxDownloads => _saveMemory ? 2 : 3;

  /// Saves to the phone leave a download slot free, so opening a file never
  /// waits behind a whole drive being downloaded.
  int get _maxSaves => _saveMemory ? 1 : 2;
  static const Duration _emitInterval = Duration(milliseconds: 300);

  /// How long one second of waiting lasts, for Telegram's pauses and for
  /// retries after a dropped connection; tests shorten it.
  @visibleForTesting
  static Duration waitUnit = const Duration(seconds: 1);

  /// Seconds before each try again after the connection let a transfer
  /// down; once they are used up with no part landing, the transfer fails.
  static const List<int> _retryAfter = [5, 20, 60];

  final Map<String, TransferRow> _rows = {};
  final Map<String, double> _speeds = {};
  final Map<String, (int bytes, DateTime at)> _samples = {};
  final Set<String> _running = {};
  final Set<String> _cancelled = {};

  /// Running transfers asked to pause; they stop at the next chance.
  final Set<String> _pausing = {};

  /// Running Wi-Fi-only transfers stopping because the phone moved onto
  /// mobile data. They go back in the queue rather than to paused.
  final Set<String> _holding = {};

  /// How many times each transfer has been tried again after the
  /// connection let it down since its last part landed.
  final Map<String, int> _attempts = {};

  /// Queued to try again after the connection let them down. They wait
  /// while Telegram has no network, then start when their time is up.
  final Set<String> _retrying = {};
  final Map<int, _Tracked> _tracked = {};
  final Map<String, int> _pendingMessages = {};
  final Map<String, int> _activeDownloads = {};
  final Map<String, Completer<String>> _completions = {};
  final Map<String, Stream<List<int>> Function()> _stagers = {};
  final Map<String, Completer<TransferRow>> _finished = {};

  /// The last rows that finished and weren't kept, backup's and an
  /// import's, so [whenFinished] asked after one has gone still answers.
  final Map<String, TransferRow> _ended = {};
  static const int _endedKept = 256;
  final Set<String> _preparing = {};

  /// Small copies photo backup sends, to the size of each one's original.
  /// They live in memory: a send TDLib carries on after a restart takes the
  /// fact back from its caption, and any other backup row is dropped then
  /// and queued again by the next pass.
  final Map<String, int> _smallCopyOf = {};

  /// Originals going into their small copy's message in its place.
  final Set<String> _replacing = {};

  /// TDLib's file for each original being uploaded ahead of its edit, so
  /// the upload can be called off.
  final Map<String, int> _preliminary = {};

  /// When queued transfers may start again: downloads Telegram asked to
  /// wait, and transfers to try again after a dropped connection.
  final Map<String, DateTime> _notBefore = {};

  /// Queued transfers the phone has no room for yet, and what they need.
  final Map<String, WaitingForRoom> _room = {};

  /// Looks at the free space again while anything waits for room.
  Timer? _roomTimer;
  static const Duration _roomRecheck = Duration(seconds: 60);

  /// When uploads may start again, or send their next part, after Telegram
  /// asked one of them to wait.
  /// The limit is the account's, so the next upload would send all its
  /// bytes only to be told the same at the end, which on mobile data spends
  /// the person's data for nothing. Downloads carry on.
  DateTime? _uploadsNotBefore;

  /// The phone's connection as last reported, for rows that wait for Wi-Fi.
  NetworkState _network = NetworkState.unknown;

  /// TDLib is waiting for a network: running transfers say so, and retries
  /// hold off until it has one.
  bool _offline = false;

  /// Android ended the background time for transfers while Telegrive was
  /// off screen: nothing starts, and what runs says it waits, until
  /// [appOpened]. See [waitForApp].
  bool _waitingForApp = false;

  StreamSubscription<td.File>? _fileSubscription;
  StreamSubscription<String>? _ingestSubscription;
  StreamSubscription<td.ConnectionState>? _connectionSubscription;
  Timer? _emitTimer;

  /// Fires when the next of [_notBefore] or [_uploadsNotBefore] comes due.
  Timer? _wakeTimer;
  int? _loadedFor;

  /// Completes once the open drive's transfers are read from the database.
  Completer<void> _ready = Completer<void>();

  TelegramClient get _client => ref.read(telegramClientProvider);
  AppDatabase get _db => ref.read(appDatabaseProvider);
  DriveRepository get _repository => ref.read(driveRepositoryProvider);
  ChannelMessenger get _messenger => ref.read(channelMessengerProvider);

  /// Running in the background backup job, for backup's uploads only.
  bool get _background => ref.read(backupRunModeProvider) == BackupRunMode.background;

  @override
  TransfersState build() {
    _fileSubscription = _client.fileUpdates.listen(_onFileUpdate);
    _ingestSubscription = _repository.ingestedFileIds.listen(_onIngested);
    _connectionSubscription = _client.connectionStates.listen(_onConnection);
    _network = ref.read(networkStatusProvider);
    ref.listen<NetworkState>(
      networkStatusProvider,
      (_, next) => _onNetwork(next),
    );
    ref.listen<DriveSession?>(driveSessionProvider, (previous, next) {
      if (next == null) {
        _reset();
      } else if (_loadedFor != next.chatId) {
        _loadedFor = next.chatId;
        unawaited(_load());
      }
    }, fireImmediately: true);
    ref.onDispose(() {
      _fileSubscription?.cancel();
      _ingestSubscription?.cancel();
      _connectionSubscription?.cancel();
      _emitTimer?.cancel();
      _wakeTimer?.cancel();
      _roomTimer?.cancel();
    });
    return TransfersState.empty;
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Completes once the drive's transfers are loaded, so something asked
  /// for as the app opens, from a notification, say, finds the rows it is
  /// about.
  Future<void> get loaded => _ready.future;

  /// When uploads may go again after Telegram asked one of them to wait,
  /// while that wait runs, or null. Photo backup reads it to tell a pause
  /// from a failure.
  DateTime? get floodWaitUntil {
    final until = _uploadsNotBefore;
    return until != null && until.isAfter(DateTime.now()) ? until : null;
  }

  /// Whether upload [id] is a small copy photo backup sends, which goes on
  /// mobile data whatever backup's Mobile data choice says.
  bool sendsSmallCopy(String id) => _smallCopyOf.containsKey(id);

  /// Queues [requests]; returns the new transfers' ids, in order.
  Future<List<String>> enqueueUploads(
    List<UploadRequest> requests, {
    String? folderId,
  }) async {
    final ids = <String>[];
    final now = DateTime.now();
    final staging = await _stagingDir();
    for (final (index, request) in requests.indexed) {
      final id = _repository.newId();
      final String sourcePath;
      final bool ownsSource;
      final int size;
      final direct = request.path == null ? null : File(request.path!);
      if (direct != null && await direct.exists()) {
        sourcePath = direct.path;
        ownsSource = request.ownsSource;
        size = await direct.length();
      } else if (request.openRead != null) {
        sourcePath = p.join(staging.path, id, request.name);
        ownsSource = true;
        size = request.size ?? 0;
        _stagers[id] = request.openRead!;
      } else {
        continue;
      }
      final row = TransferRow(
        id: id,
        kind: TransferKind.upload,
        status: TransferStatus.queued,
        name: request.name,
        // A small copy keeps the photo's name, so nothing is renamed when
        // the original arrives, but holds a JPEG.
        mimeType: request.smallCopyOf != null ? 'image/jpeg' : mimeTypeFor(request.name),
        fileId: request.fileId ?? _repository.newId(),
        folderId: folderId,
        sourcePath: sourcePath,
        ownsSource: ownsSource,
        wifiOnly: request.wifiOnly,
        totalBytes: size,
        doneBytes: 0,
        partCount: 1,
        completedParts: 0,
        // Keep the picker's order when several files share a timestamp.
        createdAt: now.add(Duration(microseconds: index)),
        origin: request.origin,
        assetId: request.assetId,
        takenAt: request.takenAt,
        thumbnailPath: request.thumbnailPath,
        replacesFileId: request.replacesFileId,
        durationSeconds: request.durationSeconds,
        albumIds: request.albumIds.isEmpty ? null : request.albumIds.join(','),
        starred: request.starred ? true : null,
      );
      if (request.smallCopyOf case final original?) _smallCopyOf[id] = original;
      if (request.replacesSmallCopy) _replacing.add(id);
      await _save(row);
      ids.add(id);
    }
    _emit();
    _pump();
    return ids;
  }

  /// Completes when transfer [id] finishes, successfully or not, with its
  /// final row. Used by photo backup to pace itself.
  Future<TransferRow> whenFinished(String id) {
    final row = _rows[id] ?? _ended[id];
    if (row != null && row.status.isFinished) return Future.value(row);
    return (_finished[id] ??= Completer<TransferRow>()).future;
  }

  /// Downloads [file] into the app's storage (visible in Transfers).
  Future<String> download(DriveFile file) async {
    final existing = _rows.values.where(
      (r) =>
          r.kind == TransferKind.download &&
          r.origin != TransferOrigin.save &&
          r.fileId == file.id &&
          r.status.isPending,
    );
    if (existing.isNotEmpty) {
      final row = existing.first;
      if (row.status == TransferStatus.paused) await resume(row.id);
      return _completionOf(row.id);
    }

    final row = TransferRow(
      id: _repository.newId(),
      kind: TransferKind.download,
      status: TransferStatus.queued,
      name: file.name,
      mimeType: file.mimeType,
      fileId: file.id,
      folderId: file.folderId,
      ownsSource: false,
      // Someone is waiting to see it, so opening a file never waits for
      // Wi-Fi.
      wifiOnly: false,
      origin: TransferOrigin.manual,
      totalBytes: file.size,
      doneBytes: 0,
      partCount: file.partCount,
      completedParts: 0,
      createdAt: DateTime.now(),
    );
    final completion = _completionOf(row.id);
    await _save(row);
    _emit();
    _pump();
    return completion;
  }

  /// Queues [requests] as downloads kept on this phone. Files already on
  /// their way there are left alone. Returns how many were queued.
  Future<int> enqueueSaves(List<SaveRequest> requests) async {
    final inFlight = {
      for (final r in _rows.values)
        if (r.origin == TransferOrigin.save && r.status.isPending) r.fileId,
    };
    final now = DateTime.now();
    final rows = <TransferRow>[];
    for (final (index, request) in requests.indexed) {
      final file = request.file;
      if (!inFlight.add(file.id)) continue;
      rows.add(
        TransferRow(
          id: _repository.newId(),
          kind: TransferKind.download,
          status: TransferStatus.queued,
          name: file.name,
          mimeType: file.mimeType,
          fileId: file.id,
          folderId: file.folderId,
          ownsSource: false,
          wifiOnly: request.wifiOnly,
          origin: TransferOrigin.save,
          totalBytes: file.size,
          doneBytes: 0,
          partCount: file.partCount,
          completedParts: 0,
          createdAt: now.add(Duration(microseconds: index)),
          takenAt: file.takenAt,
          saveTo: request.target,
          saveFolder: request.folders.isEmpty
              ? null
              : request.folders.map(DeviceStorage.safeName).join('/'),
        ),
      );
    }
    for (final row in rows) {
      _rows[row.id] = row;
    }
    await _db.saveTransfers(rows);
    _emit();
    _pump();
    return rows.length;
  }

  /// Queues copies of [requests] into [folderId], made by Telegram from the
  /// chats they are in. Files already on their way into the drive are left
  /// alone. Returns how many were queued.
  Future<int> enqueueCopies(
    List<CopyRequest> requests, {
    String? folderId,
  }) async {
    final inFlight = {
      for (final r in _rows.values)
        if (r.origin == TransferOrigin.fromChat && r.status.isPending)
          (r.sourceChatId, r.sourceMessageId),
    };
    final now = DateTime.now();
    final rows = <TransferRow>[];
    for (final (index, request) in requests.indexed) {
      if (!inFlight.add((request.chatId, request.messageId))) continue;
      rows.add(
        TransferRow(
          id: _repository.newId(),
          kind: TransferKind.upload,
          status: TransferStatus.queued,
          name: request.name,
          mimeType: request.mimeType.isEmpty
              ? mimeTypeFor(request.name)
              : request.mimeType,
          fileId: _repository.newId(),
          folderId: folderId,
          ownsSource: false,
          wifiOnly: false,
          origin: TransferOrigin.fromChat,
          totalBytes: request.size,
          doneBytes: 0,
          partCount: 1,
          completedParts: 0,
          createdAt: now.add(Duration(microseconds: index)),
          takenAt: request.date,
          sourceChatId: request.chatId,
          sourceMessageId: request.messageId,
        ),
      );
    }
    for (final row in rows) {
      _rows[row.id] = row;
    }
    await _db.saveTransfers(rows);
    _emit();
    _pump();
    return rows.length;
  }

  /// Stops every save to this phone and drops them from the list. Files
  /// already saved stay where they are.
  Future<void> cancelSaves() => _cancelAll(TransferOrigin.save);

  /// Stops every copy from a chat still to be made and drops them from the
  /// list. Files already copied stay in the drive.
  Future<void> cancelCopies() => _cancelAll(TransferOrigin.fromChat);

  /// Stops every pending transfer from [origin] and drops them from the
  /// list.
  Future<void> _cancelAll(TransferOrigin origin) async {
    final ids = [
      for (final r in _rows.values)
        if (r.origin == origin && r.status.isPending) r.id,
    ];
    // Waiting ones go first, so nothing new starts while the rest stop.
    final running = ids.where(_running.contains).toList();
    for (final id in ids) {
      if (!_running.contains(id)) _rows.remove(id);
    }
    for (final id in running) {
      await cancel(id);
      _rows.remove(id);
    }
    await _db.deleteTransfers(ids);
    _emit();
  }

  /// A local path for [file], downloading only when there isn't one yet.
  Future<String> ensureLocal(DriveFile file) async {
    final local = await localPathIfAvailable(file);
    if (local != null) return local;
    return download(file);
  }

  /// A path for [file] that already exists on this device, or null. A
  /// saved or kept copy counts only if it has the file's size: a small
  /// copy's original replaces it under the same id, and what was saved or
  /// opened of the small copy is not the original.
  Future<String?> localPathIfAvailable(DriveFile file) async {
    final offline = await _db.offlineCopyOf(file.id);
    if (offline != null &&
        offline.size == file.size &&
        await File(offline.path).exists()) {
      return offline.path;
    }
    for (final row in _rows.values) {
      if (row.kind == TransferKind.download &&
          row.fileId == file.id &&
          row.status == TransferStatus.completed &&
          row.totalBytes == file.size &&
          row.resultPath != null &&
          await File(row.resultPath!).exists()) {
        return row.resultPath;
      }
    }
    final parts = await _repository.partsOf(file.id);
    if (parts.length != 1) return null;
    try {
      final tdFile = await _resolveTdFile(parts.first);
      final path = tdFile.local.path;
      if (tdFile.local.isDownloadingCompleted && await File(path).exists()) {
        return path;
      }
    } catch (_) {}
    return null;
  }

  /// Whether a download in this queue is fetching TDLib file [tdFileId]
  /// right now, so whoever else reads that file leaves TDLib's download of
  /// it alone.
  bool isFetching(int tdFileId) => _activeDownloads.containsValue(tdFileId);

  Future<void> cancel(String id) async {
    final row = _rows[id];
    if (row == null || !row.status.isPending) return;
    _cancelled.add(id);
    _pausing.remove(id);
    _holding.remove(id);
    _retrying.remove(id);
    _notBefore.remove(id);
    _room.remove(id);
    _stagers.remove(id);
    await _interrupt(row);
    // Parts already delivered are useless without the rest.
    if (row.kind == TransferKind.upload && row.completedParts > 0) {
      await _quietly(() => _repository.deleteFileById(row.fileId));
    }
    // Nothing will send it now, so the copies made for it can go.
    if (row.kind == TransferKind.upload) await _dropOwnedFiles(row);
    // A paused split download has parts stitched together already.
    if (row.kind == TransferKind.download &&
        row.partCount > 1 &&
        !_running.contains(id)) {
      await _deleteQuietly(
        Directory(p.join((await downloadsDirectory()).path, row.fileId)),
      );
    }

    await _finish(
      row.copyWith(
        status: TransferStatus.cancelled,
        completedParts: 0,
        doneBytes: 0,
      ),
      error: const SendCancelled(),
    );
  }

  /// Stops [id] where it is, to carry on with [resume]. A download keeps
  /// what TDLib has fetched; a split upload keeps its finished parts and
  /// redoes only the one in flight.
  Future<void> pause(String id) async {
    final row = _rows[id];
    // Copying a picked file into staging can't stop halfway safely.
    if (row == null || !row.status.isActive || _preparing.contains(id)) return;
    if (!_running.contains(id)) {
      // A paused transfer waits for Resume, not for Telegram's clock, room
      // or another try.
      _notBefore.remove(id);
      _retrying.remove(id);
      _room.remove(id);
      await _save(row.copyWith(status: TransferStatus.paused));
      _emit();
      return;
    }
    _pausing.add(id);
    await _interrupt(row);
    // The work stops with an error, which marks it paused; see [_start].
  }

  Future<void> resume(String id) async {
    final row = _rows[id];
    if (row == null || row.status != TransferStatus.paused) return;
    _notBefore.remove(id);
    await _save(row.copyWith(status: TransferStatus.queued));
    _emit();
    _pump();
  }

  /// Pauses, or resumes, every transfer [which] picks out.
  Future<void> pauseAll(bool Function(TransferRow row) which) async {
    for (final row
        in _rows.values.where((r) => r.status.isActive && which(r)).toList()) {
      await pause(row.id);
    }
  }

  Future<void> resumeAll(bool Function(TransferRow row) which) async {
    final paused = _rows.values
        .where((r) => r.status == TransferStatus.paused && which(r))
        .toList();
    for (final row in paused) {
      _notBefore.remove(row.id);
      await _save(row.copyWith(status: TransferStatus.queued));
    }
    _emit();
    _pump();
  }

  /// Android ended the time it gives transfers in the background while
  /// Telegrive was off screen, so nothing starts until [appOpened], and
  /// what runs says it waits for the app. A running transfer isn't
  /// stopped: Android freezes the app soon after, which leaves TDLib's work
  /// where it is, and it carries on from there once the app is open, the
  /// way it does when the network comes back, rather than sending its part
  /// again.
  void waitForApp() {
    if (_waitingForApp) return;
    _waitingForApp = true;
    _emit();
  }

  /// Telegrive is on screen again after [waitForApp]: what waited starts,
  /// and what was running carries on.
  void appOpened() {
    if (!_waitingForApp) return;
    _waitingForApp = false;
    _emit();
    _pump();
  }

  /// Lets [ids] run on mobile data: they stop waiting for Wi-Fi and start
  /// now, or as soon as there is a free slot.
  Future<void> useMobileData(Iterable<String> ids) async {
    for (final id in ids) {
      final row = _rows[id];
      if (row == null || !row.wifiOnly) continue;
      await _save(row.copyWith(wifiOnly: false));
    }
    _emit();
    _pump();
  }

  /// Keeps [ids] for Wi-Fi: while the phone is on mobile data they wait,
  /// and those running step back into the queue, as when the phone moves
  /// onto it. [useMobileData] lets them go again.
  Future<void> waitForWifi(Iterable<String> ids) async {
    for (final id in ids) {
      final row = _rows[id];
      if (row == null || row.wifiOnly || !row.status.isPending) continue;
      await _save(row.copyWith(wifiOnly: true));
    }
    _holdForWifi();
    _emit();
    _pump();
  }

  /// Rows that wait for Wi-Fi step back into the queue when the phone moves
  /// onto mobile data, and start again once it is on Wi-Fi.
  void _onNetwork(NetworkState next) {
    _network = next;
    _holdForWifi();
    _emit();
    _pump();
  }

  /// Stops every running Wi-Fi-only row while the phone is on mobile data,
  /// the way [pause] does, except that each goes back in the queue to wait
  /// for Wi-Fi rather than for Resume; see [_start]. Losing the network
  /// altogether stops nothing: no data is spent while there is none.
  void _holdForWifi() {
    if (!_network.metered) return;
    final running = _rows.values.where(
      (r) => r.wifiOnly && _running.contains(r.id) && !_holding.contains(r.id),
    );
    for (final row in running.toList()) {
      _holding.add(row.id);
      unawaited(_interrupt(row));
    }
  }

  /// Running transfers say they wait while TDLib has no network, and
  /// retries held for one may go as soon as it has one again, even while
  /// it is still connecting.
  void _onConnection(td.ConnectionState connection) {
    final offline = connection is td.ConnectionStateWaitingForNetwork;
    final back = _offline && !offline;
    if (offline != _offline) {
      _offline = offline;
      _emit();
    }
    if (back || connection is td.ConnectionStateReady) _pump();
  }

  /// Stops whatever TDLib is doing for [row]: abandons the message being
  /// sent, the original being uploaded ahead of its edit, or the file being
  /// fetched.
  Future<void> _interrupt(TransferRow row) async {
    if (row.kind == TransferKind.upload) {
      final chatId = ref.read(driveSessionProvider)?.chatId;
      final pending = _pendingMessages.remove(row.id);
      if (pending != null && chatId != null) {
        await _quietly(() => _messenger.cancel(chatId, pending));
      }
      if (_preliminary.remove(row.id) case final fileId?) {
        await _quietly(
          () => _client.send<td.Ok>(td.CancelPreliminaryUploadFile(fileId: fileId)),
        );
      }
    } else {
      final fileId = _activeDownloads[row.id];
      if (fileId != null) {
        await _quietly(
          () => _client.send<td.Ok>(
            td.CancelDownloadFile(fileId: fileId, onlyIfPending: false),
          ),
        );
      }
    }
  }

  Future<void> retry(String id) async {
    final row = _rows[id];
    if (row == null || !row.status.isFinished) return;
    await _requeue(row);
    _emit();
    _pump();
  }

  /// Queues again every failed transfer [which] picks out, in one go.
  Future<void> retryAll(bool Function(TransferRow row) which) async {
    final failed = _rows.values
        .where((r) => r.status == TransferStatus.failed && which(r))
        .toList();
    for (final row in failed) {
      await _requeue(row);
    }
    _emit();
    _pump();
  }

  Future<void> _requeue(TransferRow row) async {
    _cancelled.remove(row.id);
    _notBefore.remove(row.id);
    _attempts.remove(row.id);
    _retrying.remove(row.id);
    _room.remove(row.id);
    await _save(
      row.copyWith(
        status: TransferStatus.queued,
        error: const Value(null),
        finishedAt: const Value(null),
      ),
    );
  }

  /// Drops [id] from the list. One that hasn't finished is cancelled first,
  /// paused ones included, so no delivered parts of a split upload or
  /// stitched-together download are left behind. One that failed takes the
  /// copies made for it along, since Retry is gone with it.
  Future<void> remove(String id) async {
    final row = _rows[id];
    if (row == null) return;
    if (row.status.isPending) {
      await cancel(id);
    } else if (row.status != TransferStatus.completed) {
      await _dropOwnedFiles(row);
    }
    _rows.remove(id);
    await _db.deleteTransfers([id]);
    _emit();
  }

  Future<void> clearFinished() async {
    final rows = _rows.values.where((r) => r.status.isFinished).toList();
    for (final row in rows) {
      _rows.remove(row.id);
      if (row.status != TransferStatus.completed) await _dropOwnedFiles(row);
    }
    await _db.deleteTransfers([for (final row in rows) row.id]);
    _emit();
  }

  /// Looks again at the phone's free space for the transfers waiting for
  /// room, lets go those it now has room for, and has the rest say what is
  /// free now. Each one checks again as it starts, so one let go on a
  /// guess that was too kind only waits again.
  Future<void> recheckRoom() async {
    if (_room.isNotEmpty) {
      final free = await ref.read(deviceStorageProvider).freeBytes();
      // A phone that can't say how much it has never holds anything back.
      _room.removeWhere((_, wait) => free == null || wait.needed <= free);
      if (free != null) {
        _room.updateAll((_, wait) => WaitingForRoom(wait.needed, free));
      }
      _emit();
      _pump();
    }
    if (_room.isEmpty) {
      _roomTimer?.cancel();
      _roomTimer = null;
    }
  }

  // ---------------------------------------------------------------------------
  // Scheduling
  // ---------------------------------------------------------------------------

  void _pump() {
    // Home can show the drive before Telegram has started. What is queued
    // meanwhile is saved and waits; opening the drive reads it back and
    // starts it.
    if (!ref.mounted || ref.read(driveSessionProvider) == null) return;
    // Saves to the phone can be thousands deep; anything else goes first.
    int rank(TransferRow r) => r.origin == TransferOrigin.save ? 1 : 0;
    final now = DateTime.now();
    final queued =
        _rows.values
            .where(
              (r) =>
                  r.status == TransferStatus.queued &&
                  !_running.contains(r.id) &&
                  (!_background || r.origin == TransferOrigin.backup) &&
                  TransferPolicy.mayRun(
                    r,
                    now: now,
                    network: _network,
                    notBefore: _notBeforeOf(r),
                    waitsForNetwork: _offline && _retrying.contains(r.id),
                    hasRoom: !_room.containsKey(r.id),
                    waitsForApp: _waitingForApp,
                  ),
            )
            .toList()
          ..sort((a, b) {
            final byRank = rank(a).compareTo(rank(b));
            return byRank != 0 ? byRank : a.createdAt.compareTo(b.createdAt);
          });

    var copies = _running
        .where((id) => _rows[id]?.origin == TransferOrigin.fromChat)
        .length;
    var uploads =
        _running.where((id) => _rows[id]?.kind == TransferKind.upload).length -
        copies;
    var downloads = _running.length - uploads - copies;
    var saves = _running
        .where((id) => _rows[id]?.origin == TransferOrigin.save)
        .length;

    for (final row in queued) {
      if (row.origin == TransferOrigin.fromChat) {
        if (copies >= _maxCopies) continue;
        copies++;
        _start(row, _copy);
      } else if (row.kind == TransferKind.upload && uploads < _maxUploads) {
        uploads++;
        _start(row, _upload);
      } else if (row.kind == TransferKind.download &&
          downloads < _maxDownloads) {
        if (row.origin == TransferOrigin.save) {
          if (saves >= _maxSaves) continue;
          saves++;
        }
        downloads++;
        _start(row, _download);
      }
    }
  }

  void _start(TransferRow row, Future<void> Function(TransferRow row) work) {
    _running.add(row.id);
    _cancelled.remove(row.id);
    _notBefore.remove(row.id);
    _retrying.remove(row.id);
    unawaited(() async {
      try {
        final running = row.copyWith(status: TransferStatus.running);
        await _save(running);
        _emit();
        await work(running);
      } catch (e, stack) {
        final wait = telegramWaitOf(e);
        final attempt = _attempts[row.id] ?? 0;
        if (_pausing.contains(row.id)) {
          await _save(
            (_rows[row.id] ?? row).copyWith(status: TransferStatus.paused),
          );
          _emit();
        } else if (_holding.contains(row.id)) {
          // On mobile data now: back in the queue with the parts and bytes
          // it has, until Wi-Fi.
          await _save(
            (_rows[row.id] ?? row).copyWith(status: TransferStatus.queued),
          );
          _emit();
        } else if (e is _NeedsRoom && !_cancelled.contains(row.id)) {
          await _waitForRoom(row, e);
        } else if (wait != null && !_cancelled.contains(row.id)) {
          await _waitOut(row, wait, e);
        } else if (isTransientTransferError(e) &&
            attempt < _retryAfter.length &&
            !_cancelled.contains(row.id)) {
          await _retryLater(row, e, attempt);
        } else if (!_cancelled.contains(row.id)) {
          debugPrint('[Transfers] ${row.name} failed: $e\n$stack');
          final current = _rows[row.id] ?? row;
          await _finish(
            current.copyWith(
              status: TransferStatus.failed,
              error: Value(describeTransferError(e)),
            ),
            error: e,
          );
        }
      } finally {
        _running.remove(row.id);
        _pausing.remove(row.id);
        _holding.remove(row.id);
        _pendingMessages.remove(row.id);
        _activeDownloads.remove(row.id);
        _tracked.removeWhere((_, t) => t.transferId == row.id);
        _pump();
      }
    }());
  }

  /// Telegram asked for a pause. The transfer goes back in the queue with
  /// the parts and bytes it has, and starts again by itself once the time
  /// is up, rather than failing halfway. An upload's pause holds every
  /// upload; see [_uploadsNotBefore].
  Future<void> _waitOut(TransferRow row, Duration wait, Object error) async {
    // TDLib keeps the message that failed to send, under a new id. It never
    // reached the channel, so deleting it only drops that local copy.
    final chatId = ref.read(driveSessionProvider)?.chatId;
    if (error is SendFailed && chatId != null) {
      await _quietly(
        () => _messenger.deleteMessages(chatId, [error.failedMessageId]),
      );
    }
    // Cancelled meanwhile: there is nothing left to wait for.
    if (_cancelled.contains(row.id)) return;
    await _save((_rows[row.id] ?? row).copyWith(status: TransferStatus.queued));
    // A second over what was asked, so the next try doesn't land early.
    final until = DateTime.now().add(waitUnit * (wait.inSeconds + 1));
    if (row.kind == TransferKind.download) {
      _notBefore[row.id] = until;
    } else if (!(_uploadsNotBefore?.isAfter(until) ?? false)) {
      _uploadsNotBefore = until;
    }
    _scheduleWake();
    _emit();
  }

  /// The phone lacks the room [row] is about to write into. It goes back in
  /// the queue with the parts and bytes it has, says what it needs, and
  /// starts again once [recheckRoom] finds the room: every minute, when the
  /// app comes back, and after something is deleted to free space. It
  /// doesn't count as in flight meanwhile, so nothing stays awake for it.
  Future<void> _waitForRoom(TransferRow row, _NeedsRoom need) async {
    await _save((_rows[row.id] ?? row).copyWith(status: TransferStatus.queued));
    _room[row.id] = WaitingForRoom(need.needed, need.free);
    _roomTimer ??= Timer.periodic(
      _roomRecheck,
      (_) => unawaited(recheckRoom()),
    );
    _emit();
  }

  /// Ends the work for a transfer before it writes what needs [needed]
  /// bytes free, when the phone has less; see [_waitForRoom].
  Future<void> _ensureRoom(int needed) async {
    final short = await Room.shortfall(ref.read(deviceStorageProvider), needed);
    if (short != null) throw _NeedsRoom(short.$1, short.$2);
  }

  /// The connection let [row] down for a moment: a request timed out, or a
  /// socket closed. The transfer goes back in the queue with the parts and
  /// bytes it has, and tries again after a wait that grows with each try,
  /// and not before Telegram has a network again.
  Future<void> _retryLater(TransferRow row, Object error, int attempt) async {
    final chatId = ref.read(driveSessionProvider)?.chatId;
    if (error is SendFailed && chatId != null) {
      await _quietly(
        () => _messenger.deleteMessages(chatId, [error.failedMessageId]),
      );
    }
    if (_cancelled.contains(row.id)) return;
    debugPrint('[Transfers] ${row.name} will be tried again: $error');
    _attempts[row.id] = attempt + 1;
    _retrying.add(row.id);
    _notBefore[row.id] = DateTime.now().add(waitUnit * _retryAfter[attempt]);
    await _save((_rows[row.id] ?? row).copyWith(status: TransferStatus.queued));
    _scheduleWake();
    _emit();
  }

  /// When [row] may start: after its own next try is due, and for an upload
  /// not before every upload may go again.
  DateTime? _notBeforeOf(TransferRow row) {
    final own = _notBefore[row.id];
    final uploads = row.kind == TransferKind.upload ? _uploadsNotBefore : null;
    if (own == null || uploads == null) return own ?? uploads;
    return own.isAfter(uploads) ? own : uploads;
  }

  /// What [row] is waiting for at [now], if anything. Telegram's pause comes
  /// first, since nothing starts before it is over. Room comes next, since
  /// only the person can make it. Then Wi-Fi: it can
  /// take hours, so a row waiting for it is held even when it is also due
  /// another try, and Use mobile data can let it go. Each of those holds a
  /// row with Telegrive open too; one free of them waits for the app while
  /// Android has the background time ended, running or not. A row being
  /// tried again says it waits for the network only while TDLib has none
  /// or its wait before the next try is running; after that it only waits
  /// for a free slot.
  TransferWait? _waitOf(TransferRow row, DateTime now) {
    switch (row.status) {
      case TransferStatus.queued:
        final retrying = _retrying.contains(row.id);
        final telegram = row.kind == TransferKind.upload
            ? _uploadsNotBefore
            : (retrying ? null : _notBefore[row.id]);
        if (telegram != null && telegram.isAfter(now)) {
          return WaitingForTelegram(telegram);
        }
        if (_room[row.id] case final room?) return room;
        if (TransferPolicy.waitsForWifi(row, _network)) {
          return const WaitingForWifi();
        }
        if (_waitingForApp) return const WaitingForApp();
        if (retrying &&
            (_offline || (_notBefore[row.id]?.isAfter(now) ?? false))) {
          return const WaitingForNetwork();
        }
        return null;
      case TransferStatus.running:
        if (_waitingForApp) return const WaitingForApp();
        return _offline ? const WaitingForNetwork() : null;
      default:
        return null;
    }
  }

  /// Sets one timer for the next transfer whose wait is over.
  void _scheduleWake() {
    _wakeTimer?.cancel();
    _wakeTimer = null;
    final now = DateTime.now();
    _notBefore.removeWhere((_, at) => !at.isAfter(now));
    if (!(_uploadsNotBefore?.isAfter(now) ?? false)) _uploadsNotBefore = null;
    final waits = [..._notBefore.values, ?_uploadsNotBefore];
    if (waits.isEmpty) return;
    final next = waits.reduce((a, b) => a.isBefore(b) ? a : b);
    _wakeTimer = Timer(next.difference(now), () {
      _wakeTimer = null;
      _scheduleWake();
      _pump();
      _emit();
    });
  }

  // ---------------------------------------------------------------------------
  // Uploading
  // ---------------------------------------------------------------------------

  Future<void> _upload(TransferRow initial, {td.Message? resume}) async {
    final session = ref.read(driveSessionProvider);
    if (session == null) throw const DriveException('Your drive is not open.');

    final source = initial.sourcePath == null
        ? null
        : File(initial.sourcePath!);
    if (_replacing.contains(initial.id)) return _replaceSmallCopy(initial, source);
    final stager = _stagers[initial.id];
    final stage = source != null && stager != null && !await source.exists();
    if (stage) {
      // Kept until there is room, so a transfer waiting for it can still
      // make its copy.
      await _ensureRoom(Room.forStage(initial.totalBytes));
      _stagers.remove(initial.id);
      initial = await _stage(initial, source, stager);
    }
    // Cancelled while the file was being prepared: nothing has gone yet. The
    // cancel could not delete a copy still being written, so it goes here.
    if (_cancelled.contains(initial.id)) {
      await _dropOwnedFiles(initial);
      return;
    }
    final hasSource = source != null && await source.exists();
    if (!hasSource && resume == null) {
      throw const DriveException('The original file is no longer available.');
    }
    // A copy cut short, by Android stopping the app as it was made, say, or
    // an original changed since it was added: what would go up is not the
    // file that was picked, so nothing is sent.
    if (hasSource &&
        !stage &&
        initial.totalBytes > 0 &&
        await source.length() != initial.totalBytes) {
      throw DriveException(_notWhole(initial));
    }
    // A video or audio file says how long it runs, so the caption can carry
    // it. Nothing is read for other kinds, and a file that won't say keeps
    // going without.
    if (hasSource && initial.durationSeconds == null) {
      final kind = FileKind.detect(
        fileName: initial.name,
        mimeType: initial.mimeType,
      );
      if (kind == FileKind.video || kind == FileKind.audio) {
        final seconds = await MediaProbe.durationSeconds(source.path);
        if (seconds != null) {
          initial = initial.copyWith(durationSeconds: Value(seconds));
          await _save(initial);
        }
      }
    }

    final limit = session.isPremium
        ? SplitPolicy.premiumLimit
        : SplitPolicy.regularLimit;
    final partCount = initial.completedParts > 0
        ? initial.partCount
        : SplitPolicy.partCountFor(initial.totalBytes, limit: limit);
    var row = initial.copyWith(partCount: partCount);
    await _save(row);

    // Parts that already reached the channel — delivered by TDLib while the
    // app was away, say — are not sent twice.
    final landed = {
      for (final part in await _repository.partsOf(row.fileId)) part.partIndex,
    };

    for (var index = row.completedParts; index < partCount; index++) {
      if (_cancelled.contains(row.id)) return;
      _stopIfPausing(row.id);
      final base = partCount == 1 ? 0 : SplitPolicy.offsetOf(index);
      if (landed.contains(index) &&
          !(resume != null && index == row.completedParts)) {
        final partEnd = partCount == 1
            ? row.totalBytes
            : base + SplitPolicy.sizeOf(index, row.totalBytes);
        row = row.copyWith(completedParts: index + 1, doneBytes: partEnd);
        await _save(row);
        continue;
      }

      final td.Message delivered;
      if (resume != null && index == row.completedParts) {
        _pendingMessages[row.id] = resume.id;
        _trackMessage(resume, row.id, base);
        delivered = await _messenger.awaitDelivery(resume.id);
      } else {
        _stopIfUploadsWait();
        final String path;
        if (partCount == 1) {
          path = source!.path;
        } else {
          await _ensureRoom(
            Room.forPart(SplitPolicy.sizeOf(index, row.totalBytes)),
          );
          path = await _writePart(row, source!, index);
        }
        final manifest = FileManifest(
          id: row.fileId,
          name: row.name,
          folderId: row.folderId,
          mimeType: row.mimeType,
          size: row.totalBytes,
          createdAt: row.createdAt,
          modifiedAt: row.createdAt,
          partCount: partCount,
          partIndex: index,
          takenAt: row.takenAt,
          durationSeconds: row.durationSeconds,
          originalSize: _smallCopyOf[row.id],
          starred: row.starred ?? false,
          albums: row.albumIds?.split(',') ?? const [],
        );
        // The first part says what the file is; the others only whose part
        // they are, so a rename or move later edits one message.
        final caption = index == 0
            ? await _repository.fileCaption(manifest)
            : ManifestCodec.encodePart(
                PartRecord(
                  fileId: row.fileId,
                  index: index,
                  count: partCount,
                  size: row.totalBytes,
                ),
              );
        final thumbnail = index == 0 ? row.thumbnailPath : null;
        try {
          // Cancelled while the part was being written: it isn't sent.
          if (_cancelled.contains(row.id)) return;
          _stopIfPausing(row.id);
          _stopIfUploadsWait();
          delivered = await _messenger.sendDocument(
            session.chatId,
            path: path,
            caption: caption,
            thumbnailPath: thumbnail != null && await File(thumbnail).exists()
                ? thumbnail
                : null,
            onPending: (pending) {
              _pendingMessages[row.id] = pending.id;
              _trackMessage(pending, row.id, base);
              // Paused, or held for Wi-Fi, in the moment the send was
              // starting.
              if (_stopping(row.id)) unawaited(_interrupt(row));
            },
          );
        } finally {
          if (partCount > 1) await _deleteQuietly(File(path));
        }
      }

      _pendingMessages.remove(row.id);
      await _repository.ingest(delivered);
      // Cancelled, or removed from the list, as the part landed or while it
      // was being indexed: too late for the send to be stopped, so it and
      // any parts before it are taken back out, rather than leave half a
      // file in the channel. Saving now would bring the row back.
      if (_cancelled.contains(row.id)) {
        await _quietly(() => _repository.deleteFileById(row.fileId));
        return;
      }
      final partEnd = partCount == 1
          ? row.totalBytes
          : base + SplitPolicy.sizeOf(index, row.totalBytes);
      row = (_rows[row.id] ?? row).copyWith(
        completedParts: index + 1,
        doneBytes: math.min(row.totalBytes, partEnd),
      );
      await _save(row);
      // A part that lands is progress, so the tries start counting afresh.
      _attempts.remove(row.id);
    }

    if (_cancelled.contains(row.id)) return;
    await _finish(row.copyWith(status: TransferStatus.completed));
    // The file this one replaces goes to the trash only now that the new
    // one is in the drive, so a failed or cancelled upload leaves it be. One
    // already gone or trashed needs nothing more, and any other failure is
    // the drive's to report: the upload itself is through.
    if (row.replacesFileId case final old?) {
      await _quietly(
        () => _repository.replaceWith(oldFileId: old, newFileId: row.fileId),
      );
    }
    await _dropOwnedFiles(row);
  }

  /// Uploads the original photo behind [row] ahead, then has TDLib put it
  /// in place of the small copy [row] names, in the same message, through
  /// [DriveRepository.replaceSmallCopy]. Progress comes from TDLib's file
  /// for the upload, and TDLib answers the edit only once the upload is
  /// done. Pausing, holding for Wi-Fi or cancelling calls the upload off;
  /// should TDLib finish the edit regardless, the original is in and the
  /// row completes. A file Telegram wouldn't edit comes back under a new
  /// id, which the row takes. Cancelling never takes the small copy out of
  /// the drive.
  Future<void> _replaceSmallCopy(TransferRow row, File? source) async {
    if (_cancelled.contains(row.id)) {
      await _dropOwnedFiles(row);
      return;
    }
    if (source == null || !await source.exists()) {
      throw const DriveException('The original file is no longer available.');
    }
    if (row.totalBytes > 0 && await source.length() != row.totalBytes) {
      throw DriveException(_notWhole(row));
    }
    _stopIfPausing(row.id);
    _stopIfUploadsWait();
    final upload = await _client.send<td.File>(
      td.PreliminaryUploadFile(
        file: td.InputFileLocal(path: source.path),
        fileType: const td.FileTypeDocument(),
        priority: 1,
      ),
    );
    _tracked[upload.id] = _Tracked(row.id, 0, upload: true);
    _preliminary[row.id] = upload.id;
    // Paused, held for Wi-Fi or cancelled in the moment the upload started.
    if (_stopping(row.id) || _cancelled.contains(row.id)) await _interrupt(row);
    if (_cancelled.contains(row.id)) return;
    _stopIfPausing(row.id);
    final String fileId;
    try {
      fileId = await _repository.replaceSmallCopy(
        row.fileId,
        tdFileId: upload.id,
        path: source.path,
        size: row.totalBytes,
        thumbnailPath: row.thumbnailPath != null && await File(row.thumbnailPath!).exists()
            ? row.thumbnailPath
            : null,
      );
    } finally {
      _preliminary.remove(row.id);
    }
    // Cancelled as the original landed: it is in the drive in the small
    // copy's place, which loses nothing, so it stays; saving now would
    // bring the row back.
    if (_cancelled.contains(row.id)) return;
    await _finish(
      (_rows[row.id] ?? row).copyWith(
        fileId: fileId,
        status: TransferStatus.completed,
        doneBytes: row.totalBytes,
        completedParts: 1,
      ),
    );
    await _dropOwnedFiles(row);
  }

  /// Has Telegram copy [row]'s message into the channel with the drive's
  /// manifest as its caption, in one request, or waits for the copy TDLib
  /// is still making when the app last stopped ([resume]). The copy keeps
  /// the message's date, which a photo or video also keeps as when it was
  /// taken. A flood wait ends the run like any upload's, to wait in the
  /// queue.
  Future<void> _copy(TransferRow row, {td.Message? resume}) async {
    final session = ref.read(driveSessionProvider);
    if (session == null) throw const DriveException('Your drive is not open.');
    // Cancelled as the copy was starting: nothing has been asked of Telegram.
    if (_cancelled.contains(row.id)) return;
    try {
      final td.Message delivered;
      if (resume != null) {
        _pendingMessages[row.id] = resume.id;
        delivered = await _messenger.awaitDelivery(resume.id);
      } else {
        final kind = FileKind.detect(
          fileName: row.name,
          mimeType: row.mimeType,
        );
        final manifest = FileManifest(
          id: row.fileId,
          name: row.name,
          folderId: row.folderId,
          mimeType: row.mimeType,
          size: row.totalBytes,
          createdAt: row.takenAt ?? row.createdAt,
          modifiedAt: DateTime.now(),
          takenAt: kind == FileKind.image || kind == FileKind.video
              ? row.takenAt
              : null,
        );
        delivered = await _messenger.sendCopy(
          session.chatId,
          fromChatId: row.sourceChatId!,
          messageId: row.sourceMessageId!,
          caption: await _repository.fileCaption(manifest),
          onPending: (pending) {
            _pendingMessages[row.id] = pending.id;
            // Paused in the moment the copy was starting.
            if (_pausing.contains(row.id)) unawaited(_interrupt(row));
          },
        );
      }
      _pendingMessages.remove(row.id);
      await _repository.ingest(delivered);
      // Cancelled as the copy landed: it is whole, so it stays in the drive,
      // and saving now would bring the row back.
      if (_cancelled.contains(row.id)) return;
      await _finish(
        (_rows[row.id] ?? row).copyWith(
          status: TransferStatus.completed,
          doneBytes: row.totalBytes,
          completedParts: 1,
        ),
      );
    } finally {
      await Future<void>.delayed(_copyGap);
    }
  }

  /// Ends the work for [id] if it was asked to pause, or to step back and
  /// wait for Wi-Fi.
  void _stopIfPausing(String id) {
    if (_stopping(id)) throw const DriveException('Paused.');
  }

  bool _stopping(String id) => _pausing.contains(id) || _holding.contains(id);

  /// Ends an upload's run before it sends another part while Telegram has
  /// every upload waiting: the part would go up in full only to be turned
  /// away at the end. The run goes back in the queue with the parts it has,
  /// as if turned away itself.
  void _stopIfUploadsWait() {
    final left = _uploadsNotBefore?.difference(DateTime.now());
    if (left == null || left <= Duration.zero) return;
    final seconds = left.inMicroseconds ~/ waitUnit.inMicroseconds;
    throw TelegramException(429, 'Too Many Requests: retry after $seconds');
  }

  /// Copies a picked content URI into staging, where TDLib can read it.
  /// The copy is written under a `.part` name and only takes the file's
  /// name once it is whole, so one cut short is never taken for the file;
  /// see [_load].
  Future<TransferRow> _stage(
    TransferRow row,
    File target,
    Stream<List<int>> Function() openRead,
  ) async {
    _preparing.add(row.id);
    _emit();
    final partial = File('${target.path}.part');
    try {
      await target.parent.create(recursive: true);
      await openRead().pipe(partial.openWrite());
      await partial.rename(target.path);
      final staged = row.copyWith(totalBytes: await target.length());
      await _save(staged);
      return staged;
    } catch (_) {
      await _deleteQuietly(partial);
      rethrow;
    } finally {
      _preparing.remove(row.id);
      _emit();
    }
  }

  /// Why [row]'s file can't be sent as it is: Telegrive's own copy of it
  /// was cut short, or the original changed after it was added.
  static String _notWhole(TransferRow row) => row.ownsSource
      ? 'The copy of ${row.name} was interrupted. Share or pick it again.'
      : '${row.name} has changed since it was added. Add it again.';

  /// Deletes the copies Telegrive made for [row]: its own copy of the file,
  /// with the folder it came in when that is one of the app's and holds
  /// nothing else, its thumbnail, and any split part still on disk.
  /// Originals are never touched.
  Future<void> _dropOwnedFiles(TransferRow row) async {
    final source = row.sourcePath;
    try {
      if (row.ownsSource && source != null) {
        await _deleteQuietly(File(source));
        final folder = File(source).parent;
        final temp = (await getTemporaryDirectory()).path;
        if (leftoverDirs.any(
          (dir) => p.isWithin(p.join(temp, dir), folder.path),
        )) {
          try {
            // Not recursive: the file picker can put two picks in one folder.
            await folder.delete();
          } on FileSystemException catch (_) {
            // It holds another file still in use.
          }
        }
      }
      if (row.thumbnailPath != null) {
        await _deleteQuietly(File(row.thumbnailPath!));
      }
      if (row.kind == TransferKind.upload && row.partCount > 1) {
        await _deleteQuietly(await _partsDir(row.id));
      }
    } catch (e) {
      debugPrint('[Transfers] Could not tidy up after ${row.name}: $e');
    }
  }

  static Future<Directory> _stagingDir() async {
    final temp = await getTemporaryDirectory();
    return Directory(p.join(temp.path, 'telegrive-staging'));
  }

  void _trackMessage(td.Message pending, String transferId, int base) {
    final file = MessageIndexer.mediaFile(pending);
    if (file == null) return;
    _tracked[file.id] = _Tracked(transferId, base, upload: true);
  }

  /// Copies one slice of [source] to a temporary file named like
  /// `movie.mkv.003`, which is the name Telegram will show for that part.
  Future<String> _writePart(TransferRow row, File source, int index) async {
    final dir = await _partsDir(row.id);
    await dir.create(recursive: true);
    final out = File(p.join(dir.path, SplitPolicy.partName(row.name, index)));
    final start = SplitPolicy.offsetOf(index);
    final end = start + SplitPolicy.sizeOf(index, row.totalBytes);
    await source.openRead(start, end).pipe(out.openWrite());
    return out.path;
  }

  Future<Directory> _partsDir(String transferId) async {
    final temp = await getTemporaryDirectory();
    return Directory(p.join(temp.path, 'telegrive-parts', transferId));
  }

  // ---------------------------------------------------------------------------
  // Downloading
  // ---------------------------------------------------------------------------

  Future<void> _download(TransferRow initial) async {
    final parts = await _repository.partsOf(initial.fileId);
    if (parts.isEmpty) {
      throw const DriveException('This file is no longer in your drive.');
    }

    // Backed up from this phone and still in its gallery: nothing to fetch.
    if (initial.saveTo == SaveTarget.gallery) {
      final assetId = await _db.localAssetOf(initial.fileId);
      if (assetId != null &&
          await ref.read(deviceStorageProvider).inGallery(assetId)) {
        await _finish(
          initial.copyWith(
            status: TransferStatus.completed,
            doneBytes: initial.totalBytes,
            completedParts: initial.partCount,
          ),
        );
        return;
      }
    }

    if (parts.length == 1) {
      await _ensureRoom(
        Room.forDownload(
          size: initial.totalBytes,
          alreadyHere: initial.doneBytes,
          split: false,
          largestPart: parts.single.size,
          keepsCopy: initial.saveTo != null,
        ),
      );
      final downloaded = await _downloadPart(initial, parts.first, base: 0);
      var row = (_rows[initial.id] ?? initial).copyWith(
        status: TransferStatus.completed,
        doneBytes: initial.totalBytes,
        completedParts: 1,
        resultPath: Value(downloaded.path),
      );
      if (row.saveTo != null) {
        row = await _keep(row, downloaded.path);
        // The saved copy is the one that counts; TDLib's would only double
        // the space a whole drive takes. Unless something else is reading it.
        if (!_otherDownloadOf(row)) {
          await _quietly(
            () => _client.send<td.Ok>(td.DeleteFile(fileId: downloaded.id)),
          );
        }
      }
      if (_cancelled.contains(initial.id)) return;
      await _finish(row);
      return;
    }

    // Split files are stitched back together as the parts arrive, and each
    // part's cached copy is dropped straight after so peak disk use stays
    // around one part over the file's own size.
    final out = File(
      p.join((await downloadsDirectory()).path, initial.fileId, initial.name),
    );
    await out.parent.create(recursive: true);
    // Parts already stitched in before a pause or a restart are kept.
    var done = 0;
    var base = 0;
    if (initial.completedParts > 0 && await out.exists()) {
      final expected = parts
          .take(initial.completedParts)
          .fold<int>(0, (sum, part) => sum + part.size);
      if (await out.length() == expected) {
        done = initial.completedParts;
        base = expected;
      }
    }
    await _ensureRoom(
      Room.forDownload(
        size: initial.totalBytes,
        alreadyHere: base,
        split: true,
        largestPart: parts.map((part) => part.size).reduce(math.max),
        keepsCopy: initial.saveTo != null,
      ),
    );
    final sink = out.openWrite(
      mode: done > 0 ? FileMode.append : FileMode.write,
    );
    try {
      for (final (index, part) in parts.indexed) {
        if (index < done) continue;
        if (_cancelled.contains(initial.id)) break;
        _stopIfPausing(initial.id);
        // Room for this part's download, as what else the phone holds may
        // have grown since the start.
        await _ensureRoom(Room.forPart(part.size));
        final downloaded = await _downloadPart(initial, part, base: base);
        await sink.addStream(File(downloaded.path).openRead());
        if (_cancelled.contains(initial.id)) break;
        base += part.size;
        await _save(
          (_rows[initial.id] ?? initial).copyWith(
            completedParts: index + 1,
            doneBytes: base,
          ),
        );
        _attempts.remove(initial.id);
        await _quietly(
          () => _client.send<td.Ok>(td.DeleteFile(fileId: part.tdFileId)),
        );
      }
    } finally {
      await sink.close();
      // Cancelled mid-part as well as between parts: the stitched copy is
      // no use without the rest.
      if (_cancelled.contains(initial.id)) await _deleteQuietly(out.parent);
    }
    if (_cancelled.contains(initial.id)) return;
    var row = (_rows[initial.id] ?? initial).copyWith(
      status: TransferStatus.completed,
      doneBytes: initial.totalBytes,
      resultPath: Value(out.path),
    );
    if (row.saveTo != null) {
      try {
        row = await _keep(row, out.path);
      } finally {
        await _deleteQuietly(out.parent);
      }
    }
    if (_cancelled.contains(initial.id)) return;
    await _finish(row);
  }

  /// Copies a finished download to where its save transfer keeps it, and
  /// points the row at the copy. A JPEG under another extension, a small
  /// copy of a HEIC photo say, is saved as .jpg, so the gallery and other
  /// apps read it for what it holds.
  Future<TransferRow> _keep(TransferRow row, String path) async {
    final storage = ref.read(deviceStorageProvider);
    final extension = p.extension(row.name).toLowerCase();
    final name = row.mimeType == 'image/jpeg' && extension != '.jpg' && extension != '.jpeg'
        ? p.setExtension(row.name, '.jpg')
        : row.name;
    switch (row.saveTo!) {
      case SaveTarget.files:
        final saved = await storage.saveFile(
          path,
          folders: row.saveFolder?.split('/') ?? const [],
          name: name,
          mimeType: row.mimeType,
        );
        return row.copyWith(resultPath: Value(saved));
      case SaveTarget.gallery:
        final kind = FileKind.detect(
          fileName: row.name,
          mimeType: row.mimeType,
        );
        final assetId = await storage.saveToGallery(
          path,
          name: name,
          video: kind == FileKind.video,
          album: row.saveFolder,
          takenAt: row.takenAt,
        );
        // Backup now knows this photo is already in the drive, and the
        // Photos tab can show the phone's sharp copy of it.
        await _db.markAssetBackedUp(assetId, row.fileId);
        return row.copyWith(resultPath: const Value(null));
      case SaveTarget.offline:
        final dir = Directory(
          p.join((await offlineDirectory()).path, row.fileId),
        );
        await dir.create(recursive: true);
        final copy = File(p.join(dir.path, DeviceStorage.safeName(name)));
        await File(path).copy(copy.path);
        await _db.saveOfflineCopy(row.fileId, copy.path, await copy.length());
        return row.copyWith(resultPath: Value(copy.path));
    }
  }

  /// Another download of the same file is running (someone opened it while
  /// it was being saved), so TDLib's copy must stay.
  bool _otherDownloadOf(TransferRow row) => _rows.values.any(
    (r) =>
        r.id != row.id &&
        r.kind == TransferKind.download &&
        r.fileId == row.fileId &&
        r.status.isActive,
  );

  Future<({String path, int id})> _downloadPart(
    TransferRow row,
    PartRow part, {
    required int base,
  }) async {
    final tdFile = await _resolveTdFile(part);
    if (tdFile.local.isDownloadingCompleted &&
        await File(tdFile.local.path).exists()) {
      return (path: tdFile.local.path, id: tdFile.id);
    }
    _tracked[tdFile.id] = _Tracked(row.id, base, upload: false);
    _activeDownloads[row.id] = tdFile.id;
    try {
      // Paused, or held for Wi-Fi, while the file was being looked up.
      _stopIfPausing(row.id);
      // Synchronous mode answers only once the file is complete (or the
      // download was cancelled), which is exactly what this needs.
      final done = await _client.send<td.File>(
        td.DownloadFile(
          fileId: tdFile.id,
          priority: 16,
          offset: 0,
          limit: 0,
          synchronous: true,
        ),
        timeout: const Duration(days: 2),
      );
      if (!done.local.isDownloadingCompleted) {
        throw const DriveException('The download stopped before finishing.');
      }
      return (path: done.local.path, id: done.id);
    } finally {
      _tracked.remove(tdFile.id);
      _activeDownloads.remove(row.id);
    }
  }

  Future<td.File> _resolveTdFile(PartRow part) =>
      _repository.resolveTdFile(part);

  static Future<Directory> downloadsDirectory() async {
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'downloads'));
  }

  /// Copies kept available offline. Clearing opened files leaves it alone.
  static Future<Directory> offlineDirectory() async {
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'offline'));
  }

  // ---------------------------------------------------------------------------
  // Progress & persistence
  // ---------------------------------------------------------------------------

  void _onFileUpdate(td.File file) {
    final tracked = _tracked[file.id];
    if (tracked == null) return;
    final row = _rows[tracked.transferId];
    if (row == null || !row.status.isActive) return;
    final partBytes = tracked.upload
        ? file.remote.uploadedSize
        : file.local.downloadedSize;
    final done = math.min(row.totalBytes, tracked.baseBytes + partBytes);
    if (done == row.doneBytes) return;
    _rows[row.id] = row.copyWith(doneBytes: done);
    _scheduleEmit();
  }

  /// An upload that was interrupted can still land — TDLib resumes sends
  /// after a restart. When its file shows up complete, close it out. The
  /// original of a small copy counts only once the file holds it: the
  /// small copy is in the drive all along, and a star or rename of it is
  /// indexed too.
  Future<void> _onIngested(String fileId) async {
    final matches = _rows.values.where(
      (r) =>
          r.kind == TransferKind.upload &&
          r.fileId == fileId &&
          !_running.contains(r.id) &&
          r.status != TransferStatus.completed &&
          r.status != TransferStatus.cancelled,
    );
    if (matches.isEmpty) return;
    final file = await _repository.fileById(fileId);
    if (file == null || !await _repository.isWhole(fileId)) return;
    for (final row in matches.toList()) {
      if (_replacing.contains(row.id) &&
          (file.isSmallCopy || file.size != row.totalBytes)) {
        continue;
      }
      await _finish(
        row.copyWith(
          status: TransferStatus.completed,
          doneBytes: row.totalBytes,
          completedParts: row.partCount,
        ),
      );
    }
  }

  Future<void> _load() async {
    try {
      await _loadRows();
    } finally {
      if (!_ready.isCompleted) _ready.complete();
    }
  }

  Future<void> _loadRows() async {
    _rows.clear();
    for (final row in await _db.allTransfers()) {
      // The person's own transfers wait for the app, untouched.
      if (_background && row.origin != TransferOrigin.backup) continue;
      _rows[row.id] = row;
    }

    final chatId = ref.read(driveSessionProvider)?.chatId;
    List<td.Message> pending = const [];
    if (chatId != null) {
      try {
        pending = await _messenger.pendingMessages(chatId);
      } catch (e) {
        debugPrint('[Transfers] Could not read pending messages: $e');
      }
    }

    for (final row in _rows.values.toList()) {
      if (!row.status.isActive) continue;
      if (row.kind == TransferKind.download) {
        await _save(row.copyWith(status: TransferStatus.queued));
        continue;
      }
      // Its copy was still being made when the app stopped, so only part of
      // the file is on the phone, under the copy's temporary name.
      final source = row.sourcePath;
      final partial = source == null ? null : File('$source.part');
      if (partial != null &&
          !await File(source!).exists() &&
          await partial.exists()) {
        await _deleteQuietly(partial);
        await _finish(
          row.copyWith(
            status: TransferStatus.failed,
            error: Value(_notWhole(row)),
          ),
        );
        continue;
      }
      // In the drive whole: it landed while the app was away. A split file
      // with a part still to go isn't, and carries on from its last part.
      if (await _repository.isWhole(row.fileId)) {
        await _finish(row.copyWith(status: TransferStatus.completed));
        continue;
      }
      final copy = row.origin == TransferOrigin.fromChat;
      final resumable = pending.where((m) {
        // A copy keeps the kind of message it was made from; an upload is
        // always a document.
        final caption = copy
            ? MessageIndexer.describe(m)?.caption
            : switch (m.content) {
                td.MessageDocument(:final caption) => caption.text,
                _ => null,
              };
        if (caption == null) return false;
        final part = ManifestCodec.partOf(caption);
        return part?.fileId == row.fileId && part?.index == row.completedParts;
      }).firstOrNull;
      if (resumable != null &&
          resumable.sendingState is td.MessageSendingStatePending) {
        // Known before the run takes the send up, so a hold for Wi-Fi in
        // the meantime still stops TDLib sending it.
        _pendingMessages[row.id] = resumable.id;
        // The caption of a small copy carries its original's size, so one
        // still going out stays a small copy: exempt from the Wi-Fi rule
        // for originals, and sent again with its mark if it is held.
        if (resumable.content case td.MessageDocument(:final caption)) {
          final original = ManifestCodec.decodeFile(caption.text)?.originalSize;
          if (original != null) _smallCopyOf[row.id] = original;
        }
        _start(
          row,
          (running) => copy
              ? _copy(running, resume: resumable)
              : _upload(running, resume: resumable),
        );
      } else if (row.origin == TransferOrigin.backup || row.origin == TransferOrigin.takeout) {
        // Photo backup and the Google Photos import re-queue these
        // themselves on their next pass.
        _rows.remove(row.id);
        await _db.deleteTransfers([row.id]);
      } else {
        await _save(row.copyWith(status: TransferStatus.queued));
      }
    }
    // TDLib carries on with a send on its own after a restart, mobile data
    // or not.
    _holdForWifi();
    _emit();
    _pump();
    // The job doesn't know the person's transfers, so it can't tell what
    // they still use from what is left over.
    if (!_background) unawaited(_sweepOnOpen());
  }

  /// Clears the [leftovers] once the drive has opened and its transfers are
  /// read, so whatever they still use stays.
  Future<void> _sweepOnOpen() async {
    try {
      final freed = await clearLeftovers();
      if (freed > 0) {
        debugPrint('[Transfers] Deleted $freed bytes of leftover copies');
      }
    } catch (e) {
      debugPrint('[Transfers] Could not sweep leftover copies: $e');
    }
  }

  /// What the transfers that haven't finished still use, as
  /// [AppDatabase.pathsInUse] reads it, with the folder a split upload
  /// cuts its parts into and the files the share sheet is holding.
  Future<Set<String>> pathsInUse() async {
    final keep = {
      ...await _db.pathsInUse(),
      for (final file in ref.read(shareIntakeProvider)) ?file.path,
    };
    // A snapshot, since transfers can be added while the parts folders are
    // looked up.
    for (final row in _rows.values.toList()) {
      if (row.status == TransferStatus.completed ||
          row.status == TransferStatus.cancelled) {
        continue;
      }
      keep.add((await _partsDir(row.id)).path);
    }
    return keep;
  }

  /// The copies made for uploads that nothing needs any more, with the
  /// bytes in each: those of transfers that are gone, those left when the
  /// app was stopped as it made them, and the channel photo from setting up
  /// the drive. Nothing in [pathsInUse] is among them.
  Future<List<Leftover>> leftovers() async {
    final (roots, files) = await _leftoverPlaces();
    return findLeftovers(roots: roots, files: files, keep: await pathsInUse());
  }

  /// Deletes the [leftovers], and returns the bytes it freed. It runs when
  /// the drive opens, from the daily trim and from Space's Clear.
  Future<int> clearLeftovers() async {
    final (roots, files) = await _leftoverPlaces();
    return sweepLeftovers(roots: roots, files: files, keep: await pathsInUse());
  }

  /// Deletes the split files joined back together to open them that no
  /// download is waiting for, those joined more than [olderThan] before
  /// [now], and returns the bytes it freed. Opening one again leaves it as
  /// it was, so its age is how long it has been on the phone.
  Future<int> clearOldDownloads({
    required Duration olderThan,
    DateTime? now,
  }) async {
    final downloads = await downloadsDirectory();
    return sweepLeftovers(
      roots: [downloads],
      keep: {
        for (final row in _rows.values)
          if (row.kind == TransferKind.download && row.status.isPending)
            p.join(downloads.path, row.fileId),
      },
      minAge: olderThan,
      now: now,
    );
  }

  static Future<(List<Directory>, List<File>)> _leftoverPlaces() async {
    final temp = (await getTemporaryDirectory()).path;
    return (
      [for (final dir in leftoverDirs) Directory(p.join(temp, dir))],
      [for (final name in leftoverFiles) File(p.join(temp, name))],
    );
  }

  void _reset() {
    _loadedFor = null;
    _ended.clear();
    // [loaded] waits for the next drive's rows. One still waiting is kept,
    // so whatever waits on it gets them too.
    if (_ready.isCompleted) _ready = Completer<void>();
    _rows.clear();
    _running.clear();
    _holding.clear();
    _attempts.clear();
    _retrying.clear();
    _notBefore.clear();
    _uploadsNotBefore = null;
    _wakeTimer?.cancel();
    _wakeTimer = null;
    _room.clear();
    _roomTimer?.cancel();
    _roomTimer = null;
    _tracked.clear();
    _pendingMessages.clear();
    _activeDownloads.clear();
    _smallCopyOf.clear();
    _replacing.clear();
    _preliminary.clear();
    for (final completer in _completions.values) {
      if (!completer.isCompleted) {
        completer.completeError(const DriveException('Signed out.'));
      }
    }
    _completions.clear();
    state = TransfersState.empty;
  }

  Future<String> _completionOf(String id) =>
      (_completions[id] ??= Completer<String>()).future;

  Future<void> _finish(TransferRow row, {Object? error}) async {
    _notBefore.remove(row.id);
    _attempts.remove(row.id);
    _retrying.remove(row.id);
    _room.remove(row.id);
    _smallCopyOf.remove(row.id);
    _replacing.remove(row.id);
    final finished = row.copyWith(finishedAt: Value(DateTime.now()));
    final keptOffline =
        row.saveTo == SaveTarget.offline &&
        row.status == TransferStatus.completed;
    if (row.origin == TransferOrigin.backup || row.origin == TransferOrigin.takeout || keptOffline) {
      // Backup and the Google Photos import keep their own record of each
      // photo, and offline copies are listed in their own table; finished
      // rows here would only bury the person's own transfers.
      _rows.remove(row.id);
      _ended[row.id] = finished;
      if (_ended.length > _endedKept) _ended.remove(_ended.keys.first);
      await _db.deleteTransfers([row.id]);
    } else {
      await _save(finished);
    }
    _finished.remove(row.id)?.complete(finished);
    _speeds.remove(row.id);
    _samples.remove(row.id);
    final completer = _completions.remove(row.id);
    if (completer != null && !completer.isCompleted) {
      if (row.status == TransferStatus.completed && row.resultPath != null) {
        completer.complete(row.resultPath);
      } else {
        completer.completeError(
          error ?? DriveException(describeTransferError(row.error)),
        );
      }
    }
    _emit();
  }

  Future<void> _save(TransferRow row) async {
    // Work still under way for a transfer that was cancelled, or removed
    // from the list, would otherwise bring it back as it saves its
    // progress, and start it again on the next launch.
    if (_cancelled.contains(row.id) && row.status != TransferStatus.cancelled) {
      return;
    }
    _rows[row.id] = row;
    await _db.saveTransfer(row);
  }

  void _scheduleEmit() {
    _emitTimer ??= Timer(_emitInterval, () {
      _emitTimer = null;
      _emit();
    });
  }

  void _emit() {
    final now = DateTime.now();
    for (final row in _rows.values) {
      if (row.status != TransferStatus.running) continue;
      final previous = _samples[row.id];
      _samples[row.id] = (row.doneBytes, now);
      if (previous == null) continue;
      final seconds = now.difference(previous.$2).inMicroseconds / 1e6;
      if (seconds <= 0) continue;
      final instant = (row.doneBytes - previous.$1) / seconds;
      final smoothed = _speeds[row.id];
      _speeds[row.id] = smoothed == null
          ? instant
          : smoothed * 0.7 + instant * 0.3;
    }
    final items =
        _rows.values
            .map(
              (r) => TransferItem(
                r,
                bytesPerSecond: _speeds[r.id] ?? 0,
                preparing: _preparing.contains(r.id),
                wait: _waitOf(r, now),
              ),
            )
            .toList()
          ..sort((a, b) => b.row.createdAt.compareTo(a.row.createdAt));
    state = TransfersState(items);
  }

  Future<void> _quietly(Future<Object?> Function() action) async {
    try {
      await action();
    } catch (e) {
      debugPrint('[Transfers] $e');
    }
  }

  Future<void> _deleteQuietly(FileSystemEntity entity) async {
    try {
      if (await entity.exists()) await entity.delete(recursive: true);
    } catch (_) {}
  }
}

final transferQueueProvider = NotifierProvider<TransferQueue, TransfersState>(
  TransferQueue.new,
);

/// Waits for upload [id] to end, and answers its final row, or null once
/// it is back in the queue waiting for Wi-Fi while the phone is on mobile
/// data. Work that paces itself on its own uploads, photo backup and the
/// watched phone folders, moves on then and leaves the upload where it is;
/// the queue starts it again on Wi-Fi by itself.
Future<TransferRow?> untilEndedOrHeld(Ref ref, String id) async {
  final ended = Completer<TransferRow?>();
  final queue = ref.listen<TransfersState>(transferQueueProvider, (_, transfers) {
    final row = transfers.byId(id)?.row;
    if (row != null &&
        row.status == TransferStatus.queued &&
        row.wifiOnly &&
        ref.read(networkStatusProvider).metered &&
        !ended.isCompleted) {
      ended.complete(null);
    }
  }, fireImmediately: true);
  unawaited(
    ref.read(transferQueueProvider.notifier).whenFinished(id).then((row) {
      if (!ended.isCompleted) ended.complete(row);
    }),
  );
  try {
    return await ended.future;
  } finally {
    queue.close();
  }
}
