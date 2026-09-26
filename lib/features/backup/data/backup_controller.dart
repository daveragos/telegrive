import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../infrastructure/database/app_database.dart';
import '../../../infrastructure/storage/preferences.dart';
import '../../drive/data/drive_repository.dart';
import '../../drive/data/drive_session.dart';
import '../../drive/data/drive_sync.dart';
import '../../transfers/data/transfer_queue.dart';
import 'backup_notifications.dart';
import 'backup_worker.dart';

enum BackupPhase {
  /// Backup is turned off.
  off,

  /// On, but the app can't see the photo library.
  needsPermission,

  /// On, waiting for the drive to open (right after launch).
  waitingForDrive,

  /// On, but only allowed over Wi-Fi and there is none.
  waitingForWifi,

  /// Looking through the photo library.
  scanning,

  /// Sending photos up.
  uploading,

  /// Everything in scope is in the drive.
  upToDate,
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
  });

  final BackupPhase phase;

  /// Photos and videos in scope (selected folders, videos on or off).
  final int total;

  /// How many of [total] are safely in the drive.
  final int done;

  /// Items that failed repeatedly and are skipped for now.
  final int failed;

  /// Name of something being uploaded right now.
  final String? current;
  final DateTime? lastCompleted;

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
  }) => BackupState(
    phase: phase ?? this.phase,
    total: total ?? this.total,
    done: done ?? this.done,
    failed: failed ?? this.failed,
    current: clearCurrent ? null : (current ?? this.current),
    lastCompleted: lastCompleted ?? this.lastCompleted,
  );
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
  static const int _maxFailures = 3;
  static const int _pageSize = 500;

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
  StreamSubscription<List<ConnectivityResult>>? _connectivity;
  final Map<String, Future<String>> _folderIds = {};
  final Set<String> _activeAssets = {};

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

    _connectivity = Connectivity().onConnectivityChanged.listen((_) {
      if (state.phase == BackupPhase.waitingForWifi) schedule(immediate: true);
    });
    BackupWorker.onNewMediaInApp = () => schedule();
    if (enabled) {
      _watchLibrary();
      // Re-arm the background checks (a no-op when they are already set).
      unawaited(BackupWorker.schedule());
    }

    ref.onDispose(() {
      _debounce?.cancel();
      _connectivity?.cancel();
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

  Future<void> disable() async {
    await _prefs.setBackupEnabled(false);
    _stopRequested = true;
    _unwatchLibrary();
    unawaited(BackupWorker.cancel());
    unawaited(BackupNotifications.clear());
    for (final item in ref.read(transferQueueProvider).backupActive) {
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
    _restart();
  }

  Future<void> setFolderIncluded(String folder, {required bool included}) async {
    final excluded = _prefs.backupExcludedFolders;
    included ? excluded.remove(folder) : excluded.add(folder);
    await _prefs.setBackupExcludedFolders(excluded);
    _restart();
  }

  /// Gives items that failed before another go.
  Future<void> retryFailed() async {
    await _db.clearBackupFailures();
    schedule(immediate: true);
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
        await _pass();
      } while (_rerun && _prefs.backupEnabled);
    } catch (e, stack) {
      debugPrint('[Backup] pass failed: $e\n$stack');
      if (_prefs.backupEnabled) {
        state = state.copyWith(phase: BackupPhase.upToDate, clearCurrent: true);
      }
    } finally {
      _running = false;
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
    if (!await _networkAllowed()) {
      state = state.copyWith(phase: BackupPhase.waitingForWifi);
      return;
    }

    final startedAt = DateTime.now();
    state = state.copyWith(phase: BackupPhase.scanning, clearCurrent: true);
    await ref.read(driveSyncProvider.notifier).whenIdle();
    final assets = await _scan();
    final known = await _db.backupAssetMap();

    var done = 0;
    var failed = 0;
    final pending = <AssetEntity>[];
    for (final asset in assets) {
      final record = known[asset.id];
      if (record?.state == BackupAssetState.done) {
        done++;
      } else if ((record?.failures ?? 0) >= _maxFailures) {
        failed++;
      } else {
        pending.add(asset);
      }
    }
    state = state.copyWith(
      phase: pending.isEmpty ? BackupPhase.upToDate : BackupPhase.uploading,
      total: assets.length,
      done: done,
      failed: failed,
    );
    if (pending.isEmpty) {
      await _finishPass(startedAt);
      return;
    }

    final fingerprints = await _repository.mediaFingerprints();
    final queue = pending.iterator;
    AssetEntity? next() => queue.moveNext() ? queue.current : null;

    Future<void> worker() async {
      while (!_stopRequested && _prefs.backupEnabled) {
        if (!await _networkAllowed()) {
          state = state.copyWith(phase: BackupPhase.waitingForWifi, clearCurrent: true);
          _stopRequested = true;
          return;
        }
        final asset = next();
        if (asset == null) return;
        final outcome = await _backUp(asset, fingerprints, known[asset.id]);
        if (outcome == null) continue;
        state = outcome
            ? state.copyWith(done: state.done + 1)
            : state.copyWith(failed: state.failed + 1);
      }
    }

    await Future.wait([for (var i = 0; i < _parallel; i++) worker()]);

    if (!_stopRequested && _prefs.backupEnabled) await _finishPass(startedAt);
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

  /// Backs one asset up. True when it is in the drive, false when it failed,
  /// null when it was skipped (already in flight, or the pass was stopped).
  Future<bool?> _backUp(
    AssetEntity asset,
    Set<String> fingerprints,
    BackupAssetRow? record,
  ) async {
    if (!_activeAssets.add(asset.id)) return null;
    String? thumbnail;
    try {
      final file = await asset.originFile;
      if (file == null || !await file.exists()) {
        return await _fail(asset, record);
      }
      final name = await _nameOf(asset, file);
      final size = await file.length();

      // Already up there, from an earlier install or another phone.
      if (fingerprints.contains('$name|$size')) {
        await _db.markAssetBackedUp(asset.id, null);
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
        ),
      ], folderId: folderId);
      if (ids.isEmpty) return await _fail(asset, record);
      thumbnail = null; // The queue owns it now.

      final row = await _queue.whenFinished(ids.first);
      switch (row.status) {
        case TransferStatus.completed:
          await _db.markAssetBackedUp(asset.id, row.fileId);
          fingerprints.add('$name|$size');
          return true;
        case TransferStatus.cancelled:
          return null;
        default:
          return await _fail(asset, record);
      }
    } catch (e) {
      debugPrint('[Backup] ${asset.id}: $e');
      return _fail(asset, record);
    } finally {
      _activeAssets.remove(asset.id);
      if (thumbnail != null) {
        try {
          await File(thumbnail).delete();
        } catch (_) {}
      }
    }
  }

  Future<bool> _fail(AssetEntity asset, BackupAssetRow? record) async {
    final failures = (record?.failures ?? 0) + 1;
    await _db.markAssetFailed(asset.id, failures);
    return false;
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
        const ThumbnailSize(320, 320),
        quality: 80,
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

  Future<bool> _networkAllowed() async {
    if (!_prefs.backupWifiOnly) return true;
    final results = await Connectivity().checkConnectivity();
    return results.contains(ConnectivityResult.wifi) ||
        results.contains(ConnectivityResult.ethernet);
  }

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
