import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../../core/format/formatters.dart';

/// The one notification photo backup posts on its own: "N new photos to
/// back up". Tapping it opens the app, which starts backing them up.
abstract final class BackupNotifications {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const int _newMediaId = 2001;
  static const String payload = 'backup';

  static const AndroidNotificationDetails _channel = AndroidNotificationDetails(
    'photo_backup',
    'Photo backup',
    channelDescription: 'Tells you when new photos are waiting to be backed up',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
    icon: 'ic_stat_telegrive',
    onlyAlertOnce: true,
  );

  static bool _initialized = false;

  /// Safe to call from any isolate, including the background worker.
  static Future<void> initialize({void Function(String? payload)? onTap}) async {
    if (_initialized && onTap == null) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_stat_telegrive'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: onTap == null
            ? null
            : (response) => onTap(response.payload),
      );
      _initialized = true;
    } catch (e) {
      debugPrint('[BackupNotifications] init failed: $e');
    }
  }

  /// Payload of the notification that launched the app, if one did.
  static Future<String?> launchPayload() async {
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      if (details?.didNotificationLaunchApp ?? false) {
        return details!.notificationResponse?.payload;
      }
    } catch (_) {}
    return null;
  }

  static Future<void> requestPermission() async {
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    } catch (e) {
      debugPrint('[BackupNotifications] permission request failed: $e');
    }
  }

  static Future<void> showNewMedia(int count) async {
    await initialize();
    await _plugin.show(
      id: _newMediaId,
      title: count == 1
          ? '1 new photo to back up'
          : '${Formatters.count(count, 'new item')} to back up',
      body: 'Tap to back them up to Telegram.',
      notificationDetails: const NotificationDetails(android: _channel),
      payload: payload,
    );
  }

  static Future<void> clear() async {
    try {
      await _plugin.cancel(id: _newMediaId);
    } catch (_) {}
  }
}
