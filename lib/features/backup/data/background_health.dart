import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../infrastructure/notifications/app_notifications.dart';
import '../../../infrastructure/storage/preferences.dart';
import 'backup_worker.dart';

/// Whether backup can work while the app is closed: the checks armed with
/// Android and running, battery saver leaving Telegrive be, notifications
/// allowed, and what the background job last did.
@immutable
class BackgroundHealth {
  const BackgroundHealth({
    required this.watching,
    this.batteryOk = true,
    this.notificationsOk = true,
    this.lastChecked,
    this.lastRun,
    this.lastUploaded = 0,
  });

  /// The checks for new photos are armed with Android.
  final bool watching;

  /// Telegrive is exempt from battery optimisation, or Android didn't say.
  final bool batteryOk;
  final bool notificationsOk;

  /// When a background job last looked for new photos.
  final DateTime? lastChecked;

  /// When the background backup job last ran a pass, and how many photos
  /// it sent up.
  final DateTime? lastRun;
  final int lastUploaded;

  /// A check should run every few hours; none in this long means Android
  /// isn't letting it.
  static const Duration staleAfter = Duration(days: 2);

  /// Whether backup, when [backupOn], can't count on running with the app
  /// closed: the checks aren't armed, or none has run in [staleAfter]. A
  /// check that hasn't run yet doesn't count, since arming one runs it soon.
  bool needsAttention(bool backupOn, {DateTime? now}) {
    if (!backupOn) return false;
    final checked = lastChecked;
    return !watching ||
        (checked != null && (now ?? DateTime.now()).difference(checked) > staleAfter);
  }
}

/// The calls on the `telegrive/system` channel that concern backup with
/// the app closed.
abstract final class BatterySettings {
  static const MethodChannel _system = MethodChannel('telegrive/system');

  /// Whether Android exempts Telegrive from battery optimisation. A phone
  /// that can't say counts as exempt, so nothing claims what isn't known.
  static Future<bool> exempt() async {
    try {
      return await _system.invokeMethod<bool>('ignoringBatteryOptimizations') ?? true;
    } catch (e) {
      debugPrint('[BatterySettings] $e');
      return true;
    }
  }

  /// Opens the system's list of apps and their battery use, where
  /// Telegrive can be set to Unrestricted.
  static Future<void> open() async {
    try {
      await _system.invokeMethod<bool>('openBatterySettings');
    } catch (e) {
      debugPrint('[BatterySettings] could not open settings: $e');
    }
  }
}

/// [BackgroundHealth] as it stands, or null off Android, where nothing runs
/// with the app closed. The jobs write what they did from their own
/// engines, so the stored values are read again from disk. The app reads
/// it again each time it comes back, and after each fix on the Backup
/// screen.
final backgroundHealthProvider = FutureProvider.autoDispose<BackgroundHealth?>((ref) async {
  if (!BackupWorker.supported) return null;
  final shared = ref.read(sharedPreferencesProvider);
  await shared.reload();
  final prefs = Preferences(shared);
  final (watching, batteryOk, notificationsOk) = await (
    BackupWorker.armed(),
    BatterySettings.exempt(),
    AppNotifications.enabled(),
  ).wait;
  return BackgroundHealth(
    watching: watching,
    batteryOk: batteryOk,
    notificationsOk: notificationsOk,
    lastChecked: prefs.backgroundChecked,
    lastRun: prefs.backgroundRun,
    lastUploaded: prefs.backgroundUploaded,
  );
});
