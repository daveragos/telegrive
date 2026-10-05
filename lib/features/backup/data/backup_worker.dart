import 'dart:io';
import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../../../infrastructure/storage/preferences.dart';
import '../../../infrastructure/telegram/td_ownership.dart';
import 'background_backup.dart';
import 'backup_notifications.dart';

/// Notices new photos while Telegrive isn't open (Android).
///
/// Two scheduled jobs, both deliberately small — they never touch Telegram:
///
/// * a **media trigger** that Android fires as soon as something is added to
///   the photo library, and
/// * a **periodic check** every few hours as a safety net.
///
/// Each runs on an engine of its own and notes when it ran. While the
/// app's engine is alive it backs up by itself, so the job leaves it at
/// that. Otherwise it counts photos newer than the last finished backup
/// and, if there are any, asks for [BackgroundBackup] when backup runs on
/// its own, and posts "N new photos to back up", unless that reminder was
/// swiped away less than a day ago.
abstract final class BackupWorker {
  static const String _periodicTask = 'telegrive.backup-check';
  static const String _triggerTask = 'telegrive.media-trigger';

  /// Android, where the jobs exist.
  static bool get supported => !kIsWeb && Platform.isAndroid;

  static Future<void>? _initializing;

  /// Hands Android the job's entry point, once. The app does it after its
  /// first frame, and backup may arm the jobs before that, so whichever
  /// comes first does it and the other waits for it.
  static Future<void> initialize() => _initializing ??= _initialize();

  static Future<void> _initialize() async {
    if (!supported) return;
    try {
      await Workmanager().initialize(backupWorkerDispatcher);
    } catch (e) {
      debugPrint('[BackupWorker] initialize failed: $e');
    }
  }

  /// Arms both jobs. The trigger already armed is kept; the periodic check
  /// is registered again.
  static Future<void> schedule() async {
    if (!supported) return;
    await initialize();
    try {
      // Handed over afresh each time rather than kept: a kept registration
      // can sit enqueued without ever reaching Android's job scheduler, and
      // then never runs. The four hours start again when the app opens,
      // which costs nothing, since the app backs up by itself while open.
      await Workmanager().registerPeriodicTask(
        _periodicTask,
        _periodicTask,
        frequency: const Duration(hours: 4),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
      );
      await _armTrigger(replace: false);
    } catch (e) {
      debugPrint('[BackupWorker] schedule failed: $e');
    }
  }

  /// Calls off both checks and a backup job waiting to run.
  static Future<void> cancel() async {
    if (!supported) return;
    try {
      await Workmanager().cancelByUniqueName(_periodicTask);
      await Workmanager().cancelByUniqueName(_triggerTask);
      await Workmanager().cancelByUniqueName(BackgroundBackup.runTask);
    } catch (_) {}
  }

  /// Whether either check is armed with Android.
  static Future<bool> armed() async {
    if (!supported) return false;
    try {
      return await Workmanager().isScheduledByUniqueName(_periodicTask) ||
          await Workmanager().isScheduledByUniqueName(_triggerTask);
    } catch (e) {
      debugPrint('[BackupWorker] armed: $e');
      return false;
    }
  }

  /// Content-URI triggers fire once, so the job re-arms itself each run.
  static Future<void> _armTrigger({required bool replace}) {
    return Workmanager().registerOneOffTask(
      _triggerTask,
      _triggerTask,
      existingWorkPolicy: replace ? ExistingWorkPolicy.replace : ExistingWorkPolicy.keep,
      constraints: Constraints(
        contentUriTriggers: [
          ContentUriTrigger(
            uri: 'content://media/external/images/media',
            triggerForDescendants: true,
          ),
          ContentUriTrigger(
            uri: 'content://media/external/video/media',
            triggerForDescendants: true,
          ),
        ],
      ),
    );
  }

  static Future<void> _run(String task) async {
    final shared = await SharedPreferences.getInstance();
    await shared.reload();
    final prefs = Preferences(shared);
    await prefs.setBackgroundChecked(DateTime.now());
    if (!prefs.backupEnabled) return;

    if (task == _triggerTask) await _armTrigger(replace: true);

    // The app's engine owns TDLib while it is alive, and backs the photos
    // up by itself.
    if (await (await TdOwnership.inAppSupport()).isHeld()) return;

    final count = await _countNewMedia(shared);
    final unattended = prefs.backupUnattended;
    final wifiOnly = prefs.backupMobileData == BackupMobileData.off;
    if (unattended && count > 0) await BackgroundBackup.enqueue(wifiOnly: wifiOnly);
    final remind = shouldRemind(
      count: count,
      notifiedCount: shared.getInt(BackupPrefKeys.notifiedCount),
      remindAfterMillis: shared.getInt(BackupPrefKeys.remindAfter),
      now: DateTime.now(),
    );
    if (!remind) return;
    await BackupNotifications.showNewMedia(count, unattended: unattended, wifiOnly: wifiOnly);
    await shared.setInt(BackupPrefKeys.notifiedCount, count);
  }

  /// Whether to post the reminder for [count] new photos. It is said once
  /// per new batch, not every time the job wakes up, so not when
  /// [notifiedCount] photos were the last ones it was posted for, and not
  /// before [remindAfterMillis], which a swipe sets a day ahead.
  @visibleForTesting
  static bool shouldRemind({
    required int count,
    int? notifiedCount,
    int? remindAfterMillis,
    required DateTime now,
  }) {
    if (count == 0) return false;
    if (remindAfterMillis != null &&
        now.isBefore(DateTime.fromMillisecondsSinceEpoch(remindAfterMillis))) {
      return false;
    }
    return count != notifiedCount;
  }

  static Future<int> _countNewMedia(SharedPreferences prefs) async {
    final permission = await PhotoManager.getPermissionState(
      requestOption: const PermissionRequestOption(
        androidPermission: AndroidPermission(
          type: RequestType.common,
          mediaLocation: false,
        ),
      ),
    );
    if (!permission.hasAccess) return 0;

    final since = DateTime.fromMillisecondsSinceEpoch(
      prefs.getInt(BackupPrefKeys.checkpoint) ?? 0,
    );
    final videos = prefs.getBool(BackupPrefKeys.videos) ?? true;
    return PhotoManager.getAssetCount(
      type: videos ? RequestType.common : RequestType.image,
      filterOption: FilterOptionGroup(
        createTimeCond: DateTimeCond(min: since, max: DateTime.now()),
      ),
    );
  }
}

/// Entry point for scheduled jobs. Android runs each on a background engine
/// of its own, never the app's, and that engine runs no main(), so the
/// plugins written in Dart are registered here.
@pragma('vm:entry-point')
void backupWorkerDispatcher() {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  Workmanager().executeTask(
    (task, _) async {
      if (task == BackgroundBackup.runTask) return BackgroundBackup.run();
      try {
        await BackupWorker._run(task);
      } catch (e) {
        debugPrint('[BackupWorker] $task failed: $e');
      }
      return true;
    },
    onTaskStopped: (task, _) async {
      if (task == BackgroundBackup.runTask) await BackgroundBackup.stop();
    },
  );
}
