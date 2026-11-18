import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/app_platform.dart';
import '../../../infrastructure/database/app_database.dart' show TransferOrigin;
import '../../../infrastructure/notifications/app_notifications.dart';
import '../../private/data/private_space.dart';
import 'transfer_notifications.dart';
import 'transfer_queue.dart';

/// On a computer, the one notification when the transfers the person
/// started have all finished while Telegrive's window wasn't in front: what
/// went where, worded as a phone's is. A phone's comes from the transfers'
/// foreground service; a computer has none, and its app keeps running with
/// its window behind others. The first batch asks a Mac for permission.
final desktopTransferNoticesProvider = Provider<void>((ref) {
  if (!AppPlatform.isDesktop) return;
  DateTime? since;
  var asked = false;
  ref.listen<TransfersState>(transferQueueProvider, (_, state) {
    final yours = state.active.any((t) => t.origin != TransferOrigin.backup);
    if (yours) {
      if (!asked) {
        asked = true;
        unawaited(AppNotifications.requestPermission());
      }
      since ??= DateTime.now();
      return;
    }
    final started = since;
    if (started == null) return;
    since = null;
    final summary = TransferSummary.of(
      state.items,
      started,
      outOfSight: ref.read(privateOutOfSightProvider),
    );
    if (summary != null && WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      unawaited(TransferNotifications.showSummary(summary));
    }
  });
});
