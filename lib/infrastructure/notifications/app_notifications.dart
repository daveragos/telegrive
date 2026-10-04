import 'dart:io';
import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../storage/preferences.dart';

/// The one way into the phone's notifications. Every notification Telegrive
/// posts goes through the single plugin instance here, so a tap or a button
/// on any of them reaches the same handler, and the channel and notification
/// ids sit side by side, where two can't end up sharing a number.
abstract final class AppNotifications {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const MethodChannel _system = MethodChannel('telegrive/system');

  /// The ongoing notification while transfers run, posted by the
  /// foreground service.
  static const String transfersChannel = 'transfers';

  /// One quiet notification when transfers finish in the background, or are
  /// paused from the shade.
  static const String transfersDoneChannel = 'transfer_done';

  /// The reminder that new photos are waiting to be backed up.
  static const String photoBackupChannel = 'photo_backup';

  static const int backupReminderId = 2001;
  static const int transfersFinishedId = 2002;
  static const int transfersPausedId = 2003;

  /// The one-colour mark, with its creases open.
  static const String icon = 'ic_stat_telegrive';

  static bool _initialized = false;

  /// Safe to call from any isolate, including the background worker. Taps
  /// on a notification or one of its buttons go to [onResponse]; swiping
  /// the backup reminder away goes to [notificationBackgroundHandler], which
  /// runs even while the app is closed.
  static Future<void> initialize({
    void Function(NotificationResponse response)? onResponse,
  }) async {
    if (_initialized && onResponse == null) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings(icon),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: onResponse,
        onDidReceiveBackgroundNotificationResponse: notificationBackgroundHandler,
      );
      _initialized = true;
    } catch (e) {
      debugPrint('[AppNotifications] init failed: $e');
    }
  }

  /// The tap that opened the app, if a notification did.
  static Future<NotificationResponse?> launchResponse() async {
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      if (details?.didNotificationLaunchApp ?? false) {
        return details!.notificationResponse;
      }
    } catch (_) {}
    return null;
  }

  /// Posts notification [id], replacing the one already there with that id.
  static Future<void> show({
    required int id,
    required String title,
    required String body,
    required AndroidNotificationDetails android,
    String? payload,
  }) async {
    await initialize();
    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(android: android),
        payload: payload,
      );
    } catch (e) {
      debugPrint('[AppNotifications] could not post $id: $e');
    }
  }

  static Future<void> cancel(int id) async {
    try {
      await _plugin.cancel(id: id);
    } catch (_) {}
  }

  /// Asks Android for permission to post notifications.
  static Future<void> requestPermission() async {
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    } catch (e) {
      debugPrint('[AppNotifications] permission request failed: $e');
    }
  }

  /// Whether Telegrive may post notifications: on Android 13 and later,
  /// whether the permission was granted, and before that, whether they were
  /// switched off in the system's settings. Anywhere else, and when Android
  /// can't say, this counts as yes, so nothing claims they are off when they
  /// may not be.
  static Future<bool> enabled() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    try {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.areNotificationsEnabled() ??
          true;
    } catch (_) {
      return true;
    }
  }

  /// Opens Telegrive's page in the system notification settings.
  static Future<void> openSettings() async {
    try {
      await _system.invokeMethod<bool>('openNotificationSettings');
    } catch (e) {
      debugPrint('[AppNotifications] could not open settings: $e');
    }
  }
}

/// How long a swiped-away backup reminder stays away.
const Duration _remindAgainAfter = Duration(hours: 24);

/// Runs on a short-lived background engine when a notification is swiped
/// away, the app open or not. Swiping the backup reminder away means 'not
/// now': the background check may post it again a day later, if photos are
/// still waiting, even when their number hasn't changed. It touches only
/// the preferences the worker reads.
@pragma('vm:entry-point')
Future<void> notificationBackgroundHandler(NotificationResponse response) async {
  if (response.notificationResponseType != NotificationResponseType.notificationDismissed ||
      response.id != AppNotifications.backupReminderId) {
    return;
  }
  DartPluginRegistrant.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt(
    BackupPrefKeys.remindAfter,
    DateTime.now().add(_remindAgainAfter).millisecondsSinceEpoch,
  );
  await prefs.remove(BackupPrefKeys.notifiedCount);
}
