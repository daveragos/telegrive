import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../../core/format/formatters.dart';
import '../../../infrastructure/notifications/app_notifications.dart';

/// The one notification photo backup posts on its own: "N new photos to
/// back up". Tapping it, or its Back up now button, opens the app, which
/// starts backing them up. Swiping it away puts it off for a day; see
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

  static Future<void> showNewMedia(int count) => AppNotifications.show(
    id: AppNotifications.backupReminderId,
    title: count == 1
        ? '1 new photo to back up'
        : '${Formatters.count(count, 'new item')} to back up',
    body: 'Tap to back them up to Telegram.',
    android: _channel,
    payload: payload,
  );

  static Future<void> clear() => AppNotifications.cancel(AppNotifications.backupReminderId);
}
