import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/app_platform.dart';
import '../../../core/platform/keep_awake.dart';
import '../../../infrastructure/storage/preferences.dart';
import '../../backup/data/watched_folders.dart';
import 'transfer_queue.dart';

/// On a computer, keeps it from sleeping on its own while files go up or
/// come down, or folder sync is sending, as long as Keep the computer
/// awake is on. A phone's transfers keep going through its foreground
/// service instead.
final desktopKeepAwakeProvider = Provider<void>((ref) {
  if (!AppPlatform.isDesktop) return;
  final wanted = ref.watch(preferencesProvider.select((p) => p.keepAwake));
  void follow() {
    final busy = ref.read(transferQueueProvider).activeCount > 0 || ref.read(watchedFoldersProvider).working;
    unawaited(wanted && busy ? KeepAwake.hold() : KeepAwake.release());
  }

  ref.listen<int>(transferQueueProvider.select((s) => s.activeCount), (_, _) => follow());
  ref.listen<bool>(watchedFoldersProvider.select((s) => s.working), (_, _) => follow(), fireImmediately: true);
  ref.onDispose(() => unawaited(KeepAwake.release()));
});
