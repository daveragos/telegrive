import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../../../infrastructure/storage/preferences.dart';
import 'backup_notifications.dart';

/// Notices new photos while Telegrive isn't open (Android).
///
/// Two scheduled jobs, both deliberately small — they never touch Telegram:
///
/// * a **media trigger** that Android fires as soon as something is added to
///   the photo library, and
/// * a **periodic check** every few hours as a safety net.
///
/// Either one counts photos newer than the last finished backup and, if
/// there are any, posts "N new photos to back up". When the app itself is
/// running, the job runs on its engine instead and simply starts the backup.
abstract final class BackupWorker {
  static const String _periodicTask = 'telegrive.backup-check';
  static const String _triggerTask = 'telegrive.media-trigger';

  /// Set by the running app; lets a job that lands on the app's own engine
  /// start the backup directly instead of notifying.
  static VoidCallback? onNewMediaInApp;

  static bool get _supported => !kIsWeb && Platform.isAndroid;

  static Future<void> initialize() async {
    if (!_supported) return;
    try {
      await Workmanager().initialize(backupWorkerDispatcher);
    } catch (e) {
      debugPrint('[BackupWorker] initialize failed: $e');
    }
  }

  /// Arms both jobs. Idempotent: existing registrations are kept.
  static Future<void> schedule() async {
    if (!_supported) return;
    try {
      await Workmanager().registerPeriodicTask(
        _periodicTask,
        _periodicTask,
        frequency: const Duration(hours: 4),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );
      await _armTrigger(replace: false);
    } catch (e) {
      debugPrint('[BackupWorker] schedule failed: $e');
    }
  }

  static Future<void> cancel() async {
    if (!_supported) return;
    try {
      await Workmanager().cancelByUniqueName(_periodicTask);
      await Workmanager().cancelByUniqueName(_triggerTask);
    } catch (_) {}
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    if (!(prefs.getBool(BackupPrefKeys.enabled) ?? false)) return;

    if (task == _triggerTask) await _armTrigger(replace: true);

    final inApp = onNewMediaInApp;
    if (inApp != null) {
      inApp();
      return;
    }

    final count = await _countNewMedia(prefs);
    if (count == 0) return;
    // Say it once per new batch, not every time the job wakes up.
    if (count == prefs.getInt(BackupPrefKeys.notifiedCount)) return;
    await BackupNotifications.showNewMedia(count);
    await prefs.setInt(BackupPrefKeys.notifiedCount, count);
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

/// Entry point for scheduled jobs, in the app's engine or a background one.
@pragma('vm:entry-point')
void backupWorkerDispatcher() {
  WidgetsFlutterBinding.ensureInitialized();
  Workmanager().executeTask((task, _) async {
    try {
      await BackupWorker._run(task);
    } catch (e) {
      debugPrint('[BackupWorker] $task failed: $e');
    }
    return true;
  });
}
