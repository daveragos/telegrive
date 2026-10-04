import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'app/launch_action.dart';
import 'features/backup/data/backup_worker.dart';
import 'infrastructure/notifications/app_notifications.dart';
import 'infrastructure/storage/device_profile.dart';
import 'infrastructure/storage/preferences.dart';
import 'infrastructure/telegram/telegram_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  final (prefs, profile) = await (SharedPreferences.getInstance(), DeviceProfile.read()).wait;
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      deviceProfileProvider.overrideWithValue(profile),
    ],
  );

  // The transfer notification launches the app with its route as Android's
  // initial route. The router starts at the splash regardless; the shell
  // opens Transfers over Home once the drive is open.
  void request(LaunchRequest? request) {
    if (request != null) container.read(pendingLaunchActionProvider.notifier).set(request);
  }

  request(
    LaunchRequest.fromRoute(WidgetsBinding.instance.platformDispatcher.defaultRouteName),
  );

  // Photo backup's background checks, and the notifications' taps and
  // buttons: each opens the app, and the shell does what it asks once the
  // drive is open.
  await BackupWorker.initialize();
  await AppNotifications.initialize(
    onResponse: (response) =>
        request(LaunchRequest.fromNotification(response.payload, response.actionId)),
  );
  final launch = await AppNotifications.launchResponse();
  if (launch != null) {
    request(LaunchRequest.fromNotification(launch.payload, launch.actionId));
  }

  // The ongoing transfer notification's Pause button reaches the app
  // through this port.
  FlutterForegroundTask.initCommunicationPort();

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
