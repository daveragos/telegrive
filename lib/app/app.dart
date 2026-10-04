import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../features/backup/data/backup_controller.dart';
import '../features/backup/data/watched_folders.dart';
import '../features/drive/data/drive_session.dart';
import '../features/drive/data/drive_sync.dart';
import '../features/drive/data/edit_outbox.dart';
import '../features/network/data/proxies.dart';
import '../features/network/data/proxy_link_intake.dart';
import '../features/network/domain/proxy_link.dart';
import '../features/network/presentation/proxy_sheet.dart';
import '../features/picker/data/picker_access.dart';
import '../features/settings/data/settings_providers.dart';
import '../features/setup/data/drive_opener.dart';
import '../features/setup/data/drive_setup.dart';
import '../features/transfers/data/transfer_keep_alive.dart';
import '../features/transfers/data/transfer_queue.dart';
import '../features/trash/data/pending_deletes.dart';
import '../infrastructure/network/network_status.dart';
import '../infrastructure/storage/device_profile.dart';
import '../infrastructure/telegram/telegram_client.dart';
import 'app_phase.dart';
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
    ref.listenManual<bool>(
      saveMemoryProvider,
      (_, on) => _sizeImageCache(on),
      fireImmediately: true,
    );
  }

  /// Decoded pictures Flutter keeps in memory: 32 MB and 300 of them while
  /// saving memory, otherwise Flutter's own 100 MB and 1,000. A smaller
  /// limit takes effect at once, dropping the pictures used longest ago.
  static void _sizeImageCache(bool saveMemory) {
    PaintingBinding.instance.imageCache
      ..maximumSizeBytes = saveMemory ? 32 << 20 : 100 << 20
      ..maximumSize = saveMemory ? 300 : 1000;
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
      // Catch up on anything added from another device while away, back up
      // whatever the camera took meanwhile, send what other apps saved into
      // the watched folders and the changes made without a connection, and
      // let go transfers waiting for room that was made in another app.
      ref.read(driveSyncProvider.notifier).refresh();
      ref.read(editOutboxProvider.notifier).soon();
      ref.read(backupControllerProvider.notifier).schedule(immediate: true);
      ref.read(watchedFoldersProvider.notifier).schedule(immediate: true);
      unawaited(ref.read(transferQueueProvider.notifier).recheckRoom());
    }
  }

  /// Offers a proxy link tapped in another app in the proxy sheet, once
  /// there is a screen that stays for the sheet to open over: not the
  /// splash, and not setup while it runs, which an open drive replaces in
  /// a blink. A setup that failed stays, and on a blocked network that is
  /// where the proxy is wanted. It also waits for TDLib's parameters,
  /// before which it takes no proxy, since Home can show a drive this
  /// phone knows before Telegram has started.
  void _offerProxyLink() {
    final link = ref.read(proxyLinkIntakeProvider);
    if (link == null) return;
    final settled =
        telegramConfigured(ref.read(authStateProvider).value) &&
        switch (ref.read(appPhaseProvider)) {
          AppPhase.starting => false,
          AppPhase.setup => ref.read(driveSetupProvider).error != null,
          _ => true,
        };
    if (!settled) return;
    ref.read(proxyLinkIntakeProvider.notifier).clear();
    // After the frame that puts this phase's screen in place, so the sheet
    // opens over it rather than over the screen it replaces, which would
    // take the sheet with it.
    unawaited(
      SchedulerBinding.instance.endOfFrame.then((_) {
        final context = rootNavigatorKey.currentContext;
        if (context != null && context.mounted) unawaited(showProxySheet(context, prefill: link));
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Created up front so interrupted transfers resume as soon as the drive
    // opens, not the first time someone visits the Transfers tab.
    ref.watch(transferQueueProvider.select((s) => s.activeCount));
    ref.watch(transferKeepAliveProvider);
    // Opens a drive this phone knows behind Home, as soon as Telegram is
    // signed in.
    ref.watch(driveOpenerProvider);
    // At the root rather than in the shell, so it still sees the drive
    // close on sign-out and takes the bridge to the stream server away.
    ref.watch(pickerAccessProvider);
    // Alive from the start so backup resumes the moment the drive opens,
    // and the watched folders are checked then too.
    ref.watch(backupControllerProvider.select((b) => b.phase));
    ref.watch(watchedFoldersProvider.select((s) => s.working));
    // Alive from the start too: it is what tells TDLib about every network
    // change, the call that makes it drop dead sockets and reconnect.
    ref.watch(networkStatusProvider);
    // A tapped proxy link waits for a screen to be offered over.
    ref.listen<ProxyLink?>(proxyLinkIntakeProvider, (_, _) => _offerProxyLink());
    ref.listen<AppPhase>(appPhaseProvider, (_, _) => _offerProxyLink());
    ref.listen<bool>(
      authStateProvider.select((auth) => telegramConfigured(auth.value)),
      (_, _) => _offerProxyLink(),
    );
    ref.listen<String?>(driveSetupProvider.select((s) => s.error), (_, _) => _offerProxyLink());

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
