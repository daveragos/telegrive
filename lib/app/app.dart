import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../features/backup/data/backup_controller.dart';
import '../features/drive/data/drive_session.dart';
import '../features/drive/data/drive_sync.dart';
import '../features/settings/data/settings_providers.dart';
import '../features/transfers/data/transfer_keep_alive.dart';
import '../features/transfers/data/transfer_queue.dart';
import '../features/trash/data/pending_deletes.dart';
import '../infrastructure/network/network_status.dart';
import 'app_shell.dart';
import 'router.dart';
import 'theme/app_theme.dart';
import '../features/lock/presentation/lock_gate.dart';

class TelegriveApp extends ConsumerStatefulWidget {
  const TelegriveApp({super.key});

  @override
  ConsumerState<TelegriveApp> createState() => _TelegriveAppState();
}

class _TelegriveAppState extends ConsumerState<TelegriveApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A delete for good waiting out its Undo runs now: once the app is in
    // the background the process can go at any moment, and the person has
    // moved on from the snack. Deleting the phone's own copies waits for
    // the app to come back, since Android asks about it over the app.
    final pending = ref.read(pendingDeletesProvider.notifier);
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      unawaited(pending.appPaused());
    }
    if (state == AppLifecycleState.resumed) unawaited(pending.appResumed());
    if (state == AppLifecycleState.resumed &&
        ref.read(driveSessionProvider) != null) {
      // Catch up on anything added from another device while away, and
      // back up whatever the camera took meanwhile.
      ref.read(driveSyncProvider.notifier).refresh();
      ref.read(backupControllerProvider.notifier).schedule(immediate: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Created up front so interrupted transfers resume as soon as the drive
    // opens, not the first time someone visits the Transfers tab.
    ref.watch(transferQueueProvider.select((s) => s.activeCount));
    ref.watch(transferKeepAliveProvider);
    // Alive from the start so backup resumes the moment the drive opens.
    ref.watch(backupControllerProvider.select((b) => b.phase));
    // Alive from the start too: it is what tells TDLib about every network
    // change, the call that makes it drop dead sockets and reconnect.
    ref.watch(networkStatusProvider);

    final router = ref.watch(routerProvider);
    final popups = ref.watch(popupRoutesProvider);
    return MaterialApp.router(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ref.watch(themeModeProvider),
      routerConfig: router,
      builder: (context, child) => LockGate(
        child: BulkStripOverShell(
          router: router,
          popups: popups,
          child: child ?? const SizedBox.shrink(),
        ),
      ),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('en')],
    );
  }
}
