import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/backup/data/backup_notifications.dart';
import '../features/transfers/data/transfer_keep_alive.dart';
import '../features/transfers/data/transfer_notifications.dart';

/// Something the app was opened to do from a notification: back up the new
/// photos, show the transfers, retry the ones that failed, resume the ones
/// paused from the shade, or open a file that finished.
enum LaunchAction { backup, transfers, retryFailed, resumePaused, openTransfer }

/// A [LaunchAction], with the transfer it is about when it opens one. The
/// shell carries it out once the drive is open, so a screen opened this way
/// sits over Home and back lands there.
@immutable
class LaunchRequest {
  const LaunchRequest(this.action, {this.transferId});

  final LaunchAction action;

  /// The transfer whose file [LaunchAction.openTransfer] opens.
  final String? transferId;

  /// The request a launch route stands for, or null for a plain launch. The
  /// transfer notification launches the app with its own route, which
  /// Android hands over as the initial route; the router does not start
  /// there (it would be the only screen, and back would close the app) but
  /// the route becomes [LaunchAction.transfers].
  static LaunchRequest? fromRoute(String route) =>
      route == TransferKeepAlive.notificationRoute
      ? const LaunchRequest(LaunchAction.transfers)
      : null;

  /// The request a tap on a notification, or on its button [actionId],
  /// stands for, or null when it is none Telegrive knows. A button wins
  /// over the notification's own [payload].
  static LaunchRequest? fromNotification(String? payload, String? actionId) {
    final opened = TransferNotifications.openedId(payload);
    switch (actionId) {
      case BackupNotifications.backUpNowAction:
        return const LaunchRequest(LaunchAction.backup);
      case TransferNotifications.retryAction:
        return const LaunchRequest(LaunchAction.retryFailed);
      case TransferNotifications.resumeAction:
        return const LaunchRequest(LaunchAction.resumePaused);
      case TransferNotifications.openAction:
        return opened == null
            ? const LaunchRequest(LaunchAction.transfers)
            : LaunchRequest(LaunchAction.openTransfer, transferId: opened);
    }
    if (payload == BackupNotifications.payload) {
      return const LaunchRequest(LaunchAction.backup);
    }
    if (payload == TransferNotifications.listPayload) {
      return const LaunchRequest(LaunchAction.transfers);
    }
    if (opened != null) {
      return LaunchRequest(LaunchAction.openTransfer, transferId: opened);
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is LaunchRequest && other.action == action && other.transferId == transferId;

  @override
  int get hashCode => Object.hash(action, transferId);

  @override
  String toString() => 'LaunchRequest($action, $transferId)';
}

class PendingLaunchAction extends Notifier<LaunchRequest?> {
  @override
  LaunchRequest? build() => null;

  // ignore: use_setters_to_change_properties
  void set(LaunchRequest? request) => state = request;
}

final pendingLaunchActionProvider =
    NotifierProvider<PendingLaunchAction, LaunchRequest?>(PendingLaunchAction.new);
