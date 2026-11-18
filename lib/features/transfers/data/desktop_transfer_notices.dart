import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/app_platform.dart';
import '../../../infrastructure/database/app_database.dart' show TransferOrigin;
import '../../../infrastructure/notifications/app_notifications.dart';
import '../../backup/data/watched_folders.dart';
import '../../private/data/private_space.dart';
import 'transfer_notifications.dart';
import 'transfer_queue.dart';

/// On a computer, the one notification when the transfers the person
/// started have all finished while Telegrive's window wasn't in front: what
/// went where, worded as a phone's is. A phone's comes from the transfers'
/// foreground service; a computer has none, and its app keeps running with
/// its window behind others. The first batch asks a Mac for permission.
/// What folder sync sends says nothing, as photo backup's doesn't: it goes
/// on all day without being asked.
final desktopTransferNoticesProvider = Provider<void>((ref) {
  if (!AppPlatform.isDesktop) return;
  DateTime? since;
  var asked = false;
  final folders = ref.read(watchedFoldersProvider.notifier);
  bool personal(TransferItem t) => t.origin != TransferOrigin.backup && !folders.queuedUpload(t.id);
  ref.listen<TransfersState>(transferQueueProvider, (_, state) {
    final yours = state.active.any(personal);
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
      state.items.where(personal).toList(),
      started,
      outOfSight: ref.read(privateOutOfSightProvider),
    );
    if (summary != null && WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      unawaited(TransferNotifications.showSummary(summary));
    }
  });
});
