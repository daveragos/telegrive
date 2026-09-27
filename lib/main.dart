import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'app/launch_action.dart';
import 'features/backup/data/backup_notifications.dart';
import 'features/backup/data/backup_worker.dart';
import 'infrastructure/storage/preferences.dart';
import 'infrastructure/telegram/telegram_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );

  // The transfer notification launches the app with its route as Android's
  // initial route. The router starts at the splash regardless; the shell
  // opens Transfers over Home once the drive is open.
  final launchedInto = LaunchAction.fromRoute(
    WidgetsBinding.instance.platformDispatcher.defaultRouteName,
  );
  if (launchedInto != null) {
    container.read(pendingLaunchActionProvider.notifier).set(launchedInto);
  }

  // Photo backup's background checks and its "new photos" notification.
  // Tapping that notification opens the app to back them up.
  void onBackupRequested() => container
      .read(pendingLaunchActionProvider.notifier)
      .set(LaunchAction.backup);
  await BackupWorker.initialize();
  await BackupNotifications.initialize(
    onTap: (payload) {
      if (payload == BackupNotifications.payload) onBackupRequested();
    },
  );
  if (await BackupNotifications.launchPayload() == BackupNotifications.payload) {
    onBackupRequested();
  }

  // Start TDLib while the first frame renders; the splash screen shows any
  // failure with a retry.
  unawaited(
    container.read(telegramClientProvider).start().then<void>(
      (_) {},
      onError: (Object e) => debugPrint('[main] TDLib failed to start: $e'),
    ),
  );

  runApp(UncontrolledProviderScope(container: container, child: const TelegriveApp()));
}
