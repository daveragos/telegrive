import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'drive_repository.dart';

/// Sits out Telegram's flood waits for changes to the channel, and says so:
/// the state is when the current wait ends, or null when nothing is
/// waiting. The status line above the bar counts down from it, and its Stop
/// cuts the wait short.
class TelegramWait extends Notifier<DateTime?> {
  /// How long one second of a wait lasts; tests shorten it.
  @visibleForTesting
  static Duration unit = const Duration(seconds: 1);

  /// What a wait cut short throws, so a bulk change can tell being stopped
  /// from failing.
  static const stopped = DriveException('Stopped.');

  final Map<Completer<void>, ({Timer timer, DateTime until, bool stoppable})> _sleeps = {};

  /// Stop was pressed and the change it ended hasn't finished yet, so a
  /// wait that comes up in the meantime ends as soon as it starts.
  bool _stopping = false;

  @override
  DateTime? build() {
    ref.onDispose(() {
      for (final MapEntry(key: done, value: sleep) in _sleeps.entries) {
        sleep.timer.cancel();
        if (!done.isCompleted) done.completeError(stopped);
      }
    });
    return null;
  }

  /// Waits out the [wait] Telegram asked for, unless [cutShort] ends it
  /// first with [stopped]. A wait that isn't [stoppable] runs its course,
  /// for an edit that is halfway through and must not be left that way.
  Future<void> sleep(Duration wait, {bool stoppable = true}) async {
    if (stoppable && _stopping) throw stopped;
    final duration = unit * wait.inSeconds;
    final done = Completer<void>();
    _sleeps[done] = (
      timer: Timer(duration, () {
        if (!done.isCompleted) done.complete();
      }),
      until: DateTime.now().add(duration),
      stoppable: stoppable,
    );
    _publish();
    try {
      await done.future;
    } finally {
      _sleeps.remove(done)?.timer.cancel();
      _publish();
    }
  }

  /// Ends every stoppable wait now, and any that starts before [reset];
  /// each one throws [stopped].
  void cutShort() {
    _stopping = true;
    for (final MapEntry(key: done, value: sleep) in _sleeps.entries) {
      if (sleep.stoppable && !done.isCompleted) done.completeError(stopped);
    }
  }

  /// The stopped change is over, so later waits are sat out again.
  void reset() => _stopping = false;

  /// The latest end among the waits running, so the line never promises a
  /// start sooner than the real one.
  void _publish() {
    if (!ref.mounted) return;
    DateTime? until;
    for (final sleep in _sleeps.values) {
      if (until == null || sleep.until.isAfter(until)) until = sleep.until;
    }
    state = until;
  }
}

final telegramWaitProvider = NotifierProvider<TelegramWait, DateTime?>(TelegramWait.new);
