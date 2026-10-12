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

import '../../../core/files/file_kind.dart';
import '../../../infrastructure/database/app_database.dart';
import '../../../infrastructure/network/network_status.dart';
import '../../../infrastructure/storage/device_profile.dart';
import '../../../infrastructure/storage/preferences.dart';
import '../../drive/data/drive_repository.dart';
import '../../drive/data/drive_session.dart';
import '../../drive/data/drive_sync.dart';
import '../../drive/domain/drive_models.dart';
import '../../network/data/mobile_data.dart';
import '../../transfers/data/transfer_queue.dart';
import '../../transfers/domain/transfer_error.dart';
import 'background_backup.dart';
import 'backup_notifications.dart';
import 'backup_rules.dart';
import 'backup_run_mode.dart';
import 'backup_worker.dart';

enum BackupPhase {
  /// Backup is turned off.
  off,

  /// On, but the app can't see the photo library.
  needsPermission,

  /// On, waiting for the drive to open (right after launch).
  waitingForDrive,

  /// On, but the phone is on mobile data and what is left may not use it:
  /// backup isn't allowed mobile data at all, or only for photos and the
  /// videos wait ([BackupState.heldVideos]). A phone's hotspot counts as
  /// mobile data.
  waitingForWifi,

  /// On, but what is left would pass the monthly mobile data limit, so it
  /// waits for Wi-Fi or the next period.
  waitingForBudget,

  /// Looking through the photo library.
  scanning,

  /// Sending photos up.
  uploading,

  /// Everything in scope is in the drive.
  upToDate,

  /// A pass hit an error it couldn't get past; Retry runs it again.
  stopped,
}

/// What a pass does with one of the phone's photos, from its backup record.
enum BackupDisposition {
  /// In the drive.
  done,

  /// Out of tries, listed under Not backed up until Retry.
  failed,

  /// Still to go up: never tried, or failed with tries left.
  pending,

  /// Out of scope: set aside by the person, deleted for good from the
  /// drive here, or gone from the drive and waiting for the person to say.
  skip,
}

/// How matching backed-up photos against the index went.
enum VerifyOutcome {
  /// Every backed-up photo is in the drive.
  ok,

  /// Some are no longer in the drive; they wait for the person's choice.
  gaps,

  /// So many look gone that the index itself is more likely incomplete;
  /// nothing was recorded.
  suspect,

  /// Not checked: backup is off, or the channel hasn't been read in full in
  /// this run of the app.
  skipped,
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

/// A photo this run of the app sent up, as the Backup queue lists it.
@immutable
class RecentBackup {
  const RecentBackup({required this.assetId, required this.fileId});

  final String assetId;

  /// The drive file it went up as: the original, or a small copy until the
  /// original takes its place.
  final String fileId;
}

/// A waiting photo the person took out of backup, with what Undo needs to
/// put it back as it was.
@immutable
class SkippedWaiting {
  const SkippedWaiting(this.assetId, this.previous, {required this.wasGoingUp});

  final String assetId;

  /// Its backup record before, or null when it had never been tried.
  final BackupAssetRow? previous;

  /// Its upload was under way and was called off.
  final bool wasGoingUp;
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
    this.recent = const [],
    this.failedIds = const {},
    this.skippedIds = const {},
    this.heldVideos = 0,
    this.heldForBudget = 0,
    this.pausedUntil,
    this.smallCopies = 0,
    this.sendingSmallCopies = false,
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

  /// The photos the last pass found still to go up, newest first, the ones
  /// going up now among them. Each leaves once it is in the drive, out of
  /// tries, or skipped.
  final List<PendingAsset> waiting;

  /// What this run of the app sent up, the latest first, at most
  /// [BackupController.recentKept]. A photo whose original followed its
  /// small copy is listed once, as the original.
  final List<RecentBackup> recent;

  /// Videos the last pass left for Wi-Fi, since mobile data is for photos
  /// only.
  final int heldVideos;

  /// Items the last pass left because they would pass the monthly mobile
  /// data limit.
  final int heldForBudget;

  /// When the pass that stopped because Telegram asked the account to wait
  /// carries on. Backup isn't moving meanwhile, and nothing it left counts
  /// as failed.
  final DateTime? pausedUntil;

  /// Photos in scope with only a small copy in the drive so far, whose
  /// originals are still to go up. They count among [remaining].
  final int smallCopies;

  /// The pass under way sends small copies, since the originals may not go
  /// on this network yet.
  final bool sendingSmallCopies;

  bool get enabled => phase != BackupPhase.off;

  /// Looking through the library or uploading, and not paused for a wait
  /// Telegram asked for.
  bool get isWorking =>
      (phase == BackupPhase.scanning || phase == BackupPhase.uploading) &&
      pausedUntil == null;
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
    List<RecentBackup>? recent,
    Set<String>? failedIds,
    Set<String>? skippedIds,
    int? heldVideos,
    int? heldForBudget,
    DateTime? pausedUntil,
    bool clearPaused = false,
    int? smallCopies,
    bool? sendingSmallCopies,
  }) => BackupState(
    phase: phase ?? this.phase,
    total: total ?? this.total,
    done: done ?? this.done,
    failed: failed ?? this.failed,
    current: clearCurrent ? null : (current ?? this.current),
    lastCompleted: lastCompleted ?? this.lastCompleted,
    error: clearError ? null : (error ?? this.error),
    waiting: waiting ?? this.waiting,
    recent: recent ?? this.recent,
    failedIds: failedIds ?? this.failedIds,
    skippedIds: skippedIds ?? this.skippedIds,
    heldVideos: heldVideos ?? this.heldVideos,
    heldForBudget: heldForBudget ?? this.heldForBudget,
    pausedUntil: clearPaused ? null : (pausedUntil ?? this.pausedUntil),
    smallCopies: smallCopies ?? this.smallCopies,
    sendingSmallCopies: sendingSmallCopies ?? this.sendingSmallCopies,
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
/// Turned on once, it keeps going by itself: a pass when the drive opens,
/// when the app returns to the foreground after a while or with new photos,
/// and whenever the photo library changes while the app is alive (the
/// transfer service keeps it alive in the background while it uploads).
/// With the app closed, the background job runs the same pass; see
/// [BackgroundBackup]. Each photo lands in `Photo backup/<device folder>`
/// with its capture time in the manifest.
///
/// A pass looks through the whole library once a day, or after a change to
/// what is backed up. In between it looks only at the photos added to the
/// phone since the last pass that dealt with everything, the ones still to
/// be tried again and the ones asked for with Back up now, and counts the
/// rest from its records.
///
/// A photo is uploaded once: the device's media id is remembered, and
/// anything already in the drive under the same name and size — say, after a
/// reinstall or from an old phone — is recognised and skipped.
///
/// With Small copies first on, a photo whose original may not go up on
/// this network yet goes up as a small JPEG when the monthly limit has room
/// for it, so it is safe at once. Its original takes the small copy's place
/// in the same message once it may go, and only then is the photo backed up.
class BackupController extends Notifier<BackupState> {
  static const String rootFolder = 'Photo backup';
  static const int _pageSize = 500;

  /// Failed attempts after which a photo stops being tried by itself and is
  /// listed under Not backed up instead.
  static const int maxFailures = 3;

  /// How many of the photos this run sent up the state lists.
  static const int recentKept = 500;

  static const PermissionRequestOption permissionOption =
      PermissionRequestOption(
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

  /// The photos the last pass found still to go up, newest first, and
  /// those of them settled since: in the drive, out of tries, or skipped.
  /// [BackupState.waiting] is the one less the other.
  List<PendingAsset> _listed = const [];
  final Set<String> _settled = {};

  /// Photos [skipWaiting] is taking out of backup, so a second tap while
  /// the first is under way does nothing.
  final Set<String> _skipping = {};

  /// A photo failed in the running pass with tries left.
  bool _retryLater = false;

  /// Uploads that stepped back into the queue to wait for Wi-Fi, by media
  /// id. They keep what they have sent, and the queue starts them again on
  /// Wi-Fi by itself; the pass that reaches the photo next follows its
  /// upload rather than sending the photo a second time.
  final Map<String, String> _heldUploads = {};

  /// When the latest pass started, and whether the library changed since,
  /// for [scheduleOnResume].
  DateTime? _lastPassAt;
  bool _libraryChanged = false;

  /// Starts the next pass once a wait Telegram asked for is over.
  Timer? _pauseTimer;

  /// The running pass is looking through the whole library, and records
  /// that as the last look once it has dealt with everything, which is also
  /// when the checkpoint moves. Recorded any earlier, a look that never got
  /// that far would have the next pass skip the older photos it didn't
  /// deal with. [_unfound] is how many of the records the look found no
  /// photo for.
  bool _recordsFullScan = false;
  int _unfound = 0;

  /// Photos the running [runInBackground] pass sent up.
  int _uploaded = 0;

  /// Items the running pass left for Wi-Fi while mobile data is off for
  /// backup and only small copies may use it.
  int _heldForWifi = 0;

  /// Completed by [stop] while [runInBackground] runs: [_halted] when the
  /// pass is to end, [_hurried] when what is under way is to go at once.
  Completer<void>? _halted;
  Completer<void>? _hurried;

  Preferences get _prefs => ref.read(preferencesProvider);
  AppDatabase get _db => ref.read(appDatabaseProvider);
  DriveRepository get _repository => ref.read(driveRepositoryProvider);
  TransferQueue get _queue => ref.read(transferQueueProvider.notifier);

  /// Running in the background job, which runs its one pass itself.
  bool get _background => ref.read(backupRunModeProvider) == BackupRunMode.background;

  /// How many photos a pass works on at once: one while the phone saves
  /// memory, so a pass holds one photo's copy and upload at a time, and at
  /// most two in the background job, which shares the phone with whatever
  /// the person is doing.
  int get _parallel => ref.read(saveMemoryProvider) ? 1 : (_background ? 2 : 3);

  @override
  BackupState build() {
    final enabled = ref.read(preferencesProvider).backupEnabled;
    final background = _background;

    ref.listen<DriveSession?>(driveSessionProvider, (previous, next) {
      if (next == null) {
        _stopRequested = true;
        _folderIds.clear();
        _heldUploads.clear();
      } else if (previous?.chatId != next.chatId) {
        _folderIds.clear();
        schedule(immediate: true);
      }
    });

    // Backup waits for a complete index; carry on once a sync gets there.
    // A full read that succeeded is also the moment the index holds all the
    // channel does, so the records are checked against it then.
    ref.listen<SyncState>(driveSyncProvider, (previous, next) {
      if ((previous?.running ?? false) &&
          !next.running &&
          next.error == null &&
          state.phase == BackupPhase.waitingForDrive) {
        schedule(immediate: true);
      }
      if (next.lastFull != previous?.lastFull && next.error == null) {
        unawaited(
          verify().catchError((Object e) {
            debugPrint('[Backup] verify: $e');
            return VerifyOutcome.skipped;
          }),
        );
      }
    });

    ref.onDispose(() {
      _debounce?.cancel();
      _pauseTimer?.cancel();
      _unwatchLibrary();
    });
    // The background job's network is fixed for its run, and it watches
    // nothing: the check jobs notice new photos, and the job runs one pass.
    if (background) {
      return BackupState(
        phase: enabled ? BackupPhase.waitingForDrive : BackupPhase.off,
        lastCompleted: ref.read(preferencesProvider).backupLastCompleted,
      );
    }

    ref.listen<NetworkState>(networkStatusProvider, (_, next) {
      // Originals behind small copies go on Wi-Fi too, whatever the pass
      // says it is doing.
      final waiting =
          state.phase == BackupPhase.waitingForWifi ||
          state.phase == BackupPhase.waitingForBudget ||
          state.smallCopies > 0;
      if (waiting && next.online && !next.metered) {
        schedule(immediate: true);
      } else if (state.isWorking && _waitsForWifi()) {
        // Uploads under way step back in the queue on their own; the pass
        // stops starting new ones and says why.
        _stopRequested = true;
        _pauseForWifi();
      } else if (next.metered && _prefs.backupEnabled) {
        // Uploads under way that may not use mobile data step back too:
        // videos on their own when it is for photos only, and those past
        // the monthly limit once marked.
        unawaited(_markQueued());
      }
    });
    // A new period makes room under the limit again.
    ref.listen<MobileDataState>(mobileDataProvider, (previous, next) {
      if (previous?.periodStart != next.periodStart &&
          state.phase == BackupPhase.waitingForBudget) {
        schedule(immediate: true);
      }
    }, weak: true);
    if (enabled) {
      _watchLibrary();
      // Arms the background checks as the app starts; see BackupWorker.schedule.
      unawaited(BackupWorker.schedule());
    }

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
    // Whatever changed while backup was off, the first pass sees it all.
    await _forgetFullScan();
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
    _pauseTimer?.cancel();
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
    _heldUploads.clear();
    state = BackupState(
      phase: BackupPhase.off,
      lastCompleted: state.lastCompleted,
    );
  }

  Future<void> setIncludeVideos(bool value) async {
    await _prefs.setBackupVideos(value);
    _restart();
  }

  /// What backup may send over mobile data. Uploads already in the queue
  /// follow the new choice at once: those it keeps for Wi-Fi step back if
  /// they are under way on mobile data, and those it allows go, as far as
  /// the monthly limit lets them.
  Future<void> setMobileData(BackupMobileData mode) async {
    await _prefs.setBackupMobileData(mode);
    await _markQueued();
    _restart();
  }

  /// Whether photos whose originals may not go up on mobile data yet go up
  /// as small copies meanwhile. The next pass looks again by the new choice.
  Future<void> setSmallCopies(bool on) async {
    await _prefs.setBackupSmallCopies(on);
    _restart();
  }

  /// Whether backup runs on its own while the phone charges, with the app
  /// closed. On, the background checks are armed and start the job when
  /// new photos arrive; off, a job waiting to run is called off, and the
  /// checks go on reminding.
  Future<void> setUnattended(bool on) async {
    await _prefs.setBackupUnattended(on);
    if (on) {
      await BackupWorker.schedule();
    } else {
      await BackgroundBackup.cancel();
    }
  }

  /// Lets backup go past the monthly mobile data limit until the phone is
  /// on an unmetered network again, or the app restarts, and carries on.
  void useDataAnyway() {
    ref.read(mobileDataProvider.notifier).useDataAnyway();
    schedule(immediate: true);
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
    // Their records are gone, and most were added to the phone long ago,
    // so only a look through the whole library finds them again.
    await _forgetFullScan();
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
          ._withFailed(
            {...state.failedIds}..remove(assetId),
            total: math.max(0, state.total - 1),
          )
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
    await _forgetFullScan();
    schedule(immediate: true);
  }

  /// Takes a photo still waiting to go up out of backup, from the Backup
  /// queue: it is skipped, like a failed photo set aside, and its upload is
  /// called off if it is under way. A photo with a small copy keeps it.
  /// Answers what [undoSkip] puts back, or null when the photo wasn't
  /// waiting: in the drive already, out of tries, or skipped by a tap a
  /// moment ago. One whose upload lands before it can be called off is in
  /// the drive, and stays backed up.
  Future<SkippedWaiting?> skipWaiting(String assetId) async {
    if (!_skipping.add(assetId)) return null;
    try {
      final previous = await _db.backupAssetOf(assetId);
      if (classify(previous) != BackupDisposition.pending) return null;
      // Set aside before the upload is called off, so the worker that has
      // the photo sees as much and lets it go rather than trying again.
      await _db.setAssetSkipped(assetId);
      _heldUploads.remove(assetId);
      final upload = ref
          .read(transferQueueProvider)
          .items
          .where((t) => t.row.assetId == assetId && t.status.isPending)
          .firstOrNull;
      if (upload != null) await _queue.remove(upload.id);
      if ((await _db.backupAssetOf(assetId))?.state != BackupAssetState.skipped) {
        return null;
      }
      _settled.add(assetId);
      state = state.copyWith(
        total: math.max(0, state.total - 1),
        skippedIds: {...state.skippedIds, assetId},
        smallCopies: previous?.state == BackupAssetState.smallCopy
            ? math.max(0, state.smallCopies - 1)
            : null,
        waiting: _shown(),
      );
      return SkippedWaiting(assetId, previous, wasGoingUp: upload != null);
    } finally {
      _skipping.remove(assetId);
    }
  }

  /// Puts a photo [skipWaiting] took out back as it was, and sends it up
  /// ahead of the rest: it was in line, or going up, a moment ago. One no
  /// longer skipped (Bring back ran, and it may have gone up since) stays
  /// as it is.
  Future<void> undoSkip(SkippedWaiting skipped) async {
    final id = skipped.assetId;
    if (await _db.unskipAsset(id, skipped.previous) == 0) return;
    if (state.skippedIds.contains(id)) {
      _settled.remove(id);
      state = state.copyWith(
        total: state.total + 1,
        skippedIds: {...state.skippedIds}..remove(id),
        smallCopies: skipped.previous?.state == BackupAssetState.smallCopy
            ? state.smallCopies + 1
            : null,
        waiting: _shown(),
      );
    }
    // A photo the scans between full looks wouldn't find again, being
    // older than the last pass that dealt with everything, is found as one
    // asked for.
    backUpNow(id);
  }

  /// The photos still to go up, as [BackupState.waiting] lists them.
  List<PendingAsset> _shown() => [
    for (final asset in _listed)
      if (!_settled.contains(asset.assetId)) asset,
  ];

  /// Matches the photos backed up from this phone against the index, and
  /// records the ones whose files are no longer in the drive, so the person
  /// can have them sent up again or leave them out. Nothing is uploaded
  /// here. It runs only after a full read of the channel that succeeded in
  /// this run of the app, since against a partial index every photo the
  /// read hadn't reached would look gone; and when more than fifty, and
  /// more than a tenth, look gone anyway, the index is the suspect and
  /// nothing is recorded.
  Future<VerifyOutcome> verify() async {
    if (!_prefs.backupEnabled ||
        !_indexComplete() ||
        ref.read(driveSyncProvider).lastFull == null) {
      return VerifyOutcome.skipped;
    }
    final missing = await _db.backedUpButMissing();
    final verified = await _db.countBackedUpWithFile();
    if (missing.length > suspectAbove && missing.length > verified * suspectShare) {
      return VerifyOutcome.suspect;
    }
    await _db.markAssetsMissing(missing);
    await _prefs.setBackupVerifiedAt(DateTime.now());
    return missing.isEmpty ? VerifyOutcome.ok : VerifyOutcome.gaps;
  }

  /// More missing photos than this, and more than [suspectShare] of the
  /// backed-up ones, means the index is doubted rather than the drive.
  static const int suspectAbove = 50;
  static const double suspectShare = 0.1;

  /// Sends the photos that went missing from the drive up again. Their
  /// records go, so the next pass judges them afresh; one that has a copy
  /// elsewhere in the drive is recognised by name and size, as in any pass.
  Future<void> retryMissing() async {
    await _db.backUpMissingAgain();
    await _forgetFullScan();
    schedule(immediate: true);
  }

  /// Leaves the photos that went missing from the drive out of backup.
  Future<void> leaveOutMissing() => _db.leaveOutMissing();

  /// What a pass does with a photo that has [record], or none.
  @visibleForTesting
  static BackupDisposition classify(BackupAssetRow? record) => switch (record?.state) {
    null => BackupDisposition.pending,
    BackupAssetState.done => BackupDisposition.done,
    BackupAssetState.failed =>
      record!.failures >= maxFailures ? BackupDisposition.failed : BackupDisposition.pending,
    BackupAssetState.skipped ||
    BackupAssetState.missing ||
    BackupAssetState.removed => BackupDisposition.skip,
    // Safe as a small copy, but its original is still to go up.
    BackupAssetState.smallCopy => BackupDisposition.pending,
  };

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

  /// Makes the next pass look through the whole library. A pass under way
  /// that began before this doesn't record its own look as the last.
  Future<void> _forgetFullScan() {
    _recordsFullScan = false;
    return _prefs.forgetBackupFullScan();
  }

  /// A backup choice changed, so the next pass looks through the whole
  /// library by the new choice, and one under way makes way for it.
  void _restart() {
    unawaited(_forgetFullScan());
    if (!state.enabled) return;
    if (_running) _stopRequested = true;
    schedule(immediate: true);
  }

  // ---------------------------------------------------------------------------
  // Running
  // ---------------------------------------------------------------------------

  /// Runs a pass soon. Library changes arrive in bursts (a camera writes
  /// several rows per photo), so non-urgent calls are debounced. The
  /// background job runs its one pass itself and schedules none.
  void schedule({bool immediate = false}) {
    if (!_prefs.backupEnabled || _background) return;
    _debounce?.cancel();
    _debounce = Timer(
      immediate ? Duration.zero : const Duration(seconds: 4),
      () => unawaited(run()),
    );
  }

  /// How long after a pass coming back to the app starts no other, unless
  /// the library changed.
  static const Duration _resumeQuiet = Duration(minutes: 15);

  /// Runs a pass as the app comes back to the foreground, unless one that
  /// left everything up to date started less than [_resumeQuiet] ago and
  /// the library hasn't changed since: a quick look at another app doesn't
  /// look through the photos again.
  void scheduleOnResume() {
    final due = resumeDue(
      lastPass: _lastPassAt,
      upToDate: state.phase == BackupPhase.upToDate,
      libraryChanged: _libraryChanged,
      now: DateTime.now(),
    );
    if (due) schedule(immediate: true);
  }

  /// Whether coming back to the app at [now] starts a pass: always, unless
  /// the last one began at [lastPass], left everything [upToDate] and
  /// less than [_resumeQuiet] ago, and the library hasn't changed since.
  @visibleForTesting
  static bool resumeDue({
    DateTime? lastPass,
    required bool upToDate,
    required bool libraryChanged,
    required DateTime now,
  }) =>
      lastPass == null ||
      libraryChanged ||
      !upToDate ||
      lastPass.isAfter(now) ||
      now.difference(lastPass) >= _resumeQuiet;

  /// Ends the pass under way, without another after it. Workers take no
  /// new photo, and in [runInBackground] the uploads under way get the
  /// job's grace to finish, or none when [now], before they are cancelled.
  void stop({bool now = false}) {
    _stopRequested = true;
    _rerun = false;
    _debounce?.cancel();
    final halted = _halted;
    if (halted != null && !halted.isCompleted) halted.complete();
    final hurried = _hurried;
    if (now && hurried != null && !hurried.isCompleted) hurried.complete();
  }

  /// How long uploads under way get to finish once the background job's
  /// time is up.
  static const Duration _grace = Duration(seconds: 45);

  /// Runs one pass for the background job, for at most [budget], and
  /// answers how many photos it sent up. Once the time is up, or [stop] is
  /// called, the uploads under way get [_grace] to finish and the rest are
  /// cancelled, so no message half sent outlives the job.
  Future<int> runInBackground(Duration budget) async {
    _uploaded = 0;
    final halted = _halted = Completer<void>();
    final hurried = _hurried = Completer<void>();
    final timer = Timer(budget, stop);
    try {
      final pass = run();
      await Future.any([pass, halted.future]);
      if (halted.isCompleted) {
        final grace = Timer(_grace, () {
          if (!hurried.isCompleted) hurried.complete();
        });
        await Future.any([pass, hurried.future]);
        grace.cancel();
        await _cancelUploads();
        await pass;
      }
    } finally {
      timer.cancel();
      _halted = null;
      _hurried = null;
    }
    return _uploaded;
  }

  Future<void> _cancelUploads() async {
    final left = ref
        .read(transferQueueProvider)
        .items
        .where((t) => t.origin == TransferOrigin.backup && t.status.isPending)
        .toList();
    for (final item in left) {
      await _queue.cancel(item.id);
    }
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
        _lastPassAt = DateTime.now();
        _libraryChanged = false;
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
    _heldForWifi = 0;
    state = state.copyWith(
      phase: _waitsForWifi()
          ? BackupPhase.waitingForWifi
          : BackupPhase.scanning,
      heldVideos: 0,
      heldForBudget: 0,
      sendingSmallCopies: false,
      clearCurrent: true,
      clearError: true,
      clearPaused: true,
    );
    await ref.read(driveSyncProvider.notifier).whenIdle();
    // "Already in the drive" is judged against the index, so it has to hold
    // the whole channel. After a reinstall, a first read that stopped short
    // would make older photos look new and send them up a second time.
    if (!_indexComplete()) {
      state = state.copyWith(
        phase: BackupPhase.waitingForDrive,
        clearCurrent: true,
      );
      return;
    }
    final known = await _db.backupAssetMap();
    final checkpoint = _prefs.backupCheckpoint;
    final full = fullScanDue(
      lastFullScan: _prefs.backupLastFullScan,
      checkpoint: checkpoint,
      now: startedAt,
    );
    // Set before the scan, so a change that comes while it runs and makes
    // the next pass look through everything is not undone by this one.
    _recordsFullScan = full;
    // Between full looks, the photos added since everything was last dealt
    // with, an hour's overlap included, plus the ones still to be tried
    // again and the ones asked for, which may be older.
    final assets = full
        ? await _scan()
        : await _scan(
            since: checkpoint!.subtract(_scanOverlap),
            also: {
              for (final record in known.values)
                if (classify(record) == BackupDisposition.pending) record.assetId,
              ..._priority,
            },
          );
    final inScope = <String, AssetEntity>{};
    var failedIds = <String>{};
    var skippedIds = <String>{};
    final waiting = <AssetEntity>[];
    var done = 0;
    for (final asset in assets) {
      final record = known[asset.id];
      switch (classify(record)) {
        case BackupDisposition.skip:
          // Out of scope, like a folder that is switched off. Only the
          // photos set aside are counted as such; one deleted for good
          // from the drive, or gone from it and waiting on the person, is
          // not offered back.
          if (record?.state == BackupAssetState.skipped) skippedIds.add(asset.id);
          continue;
        case BackupDisposition.done:
          done++;
        case BackupDisposition.failed:
          failedIds.add(asset.id);
        case BackupDisposition.pending:
          waiting.add(asset);
      }
      inScope[asset.id] = asset;
    }

    // The list stays newest first while Back up now changes the order the
    // photos go up in. Photos leave it once they are in the drive, out of
    // tries or skipped.
    _listed = [
      for (final asset in waiting)
        PendingAsset(
          assetId: asset.id,
          takenAt: asset.createDateTime,
          folder: _folderName(asset),
        ),
    ];
    _settled.clear();

    final asked = _priority.toSet();
    var pending = orderPending(waiting, asked, (a) => a.id);
    // A request for a photo the scan didn't find has nothing left to send:
    // the photo was deleted, or its folder switched off. Nor has one for a
    // photo that is in the drive, such as one asked for while it was going
    // up. A failed photo the person retried stays asked for.
    _priority.removeWhere(
      (id) =>
          !inScope.containsKey(id) || known[id]?.state == BackupAssetState.done,
    );
    // Read after the scan, so a phone that moved onto mobile data while the
    // library was read is caught. With mobile data for photos only, videos
    // wait for Wi-Fi without their files being opened. One asked for with
    // Back up now stays, and is held when its turn comes.
    var heldVideos = 0;
    final metered = ref.read(networkStatusProvider).metered;
    if (metered && _prefs.backupMobileData == BackupMobileData.photos) {
      final kept = [
        for (final asset in pending)
          if (asset.type != AssetType.video || asked.contains(asset.id)) asset,
      ];
      heldVideos = pending.length - kept.length;
      pending = kept;
    } else if (metered &&
        _prefs.backupMobileData == BackupMobileData.off &&
        _prefs.backupSmallCopies) {
      // Mobile data carries small copies only: photos with none in the
      // drive yet go, and the rest wait for Wi-Fi without their files
      // being opened.
      final kept = [
        for (final asset in pending)
          if ((asset.type == AssetType.image &&
                  known[asset.id]?.state != BackupAssetState.smallCopy) ||
              asked.contains(asset.id))
            asset,
      ];
      _heldForWifi = pending.length - kept.length;
      pending = kept;
    }
    final smallCopies = inScope.keys
        .where((id) => known[id]?.state == BackupAssetState.smallCopy)
        .length;
    final hasWork = pending.isNotEmpty || _priority.isNotEmpty;
    _passIds = hasWork ? inScope.keys.toSet() : const {};

    var total = inScope.length;
    final records = known.values.where((r) => classify(r) != BackupDisposition.skip).length;
    if (full) {
      final found = inScope.keys.where(known.containsKey).length;
      _unfound = math.max(0, records - found);
    } else {
      // The photos this pass didn't look at are counted from the records:
      // the failed and skipped ones by their own, and the rest as done.
      failedIds = {
        for (final record in known.values)
          if (classify(record) == BackupDisposition.failed) record.assetId,
      };
      skippedIds = {
        for (final record in known.values)
          if (record.state == BackupAssetState.skipped) record.assetId,
      };
      final totals = incrementalTotals(
        records: records,
        unfound: _prefs.backupUnfoundRecords,
        unrecorded: inScope.keys.where((id) => !known.containsKey(id)).length,
        pending: waiting.length,
        failed: failedIds.length,
      );
      total = totals.total;
      done = totals.done;
    }

    // Counted before the network decides, so a backup waiting for Wi-Fi
    // says how much is left.
    state = state
        ._withFailed(failedIds, total: total)
        .copyWith(
          done: done,
          waiting: _shown(),
          skippedIds: skippedIds,
          heldVideos: heldVideos,
          smallCopies: smallCopies,
        );
    if (!hasWork) {
      if (heldVideos > 0 || _heldForWifi > 0) {
        state = state.copyWith(
          phase: BackupPhase.waitingForWifi,
          clearCurrent: true,
        );
      } else {
        await _finishPass(startedAt);
      }
      return;
    }
    // Requests stay queued while the pass waits, so the photos still go
    // first once Wi-Fi is back.
    if (_waitsForWifi()) {
      _pauseForWifi();
      return;
    }
    // The ones the order above put first go up from the front of it.
    final placed = {for (final asset in waiting) asset.id}.intersection(asked);
    _priority.removeWhere(placed.contains);
    state = state.copyWith(phase: BackupPhase.uploading);
    // Uploads earlier passes left in the queue go, or wait, by the rule as
    // it stands now: the limit may have renewed, or 'Use data anyway' been
    // tapped.
    await _markQueued();

    final fingerprints = await _repository.mediaFingerprints();
    final queue = pending.iterator;
    final started = <String>{};

    Future<void> worker() async {
      while (!_stopRequested && _prefs.backupEnabled) {
        if (_waitsForWifi()) {
          _pauseForWifi();
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
        if (!_due(record)) {
          // Skipped since the scan, or sent up by an earlier request: it
          // isn't waiting any more.
          if (_settled.add(asset.id)) state = state.copyWith(waiting: _shown());
          continue;
        }
        final wasSmall = record?.state == BackupAssetState.smallCopy;
        int? fewerSmall() => wasSmall ? math.max(0, state.smallCopies - 1) : null;
        // A held item stays on the list of what is waiting, and the worker
        // moves on, so smaller photos behind a video too big for the limit
        // still go. A small copy leaves it only once its original is in.
        switch (await _backUp(asset, fingerprints, record)) {
          case _Outcome.held:
            continue;
          case _Outcome.skipped:
            // A failed try for the original records the photo as failed,
            // with tries left, so it stops counting as a small copy. One
            // the person skipped was taken off the count then.
            if (wasSmall &&
                (await _db.backupAssetOf(asset.id))?.state == BackupAssetState.failed) {
              state = state.copyWith(smallCopies: fewerSmall());
            }
          case _Outcome.smallCopy:
            state = state.copyWith(smallCopies: state.smallCopies + 1);
          case _Outcome.done:
            _settled.add(asset.id);
            // Skipped as it landed, or as the drive turned out to hold it:
            // it is backed up, and counts as such.
            final landed = state.skippedIds.contains(asset.id);
            state = state.copyWith(
              done: state.done + 1,
              total: landed ? state.total + 1 : null,
              skippedIds: landed ? ({...state.skippedIds}..remove(asset.id)) : null,
              smallCopies: fewerSmall(),
              waiting: _shown(),
            );
          case _Outcome.failed:
            _settled.add(asset.id);
            state = state
                ._withFailed({...state.failedIds, asset.id})
                .copyWith(smallCopies: fewerSmall(), waiting: _shown());
        }
      }
    }

    await Future.wait([for (var i = 0; i < _parallel; i++) worker()]);
    // Nothing more goes up in this pass, so a request from here on needs
    // another.
    _passIds = const {};

    if (_stopRequested || !_prefs.backupEnabled) return;
    // Originals behind small copies wait like anything else held.
    final heldForWifi = state.heldVideos > 0 || _heldForWifi > 0 || state.smallCopies > 0;
    if (state.heldForBudget > 0 || heldForWifi) {
      // Not up to date: what is held goes on Wi-Fi, or once the limit
      // allows, and a photo that failed with tries left still gets its
      // next try.
      state = state.copyWith(
        phase: state.heldForBudget > 0
            ? BackupPhase.waitingForBudget
            : BackupPhase.waitingForWifi,
        clearCurrent: true,
      );
      final network = ref.read(networkStatusProvider);
      if (network.online && !network.metered) {
        // Wi-Fi came back while the pass ran, so what it held goes now.
        _rerun = true;
      } else if (_retryLater && !_rerun) {
        schedule();
      }
    } else if (_retryLater) {
      // A photo that failed with tries left gets its next try in a few
      // seconds, and backup isn't up to date until then.
      state = state.copyWith(clearCurrent: true);
      if (!_rerun) schedule();
    } else {
      await _finishPass(startedAt);
    }
  }

  /// Whether a photo with [record] still needs sending: never tried,
  /// failed with tries left, or in the drive only as a small copy. One in
  /// the drive, set aside, or out of tries (until Retry) is not.
  static bool _due(BackupAssetRow? record) =>
      record == null ||
      record.state == BackupAssetState.smallCopy ||
      (record.state == BackupAssetState.failed &&
          record.failures < maxFailures);

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
    if (_recordsFullScan) {
      await _prefs.setBackupFullScan(startedAt, unfound: _unfound);
      _recordsFullScan = false;
    }
    await BackupNotifications.clear();
    state = state.copyWith(
      phase: BackupPhase.upToDate,
      clearCurrent: true,
      lastCompleted: startedAt,
    );
  }

  /// Backs one asset up, and says how it went: [_Outcome.done] once it is
  /// in the drive, [_Outcome.smallCopy] once a small copy of it is and its
  /// original has to wait, [_Outcome.failed] once it is out of tries,
  /// [_Outcome.held] when it may not go up on this network now, and
  /// [_Outcome.skipped] when it stays waiting for another reason (already
  /// in flight, the pass was stopped, or a failure with tries left).
  ///
  /// The policy for one photo, in order: an upload an earlier pass left
  /// waiting is followed; a photo already in the drive is recorded, as a
  /// small copy when that is all there is; a photo with a small copy has
  /// its original put in the copy's place once the network and the monthly
  /// limit let it go; any other goes up whole when they let it, and as a
  /// small copy when only that fits; and anything else waits.
  Future<_Outcome> _backUp(
    AssetEntity asset,
    Map<String, ({String fileId, bool smallCopy})> fingerprints,
    BackupAssetRow? record,
  ) async {
    if (!_activeAssets.add(asset.id)) return _Outcome.skipped;
    final isVideo = asset.type == AssetType.video;
    String? thumbnail;
    try {
      // An earlier pass left its upload waiting for Wi-Fi, with what it has
      // sent so far: this one follows it, unless it still has to wait.
      if (_heldUploads.remove(asset.id) case final id?) {
        final held = ref
            .read(transferQueueProvider)
            .items
            .where((t) => t.id == id)
            .firstOrNull
            ?.row;
        void uploaded(String fileId) =>
            fingerprints['${held!.name}|${held.totalBytes}'] = (fileId: fileId, smallCopy: false);
        if (held?.status == TransferStatus.completed) {
          return await _landed(asset, held!, record, uploaded: uploaded);
        }
        if (held != null && held.status.isPending) {
          if (held.wifiOnly && ref.read(networkStatusProvider).metered) {
            _heldUploads[asset.id] = id;
            return _hold(isVideo: isVideo);
          }
          state = state.copyWith(current: held.name);
          return await _follow(asset, id, record, uploaded: uploaded);
        }
      }

      // Only a small copy is in the drive, and the original is what is left
      // to send. One whose file left the drive on purpose isn't sent again,
      // and one whose original is in already is done.
      FileRow? small;
      if (record?.state == BackupAssetState.smallCopy) {
        small = record!.fileId == null ? null : await _db.fileById(record.fileId!);
        if (small == null || small.originalSize == null) {
          await _db.markAssetBackedUp(asset.id, small?.id);
          return _Outcome.done;
        }
      }
      // Mobile data it may not use at all: there is no need to open the
      // file, unless a photo may go up as a small copy meanwhile.
      if (_waitsForWifi(isVideo: isVideo) && (small != null || !_smallCopyTier(asset))) {
        return _hold(isVideo: isVideo);
      }

      final file = await asset.originFile;
      if (file == null || !await file.exists()) {
        return await _fail(
          asset,
          record,
          'This photo is no longer on this phone.',
        );
      }
      final name = await _nameOf(asset, file);
      final size = await file.length();

      // Already up there, from an earlier install or another phone; as a
      // small copy, its original still goes up from here. A photo whose
      // original already failed keeps its tries, so one that keeps failing
      // ends up under Not backed up rather than starting over each pass.
      var recognised = false;
      if (fingerprints['$name|$size'] case final existing? when small == null) {
        if (!existing.smallCopy) {
          await _db.markAssetBackedUp(asset.id, existing.fileId);
          return _Outcome.done;
        }
        small = await _db.fileById(existing.fileId);
        if (small != null && record?.state != BackupAssetState.failed) {
          await _db.markAssetSmallCopy(asset.id, small.id);
          record = await _db.backupAssetOf(asset.id);
          recognised = true;
        }
      }

      // Android 11+ hands back the original; only delete our own copies.
      final temp = (await getTemporaryDirectory()).path;
      final ownsSource = file.path.startsWith(temp);
      final allowance = await _allowance(isVideo: isVideo, bytes: size);

      if (small != null) {
        if (allowance != BackupAllowance.go) {
          if (ownsSource) await _deleteQuietly(file.path);
          final held = _hold(isVideo: false);
          return recognised ? _Outcome.smallCopy : held;
        }
        state = state.copyWith(current: name);
        thumbnail = await _thumbnailFor(asset);
        final ids = await _queue.enqueueUploads([
          UploadRequest(
            name: name,
            path: file.path,
            size: size,
            ownsSource: ownsSource,
            origin: TransferOrigin.backup,
            assetId: asset.id,
            takenAt: asset.createDateTime,
            thumbnailPath: thumbnail,
            wifiOnly: !mayUseMobileData(_prefs.backupMobileData, isVideo: false),
            fileId: small.id,
            replacesSmallCopy: true,
          ),
        ], folderId: small.folderId);
        if (ids.isEmpty) {
          return await _fail(asset, record, 'Couldn\'t start the upload.');
        }
        thumbnail = null; // The queue owns it now.
        return await _follow(asset, ids.first, record, uploaded: (fileId) {
          fingerprints['$name|$size'] = (fileId: fileId, smallCopy: false);
        });
      }

      if (allowance != BackupAllowance.go) {
        if (ownsSource) await _deleteQuietly(file.path);
        // The original may not go now; a photo can still go as a small
        // copy, as long as the monthly limit has room for it.
        return _smallCopyTier(asset)
            ? await _sendSmallCopy(asset, name, size, record, fingerprints)
            : _hold(isVideo: isVideo);
      }

      state = state.copyWith(current: name);
      final folderId = await _folderFor(asset);
      thumbnail = await _thumbnailFor(asset);

      final ids = await _queue.enqueueUploads([
        UploadRequest(
          name: name,
          path: file.path,
          size: size,
          ownsSource: ownsSource,
          origin: TransferOrigin.backup,
          assetId: asset.id,
          takenAt: asset.createDateTime,
          thumbnailPath: thumbnail,
          // An upload under way when the phone moves onto mobile data it
          // may not use (a hotspot included) steps back to wait for Wi-Fi.
          wifiOnly: !mayUseMobileData(
            _prefs.backupMobileData,
            isVideo: isVideo,
          ),
          // The gallery already knows a video's length, in whole seconds.
          durationSeconds: isVideo && asset.duration > 0
              ? asset.duration
              : null,
        ),
      ], folderId: folderId);
      if (ids.isEmpty) {
        return await _fail(asset, record, 'Couldn\'t start the upload.');
      }
      thumbnail = null; // The queue owns it now.

      return await _follow(asset, ids.first, record, uploaded: (fileId) {
        fingerprints['$name|$size'] = (fileId: fileId, smallCopy: false);
      });
    } catch (e) {
      debugPrint('[Backup] ${asset.id}: $e');
      if (_pauseFor(e)) return _Outcome.skipped;
      return _fail(asset, record, describeTransferError(e));
    } finally {
      _activeAssets.remove(asset.id);
      if (thumbnail != null) await _deleteQuietly(thumbnail);
    }
  }

  /// Sends a small copy of [asset], the photo [name] whose original is
  /// [size] bytes, when the phone makes one that fits what is left of the
  /// monthly limit; otherwise the photo waits as it would without.
  Future<_Outcome> _sendSmallCopy(
    AssetEntity asset,
    String name,
    int size,
    BackupAssetRow? record,
    Map<String, ({String fileId, bool smallCopy})> fingerprints,
  ) async {
    final copy = await _smallCopyFor(asset);
    if (copy == null) return _hold(isVideo: false);
    String? thumbnail;
    var queued = false;
    try {
      final bytes = await File(copy).length();
      if (!await _fits(bytes)) return _hold(isVideo: false);
      state = state.copyWith(current: name, sendingSmallCopies: true);
      final folderId = await _folderFor(asset);
      thumbnail = await _thumbnailFor(asset);
      final ids = await _queue.enqueueUploads([
        UploadRequest(
          name: name,
          path: copy,
          size: bytes,
          ownsSource: true,
          origin: TransferOrigin.backup,
          assetId: asset.id,
          takenAt: asset.createDateTime,
          thumbnailPath: thumbnail,
          smallCopyOf: size,
        ),
      ], folderId: folderId);
      if (ids.isEmpty) {
        return await _fail(asset, record, 'Couldn\'t start the upload.');
      }
      queued = true; // The queue owns the copy and the thumbnail now.
      return await _follow(asset, ids.first, record, smallCopy: true, uploaded: (fileId) {
        fingerprints['$name|$size'] = (fileId: fileId, smallCopy: true);
      });
    } finally {
      if (!queued) {
        await _deleteQuietly(copy);
        if (thumbnail != null) await _deleteQuietly(thumbnail);
      }
    }
  }

  /// Whether [asset] may go up as a small copy now: the switch is on, it is
  /// a photo, and the phone is on mobile data. Videos have no small copy.
  bool _smallCopyTier(AssetEntity asset) =>
      _prefs.backupSmallCopies &&
      asset.type == AssetType.image &&
      ref.read(networkStatusProvider).metered;

  /// Waits for [asset]'s upload [id] to end, and calls [uploaded] with the
  /// new file's id once it is in the drive. A [smallCopy] is recorded as
  /// one. An upload that steps back into the queue to wait for Wi-Fi is
  /// left there for a later pass to follow, so the worker can move on to
  /// what may still go.
  Future<_Outcome> _follow(
    AssetEntity asset,
    String id,
    BackupAssetRow? record, {
    bool smallCopy = false,
    required void Function(String fileId) uploaded,
  }) async {
    // Skipped from the Backup queue as it was being got ready: the upload
    // goes before it sends anything.
    if ((await _db.backupAssetOf(asset.id))?.state == BackupAssetState.skipped) {
      await _queue.remove(id);
      return _Outcome.skipped;
    }
    final row = await untilEndedOrHeld(ref, id);
    if (row == null) {
      _heldUploads[asset.id] = id;
      return _hold(isVideo: asset.type == AssetType.video);
    }
    switch (row.status) {
      case TransferStatus.completed:
        return _landed(asset, row, record, smallCopy: smallCopy, uploaded: uploaded);
      case TransferStatus.cancelled:
        return _Outcome.skipped;
      default:
        if (_pauseFor(null)) return _Outcome.skipped;
        return _fail(asset, record, row.error ?? 'Something went wrong.');
    }
  }

  /// [asset]'s upload [row] is in the drive. A [smallCopy] is recorded as
  /// such, so its original still goes up and the phone's copy is kept. An
  /// original counts as backed up only once the index holds it: one that
  /// went into a small copy's message must have cleared the small copy's
  /// mark, or the phone's copy could be deleted with only the small copy
  /// in the drive.
  Future<_Outcome> _landed(
    AssetEntity asset,
    TransferRow row,
    BackupAssetRow? record, {
    bool smallCopy = false,
    required void Function(String fileId) uploaded,
  }) async {
    if (smallCopy) {
      await _db.markAssetSmallCopy(asset.id, row.fileId);
    } else if ((await _db.fileById(row.fileId))?.originalSize != null) {
      return _fail(asset, record, 'The original couldn\'t replace the small copy.');
    } else {
      await _db.markAssetBackedUp(asset.id, row.fileId);
    }
    uploaded(row.fileId);
    _uploaded++;
    state = state.copyWith(
      recent: [
        RecentBackup(assetId: asset.id, fileId: row.fileId),
        ...state.recent.where((r) => r.assetId != asset.id).take(recentKept - 1),
      ],
    );
    return smallCopy ? _Outcome.smallCopy : _Outcome.done;
  }

  /// Telegram asked the account to wait, for [error] or for the uploads in
  /// the queue: the photo stays waiting without a failure counted, the
  /// pass stops, and in the app the next one starts once the wait is over.
  /// The background job ends with photos left, so Android runs it again.
  bool _pauseFor(Object? error) {
    final wait = error == null ? null : telegramWaitOf(error);
    final own = wait == null ? null : DateTime.now().add(wait);
    final queued = _queue.floodWaitUntil;
    final until = own == null || (queued != null && queued.isAfter(own)) ? queued : own;
    if (until == null) return false;
    _stopRequested = true;
    _rerun = false;
    final paused = state.pausedUntil;
    if (paused != null && !until.isAfter(paused)) return true;
    state = state.copyWith(pausedUntil: until, clearCurrent: true);
    if (!_background) {
      _pauseTimer?.cancel();
      _pauseTimer = Timer(until.difference(DateTime.now()) + const Duration(seconds: 1), () {
        _pauseTimer = null;
        schedule(immediate: true);
      });
    }
    return true;
  }

  /// Records a failed try with [reason]. [_Outcome.failed] once the photo
  /// is out of tries; while it has tries left it stays waiting, and the
  /// pass asks for another soon after it ends.
  Future<_Outcome> _fail(
    AssetEntity asset,
    BackupAssetRow? record,
    String reason,
  ) async {
    // Skipped while it was being got ready: it stays skipped.
    if ((await _db.backupAssetOf(asset.id))?.state == BackupAssetState.skipped) {
      return _Outcome.skipped;
    }
    final failures = (record?.failures ?? 0) + 1;
    await _db.markAssetFailed(asset.id, failures, reason: reason);
    if (failures >= maxFailures) return _Outcome.failed;
    _retryLater = true;
    return _Outcome.skipped;
  }

  /// Counts an item that may not go up on this network now, for the line
  /// the pass ends on: the monthly limit when its kind may use mobile data,
  /// or Wi-Fi for a video when mobile data is for photos only, or for
  /// anything but a small copy when mobile data is off for backup.
  _Outcome _hold({required bool isVideo}) {
    final mode = _prefs.backupMobileData;
    if (mayUseMobileData(mode, isVideo: isVideo)) {
      state = state.copyWith(heldForBudget: state.heldForBudget + 1);
    } else if (mode == BackupMobileData.photos) {
      state = state.copyWith(heldVideos: state.heldVideos + 1);
    } else {
      _heldForWifi++;
    }
    return _Outcome.held;
  }

  /// The backup rule for an item of [bytes], against the monthly limit as
  /// TDLib counts it now, with what the backup uploads already let onto
  /// mobile data still have to send.
  Future<BackupAllowance> _allowance({
    required bool isVideo,
    required int bytes,
  }) async {
    final committed = await _committed();
    return backupAllowance(
      data: ref.read(mobileDataProvider),
      mode: _prefs.backupMobileData,
      isVideo: isVideo,
      bytes: committed + bytes,
    );
  }

  /// Whether a small copy of [bytes] fits what is left of the monthly
  /// limit, with what the backup uploads already let onto mobile data.
  Future<bool> _fits(int bytes) async {
    final committed = await _committed();
    return ref.read(mobileDataProvider).fits(committed + bytes);
  }

  /// What the backup uploads let onto mobile data still have to send, with
  /// the monthly count brought up to date.
  Future<int> _committed() async {
    await ref.read(mobileDataProvider.notifier).refresh();
    return ref
        .read(transferQueueProvider)
        .items
        .where(
          (t) =>
              t.origin == TransferOrigin.backup &&
              t.status.isPending &&
              !t.row.wifiOnly,
        )
        .fold<int>(0, (sum, t) => sum + t.row.totalBytes - t.row.doneBytes);
  }

  /// Marks the backup uploads in the queue by the backup rule as it stands,
  /// oldest first so what is under way keeps going. Those it holds become
  /// Wi-Fi only, so the queue keeps them and steps back any under way on
  /// mobile data; those it lets go are released.
  Future<void> _markQueued() async {
    if (!ref
        .read(transferQueueProvider)
        .items
        .any((t) => t.origin == TransferOrigin.backup)) {
      return;
    }
    await ref.read(mobileDataProvider.notifier).refresh();
    final data = ref.read(mobileDataProvider);
    final mode = _prefs.backupMobileData;
    final hold = <String>[];
    final release = <String>[];
    var planned = 0;
    for (final item in ref.read(transferQueueProvider).items.reversed) {
      if (item.origin != TransferOrigin.backup || !item.status.isPending) {
        continue;
      }
      final row = item.row;
      // A small copy was fitted into the limit as it was queued, and goes
      // on mobile data whatever the choice for originals.
      if (_queue.sendsSmallCopy(row.id)) {
        planned += row.totalBytes - row.doneBytes;
        continue;
      }
      final isVideo = item.fileKind == FileKind.video;
      final left = row.totalBytes - row.doneBytes;
      final allowed =
          mayUseMobileData(mode, isVideo: isVideo) &&
          backupAllowance(
                data: data,
                mode: mode,
                isVideo: isVideo,
                bytes: planned + left,
              ) ==
              BackupAllowance.go;
      if (allowed) planned += left;
      if (allowed && row.wifiOnly) release.add(row.id);
      if (!allowed && !row.wifiOnly) hold.add(row.id);
    }
    if (hold.isNotEmpty) await _queue.waitForWifi(hold);
    if (release.isNotEmpty) await _queue.useMobileData(release);
  }

  /// The phone is on mobile data, and backup may not use it for anything,
  /// small copies included, or, given [isVideo], for this item in full.
  bool _waitsForWifi({bool? isVideo}) {
    final mode = _prefs.backupMobileData;
    return ref.read(networkStatusProvider).metered &&
        (isVideo == null
            ? mode == BackupMobileData.off && !_prefs.backupSmallCopies
            : !mayUseMobileData(mode, isVideo: isVideo));
  }

  /// Backup as a whole waits for Wi-Fi, so no count of held videos applies.
  void _pauseForWifi() => state = state.copyWith(
    phase: BackupPhase.waitingForWifi,
    heldVideos: 0,
    clearCurrent: true,
  );

  static Future<void> _deleteQuietly(String path) async {
    try {
      await File(path).delete();
    } catch (_) {}
  }

  /// How far before the checkpoint a look at the newest photos starts, so
  /// a photo the phone added just as the last pass began isn't missed.
  static const Duration _scanOverlap = Duration(hours: 1);

  /// How often a pass looks through the whole library at the least.
  static const Duration _fullScanEvery = Duration(hours: 24);

  /// Whether the pass starting at [now] looks through the whole library:
  /// it never has ([lastFullScan] null, which a change to what is backed
  /// up also makes it), it last did a day or more ago, or no pass has yet
  /// dealt with everything ([checkpoint] null), so there is no telling
  /// which photos are new.
  @visibleForTesting
  static bool fullScanDue({
    DateTime? lastFullScan,
    DateTime? checkpoint,
    required DateTime now,
  }) =>
      lastFullScan == null ||
      checkpoint == null ||
      lastFullScan.isAfter(now) ||
      now.difference(lastFullScan) >= _fullScanEvery;

  /// The counts after a pass that looked only at the newest photos: every
  /// record still in scope, less the [unfound] ones the last full look
  /// found no photo for, plus the [unrecorded] photos the pass found that
  /// have none yet, makes the total. What isn't [pending] or [failed] of
  /// that is done.
  @visibleForTesting
  static ({int total, int done}) incrementalTotals({
    required int records,
    required int unfound,
    required int unrecorded,
    required int pending,
    required int failed,
  }) {
    final total = math.max(0, records - unfound) + unrecorded;
    return (total: total, done: math.max(0, total - pending - failed));
  }

  /// Everything in scope, newest first, or with [since] only the photos
  /// added to the phone since then, which Android tells by when each was
  /// added, so an old photo saved today counts as new. The photos in
  /// [also] are fetched one by one and follow, when they are still on the
  /// phone and in scope.
  Future<List<AssetEntity>> _scan({DateTime? since, Set<String> also = const {}}) async {
    final videos = _prefs.backupVideos;
    final paths = await PhotoManager.getAssetPathList(
      type: videos ? RequestType.common : RequestType.image,
      onlyAll: true,
      filterOption: FilterOptionGroup(
        orders: [
          const OrderOption(type: OrderOptionType.createDate, asc: false),
        ],
        createTimeCond: since == null
            ? null
            : DateTimeCond(min: since, max: DateTime.now()),
      ),
    );
    final excluded = _prefs.backupExcludedFolders
        .map((f) => f.toLowerCase())
        .toSet();
    bool inScope(AssetEntity asset) =>
        (asset.type == AssetType.image || (videos && asset.type == AssetType.video)) &&
        !excluded.contains(_folderName(asset).toLowerCase());

    final assets = <AssetEntity>[];
    if (paths.isNotEmpty) {
      final all = paths.first;
      final count = await all.assetCountAsync;
      for (var start = 0; start < count; start += _pageSize) {
        final page = await all.getAssetListRange(
          start: start,
          end: math.min(start + _pageSize, count),
        );
        assets.addAll(page.where(inScope));
      }
    }
    final seen = {for (final asset in assets) asset.id};
    for (final id in also) {
      if (seen.contains(id)) continue;
      final asset = await AssetEntity.fromId(id);
      if (asset != null && inScope(asset)) assets.add(asset);
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

  /// A JPEG of the photo, asked for at 1600 px and quality 80, about 300 KB:
  /// what goes up first while the original can't. Null when the phone can't
  /// make one, or it comes out over 1 MB, which isn't worth sending ahead
  /// of the original; the photo then waits as it would without.
  static Future<String?> _smallCopyFor(AssetEntity asset) async {
    try {
      final bytes = await asset.thumbnailDataWithSize(
        const ThumbnailSize(1600, 1600),
        quality: 80,
      );
      if (bytes == null || bytes.isEmpty || bytes.length > 1024 * 1024) {
        return null;
      }
      final dir = Directory(
        p.join((await getTemporaryDirectory()).path, 'telegrive-small'),
      );
      await dir.create(recursive: true);
      final file = File(p.join(dir.path, '${asset.id.hashCode}.jpg'));
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (_) {
      return null;
    }
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

  // ---------------------------------------------------------------------------
  // Watching the library while the app is alive
  // ---------------------------------------------------------------------------

  bool _watching = false;

  /// A photo deleted from the phone still has its record, so the next pass
  /// looks through the whole library to count it out.
  void _onLibraryChanged(MethodCall call) {
    _libraryChanged = true;
    final change = call.arguments;
    if (change is Map && change['type'] == 'delete') {
      unawaited(_forgetFullScan());
    }
    schedule();
  }

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

/// How one item's turn in a pass ended.
enum _Outcome { done, smallCopy, failed, skipped, held }

final backupControllerProvider =
    NotifierProvider<BackupController, BackupState>(BackupController.new);

/// Backup's uploads in the transfer queue that haven't ended, in the order
/// they were queued: what the Backup queue shows going up now.
final backupUploadsProvider = Provider.autoDispose<List<TransferItem>>(
  (ref) => ref
      .watch(transferQueueProvider)
      .items
      .reversed
      .where(
        (t) => t.origin == TransferOrigin.backup && t.row.assetId != null && t.status.isPending,
      )
      .toList(),
);

/// The photos and videos this run of the app backed up that are still in
/// the drive and out of the trash, newest moment first, live.
final recentBackupsProvider = StreamProvider.autoDispose<List<DriveFile>>((ref) {
  final recent = ref.watch(backupControllerProvider.select((s) => s.recent));
  return ref.watch(driveRepositoryProvider).watchFiles([for (final r in recent) r.fileId]);
});

/// How many photos and videos the drive holds from backup, live.
final backedUpCountProvider = StreamProvider.autoDispose<int>(
  (ref) => ref.watch(appDatabaseProvider).watchBackedUpCount(),
);

/// Photos that are out of tries, most recently failed first, live. Only
/// the ones in [BackupState.failedIds], so the list matches the count.
final failedBackupAssetsProvider =
    StreamProvider.autoDispose<List<BackupAssetRow>>((ref) {
      final counted = ref.watch(
        backupControllerProvider.select((s) => s.failedIds),
      );
      return ref
          .watch(appDatabaseProvider)
          .watchFailedAssets(minFailures: BackupController.maxFailures)
          .map(
            (rows) => [
              for (final row in rows)
                if (counted.contains(row.assetId)) row,
            ],
          );
    });

/// How many of this phone's photos have only a small copy in the drive,
/// and how big their originals are, live: what the Backup screen says is
/// still to send.
final pendingOriginalsProvider = StreamProvider.autoDispose<({int count, int bytes})>(
  (ref) => ref.watch(appDatabaseProvider).watchPendingOriginals(),
);

/// How many photos backed up from this phone are no longer in the drive
/// and wait for the person's choice, live.
final missingCountProvider = StreamProvider.autoDispose<int>(
  (ref) => ref.watch(appDatabaseProvider).watchMissingCount(),
);

/// How many photos the person set aside, live. Only the ones in
/// [BackupState.skippedIds], so the count covers the photos the total
/// leaves out.
final skippedBackupCountProvider = StreamProvider.autoDispose<int>((ref) {
  final counted = ref.watch(
    backupControllerProvider.select((s) => s.skippedIds),
  );
  return ref
      .watch(appDatabaseProvider)
      .watchSkippedAssetIds()
      .map((ids) => ids.where(counted.contains).length);
});
