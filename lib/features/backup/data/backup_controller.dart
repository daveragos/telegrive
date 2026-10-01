import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../infrastructure/database/app_database.dart';
import '../../../infrastructure/network/network_status.dart';
import '../../../infrastructure/storage/preferences.dart';
import '../../drive/data/drive_repository.dart';
import '../../drive/data/drive_session.dart';
import '../../drive/data/drive_sync.dart';
import '../../transfers/data/transfer_queue.dart';
import '../../transfers/domain/transfer_error.dart';
import 'backup_notifications.dart';
import 'backup_worker.dart';

enum BackupPhase {
  /// Backup is turned off.
  off,

  /// On, but the app can't see the photo library.
  needsPermission,

  /// On, waiting for the drive to open (right after launch).
  waitingForDrive,

  /// On, but only allowed over Wi-Fi and the phone is on mobile data. A
  /// phone's hotspot counts as mobile data.
  waitingForWifi,

  /// Looking through the photo library.
  scanning,

  /// Sending photos up.
  uploading,

  /// Everything in scope is in the drive.
  upToDate,

  /// A pass hit an error it couldn't get past; Retry runs it again.
  stopped,
}

/// A photo still to go up, as the Not backed up screen lists it. Only ids
/// and plain values, so the state stays cheap to compare and rebuild.
@immutable
class PendingAsset {
  const PendingAsset({
    required this.assetId,
    required this.takenAt,
    required this.folder,
  });

  final String assetId;
  final DateTime takenAt;

  /// The phone folder it comes from, such as Camera.
  final String folder;
}

@immutable
class BackupState {
  const BackupState({
    required this.phase,
    this.total = 0,
    this.done = 0,
    this.failed = 0,
    this.current,
    this.lastCompleted,
    this.error,
    this.waiting = const [],
    this.failedIds = const {},
    this.skippedIds = const {},
  });

  final BackupPhase phase;

  /// Photos and videos in scope (selected folders, videos on or off),
  /// leaving out the ones the person skipped.
  final int total;

  /// How many of [total] are safely in the drive.
  final int done;

  /// Items that failed [BackupController.maxFailures] times and wait for
  /// the person to retry or skip them.
  final int failed;

  /// The media ids behind [failed], so Not backed up lists the photos the
  /// count stands for. A failed record for a photo the last scan didn't
  /// find (deleted from the phone, or in a folder switched off) is in
  /// neither.
  final Set<String> failedIds;

  /// The skipped photos [total] leaves out: the ones the last scan found,
  /// and those skipped since. Like [failedIds], it leaves out a record for
  /// a photo the scan didn't find, so the skipped count covers the same
  /// photos as the other counts.
  final Set<String> skippedIds;

  /// Name of something being uploaded right now.
  final String? current;
  final DateTime? lastCompleted;

  /// Why the last pass stopped, while [phase] is [BackupPhase.stopped].
  final String? error;

  /// The newest photos still to go up, at most twenty, newest first.
  final List<PendingAsset> waiting;

  bool get enabled => phase != BackupPhase.off;
  bool get isWorking =>
      phase == BackupPhase.scanning || phase == BackupPhase.uploading;
  int get remaining => math.max(0, total - done - failed);
  double get progress => total == 0 ? 1 : (done / total).clamp(0.0, 1.0);

  BackupState copyWith({
    BackupPhase? phase,
    int? total,
    int? done,
    int? failed,
    String? current,
    bool clearCurrent = false,
    DateTime? lastCompleted,
    String? error,
    bool clearError = false,
    List<PendingAsset>? waiting,
    Set<String>? failedIds,
    Set<String>? skippedIds,
  }) => BackupState(
    phase: phase ?? this.phase,
    total: total ?? this.total,
    done: done ?? this.done,
    failed: failed ?? this.failed,
    current: clearCurrent ? null : (current ?? this.current),
    lastCompleted: lastCompleted ?? this.lastCompleted,
    error: clearError ? null : (error ?? this.error),
    waiting: waiting ?? this.waiting,
    failedIds: failedIds ?? this.failedIds,
    skippedIds: skippedIds ?? this.skippedIds,
  );

  /// This state with [ids] as the photos out of tries, and [failed]
  /// counting them.
  BackupState _withFailed(Set<String> ids, {int? total}) =>
      copyWith(failed: ids.length, failedIds: ids, total: total);
}

/// What happens to one of the phone's photo folders.
enum FolderBackupMode {
  shown('Back up and show in Photos', 'Shown in Photos'),
  keptOut('Back up, keep out of Photos', 'Kept out of Photos'),
  off("Don't back up", 'Not backed up');

  const FolderBackupMode(this.label, this.shortLabel);

  /// The choice as a sentence, for the menu.
  final String label;

  /// The choice as it stands, beside the folder's name.
  final String shortLabel;
}

/// One of the phone's photo folders, for choosing what gets backed up.
@immutable
class DeviceFolder {
  const DeviceFolder({required this.name, required this.count});

  final String name;
  final int count;
}

/// Backs the camera roll up to the drive.
///
/// Turned on once, it keeps going by itself: a full pass when the drive
/// opens and whenever the app returns to the foreground, and a quick pass
/// whenever the photo library changes while the app is alive (the transfer
/// service keeps it alive in the background). Each photo lands in
/// `Photo backup/<device folder>` with its capture time in the manifest.
///
/// A photo is uploaded once: the device's media id is remembered, and
/// anything already in the drive under the same name and size — say, after a
/// reinstall or from an old phone — is recognised and skipped.
class BackupController extends Notifier<BackupState> {
  static const String rootFolder = 'Photo backup';
  static const int _parallel = 3;
  static const int _pageSize = 500;

  /// Failed attempts after which a photo stops being tried by itself and is
  /// listed under Not backed up instead.
  static const int maxFailures = 3;

  /// How many of the photos still to go up the state lists by name.
  static const int _waitingShown = 20;

  static const PermissionRequestOption permissionOption = PermissionRequestOption(
    androidPermission: AndroidPermission(
      type: RequestType.common,
      // Keeps GPS in the EXIF of backed-up originals; Android strips it
      // from apps without this permission.
      mediaLocation: true,
    ),
  );

  bool _running = false;
  bool _rerun = false;
  bool _stopRequested = false;
  Timer? _debounce;
  final Map<String, Future<String>> _folderIds = {};
  final Set<String> _activeAssets = {};

  /// Photos asked for with Back up now, oldest request first.
  final Queue<String> _priority = Queue();

  /// Media ids the running pass found in scope, while its workers still
  /// take requests, so Back up now knows whether a photo goes up in this
  /// pass or needs another. Null until the pass has scanned, since the scan
  /// takes every request made before it into account.
  Set<String>? _passIds;

  /// A photo failed in the running pass with tries left.
  bool _retryLater = false;

  Preferences get _prefs => ref.read(preferencesProvider);
  AppDatabase get _db => ref.read(appDatabaseProvider);
  DriveRepository get _repository => ref.read(driveRepositoryProvider);
  TransferQueue get _queue => ref.read(transferQueueProvider.notifier);

  @override
  BackupState build() {
    final enabled = ref.read(preferencesProvider).backupEnabled;

    ref.listen<DriveSession?>(driveSessionProvider, (previous, next) {
      if (next == null) {
        _stopRequested = true;
        _folderIds.clear();
      } else if (previous?.chatId != next.chatId) {
        _folderIds.clear();
        schedule(immediate: true);
      }
    });

    // Backup waits for a complete index; carry on once a sync gets there.
    ref.listen<SyncState>(driveSyncProvider, (previous, next) {
      if ((previous?.running ?? false) &&
          !next.running &&
          next.error == null &&
          state.phase == BackupPhase.waitingForDrive) {
        schedule(immediate: true);
      }
    });

    ref.listen<NetworkState>(networkStatusProvider, (_, next) {
      if (state.phase == BackupPhase.waitingForWifi && next.online && !next.metered) {
        schedule(immediate: true);
      } else if (state.isWorking && !_networkAllowed()) {
        // Uploads under way step back in the queue on their own; the pass
        // stops starting new ones and says why.
        _stopRequested = true;
        state = state.copyWith(phase: BackupPhase.waitingForWifi, clearCurrent: true);
      }
    });
    BackupWorker.onNewMediaInApp = () => schedule();
    if (enabled) {
      _watchLibrary();
      // Re-arm the background checks (a no-op when they are already set).
      unawaited(BackupWorker.schedule());
    }

    ref.onDispose(() {
      _debounce?.cancel();
      _unwatchLibrary();
      BackupWorker.onNewMediaInApp = null;
    });

    return BackupState(
      phase: enabled ? BackupPhase.waitingForDrive : BackupPhase.off,
      lastCompleted: ref.read(preferencesProvider).backupLastCompleted,
    );
  }

  // ---------------------------------------------------------------------------
  // Turning it on and off
  // ---------------------------------------------------------------------------

  /// Asks for photo access and starts backing up. Returns false if access
  /// was refused.
  Future<bool> enable() async {
    final permission = await PhotoManager.requestPermissionExtend(
      requestOption: permissionOption,
    );
    await _prefs.setBackupPromptShown();
    if (!permission.hasAccess) {
      state = state.copyWith(phase: BackupPhase.needsPermission);
      return false;
    }
    await _prefs.setBackupEnabled(true);
    state = state.copyWith(phase: BackupPhase.waitingForDrive);
    _watchLibrary();
    unawaited(BackupNotifications.requestPermission());
    unawaited(BackupWorker.schedule());
    schedule(immediate: true);
    return true;
  }

  /// Forgets which drive folders photos go into, so they are looked up
  /// again (after backup folders were merged, say).
  void forgetFolders() => _folderIds.clear();

  Future<void> disable() async {
    await _prefs.setBackupEnabled(false);
    _stopRequested = true;
    _unwatchLibrary();
    unawaited(BackupWorker.cancel());
    unawaited(BackupNotifications.clear());
    // Uploads on a long Telegram wait as well, or they would start again
    // by themselves once it is over.
    final uploads = ref
        .read(transferQueueProvider)
        .items
        .where((t) => t.status.isActive && t.origin == TransferOrigin.backup);
    for (final item in uploads) {
      unawaited(_queue.cancel(item.id));
    }
    state = BackupState(phase: BackupPhase.off, lastCompleted: state.lastCompleted);
  }

  Future<void> setIncludeVideos(bool value) async {
    await _prefs.setBackupVideos(value);
    _restart();
  }

  Future<void> setWifiOnly(bool value) async {
    await _prefs.setBackupWifiOnly(value);
    // Uploads already waiting for Wi-Fi go now, rather than hold up the
    // pass that is waiting for them.
    if (!value) {
      final waiting = ref
          .read(transferQueueProvider)
          .items
          .where((t) => t.origin == TransferOrigin.backup && t.row.wifiOnly)
          .map((t) => t.id);
      await _queue.useMobileData(waiting.toList());
    }
    _restart();
  }

  /// Where [folder] stands, compared by name without regard to case.
  FolderBackupMode modeOf(String folder) {
    bool named(String f) => f.toLowerCase() == folder.toLowerCase();
    if (_prefs.backupExcludedFolders.any(named)) return FolderBackupMode.off;
    if (_prefs.photosHiddenFolders.any(named)) return FolderBackupMode.keptOut;
    return FolderBackupMode.shown;
  }

  /// Turning a folder off leaves its Photos choice alone, so what it already
  /// backed up stays shown or kept out as before. Only a change to what gets
  /// backed up starts a new pass.
  Future<void> setFolderMode(String folder, FolderBackupMode mode) async {
    bool named(String f) => f.toLowerCase() == folder.toLowerCase();
    final excluded = _prefs.backupExcludedFolders;
    final hidden = {..._prefs.photosHiddenFolders};
    final wasIncluded = !excluded.any(named);
    excluded.removeWhere(named);
    if (mode == FolderBackupMode.off) {
      excluded.add(folder);
    } else {
      hidden.removeWhere(named);
      if (mode == FolderBackupMode.keptOut) hidden.add(folder);
    }
    await _prefs.setBackupExcludedFolders(excluded);
    await _prefs.setPhotosHiddenFolders(hidden);
    if (wasIncluded != (mode != FolderBackupMode.off)) _restart();
  }

  /// Gives items that failed before another go. They count as waiting
  /// again straight away, so nothing reads as backed up meanwhile.
  Future<void> retryFailed() async {
    await _db.clearBackupFailures();
    state = state._withFailed(const {});
    schedule(immediate: true);
  }

  /// Gives one failed photo another go, ahead of everything else. A second
  /// tap finds nothing left to clear and changes nothing.
  Future<void> retryOne(String assetId) async {
    if (await _db.clearBackupFailure(assetId) == 0) return;
    if (state.failedIds.contains(assetId)) {
      state = state._withFailed({...state.failedIds}..remove(assetId));
    }
    backUpNow(assetId);
  }

  /// Sets a failed photo aside: it leaves the counts and isn't tried again
  /// until [unskipAll] or [unskip]. Returns whether it was set aside; a
  /// second tap finds it set aside already and changes nothing.
  Future<bool> skip(String assetId) async {
    if (await _db.markAssetSkipped(assetId) == 0) return false;
    if (state.failedIds.contains(assetId)) {
      state = state
          ._withFailed({...state.failedIds}..remove(assetId), total: math.max(0, state.total - 1))
          .copyWith(skippedIds: {...state.skippedIds, assetId});
    }
    return true;
  }

  /// Puts a photo skipped a moment ago back among the failed ones, with the
  /// failures and reason it kept. One that is no longer set aside (Bring
  /// back ran, and it may have gone up since) stays as it is.
  Future<void> unskip(String assetId) async {
    if (await _db.unmarkAssetSkipped(assetId) == 0) return;
    if (!state.skippedIds.contains(assetId)) return;
    state = state
        ._withFailed({...state.failedIds, assetId}, total: state.total + 1)
        .copyWith(skippedIds: {...state.skippedIds}..remove(assetId));
  }

  /// Brings every skipped photo back; the next pass counts them as waiting.
  Future<void> unskipAll() async {
    await _db.clearSkipped();
    schedule(immediate: true);
  }

  /// Sends [assetId] up before the rest of what is waiting. A photo the
  /// running pass holds goes up in it as soon as a worker is free; any
  /// other gets another pass.
  void backUpNow(String assetId) {
    if (!_priority.contains(assetId)) _priority.addLast(assetId);
    if (!_running) {
      schedule(immediate: true);
    } else if (_passIds case final ids? when !ids.contains(assetId)) {
      _rerun = true;
    }
  }

  /// [pending] with the ids in [priority] first, in the order they were
  /// asked for, and everything else in its original order.
  static List<T> orderPending<T>(
    List<T> pending,
    Set<String> priority,
    String Function(T item) idOf,
  ) {
    if (priority.isEmpty) return pending;
    final byId = {for (final item in pending) idOf(item): item};
    return [
      for (final id in priority) ?byId[id],
      ...pending.where((item) => !priority.contains(idOf(item))),
    ];
  }

  /// What a worker sends up next. A Back up now request comes first and is
  /// taken off [priority], even for a photo this pass tried already (it
  /// failed, and the person tapped Retry), as long as the pass found it in
  /// [inScope] and it isn't going up right now ([active]). A request for a
  /// photo the pass didn't find stays for the next pass. Otherwise it is
  /// the next item of [queue] that hasn't [started]. Whatever is returned
  /// is added to [started].
  static T? nextInLine<T>({
    required Queue<String> priority,
    required Map<String, T> inScope,
    required Set<String> active,
    required Iterator<T> queue,
    required Set<String> started,
    required String Function(T item) idOf,
  }) {
    final asked = priority
        .where((id) => inScope.containsKey(id) && !active.contains(id))
        .firstOrNull;
    if (asked != null) {
      priority.remove(asked);
      started.add(asked);
      return inScope[asked];
    }
    while (queue.moveNext()) {
      if (started.add(idOf(queue.current))) return queue.current;
    }
    return null;
  }

  /// The phone's photo folders, biggest first.
  Future<List<DeviceFolder>> deviceFolders() async {
    final paths = await PhotoManager.getAssetPathList(
      type: _prefs.backupVideos ? RequestType.common : RequestType.image,
      hasAll: false,
    );
    final folders = <DeviceFolder>[];
    for (final path in paths) {
      final count = await path.assetCountAsync;
      if (count > 0) folders.add(DeviceFolder(name: path.name, count: count));
    }
    folders.sort((a, b) => b.count.compareTo(a.count));
    return folders;
  }

  void _restart() {
    if (!state.enabled) return;
    if (_running) _stopRequested = true;
    schedule(immediate: true);
  }

  // ---------------------------------------------------------------------------
  // Running
  // ---------------------------------------------------------------------------

  /// Runs a pass soon. Library changes arrive in bursts (a camera writes
  /// several rows per photo), so non-urgent calls are debounced.
  void schedule({bool immediate = false}) {
    if (!_prefs.backupEnabled) return;
    _debounce?.cancel();
    _debounce = Timer(
      immediate ? Duration.zero : const Duration(seconds: 4),
      () => unawaited(run()),
    );
  }

  Future<void> run() async {
    if (!_prefs.backupEnabled) return;
    if (_running) {
      _rerun = true;
      return;
    }
    _running = true;
    try {
      do {
        _rerun = false;
        _stopRequested = false;
        _retryLater = false;
        _passIds = null;
        await _pass();
      } while (_rerun && _prefs.backupEnabled);
    } catch (e, stack) {
      debugPrint('[Backup] pass failed: $e\n$stack');
      // A crashed pass says so, with the reason. Calling it up to date
      // would claim photos are in the drive that were never looked at.
      if (_prefs.backupEnabled) {
        state = state.copyWith(
          phase: BackupPhase.stopped,
          error: describeTransferError(e),
          clearCurrent: true,
        );
      }
    } finally {
      _running = false;
      _passIds = null;
    }
  }

  Future<void> _pass() async {
    if (ref.read(driveSessionProvider) == null) {
      state = state.copyWith(phase: BackupPhase.waitingForDrive);
      return;
    }

    final permission = await PhotoManager.getPermissionState(
      requestOption: permissionOption,
    );
    if (!permission.hasAccess) {
      state = state.copyWith(phase: BackupPhase.needsPermission);
      return;
    }

    final startedAt = DateTime.now();
    // The scan runs on any network, so a backup waiting for Wi-Fi still
    // counts what is left. While it waits, the pass doesn't read as
    // working, which would start the transfer service for nothing. The
    // check after the scan is the one that decides.
    final allowed = _networkAllowed();
    state = state.copyWith(
      phase: allowed ? BackupPhase.scanning : BackupPhase.waitingForWifi,
      clearCurrent: true,
      clearError: true,
    );
    await ref.read(driveSyncProvider.notifier).whenIdle();
    // "Already in the drive" is judged against the index, so it has to hold
    // the whole channel. After a reinstall, a first read that stopped short
    // would make older photos look new and send them up a second time.
    if (!_indexComplete()) {
      state = state.copyWith(phase: BackupPhase.waitingForDrive, clearCurrent: true);
      return;
    }
    final assets = await _scan();
    final known = await _db.backupAssetMap();
    final inScope = <String, AssetEntity>{};
    final failedIds = <String>{};
    final skippedIds = <String>{};
    final waiting = <AssetEntity>[];
    var done = 0;
    for (final asset in assets) {
      final record = known[asset.id];
      // Skipped photos are out of scope, like a folder that is switched off.
      if (record?.state == BackupAssetState.skipped) {
        skippedIds.add(asset.id);
        continue;
      }
      inScope[asset.id] = asset;
      if (record?.state == BackupAssetState.done) {
        done++;
      } else if ((record?.failures ?? 0) >= maxFailures) {
        failedIds.add(asset.id);
      } else {
        waiting.add(asset);
      }
    }

    // The list stays newest first while Back up now changes the order the
    // photos go up in. Photos leave it once they are in the drive or out of
    // tries, and the next ones move up.
    final settled = <String>{};
    var from = 0;
    List<PendingAsset> shown() {
      while (from < waiting.length && settled.contains(waiting[from].id)) {
        from++;
      }
      return [
        for (final asset in waiting
            .skip(from)
            .where((a) => !settled.contains(a.id))
            .take(_waitingShown))
          PendingAsset(
            assetId: asset.id,
            takenAt: asset.createDateTime,
            folder: _folderName(asset),
          ),
      ];
    }

    final asked = _priority.toSet();
    final pending = orderPending(waiting, asked, (a) => a.id);
    // A request for a photo the scan didn't find has nothing left to send:
    // the photo was deleted, or its folder switched off. Nor has one for a
    // photo that is in the drive, such as one asked for while it was going
    // up. A failed photo the person retried stays asked for.
    _priority.removeWhere(
      (id) => !inScope.containsKey(id) || known[id]?.state == BackupAssetState.done,
    );
    final hasWork = pending.isNotEmpty || _priority.isNotEmpty;
    _passIds = hasWork ? inScope.keys.toSet() : const {};

    // Counted before the network decides, so a backup waiting for Wi-Fi
    // says how much is left.
    state = state
        ._withFailed(failedIds, total: inScope.length)
        .copyWith(done: done, waiting: shown(), skippedIds: skippedIds);
    if (!hasWork) {
      await _finishPass(startedAt);
      return;
    }
    // Requests stay queued while the pass waits, so the photos still go
    // first once Wi-Fi is back. This check also catches a phone that moved
    // onto mobile data while the library was read.
    if (!_networkAllowed()) {
      state = state.copyWith(phase: BackupPhase.waitingForWifi, clearCurrent: true);
      return;
    }
    // The ones the order above put first go up from the front of it.
    final placed = {for (final asset in waiting) asset.id}.intersection(asked);
    _priority.removeWhere(placed.contains);
    state = state.copyWith(phase: BackupPhase.uploading);

    final fingerprints = await _repository.mediaFingerprints();
    final queue = pending.iterator;
    final started = <String>{};

    Future<void> worker() async {
      while (!_stopRequested && _prefs.backupEnabled) {
        if (!_networkAllowed()) {
          state = state.copyWith(phase: BackupPhase.waitingForWifi, clearCurrent: true);
          _stopRequested = true;
          return;
        }
        final asset = nextInLine(
          priority: _priority,
          inScope: inScope,
          active: _activeAssets,
          queue: queue,
          started: started,
          idOf: (a) => a.id,
        );
        if (asset == null) return;
        // Read when its turn comes rather than at the scan: Retry may have
        // cleared it since, or an earlier request sent the photo up.
        final record = await _db.backupAssetOf(asset.id);
        if (!_due(record)) continue;
        final outcome = await _backUp(asset, fingerprints, record);
        if (outcome == null) continue;
        settled.add(asset.id);
        state = outcome
            ? state.copyWith(done: state.done + 1, waiting: shown())
            : state._withFailed({...state.failedIds, asset.id}).copyWith(waiting: shown());
      }
    }

    await Future.wait([for (var i = 0; i < _parallel; i++) worker()]);
    // Nothing more goes up in this pass, so a request from here on needs
    // another.
    _passIds = const {};

    if (_stopRequested || !_prefs.backupEnabled) return;
    if (_retryLater) {
      // A photo that failed with tries left gets its next try in a few
      // seconds, and backup isn't up to date until then.
      state = state.copyWith(clearCurrent: true);
      if (!_rerun) schedule();
    } else {
      await _finishPass(startedAt);
    }
  }

  /// Whether a photo with [record] still needs sending: never tried, or
  /// failed with tries left. One in the drive, set aside, or out of tries
  /// (until Retry) is not.
  static bool _due(BackupAssetRow? record) =>
      record == null ||
      (record.state == BackupAssetState.failed && record.failures < maxFailures);

  /// The channel has been read in full at least once on this phone, and
  /// the latest sync didn't fail.
  bool _indexComplete() {
    final chatId = ref.read(driveSessionProvider)?.chatId;
    return chatId != null &&
        _prefs.lastFullSync(chatId) != null &&
        ref.read(driveSyncProvider).error == null;
  }

  Future<void> _finishPass(DateTime startedAt) async {
    await _prefs.setBackupCompleted(startedAt);
    await BackupNotifications.clear();
    state = state.copyWith(
      phase: BackupPhase.upToDate,
      clearCurrent: true,
      lastCompleted: startedAt,
    );
  }

  /// Backs one asset up. True when it is in the drive, false when it has
  /// now failed [maxFailures] times, null when it stays waiting (already in
  /// flight, the pass was stopped, or a failure with tries left).
  Future<bool?> _backUp(
    AssetEntity asset,
    Map<String, String> fingerprints,
    BackupAssetRow? record,
  ) async {
    if (!_activeAssets.add(asset.id)) return null;
    String? thumbnail;
    try {
      final file = await asset.originFile;
      if (file == null || !await file.exists()) {
        return await _fail(asset, record, 'This photo is no longer on this phone.');
      }
      final name = await _nameOf(asset, file);
      final size = await file.length();

      // Already up there, from an earlier install or another phone.
      final existing = fingerprints['$name|$size'];
      if (existing != null) {
        await _db.markAssetBackedUp(asset.id, existing);
        return true;
      }

      state = state.copyWith(current: name);
      final folderId = await _folderFor(asset);
      thumbnail = await _thumbnailFor(asset);
      final temp = (await getTemporaryDirectory()).path;

      final ids = await _queue.enqueueUploads([
        UploadRequest(
          name: name,
          path: file.path,
          size: size,
          // Android 11+ hands back the original; only delete our own copies.
          ownsSource: file.path.startsWith(temp),
          origin: TransferOrigin.backup,
          assetId: asset.id,
          takenAt: asset.createDateTime,
          thumbnailPath: thumbnail,
          // An upload under way when a hotspot takes over steps back too.
          wifiOnly: _prefs.backupWifiOnly,
        ),
      ], folderId: folderId);
      if (ids.isEmpty) return await _fail(asset, record, 'Couldn\'t start the upload.');
      thumbnail = null; // The queue owns it now.

      final row = await _queue.whenFinished(ids.first);
      switch (row.status) {
        case TransferStatus.completed:
          await _db.markAssetBackedUp(asset.id, row.fileId);
          fingerprints['$name|$size'] = row.fileId;
          return true;
        case TransferStatus.cancelled:
          return null;
        default:
          return await _fail(asset, record, row.error ?? 'Something went wrong.');
      }
    } catch (e) {
      debugPrint('[Backup] ${asset.id}: $e');
      return _fail(asset, record, describeTransferError(e));
    } finally {
      _activeAssets.remove(asset.id);
      if (thumbnail != null) {
        try {
          await File(thumbnail).delete();
        } catch (_) {}
      }
    }
  }

  /// Records a failed try with [reason]. False once the photo is out of
  /// tries, null while it has tries left, in which case the pass asks for
  /// another soon after it ends.
  Future<bool?> _fail(AssetEntity asset, BackupAssetRow? record, String reason) async {
    final failures = (record?.failures ?? 0) + 1;
    await _db.markAssetFailed(asset.id, failures, reason: reason);
    if (failures >= maxFailures) return false;
    _retryLater = true;
    return null;
  }

  /// Everything in scope, newest first.
  Future<List<AssetEntity>> _scan() async {
    final paths = await PhotoManager.getAssetPathList(
      type: _prefs.backupVideos ? RequestType.common : RequestType.image,
      onlyAll: true,
      filterOption: FilterOptionGroup(
        orders: [const OrderOption(type: OrderOptionType.createDate, asc: false)],
      ),
    );
    if (paths.isEmpty) return const [];
    final all = paths.first;
    final count = await all.assetCountAsync;
    final excluded = _prefs.backupExcludedFolders
        .map((f) => f.toLowerCase())
        .toSet();

    final assets = <AssetEntity>[];
    for (var start = 0; start < count; start += _pageSize) {
      final page = await all.getAssetListRange(
        start: start,
        end: math.min(start + _pageSize, count),
      );
      for (final asset in page) {
        if (excluded.contains(_folderName(asset).toLowerCase())) continue;
        assets.add(asset);
      }
    }
    return assets;
  }

  /// `DCIM/Camera/` → `Camera`. iOS has no folders; everything is the roll.
  static String _folderName(AssetEntity asset) {
    final relative = asset.relativePath;
    if (relative == null || relative.isEmpty) return 'Camera Roll';
    final parts = relative.split('/').where((s) => s.isNotEmpty).toList();
    return parts.isEmpty ? 'Camera Roll' : parts.last;
  }

  Future<String> _folderFor(AssetEntity asset) {
    final name = _folderName(asset);
    // Parallel workers must not race to create the same folder twice.
    return _folderIds[name] ??= _repository
        .ensureFolderPath([rootFolder, name])
        .catchError((Object e) {
          _folderIds.remove(name);
          throw e;
        });
  }

  static Future<String> _nameOf(AssetEntity asset, File file) async {
    try {
      final title = await asset.titleAsync;
      if (title.trim().isNotEmpty) return title.trim();
    } catch (_) {}
    return p.basename(file.path);
  }

  /// A ≤ 320 px JPEG preview, so the drive shows thumbnails for videos too
  /// (Telegram only makes its own for images).
  static Future<String?> _thumbnailFor(AssetEntity asset) async {
    try {
      final bytes = await asset.thumbnailDataWithSize(
        // Telegram's ceiling for document thumbnails; as sharp as allowed.
        const ThumbnailSize(320, 320),
        quality: 90,
      );
      if (bytes == null || bytes.isEmpty || bytes.length > 200 * 1024) {
        return null;
      }
      final dir = Directory(
        p.join((await getTemporaryDirectory()).path, 'telegrive-thumbs'),
      );
      await dir.create(recursive: true);
      final file = File(p.join(dir.path, '${asset.id.hashCode}.jpg'));
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  /// Mobile data is allowed, or the phone isn't on it. A phone's hotspot
  /// counts as mobile data, since Android reports it as metered.
  bool _networkAllowed() =>
      !_prefs.backupWifiOnly || !ref.read(networkStatusProvider).metered;

  // ---------------------------------------------------------------------------
  // Watching the library while the app is alive
  // ---------------------------------------------------------------------------

  bool _watching = false;

  void _onLibraryChanged(MethodCall _) => schedule();

  void _watchLibrary() {
    if (_watching) return;
    _watching = true;
    PhotoManager.addChangeCallback(_onLibraryChanged);
    unawaited(PhotoManager.startChangeNotify());
  }

  void _unwatchLibrary() {
    if (!_watching) return;
    _watching = false;
    PhotoManager.removeChangeCallback(_onLibraryChanged);
    unawaited(PhotoManager.stopChangeNotify());
  }
}

final backupControllerProvider = NotifierProvider<BackupController, BackupState>(
  BackupController.new,
);

/// How many photos and videos the drive holds from backup, live.
final backedUpCountProvider = StreamProvider.autoDispose<int>(
  (ref) => ref.watch(appDatabaseProvider).watchBackedUpCount(),
);

/// Photos that are out of tries, most recently failed first, live. Only
/// the ones in [BackupState.failedIds], so the list matches the count.
final failedBackupAssetsProvider = StreamProvider.autoDispose<List<BackupAssetRow>>((ref) {
  final counted = ref.watch(backupControllerProvider.select((s) => s.failedIds));
  return ref
      .watch(appDatabaseProvider)
      .watchFailedAssets(minFailures: BackupController.maxFailures)
      .map((rows) => [for (final row in rows) if (counted.contains(row.assetId)) row]);
});

/// How many photos the person set aside, live. Only the ones in
/// [BackupState.skippedIds], so the count covers the photos the total
/// leaves out.
final skippedBackupCountProvider = StreamProvider.autoDispose<int>((ref) {
  final counted = ref.watch(backupControllerProvider.select((s) => s.skippedIds));
  return ref
      .watch(appDatabaseProvider)
      .watchSkippedAssetIds()
      .map((ids) => ids.where(counted.contains).length);
});
