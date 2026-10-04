import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../../core/format/formatters.dart';
import '../../../infrastructure/notifications/app_notifications.dart';

/// The one notification photo backup posts on its own: "N new photos to
/// back up". Tapping it, or its Back up now button, opens the app, which
/// starts backing them up. With backup running on its own, it says when
/// they go up without a tap. Swiping it away puts it off for a day; see
/// [notificationBackgroundHandler].
abstract final class BackupNotifications {
  static const String payload = 'backup';

  /// The id of the Back up now button.
  static const String backUpNowAction = 'back_up_now';

  static const AndroidNotificationDetails _channel = AndroidNotificationDetails(
    AppNotifications.photoBackupChannel,
    'Photo backup',
    channelDescription: 'Tells you when new photos are waiting to be backed up',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
    icon: AppNotifications.icon,
    onlyAlertOnce: true,
    actions: [
      AndroidNotificationAction(
        backUpNowAction,
        'Back up now',
        showsUserInterface: true,
      ),
    ],
    dismissIsolate: NotificationDismissedIsolate.background,
  );

  static Future<void> requestPermission() => AppNotifications.requestPermission();

  /// Posts the reminder for [count] new photos. When backup runs on its own
  /// ([unattended]), it says they go up the next time the phone charges, on
  /// Wi-Fi when [wifiOnly].
  static Future<void> showNewMedia(
    int count, {
    bool unattended = false,
    bool wifiOnly = true,
  }) => AppNotifications.show(
    id: AppNotifications.backupReminderId,
    title: count == 1
        ? '1 new photo to back up'
        : '${Formatters.count(count, 'new item')} to back up',
    body: newMediaBody(unattended: unattended, wifiOnly: wifiOnly),
    android: _channel,
    payload: payload,
  );

  /// The reminder's sentence.
  @visibleForTesting
  static String newMediaBody({required bool unattended, required bool wifiOnly}) {
    if (!unattended) return 'Tap to back them up to Telegram.';
    return wifiOnly
        ? 'They go up on their own next time the phone charges on Wi-Fi. Tap to back up now.'
        : 'They go up on their own next time the phone charges. Tap to back up now.';
  }

  static Future<void> clear() => AppNotifications.cancel(AppNotifications.backupReminderId);
}
