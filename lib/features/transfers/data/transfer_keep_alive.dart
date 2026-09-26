import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format/formatters.dart';
import '../../../infrastructure/database/app_database.dart'
    show TransferKind, TransferOrigin;
import '../../backup/data/backup_controller.dart';
import 'transfer_queue.dart';

/// Keeps transfers alive when Telegrive leaves the screen (Android).
///
/// TDLib does the actual network work on its own native threads, so all an
/// upload needs to finish in the background is for the process to survive.
/// A foreground service — the ongoing "Uploading 3 files · 42%" notification
/// — is Android's way of saying so. It starts with the first active transfer
/// and stops when the queue drains.
class TransferKeepAlive {
  static const int _serviceId = 4107;
  static const Duration _updateEvery = Duration(milliseconds: 1500);

  bool _running = false;
  bool _starting = false;
  bool _askedPermission = false;
  DateTime _lastUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  (TransfersState, BackupState)? _pending;
  (TransfersState, BackupState)? _latest;
  Timer? _stopTimer;

  static void _init() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'transfers',
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

  /// Anything worth keeping the process alive for: a transfer, or a photo
  /// backup pass (which has short gaps between photos that must not bounce
  /// the service off and on).
  static bool _isActive(TransfersState state, BackupState backup) =>
      state.activeCount > 0 || backup.isWorking;

  Future<void> update(TransfersState state, BackupState backup) async {
    _latest = (state, backup);
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
    if (now.difference(_lastUpdate) < _updateEvery) return;
    _lastUpdate = now;
    final (title, text) = _describe(state, backup);
    await FlutterForegroundTask.updateService(
      notificationTitle: title,
      notificationText: text,
    );
  }

  Future<void> _start(TransfersState state, BackupState backup) async {
    _starting = true;
    try {
      _init();
      if (!_askedPermission) {
        _askedPermission = true;
        final permission = await FlutterForegroundTask.checkNotificationPermission();
        if (permission != NotificationPermission.granted) {
          // Without it the service still runs; the notification just stays
          // out of the shade.
          await FlutterForegroundTask.requestNotificationPermission();
        }
      }
      final (title, text) = _describe(state, backup);
      final result = await FlutterForegroundTask.startService(
        serviceId: _serviceId,
        serviceTypes: const [ForegroundServiceTypes.dataSync],
        notificationTitle: title,
        notificationText: text,
        notificationInitialRoute: '/transfers',
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
    try {
      await FlutterForegroundTask.stopService();
    } catch (e) {
      debugPrint('[KeepAlive] $e');
    }
  }

  static (String, String) _describe(TransfersState state, BackupState backup) {
    final active = state.active
        .where((t) => t.origin == TransferOrigin.manual)
        .toList();
    final uploads = active.where((t) => t.kind == TransferKind.upload).length;
    final downloads = active.length - uploads;
    final speed = state.active.fold<double>(0, (sum, t) => sum + t.bytesPerSecond);

    final parts = [
      if (uploads > 0) 'Uploading ${Formatters.count(uploads, 'file')}',
      if (downloads > 0) 'Downloading ${Formatters.count(downloads, 'file')}',
      if (backup.isWorking) active.isEmpty ? 'Backing up photos' : 'backing up photos',
    ];
    final title = parts.isEmpty ? 'Telegrive' : parts.join(' · ');
    final text = [
      if (backup.isWorking && backup.total > 0)
        '${Formatters.count(backup.remaining, 'item')} left'
      else
        '${(state.activeProgress * 100).round()}%',
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
  void onNotificationPressed() => FlutterForegroundTask.launchApp('/transfers');
}

/// Watched from the app root; does nothing off Android.
final transferKeepAliveProvider = Provider<void>((ref) {
  if (kIsWeb || !Platform.isAndroid) return;
  final keeper = TransferKeepAlive();
  void push() => unawaited(
    keeper.update(ref.read(transferQueueProvider), ref.read(backupControllerProvider)),
  );
  ref.listen<TransfersState>(transferQueueProvider, (_, _) => push());
  ref.listen<BackupState>(backupControllerProvider, (_, _) => push(), fireImmediately: true);
  ref.onDispose(
    () => unawaited(
      keeper.update(TransfersState.empty, const BackupState(phase: BackupPhase.off)),
    ),
  );
});
