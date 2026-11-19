import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format/formatters.dart';
import '../../../infrastructure/database/app_database.dart' show TransferKind, TransferOrigin, TransferStatus;
import 'transfer_queue.dart';

/// Keeps the transfers the person started going on an iPhone when the
/// screen locks or another app comes up, as Android's foreground service
/// does there.
///
/// iOS suspends an app soon after it leaves the screen, and TDLib's
/// uploads stop with it. From iOS 26 an app may carry on a task the person
/// started, as long as it says how far along it is: iOS shows the progress
/// on the Lock Screen and in the Dynamic Island, where the person can stop
/// it. The task is asked for while Telegrive is on screen, as iOS requires,
/// once a transfer the person started is in flight; it follows the
/// progress of everything started since, and ends when the last is done.
/// Before iOS 26 the runner can only ask for the half minute or so any app
/// gets. Photo backup and the Google Photos import aren't counted: on an
/// iPhone they run while the app is open.
class IosBackgroundTransfers {
  IosBackgroundTransfers({required this.onScreen, @visibleForTesting MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('telegrive/background_transfers') {
    _channel.setMethodCallHandler(_fromIos);
  }

  /// Whether Telegrive is on screen, where iOS lets a task begin.
  final bool Function() onScreen;
  final MethodChannel _channel;

  /// The progress is a share of this many units.
  static const int units = 1000;

  /// How often the progress iOS shows is moved on, at most.
  static const Duration updateEvery = Duration(seconds: 1);

  bool _running = false;

  /// The transfers started since the task began, by id, so the share done
  /// only ever grows as each one finishes and the next starts.
  final Set<String> _batch = {};

  (String, String, int)? _shown;
  DateTime _shownAt = DateTime(0);

  /// Whether a transfer is one the person started, which the task covers.
  static bool counts(TransferItem item) =>
      item.origin != TransferOrigin.backup && item.origin != TransferOrigin.takeout;

  /// Begins, moves on or ends the task for [state].
  Future<void> follow(TransfersState state, {DateTime? now}) async {
    final yours = state.active.where(counts).toList();
    if (yours.isEmpty) {
      await end();
      return;
    }
    _batch.addAll(yours.map((t) => t.id));
    final shown = describe(state, _batch);
    final (title, subtitle, done) = shown;
    final arguments = {'title': title, 'subtitle': subtitle, 'done': done, 'total': units};
    final at = now ?? DateTime.now();
    if (!_running) {
      if (!onScreen()) return;
      _running = true;
      _shown = shown;
      _shownAt = at;
      if (await _invoke('begin', arguments) != true) _running = false;
      return;
    }
    if (shown == _shown) return;
    if (title == _shown?.$1 && at.difference(_shownAt) < updateEvery) return;
    _shown = shown;
    _shownAt = at;
    await _invoke('update', arguments);
  }

  /// Ends the task, once nothing the person started is in flight.
  Future<void> end() async {
    _batch.clear();
    if (!_running) return;
    _running = false;
    _shown = null;
    await _invoke('end', {'success': true});
  }

  /// What iOS shows for the transfers in [batch]: what is under way, the
  /// share done with the speed, and that share in [units]. Copies from
  /// chats count by file, since Telegram makes each in one request, and
  /// the rest by byte, with the finished counted whole.
  @visibleForTesting
  static (String, String, int) describe(TransfersState state, Set<String> batch) {
    final inFlight = state.active.where((t) => batch.contains(t.id)).toList();
    final copies = inFlight.where((t) => t.origin == TransferOrigin.fromChat).length;
    final uploads = inFlight.where((t) => t.kind == TransferKind.upload).length - copies;
    final downloads = inFlight.length - uploads - copies;
    final title = [
      if (uploads > 0) 'Uploading ${Formatters.count(uploads, 'file')}',
      if (downloads > 0) 'Downloading ${Formatters.count(downloads, 'file')}',
      if (copies > 0) 'Saving ${Formatters.count(copies, 'file')} from Telegram',
    ].join(' · ');

    final counted = state.items.where(
      (t) => batch.contains(t.id) && t.status != TransferStatus.cancelled && t.status != TransferStatus.failed,
    );
    final byBytes = counted.where((t) => t.origin != TransferOrigin.fromChat).toList();
    double share;
    if (byBytes.isEmpty) {
      final all = counted.length;
      share = all == 0 ? 0 : counted.where((t) => t.status == TransferStatus.completed).length / all;
    } else {
      var total = 0;
      var done = 0;
      for (final item in byBytes) {
        total += item.row.totalBytes;
        done += item.status == TransferStatus.completed ? item.row.totalBytes : item.row.doneBytes;
      }
      share = total == 0 ? 0 : done / total;
    }
    share = share.clamp(0.0, 1.0);
    final speed = inFlight.fold<double>(0, (sum, t) => sum + t.bytesPerSecond);
    final subtitle = ['${(share * 100).floor()}%', if (speed > 0) Formatters.speed(speed)].join(' · ');
    return (title, subtitle, (share * units).floor());
  }

  Future<Object?> _invoke(String method, Map<String, Object> arguments) async {
    try {
      return await _channel.invokeMethod<Object>(method, arguments);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      debugPrint('[BackgroundTransfers] $method failed: $e');
      return null;
    }
  }

  /// iOS ended the task early: its time ran out, or the person stopped it.
  /// The next time Telegrive is on screen with transfers in flight, a new
  /// one begins.
  Future<Object?> _fromIos(MethodCall call) async {
    if (call.method == 'stopped') {
      _running = false;
      _shown = null;
    }
    return null;
  }
}

/// [IosBackgroundTransfers] following the transfer queue, on an iPhone.
final iosBackgroundTransfersProvider = Provider<IosBackgroundTransfers?>((ref) {
  if (kIsWeb || !Platform.isIOS) return null;
  bool onScreen() {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  final keeper = IosBackgroundTransfers(onScreen: onScreen);
  void follow() => unawaited(keeper.follow(ref.read(transferQueueProvider)));
  ref.listen<TransfersState>(transferQueueProvider, (_, _) => follow(), fireImmediately: true);
  // Back on screen, a task iOS ended begins again for what is still going.
  final lifecycle = AppLifecycleListener(onResume: follow);
  ref.onDispose(() {
    lifecycle.dispose();
    unawaited(keeper.end());
  });
  return keeper;
});
