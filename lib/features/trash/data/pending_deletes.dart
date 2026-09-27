import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../transfers/domain/transfer_error.dart';

/// Deletes for good, empties of the trash, album deletes and deletes of the
/// phone's own copies that are waiting out their Undo window.
@immutable
class PendingDeletesState {
  const PendingDeletesState({this.hiddenIds = const {}, this.lastFailure});

  /// Every file, folder and album a waiting or running delete covers. Lists
  /// leave these out, so a delete looks done the moment it is asked for.
  final Set<String> hiddenIds;

  /// Why the latest delete that ran didn't go through, for the shell to say
  /// wherever the person is by then.
  final String? lastFailure;
}

class _PendingDelete {
  _PendingDelete({
    required this.ids,
    required this.label,
    required this.failure,
    required this.needsForeground,
    required this.run,
  });

  final Set<String> ids;
  final String label;
  final String? failure;
  final bool needsForeground;
  final Future<void> Function() run;
  Timer? timer;

  /// Its window closed while the app was in the background, so it runs as
  /// soon as the app is back.
  bool due = false;
}

/// Holds back what can't be undone: the items vanish at once, and the
/// messages are deleted only after [wait] without Undo, when the app goes
/// to the background, or when another delete like it is asked for (its
/// snack takes the place of the one offering Undo).
///
/// The wait runs on its own timer, not the snack's. Any other snack hides
/// the Undo early while the delete still waits its full time, and a delete
/// that was never run because the app was killed leaves the items where
/// they were. Nothing is kept across a restart.
///
/// A delete of the phone's own copies differs in three ways. It follows
/// the snack offering Undo, whose owner calls [commit] when it closes
/// unused, with [wait] left as the backstop. Android asks about it over the
/// app, which it can't do from the background: sending the app away leaves
/// it waiting, and if its window closes meanwhile it runs when the app
/// comes back. Its backstop starts again when the app is back and doesn't
/// count while it is away, since a snack shown to nobody hasn't offered
/// Undo yet. And these deletes run one at a time, since the phone's
/// library takes one request at a time and leaves the first unanswered
/// when a second comes.
class PendingDeletes extends Notifier<PendingDeletesState> {
  /// How long Undo is offered before the delete runs.
  static const wait = Duration(seconds: 10);

  final _waiting = <String, _PendingDelete>{};
  final _running = <String, _PendingDelete>{};
  var _nextToken = 0;
  var _inFront = true;

  /// The latest delete of the phone's own copies, which the next one waits
  /// for however it ends.
  Future<void> _lastPhoneDelete = Future.value();

  @override
  PendingDeletesState build() {
    ref.onDispose(() {
      for (final pending in _waiting.values) {
        pending.timer?.cancel();
      }
      _waiting.clear();
    });
    return const PendingDeletesState();
  }

  /// Hides [fileIds], [folderIds] and [albumIds] now and runs [run] once
  /// [wait] is up. [label] names what goes, e.g. `3 items` or
  /// `"report.pdf"`, for the sentence if it fails; [failure] replaces that
  /// sentence and its reason. With [needsForeground], [run] waits for the
  /// app to be in front and for any other such run to finish. Returns the
  /// token that [undo] and [commit] take.
  String schedule({
    Set<String> fileIds = const {},
    Set<String> folderIds = const {},
    Set<String> albumIds = const {},
    required String label,
    String? failure,
    bool needsForeground = false,
    required Future<void> Function() run,
  }) {
    unawaited(flush());
    final token = '${_nextToken++}';
    _waiting[token] = _PendingDelete(
      ids: {...fileIds, ...folderIds, ...albumIds},
      label: label,
      failure: failure,
      needsForeground: needsForeground,
      run: run,
    )..timer = Timer(wait, () => _backstop(token));
    state = PendingDeletesState(hiddenIds: _hidden());
    return token;
  }

  /// Keeps what [token] was going to delete and shows it again. Returns
  /// false when it is too late: the delete has already started.
  bool undo(String token) {
    final pending = _waiting.remove(token);
    if (pending == null) return false;
    pending.timer?.cancel();
    state = PendingDeletesState(hiddenIds: _hidden(), lastFailure: state.lastFailure);
    return true;
  }

  /// The Undo for [token] closed without being used: its delete runs now,
  /// or once the app is back in front if it needs that.
  Future<void> commit(String token) => _fire(token);

  /// Runs every waiting delete now, one after another.
  Future<void> flush() async {
    for (final token in _waiting.keys.toList()) {
      await _fire(token);
    }
  }

  /// The app went to the background, where the process can go at any
  /// moment and the person has moved on from the snack: every waiting
  /// delete runs now, except those that need the app in front, which keep
  /// their window.
  Future<void> appPaused() async {
    _inFront = false;
    for (final MapEntry(key: token, value: pending) in _waiting.entries.toList()) {
      if (!pending.needsForeground) await _fire(token);
    }
  }

  /// The app is in front again: what came due while it was away runs now.
  /// Every other delete that needs the app in front waits a full [wait]
  /// again, since its snack, whose own time starts only once it is on
  /// screen, may not have been seen yet.
  Future<void> appResumed() async {
    _inFront = true;
    final due = <Future<void>>[];
    for (final MapEntry(key: token, value: pending) in _waiting.entries.toList()) {
      if (pending.due) {
        due.add(_fire(token));
      } else if (pending.needsForeground) {
        pending.timer?.cancel();
        pending.timer = Timer(wait, () => _backstop(token));
      }
    }
    await Future.wait(due);
  }

  /// Says [failure] as if a delete had just failed with it.
  @visibleForTesting
  void reportFailure(String failure) =>
      state = PendingDeletesState(hiddenIds: state.hiddenIds, lastFailure: failure);

  /// The time for [token] ran out with no word from its snack. A delete
  /// that needs the app in front and finds it away is left for
  /// [appResumed] to start its time again, rather than counting a window
  /// nobody saw as one that closed.
  void _backstop(String token) {
    final pending = _waiting[token];
    if (pending == null || (pending.needsForeground && !_inFront)) return;
    unawaited(_fire(token));
  }

  /// The items stay hidden while the delete runs, so they don't flash back
  /// before Telegram answers; they come back only if it fails.
  Future<void> _fire(String token) async {
    final pending = _waiting[token];
    if (pending == null) return;
    pending.timer?.cancel();
    if (pending.needsForeground && !_inFront) {
      pending.due = true;
      return;
    }
    _waiting.remove(token);
    _running[token] = pending;
    String? failure;
    try {
      await (pending.needsForeground ? _afterOtherPhoneDeletes(pending.run) : pending.run());
    } catch (e) {
      debugPrint('[Trash] Could not delete ${pending.label}: $e');
      failure =
          pending.failure ??
          'Couldn\'t delete ${pending.label} for good: ${describeTransferError(e)}';
    } finally {
      _running.remove(token);
    }
    if (!ref.mounted) return;
    state = PendingDeletesState(
      hiddenIds: _hidden(),
      lastFailure: failure ?? state.lastFailure,
    );
  }

  /// Runs [run] once the phone delete before it has ended.
  Future<void> _afterOtherPhoneDeletes(Future<void> Function() run) {
    final next = _lastPhoneDelete.then((_) => run());
    _lastPhoneDelete = next.catchError((Object _) {});
    return next;
  }

  Set<String> _hidden() => {
    for (final pending in [..._waiting.values, ..._running.values]) ...pending.ids,
  };
}

final pendingDeletesProvider = NotifierProvider<PendingDeletes, PendingDeletesState>(
  PendingDeletes.new,
);
