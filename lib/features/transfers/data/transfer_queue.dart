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
import '../../../infrastructure/network/network_status.dart';
import '../../../infrastructure/storage/device_storage.dart';
import '../../../infrastructure/telegram/telegram_client.dart';
import '../../../infrastructure/telegram/telegram_exception.dart';
import '../../drive/data/channel_messenger.dart';
import '../../drive/data/drive_repository.dart';
import '../../drive/data/drive_session.dart';
import '../../drive/data/message_indexer.dart';
import '../../drive/domain/drive_models.dart';
import '../../drive/domain/manifest.dart';
import '../domain/transfer_error.dart';
import '../domain/transfer_wait.dart';
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
}

/// A drive file to download and keep on this phone.
@immutable
class SaveRequest {
  const SaveRequest(this.file, {required this.target, this.folders = const []});

  final DriveFile file;
  final SaveTarget target;

  /// Folders under the save location, so the drive's layout carries over.
  /// For the gallery, the phone folder the photo was backed up from.
  final List<String> folders;
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

  /// What a queued transfer is waiting for before it starts again by itself.
  final TransferWait? wait;

  String get id => row.id;
  String get name => row.name;
  TransferKind get kind => row.kind;
  TransferOrigin get origin => row.origin;
  TransferStatus get status => row.status;
  FileKind get fileKind =>
      FileKind.detect(fileName: row.name, mimeType: row.mimeType);

  /// Queued on a wait that, at [now], is long enough that it doesn't count
  /// as in flight. A paused transfer is never held: it waits for a person,
  /// not for the clock.
  bool heldAt(DateTime now) =>
      status == TransferStatus.queued && (wait?.holdsAt(now) ?? false);

  /// Running, or queued with nothing holding it back for long at [now]. A
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
  List<TransferItem> get backupActive => active
      .where((t) => t.origin == TransferOrigin.backup)
      .toList();

  /// Queued, but on a wait long enough that they don't count as in flight.
  List<TransferItem> get held => heldAt(DateTime.now());

  /// [held] as it stands at [now].
  List<TransferItem> heldAt(DateTime now) =>
      items.where((t) => t.heldAt(now)).toList();

  /// Downloads to this phone, which the UI also shows as one group.
  List<TransferItem> get saves =>
      items.where((t) => t.origin == TransferOrigin.save).toList();

  List<TransferItem> get finished =>
      items.where((t) => t.status.isFinished).toList();

  /// Running, waiting or paused: everything the Transfers list shows as in
  /// progress.
  List<TransferItem> get pending =>
      items.where((t) => t.status.isPending).toList();

  int get pausedCount => items.where((t) => t.status == TransferStatus.paused).length;

  int get activeCount => active.length;

  /// Failed uploads and downloads the person can retry; backup retries its
  /// own.
  int get failedCount => items
      .where((t) => t.status == TransferStatus.failed && t.origin != TransferOrigin.backup)
      .length;

  /// Combined progress of everything in flight, for the global indicator.
  double get activeProgress {
    var total = 0;
    var done = 0;
    for (final item in active) {
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
class TransferQueue extends Notifier<TransfersState> {
  static const int _maxUploads = 2;
  static const int _maxDownloads = 3;

  /// Saves to the phone leave a download slot free, so opening a file never
  /// waits behind a whole drive being downloaded.
  static const int _maxSaves = 2;
  static const Duration _emitInterval = Duration(milliseconds: 300);

  /// How long one second of a Telegram flood wait lasts; tests shorten it.
  @visibleForTesting
  static Duration waitUnit = const Duration(seconds: 1);

  final Map<String, TransferRow> _rows = {};
  final Map<String, double> _speeds = {};
  final Map<String, (int bytes, DateTime at)> _samples = {};
  final Set<String> _running = {};
  final Set<String> _cancelled = {};

  /// Running transfers asked to pause; they stop at the next chance.
  final Set<String> _pausing = {};
  final Map<int, _Tracked> _tracked = {};
  final Map<String, int> _pendingMessages = {};
  final Map<String, int> _activeDownloads = {};
  final Map<String, Completer<String>> _completions = {};
  final Map<String, Stream<List<int>> Function()> _stagers = {};
  final Map<String, Completer<TransferRow>> _finished = {};
  final Set<String> _preparing = {};

  /// Queued downloads Telegram asked to wait, and when they may start again.
  final Map<String, DateTime> _notBefore = {};

  /// When uploads may start again, or send their next part, after Telegram
  /// asked one of them to wait.
  /// The limit is the account's, so the next upload would send all its
  /// bytes only to be told the same at the end, which on mobile data spends
  /// the person's data for nothing. Downloads carry on.
  DateTime? _uploadsNotBefore;

  /// The phone's connection as last reported, for rows that wait for Wi-Fi.
  NetworkState _network = NetworkState.unknown;

  StreamSubscription<td.File>? _fileSubscription;
  StreamSubscription<String>? _ingestSubscription;
  Timer? _emitTimer;

  /// Fires when the next of [_notBefore] or [_uploadsNotBefore] comes due.
  Timer? _wakeTimer;
  int? _loadedFor;

  TelegramClient get _client => ref.read(telegramClientProvider);
  AppDatabase get _db => ref.read(appDatabaseProvider);
  DriveRepository get _repository => ref.read(driveRepositoryProvider);
  ChannelMessenger get _messenger => ref.read(channelMessengerProvider);

  @override
  TransfersState build() {
    _fileSubscription = _client.fileUpdates.listen(_onFileUpdate);
    _ingestSubscription = _repository.ingestedFileIds.listen(_onIngested);
    ref.listen<NetworkState>(networkStatusProvider, (_, next) {
      _network = next;
      // Back on Wi-Fi, rows that waited for it may start.
      _pump();
    }, fireImmediately: true);
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
      _emitTimer?.cancel();
      _wakeTimer?.cancel();
    });
    return TransfersState.empty;
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

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
        mimeType: mimeTypeFor(request.name),
        fileId: _repository.newId(),
        folderId: folderId,
        sourcePath: sourcePath,
        ownsSource: ownsSource,
        wifiOnly: false,
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
      );
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
    final row = _rows[id];
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
          wifiOnly: false,
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

  /// Stops every save to this phone and drops them from the list. Files
  /// already saved stay where they are.
  Future<void> cancelSaves() async {
    final ids = [
      for (final r in _rows.values)
        if (r.origin == TransferOrigin.save && r.status.isPending) r.id,
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

  /// A path for [file] that already exists on this device, or null.
  Future<String?> localPathIfAvailable(DriveFile file) async {
    final offline = await _db.offlineCopyOf(file.id);
    if (offline != null && await File(offline.path).exists()) return offline.path;
    for (final row in _rows.values) {
      if (row.kind == TransferKind.download &&
          row.fileId == file.id &&
          row.status == TransferStatus.completed &&
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

  Future<void> cancel(String id) async {
    final row = _rows[id];
    if (row == null || !row.status.isPending) return;
    _cancelled.add(id);
    _pausing.remove(id);
    _notBefore.remove(id);
    await _interrupt(row);
    // Parts already delivered are useless without the rest.
    if (row.kind == TransferKind.upload && row.completedParts > 0) {
      await _quietly(() => _repository.deleteFileById(row.fileId));
    }
    // A paused split download has parts stitched together already.
    if (row.kind == TransferKind.download &&
        row.partCount > 1 &&
        !_running.contains(id)) {
      await _deleteQuietly(Directory(p.join((await downloadsDirectory()).path, row.fileId)));
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
      // A paused transfer waits for Resume, not for Telegram's clock.
      _notBefore.remove(id);
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
    for (final row in _rows.values.where((r) => r.status.isActive && which(r)).toList()) {
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

  /// Stops whatever TDLib is doing for [row]: abandons the message being
  /// sent, or the file being fetched.
  Future<void> _interrupt(TransferRow row) async {
    if (row.kind == TransferKind.upload) {
      final chatId = ref.read(driveSessionProvider)?.chatId;
      final pending = _pendingMessages.remove(row.id);
      if (pending != null && chatId != null) {
        await _quietly(() => _messenger.cancel(chatId, pending));
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
  /// stitched-together download are left behind.
  Future<void> remove(String id) async {
    final row = _rows[id];
    if (row == null) return;
    if (row.status.isPending) await cancel(id);
    _rows.remove(id);
    await _db.deleteTransfers([id]);
    _emit();
  }

  Future<void> clearFinished() async {
    final ids = _rows.values
        .where((r) => r.status.isFinished)
        .map((r) => r.id)
        .toList();
    for (final id in ids) {
      _rows.remove(id);
    }
    await _db.deleteTransfers(ids);
    _emit();
  }

  // ---------------------------------------------------------------------------
  // Scheduling
  // ---------------------------------------------------------------------------

  void _pump() {
    // Saves to the phone can be thousands deep; anything else goes first.
    int rank(TransferRow r) => r.origin == TransferOrigin.save ? 1 : 0;
    final now = DateTime.now();
    final queued = _rows.values
        .where(
          (r) =>
              r.status == TransferStatus.queued &&
              !_running.contains(r.id) &&
              TransferPolicy.mayRun(
                r,
                now: now,
                network: _network,
                notBefore: _notBeforeOf(r),
              ),
        )
        .toList()
      ..sort((a, b) {
        final byRank = rank(a).compareTo(rank(b));
        return byRank != 0 ? byRank : a.createdAt.compareTo(b.createdAt);
      });

    var uploads = _running.where((id) => _rows[id]?.kind == TransferKind.upload).length;
    var downloads = _running.length - uploads;
    var saves = _running
        .where((id) => _rows[id]?.origin == TransferOrigin.save)
        .length;

    for (final row in queued) {
      if (row.kind == TransferKind.upload && uploads < _maxUploads) {
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
    unawaited(() async {
      try {
        final running = row.copyWith(status: TransferStatus.running);
        await _save(running);
        _emit();
        await work(running);
      } catch (e, stack) {
        final wait = telegramWaitOf(e);
        if (_pausing.contains(row.id)) {
          await _save((_rows[row.id] ?? row).copyWith(status: TransferStatus.paused));
          _emit();
        } else if (wait != null && !_cancelled.contains(row.id)) {
          await _waitOut(row, wait, e);
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
      await _quietly(() => _messenger.deleteMessages(chatId, [error.failedMessageId]));
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

  /// When [row] may start, if Telegram asked it, or every upload, to wait.
  DateTime? _notBeforeOf(TransferRow row) =>
      row.kind == TransferKind.upload ? _uploadsNotBefore : _notBefore[row.id];

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

    final source = initial.sourcePath == null ? null : File(initial.sourcePath!);
    final stager = _stagers.remove(initial.id);
    if (source != null && stager != null && !await source.exists()) {
      initial = await _stage(initial, source, stager);
    }
    // Cancelled while the file was being prepared: nothing has gone yet.
    if (_cancelled.contains(initial.id)) return;
    final hasSource = source != null && await source.exists();
    if (!hasSource && resume == null) {
      throw const DriveException('The original file is no longer available.');
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
      if (landed.contains(index) && !(resume != null && index == row.completedParts)) {
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
        final path = partCount == 1
            ? source!.path
            : await _writePart(row, source!, index);
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
            caption: ManifestCodec.encodeFile(manifest),
            thumbnailPath: thumbnail != null && await File(thumbnail).exists()
                ? thumbnail
                : null,
            onPending: (pending) {
              _pendingMessages[row.id] = pending.id;
              _trackMessage(pending, row.id, base);
              // Paused in the moment the send was starting.
              if (_pausing.contains(row.id)) unawaited(_interrupt(row));
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
    }

    if (_cancelled.contains(row.id)) return;
    await _finish(row.copyWith(status: TransferStatus.completed));
    if (row.ownsSource && source != null) await _deleteQuietly(source);
    if (row.thumbnailPath != null) {
      await _deleteQuietly(File(row.thumbnailPath!));
    }
    if (partCount > 1) await _deleteQuietly(await _partsDir(row.id));
  }

  /// Copies a picked content URI into staging, where TDLib can read it.
  /// Ends the work for [id] if it was asked to pause.
  void _stopIfPausing(String id) {
    if (_pausing.contains(id)) throw const DriveException('Paused.');
  }

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

  Future<TransferRow> _stage(
    TransferRow row,
    File target,
    Stream<List<int>> Function() openRead,
  ) async {
    _preparing.add(row.id);
    _emit();
    try {
      await target.parent.create(recursive: true);
      await openRead().pipe(target.openWrite());
      final staged = row.copyWith(totalBytes: await target.length());
      await _save(staged);
      return staged;
    } finally {
      _preparing.remove(row.id);
      _emit();
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
    final sink = out.openWrite(mode: done > 0 ? FileMode.append : FileMode.write);
    try {
      for (final (index, part) in parts.indexed) {
        if (index < done) continue;
        if (_cancelled.contains(initial.id)) break;
        _stopIfPausing(initial.id);
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
  /// points the row at the copy.
  Future<TransferRow> _keep(TransferRow row, String path) async {
    final storage = ref.read(deviceStorageProvider);
    switch (row.saveTo!) {
      case SaveTarget.files:
        final saved = await storage.saveFile(
          path,
          folders: row.saveFolder?.split('/') ?? const [],
          name: row.name,
          mimeType: row.mimeType,
        );
        return row.copyWith(resultPath: Value(saved));
      case SaveTarget.gallery:
        final kind = FileKind.detect(fileName: row.name, mimeType: row.mimeType);
        final assetId = await storage.saveToGallery(
          path,
          name: row.name,
          video: kind == FileKind.video,
          album: row.saveFolder,
          takenAt: row.takenAt,
        );
        // Backup now knows this photo is already in the drive, and the
        // Photos tab can show the phone's sharp copy of it.
        await _db.markAssetBackedUp(assetId, row.fileId);
        return row.copyWith(resultPath: const Value(null));
      case SaveTarget.offline:
        final dir = Directory(p.join((await offlineDirectory()).path, row.fileId));
        await dir.create(recursive: true);
        final copy = File(p.join(dir.path, DeviceStorage.safeName(row.name)));
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

  /// Copies kept available offline. Clearing downloaded copies skips it.
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
  /// after a restart. When its file shows up complete, close it out.
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
    if (file == null) return;
    for (final row in matches.toList()) {
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
    _rows.clear();
    for (final row in await _db.allTransfers()) {
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
      if (await _repository.fileById(row.fileId) != null) {
        await _finish(row.copyWith(status: TransferStatus.completed));
        continue;
      }
      final resumable = pending.where((m) {
        final content = m.content;
        if (content is! td.MessageDocument) return false;
        final manifest = ManifestCodec.decodeFile(content.caption.text);
        return manifest?.id == row.fileId &&
            manifest?.partIndex == row.completedParts;
      }).firstOrNull;
      if (resumable != null &&
          resumable.sendingState is td.MessageSendingStatePending) {
        _start(row, (running) => _upload(running, resume: resumable));
      } else if (row.origin == TransferOrigin.backup) {
        // Photo backup re-queues these itself on its next pass.
        _rows.remove(row.id);
        await _db.deleteTransfers([row.id]);
      } else {
        await _save(row.copyWith(status: TransferStatus.queued));
      }
    }
    _emit();
    _pump();
  }

  void _reset() {
    _loadedFor = null;
    _rows.clear();
    _running.clear();
    _notBefore.clear();
    _uploadsNotBefore = null;
    _wakeTimer?.cancel();
    _wakeTimer = null;
    _tracked.clear();
    _pendingMessages.clear();
    _activeDownloads.clear();
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
    final finished = row.copyWith(finishedAt: Value(DateTime.now()));
    final keptOffline =
        row.saveTo == SaveTarget.offline && row.status == TransferStatus.completed;
    if (row.origin == TransferOrigin.backup || keptOffline) {
      // Backup keeps its own record of each photo, and offline copies are
      // listed in their own table; finished rows here would only bury the
      // person's own transfers.
      _rows.remove(row.id);
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
        completer.completeError(error ?? DriveException(describeTransferError(row.error)));
      }
    }
    _emit();
  }

  Future<void> _save(TransferRow row) async {
    // Work still under way for a transfer that was cancelled, or removed
    // from the list, would otherwise bring it back as it saves its
    // progress, and start it again on the next launch.
    if (_cancelled.contains(row.id) && row.status != TransferStatus.cancelled) return;
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
    final items = _rows.values
        .map(
          (r) => TransferItem(
            r,
            bytesPerSecond: _speeds[r.id] ?? 0,
            preparing: _preparing.contains(r.id),
            // Only a queued transfer waits on the clock; paused and
            // finished ones don't start by themselves.
            wait: switch (_notBeforeOf(r)) {
              final until? when r.status == TransferStatus.queued && until.isAfter(now) =>
                WaitingForTelegram(until),
              _ => null,
            },
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

final transferQueueProvider =
    NotifierProvider<TransferQueue, TransfersState>(TransferQueue.new);
