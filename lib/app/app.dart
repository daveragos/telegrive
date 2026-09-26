import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;

import '../core/config/app_config.dart';
import '../features/backup/data/backup_controller.dart';
import '../features/drive/data/drive_session.dart';
import '../features/drive/data/drive_sync.dart';
import '../features/settings/data/settings_providers.dart';
import '../features/transfers/data/transfer_keep_alive.dart';
import '../features/transfers/data/transfer_queue.dart';
import '../infrastructure/telegram/telegram_client.dart';
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
  StreamSubscription<List<ConnectivityResult>>? _connectivity;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // TDLib must be told about every network change — that call is what
    // makes it drop dead sockets and reconnect straight away.
    _connectivity = Connectivity().onConnectivityChanged.listen((results) {
      ref.read(telegramClientProvider).setNetworkType(_networkType(results));
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivity?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        ref.read(driveSessionProvider) != null) {
      // Catch up on anything added from another device while away, and
      // back up whatever the camera took meanwhile.
      ref.read(driveSyncProvider.notifier).refresh();
      ref.read(backupControllerProvider.notifier).schedule(immediate: true);
    }
  }

  static td.NetworkType _networkType(List<ConnectivityResult> results) {
    if (results.contains(ConnectivityResult.wifi)) return const td.NetworkTypeWiFi();
    if (results.contains(ConnectivityResult.ethernet)) return const td.NetworkTypeOther();
    if (results.contains(ConnectivityResult.mobile)) return const td.NetworkTypeMobile();
    if (results.contains(ConnectivityResult.none) || results.isEmpty) {
      return const td.NetworkTypeNone();
    }
    return const td.NetworkTypeOther();
  }

  @override
  Widget build(BuildContext context) {
    // Created up front so interrupted transfers resume as soon as the drive
    // opens, not the first time someone visits the Transfers tab.
    ref.watch(transferQueueProvider.select((s) => s.activeCount));
    ref.watch(transferKeepAliveProvider);
    // Alive from the start so backup resumes the moment the drive opens.
    ref.watch(backupControllerProvider.select((b) => b.phase));

    return MaterialApp.router(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ref.watch(themeModeProvider),
      routerConfig: ref.watch(routerProvider),
      builder: (context, child) => LockGate(child: child ?? const SizedBox.shrink()),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('en')],
    );
  }
}
