import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format/formatters.dart';
import '../../../infrastructure/database/app_database.dart'
    show TransferKind, TransferOrigin, TransferRow;
import '../../../infrastructure/notifications/app_notifications.dart';
import '../../../infrastructure/storage/preferences.dart';
import '../../backup/data/backup_controller.dart';
import '../domain/transfer_wait.dart';
import 'transfer_notifications.dart';
import 'transfer_queue.dart';

/// Keeps transfers alive when Telegrive leaves the screen (Android).
///
/// TDLib does the actual network work on its own native threads, so all an
/// upload needs to finish in the background is for the process to survive.
/// A foreground service — the ongoing "Uploading 3 files · 42%" notification
/// — is Android's way of saying so. It starts with the first active transfer
/// and stops when the queue drains.
///
/// When the last transfer in flight steps back to wait for Wi-Fi, the
/// service stays for a while longer. Android won't let an app in the
/// background start it again, and Wi-Fi is often back in minutes, after a
/// walk to the car, say, so the waiting rows can start the moment it is.
///
/// The notification shows the one-colour mark, and Pause while transfers
/// the person started are running; photo backup has its own place to be
/// stopped.
class TransferKeepAlive {
  TransferKeepAlive(this._prefs);

  final Preferences _prefs;

  /// The route the transfer notification launches the app with. It rides on
  /// the notification's launch intent as Android's initial route; the app
  /// reads it as a LaunchRequest and opens Transfers over Home.
  static const String notificationRoute = '/transfers';

  /// The id of the Pause button, which the service's isolate sends on to
  /// the app's.
  static const String pauseButton = 'pause';

  static const int _serviceId = 4107;
  static const Duration _updateEvery = Duration(milliseconds: 1500);

  /// How long the service stays for transfers waiting for Wi-Fi.
  static const Duration _lingerForWifi = Duration(minutes: 10);

  /// The manifest entry naming the notification's small icon.
  static const NotificationIcon _icon = NotificationIcon(
    metaDataName: 'dev.ragoose.telegrive.STAT_ICON',
  );

  bool _running = false;
  bool _starting = false;
  DateTime _lastUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  (TransfersState, BackupState)? _pending;
  (TransfersState, BackupState)? _latest;
  Timer? _stopTimer;

  /// Brings the notification up to date once [_updateEvery] is over, when
  /// the last change came too soon after the one before to show at once.
  Timer? _refreshTimer;

  /// When the last transfer in flight stepped back to wait for Wi-Fi, while
  /// the service was running; null when that isn't the case.
  DateTime? _heldSince;
  Timer? _lingerTimer;

  /// The transfers in flight at the last update, to tell one that steps
  /// back to wait for Wi-Fi from one that was waiting already.
  Set<String> _inFlight = {};

  static void _init() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: AppNotifications.transfersChannel,
        channelName: 'Transfers',
        channelDescription: 'Progress of uploads and downloads',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(showNotification: false),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,
        allowWifiLock: true,
        allowAutoRestart: false,
      ),
    );
  }

  /// Anything worth keeping the process alive for: a transfer, a photo
  /// backup pass (which has short gaps between photos that must not bounce
  /// the service off and on), or transfers that only just began to wait for
  /// Wi-Fi.
  bool _isActive(TransfersState state, BackupState backup) =>
      state.activeCount > 0 || _backingUp(state, backup) || _lingering;

  bool get _lingering {
    final since = _heldSince;
    return since != null && DateTime.now().difference(since) < _lingerForWifi;
  }

  /// Notes when the last transfer in flight has stepped back to wait for
  /// Wi-Fi, and looks again once the linger is over, since nothing else
  /// may change by then. Rows that were waiting already, from before the
  /// app opened, say, keep nothing alive when something else finishes.
  void _noteHeld(TransfersState state) {
    final active = state.active;
    final steppedBack = state.waitingForWifi.any((t) => _inFlight.contains(t.id));
    _inFlight = {for (final t in active) t.id};
    final held = active.isEmpty && state.waitingForWifi.isNotEmpty;
    if (!held) {
      _heldSince = null;
      _lingerTimer?.cancel();
      _lingerTimer = null;
    } else if (_running && _heldSince == null && steppedBack) {
      _heldSince = DateTime.now();
      _lingerTimer = Timer(_lingerForWifi, () {
        _lingerTimer = null;
        final latest = _latest;
        if (latest != null) unawaited(update(latest.$1, latest.$2));
      });
    }
  }

  /// A backup pass that is moving. One whose upload Telegram has put on a
  /// long wait, or that waits for room on the phone, sits out that wait
  /// without the service, and so without a wake lock; the service starts
  /// again when the upload does. A backup upload waiting for Wi-Fi doesn't
  /// stop the pass, which moves on to the photos mobile data may carry.
  static bool _backingUp(TransfersState state, BackupState backup) =>
      backup.isWorking &&
      !state.held.any(
        (t) =>
            t.origin == TransferOrigin.backup &&
            (t.wait is WaitingForTelegram || t.wait is WaitingForRoom),
      );

  Future<void> update(TransfersState state, BackupState backup) async {
    _latest = (state, backup);
    _noteHeld(state);
    if (!_isActive(state, backup)) {
      _pending = null;
      if (_running) {
        // Linger briefly: the next photo is usually a moment away.
        _stopTimer ??= Timer(const Duration(seconds: 6), () {
          _stopTimer = null;
          final latest = _latest;
          if (latest != null && !_isActive(latest.$1, latest.$2)) unawaited(_stop());
        });
      }
      return;
    }
    _stopTimer?.cancel();
    _stopTimer = null;
    if (_starting) {
      _pending = (state, backup);
      return;
    }
    if (!_running) {
      await _start(state, backup);
      return;
    }
    final now = DateTime.now();
    final since = now.difference(_lastUpdate);
    if (since < _updateEvery) {
      _refreshTimer ??= Timer(_updateEvery - since, () {
        _refreshTimer = null;
        final latest = _latest;
        if (latest != null) unawaited(update(latest.$1, latest.$2));
      });
      return;
    }
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _lastUpdate = now;
    final (title, text) = describe(state, backup);
    await FlutterForegroundTask.updateService(
      notificationTitle: title,
      notificationText: text,
      notificationIcon: _icon,
      notificationButtons: buttons(state),
    );
  }

  Future<void> _start(TransfersState state, BackupState backup) async {
    _starting = true;
    try {
      _init();
      // Asked once ever. Without it the service still runs; the
      // notification just stays out of the shade, and Settings says so.
      if (!_prefs.notificationsAsked) {
        await _prefs.setNotificationsAsked();
        final permission = await FlutterForegroundTask.checkNotificationPermission();
        if (permission != NotificationPermission.granted) {
          await FlutterForegroundTask.requestNotificationPermission();
        }
      }
      final (title, text) = describe(state, backup);
      final result = await FlutterForegroundTask.startService(
        serviceId: _serviceId,
        serviceTypes: const [ForegroundServiceTypes.dataSync],
        notificationTitle: title,
        notificationText: text,
        notificationIcon: _icon,
        notificationButtons: buttons(state),
        notificationInitialRoute: notificationRoute,
        callback: transferServiceEntryPoint,
      );
      _running = result is ServiceRequestSuccess;
      if (!_running) debugPrint('[KeepAlive] Could not start: $result');
    } catch (e) {
      debugPrint('[KeepAlive] $e');
    } finally {
      _starting = false;
    }
    final pending = _pending;
    _pending = null;
    if (pending != null) await update(pending.$1, pending.$2);
  }

  Future<void> _stop() async {
    _running = false;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    try {
      await FlutterForegroundTask.stopService();
    } catch (e) {
      debugPrint('[KeepAlive] $e');
    }
  }

  /// The notification's buttons for [state]: Pause while any transfer the
  /// person started is in flight, and none while only photo backup runs.
  @visibleForTesting
  static List<NotificationButton> buttons(TransfersState state) => [
    if (state.active.any((t) => t.origin != TransferOrigin.backup))
      const NotificationButton(id: pauseButton, text: 'Pause'),
  ];

  /// The notification's title and text for [state] and [backup]. Copies
  /// from chats are counted apart from uploads, since nothing goes up, and
  /// by file rather than by byte, since Telegram makes each in one request.
  @visibleForTesting
  static (String, String) describe(TransfersState state, BackupState backup) {
    final inFlight = state.active;
    final percent = '${(state.activeProgress * 100).round()}%';
    if (inFlight.isNotEmpty && inFlight.every((t) => t.wait is WaitingForNetwork)) {
      return ('Waiting for network', 'Carries on when you\'re back online · $percent');
    }
    if (inFlight.isEmpty && state.waitingForWifi.isNotEmpty) {
      final waiting = state.waitingForWifi.length;
      return (
        'Waiting for Wi-Fi',
        waiting == 1
            ? '1 transfer starts on its own on Wi-Fi'
            : '${Formatters.count(waiting, 'transfer')} start on their own on Wi-Fi',
      );
    }
    final active = inFlight
        .where((t) => t.origin != TransferOrigin.backup)
        .toList();
    final copies = active.where((t) => t.origin == TransferOrigin.fromChat).length;
    final uploads = active.where((t) => t.kind == TransferKind.upload).length - copies;
    final downloads = active.length - uploads - copies;
    final speed = state.active.fold<double>(0, (sum, t) => sum + t.bytesPerSecond);
    final backingUp = _backingUp(state, backup);

    final parts = [
      if (uploads > 0) 'Uploading ${Formatters.count(uploads, 'file')}',
      if (downloads > 0) 'Downloading ${Formatters.count(downloads, 'file')}',
      if (copies > 0) 'Saving ${Formatters.count(copies, 'file')} from Telegram',
      if (backingUp) active.isEmpty ? 'Backing up photos' : 'backing up photos',
    ];
    final title = parts.isEmpty ? 'Telegrive' : parts.join(' · ');
    final text = [
      if (backingUp && backup.total > 0)
        '${Formatters.count(backup.remaining, 'item')} left'
      else if (copies > 0 && copies == active.length)
        '${Formatters.count(state.copyCount.left, 'file')} left'
      else
        percent,
      if (speed > 0) Formatters.speed(speed),
    ].join(' · ');
    return (title, text);
  }
}

/// Runs inside the service's own isolate. It has nothing to do — the
/// service exists only to keep the process, and TDLib, alive.
@pragma('vm:entry-point')
void transferServiceEntryPoint() {
  FlutterForegroundTask.setTaskHandler(_IdleTaskHandler());
}

class _IdleTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  @override
  void onNotificationPressed() =>
      FlutterForegroundTask.launchApp(TransferKeepAlive.notificationRoute);

  /// The app's isolate holds the queue, so the press goes there.
  @override
  void onNotificationButtonPressed(String id) => FlutterForegroundTask.sendDataToMain(id);
}

/// Watched from the app root; does nothing off Android.
///
/// Besides the ongoing notification, it carries out Pause from the shade
/// and posts the quiet notifications about the person's own transfers:
/// 'Transfers paused' after Pause, cleared once nothing is paused, and one
/// summary when a batch finishes while Telegrive is off screen. On screen,
/// Home and the snacks already say it.
final transferKeepAliveProvider = Provider<void>((ref) {
  if (kIsWeb || !Platform.isAndroid) return;
  final keeper = TransferKeepAlive(ref.read(preferencesProvider));
  void push() => unawaited(
    keeper.update(ref.read(transferQueueProvider), ref.read(backupControllerProvider)),
  );

  // When the transfers the person started last went from none in flight to
  // some; null while none are.
  DateTime? batchSince;
  void noteBatch(TransfersState state) {
    final yours = state.active.any((t) => t.origin != TransferOrigin.backup);
    if (yours) {
      batchSince ??= DateTime.now();
      return;
    }
    final since = batchSince;
    if (since == null) return;
    batchSince = null;
    final summary = TransferSummary.of(state.items, since);
    if (summary != null &&
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      unawaited(TransferNotifications.showSummary(summary));
    }
  }

  Future<void> pauseYours() async {
    bool yours(TransferRow row) => row.origin != TransferOrigin.backup;
    final count = ref
        .read(transferQueueProvider)
        .items
        .where((t) => t.status.isActive && yours(t.row))
        .length;
    if (count == 0) return;
    await ref.read(transferQueueProvider.notifier).pauseAll(yours);
    await TransferNotifications.showPaused(count);
  }

  void onData(Object data) {
    if (data == TransferKeepAlive.pauseButton) unawaited(pauseYours());
  }

  FlutterForegroundTask.addTaskDataCallback(onData);
  ref.listen<TransfersState>(transferQueueProvider, (_, next) {
    push();
    noteBatch(next);
  });
  ref.listen<int>(transferQueueProvider.select((s) => s.pausedCount), (previous, next) {
    if (next == 0 && (previous ?? 0) > 0) unawaited(TransferNotifications.clearPaused());
  });
  ref.listen<BackupState>(backupControllerProvider, (_, _) => push(), fireImmediately: true);
  ref.onDispose(() {
    FlutterForegroundTask.removeTaskDataCallback(onData);
    unawaited(
      keeper.update(TransfersState.empty, const BackupState(phase: BackupPhase.off)),
    );
  });
});
