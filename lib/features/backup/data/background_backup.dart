import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../../../infrastructure/network/network_status.dart';
import '../../../infrastructure/storage/preferences.dart';
import '../../../infrastructure/telegram/telegram_client.dart';
import '../../auth/data/auth_controller.dart';
import '../../setup/data/drive_setup.dart';
import 'backup_controller.dart';
import 'backup_run_mode.dart';
import 'backup_worker.dart';

/// Backs new photos up with the app closed (Android), while the phone
/// charges on Wi-Fi, or on any network when backup may use mobile data.
///
/// The check jobs ([BackupWorker]) enqueue this job when new photos are
/// waiting and 'Back up on its own' is on. It runs in its own engine in the
/// app's process: it starts TDLib only when the app's engine doesn't hold
/// it, opens the drive saved on this phone without ever searching for,
/// making or changing a channel, and runs one ordinary backup pass through
/// the transfer queue for up to [_budget]. The app opening meanwhile asks
/// it to hand over, and it does so at once. Photos left at the end make
/// Android run it again later.
abstract final class BackgroundBackup {
  static const String runTask = 'telegrive.backup-run';

  /// Setting up and the pass, from the job's start. With the grace for
  /// uploads under way and closing TDLib after, the job stays inside the
  /// ten minutes Android gives one.
  static const Duration _budget = Duration(minutes: 8);

  /// How long TDLib gets to say the account is signed in.
  static const Duration _readyTimeout = Duration(seconds: 60);

  /// How long Android's stop waits for the job to close TDLib.
  static const Duration _stopTimeout = Duration(seconds: 20);

  static _Run? _running;

  /// Asks Android to run the job once the phone is charging, and on Wi-Fi
  /// when [wifiOnly]. One already waiting is kept.
  static Future<void> enqueue({required bool wifiOnly}) async {
    if (!BackupWorker.supported) return;
    try {
      await Workmanager().registerOneOffTask(
        runTask,
        runTask,
        existingWorkPolicy: ExistingWorkPolicy.keep,
        constraints: Constraints(
          requiresCharging: true,
          networkType: wifiOnly ? NetworkType.unmetered : NetworkType.connected,
        ),
        backoffPolicy: BackoffPolicy.linear,
        backoffPolicyDelay: const Duration(minutes: 15),
      );
    } catch (e) {
      debugPrint('[BackgroundBackup] enqueue failed: $e');
    }
  }

  static Future<void> cancel() async {
    if (!BackupWorker.supported) return;
    try {
      await Workmanager().cancelByUniqueName(runTask);
    } catch (_) {}
  }

  /// The job itself. True when it is done: nothing is left to send, what
  /// is left waits for something another run can't give it (see [isDone]),
  /// or the app took over. False makes Android run it again.
  static Future<bool> run() async {
    final startedAt = DateTime.now();
    final shared = await SharedPreferences.getInstance();
    await shared.reload();
    final prefs = Preferences(shared);
    if (!prefs.backupEnabled || !prefs.backupUnattended) return true;
    final wifiOnly = prefs.backupMobileData == BackupMobileData.off;
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(shared),
        tdRoleProvider.overrideWithValue(TdRole.worker),
        backupRunModeProvider.overrideWithValue(BackupRunMode.background),
        networkStatusProvider.overrideWith(
          () => _AssumedNetwork(NetworkState(online: true, metered: !wifiOnly)),
        ),
      ],
    );
    final run = _running = _Run();
    Duration left() => _budget - DateTime.now().difference(startedAt);
    final client = container.read(telegramClientProvider);
    var started = false;
    StreamSubscription<void>? yields;
    try {
      try {
        await client.start();
        started = true;
      } on TdBusy catch (e) {
        // The app is up and backs up by itself.
        debugPrint('[BackgroundBackup] ${e.reason}');
        return true;
      }
      yields = client.yieldRequests.listen((_) {
        run.yielded = true;
        run.stop();
      });

      final auth = await run.until(_settled(client), timeout: _readyTimeout);
      if (auth == null) return true;
      if (asksToSignIn(auth)) {
        // Nothing to back up into until someone signs in, which the app
        // asks for; it arms the checks again once the drive opens.
        await BackupWorker.cancel();
        return true;
      }
      final opened = await run.until(
        container.read(driveSetupProvider.notifier).openExisting(),
        timeout: left(),
      );
      // No drive saved here, the run was stopped, or the time ran out.
      if (opened == null) return run.halted || left() > Duration.zero;

      if (run.halted) return true;
      final remaining = left();
      if (remaining <= Duration.zero) return false;
      final controller = container.read(backupControllerProvider.notifier);
      run.controller = controller;
      final uploaded = await controller.runInBackground(remaining);
      final state = container.read(backupControllerProvider);
      final now = DateTime.now();
      // A pass that ended before it looked at the photos (the index wasn't
      // ready, say) isn't a run to report.
      final ran =
          uploaded > 0 ||
          state.phase == BackupPhase.upToDate ||
          state.phase == BackupPhase.uploading;
      if (ran) await prefs.setBackgroundRun(now, uploaded);
      await prefs.setBackgroundChecked(now);
      return run.yielded || isDone(state);
    } catch (e, stack) {
      debugPrint('[BackgroundBackup] $e\n$stack');
      return false;
    } finally {
      await yields?.cancel();
      if (started) await client.shutDown();
      container.dispose();
      _running = null;
      run.done.complete();
    }
  }

  /// Whether the job is done with a pass that ended in [state]: nothing is
  /// left to send, or what is left waits for Wi-Fi, the monthly limit, the
  /// photo permission or the drive, none of which another run on the
  /// charger would change. Photos left to a stop, an error or a wait
  /// Telegram asked for are for Android to run the job again.
  @visibleForTesting
  static bool isDone(BackupState state) => switch (state.phase) {
    BackupPhase.waitingForWifi ||
    BackupPhase.waitingForBudget ||
    BackupPhase.needsPermission ||
    BackupPhase.waitingForDrive => true,
    BackupPhase.stopped => false,
    _ => state.remaining == 0,
  };

  /// Android stopped the job: the phone was unplugged, it left Wi-Fi, or
  /// the time ran out. The uploads under way are cancelled and TDLib is
  /// closed before Android takes the engine away.
  static Future<void> stop() async {
    final run = _running;
    if (run == null) return;
    run.stop();
    await run.done.future.timeout(_stopTimeout, onTimeout: () {});
  }

  /// The first authorization state that settles the job: signed in, or
  /// asking to sign in. Null when TDLib gave up on starting.
  static Future<td.AuthorizationState?> _settled(TelegramClient client) {
    final failed = Completer<td.AuthorizationState?>();
    void onFatal() {
      if (client.fatalError.value != null && !failed.isCompleted) failed.complete(null);
    }

    client.fatalError.addListener(onFatal);
    onFatal();
    return Future.any<td.AuthorizationState?>([
      client.authStates.firstWhere(
        (state) => state is td.AuthorizationStateReady || asksToSignIn(state),
      ),
      failed.future,
    ]).whenComplete(() => client.fatalError.removeListener(onFatal));
  }
}

/// One run of the job, for [BackgroundBackup.stop] to end.
class _Run {
  final Completer<void> _halt = Completer<void>();
  final Completer<void> done = Completer<void>();
  BackupController? controller;

  /// The app asked for TDLib.
  bool yielded = false;

  bool get halted => _halt.isCompleted;

  /// Ends the run as soon as it can: before the pass, at the next step;
  /// during it, with the uploads under way cancelled at once.
  void stop() {
    if (!_halt.isCompleted) _halt.complete();
    controller?.stop(now: true);
  }

  /// What [work] answers, unless the run is stopped first or [timeout]
  /// passes, when it is null.
  Future<T?> until<T extends Object>(Future<T?> work, {Duration? timeout}) {
    var settled = work;
    if (timeout != null) settled = settled.timeout(timeout, onTimeout: () => null);
    return Future.any<T?>([settled, _halt.future.then((_) => null)]);
  }
}

/// The job's network, as its constraint makes it. Android's network
/// callback answers only the app's own engine, so the job takes Wi-Fi as
/// given when backup keeps off mobile data, which is when it runs on Wi-Fi
/// only, and otherwise counts the connection as mobile data, so the Mobile
/// data choice and the monthly limit hold for everything it sends.
class _AssumedNetwork extends NetworkStatus {
  _AssumedNetwork(this._assumed);

  final NetworkState _assumed;

  @override
  NetworkState build() => _assumed;
}
