import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../transfers/domain/transfer_error.dart';

/// Why a delete that ran didn't go through. Every failure is an object of
/// its own, so the same sentence twice in a row is still said twice.
class DeleteFailure {
  DeleteFailure(this.message);

  final String message;
}

/// Deletes for good, empties of the trash, album deletes and deletes of the
/// phone's own copies that are waiting out their Undo window.
@immutable
class PendingDeletesState {
  const PendingDeletesState({this.hiddenIds = const {}, this.lastFailure});

  /// Every file, folder and album a waiting or running delete covers. Lists
  /// leave these out, so a delete looks done the moment it is asked for.
  final Set<String> hiddenIds;

  /// The latest delete that ran and didn't go through, for the shell to say
  /// wherever the person is by then.
  final DeleteFailure? lastFailure;
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

  /// For a delete of the phone's own copies: each drive file's id and the
  /// phone media ids it stands for, less the files restored since. What is
  /// left is what the delete takes.
  Map<String, List<String>>? copies;

  /// Its window has closed, but it needs the app in front and waits for
  /// that, or for its turn after another such delete.
  bool due = false;
}

/// Holds back what can't be undone: the items vanish at once, and the
/// messages are deleted only after [wait] without Undo, when the app goes
/// to the background, or when another delete like it is asked for (its
/// snack takes the place of the one offering Undo).
///
/// The wait runs on its own timer, not the snack's, and starts again when
/// the snack is fully in ([shown]). Any other snack hides the Undo early
/// while the delete still waits its full time, and a delete that was never
/// run because the app was killed leaves the items where they were.
/// Nothing is kept across a restart, and signing out drops what is waiting
/// ([discardAll]).
///
/// A delete of the phone's own copies differs in four ways. It follows
/// the snack offering Undo, whose owner calls [commit] when it closes
/// unused, with [wait] left as the backstop. Android asks about it over the
/// app, which it can't do from the background: sending the app away leaves
/// it waiting, and if its window closes meanwhile it runs when the app
/// comes back. Its backstop starts again when the app is back and doesn't
/// count while it is away, since a snack shown to nobody hasn't offered
/// Undo yet. These deletes run one at a time, since the phone's library
/// takes one request at a time and leaves the first unanswered when a
/// second comes; one waiting its turn can still be undone, and waits for
/// the app again if it has gone by then. And a file restored from the Trash
/// before its delete starts keeps its phone copy ([keepPhoneCopies]).
class PendingDeletes extends Notifier<PendingDeletesState> {
  /// How long Undo is offered before the delete runs.
  static const wait = Duration(seconds: 10);

  final _waiting = <String, _PendingDelete>{};
  final _running = <String, _PendingDelete>{};
  var _nextToken = 0;
  var _inFront = true;

  /// A delete of the phone's own copies is under way.
  var _phoneDeleteRunning = false;

  /// Counts [discardAll] calls, so a delete that was under way at a
  /// sign-out doesn't report into whatever drive comes next.
  var _generation = 0;

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
  /// token that [undo], [commit] and [shown] take.
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

  /// Schedules a delete of the phone's own copies of drive files that have
  /// just gone to the Trash. [copies] maps each file's id to the phone media
  /// ids it stands for, and [run] deletes the media ids it is handed: those
  /// of the files still in [copies] when it starts.
  String schedulePhoneDelete({
    required Map<String, List<String>> copies,
    required String label,
    required String failure,
    required Future<void> Function(List<String> assetIds) run,
  }) {
    final left = {...copies};
    final token = schedule(
      label: label,
      failure: failure,
      needsForeground: true,
      run: () => run([for (final ids in left.values) ...ids]),
    );
    _waiting[token]!.copies = left;
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
  /// or, if it needs the app in front, once the app is and its turn has
  /// come.
  Future<void> commit(String token) => _fire(token);

  /// The snack offering Undo for [token] is fully on screen. Its own time
  /// starts only now, after it has come in, so the delete's starts again
  /// too, and Undo is never on screen after the delete has run.
  void shown(String token) {
    final pending = _waiting[token];
    if (pending == null || pending.due) return;
    pending.timer?.cancel();
    pending.timer = Timer(wait, () => _backstop(token));
  }

  /// [fileIds] are coming back from the Trash, so the phone keeps its
  /// copies of them. A delete of the phone's own copies that hasn't started
  /// leaves them out, and one left with nothing to delete is dropped. The
  /// restore's own snack then takes the place of the one offering Undo,
  /// which closes unused, and the delete that follows no longer reaches
  /// them.
  void keepPhoneCopies(Iterable<String> fileIds) {
    final ids = fileIds.toSet();
    for (final MapEntry(key: token, value: pending) in _waiting.entries.toList()) {
      final copies = pending.copies;
      if (copies == null) continue;
      copies.removeWhere((fileId, _) => ids.contains(fileId));
      if (copies.isEmpty) undo(token);
    }
  }

  /// Runs every waiting delete now, one after another.
  Future<void> flush() async {
    for (final token in _waiting.keys.toList()) {
      await _fire(token);
    }
  }

  /// Drops every delete that hasn't started, without running it, and
  /// forgets what was hidden and what failed. Signing out calls this first:
  /// nothing is deleted once the drive has left the phone, and what was
  /// waiting is still in the channel for the next sign-in. A delete already
  /// under way finishes, but no longer reports back.
  void discardAll() {
    for (final pending in _waiting.values) {
      pending.timer?.cancel();
    }
    _waiting.clear();
    _running.clear();
    _generation++;
    state = const PendingDeletesState();
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
    for (final MapEntry(key: token, value: pending) in _waiting.entries) {
      if (pending.needsForeground && !pending.due) {
        pending.timer?.cancel();
        pending.timer = Timer(wait, () => _backstop(token));
      }
    }
    await _runDuePhoneDeletes();
  }

  /// Says [failure] as if a delete had just failed with it.
  @visibleForTesting
  void reportFailure(String failure) => state = PendingDeletesState(
    hiddenIds: state.hiddenIds,
    lastFailure: DeleteFailure(failure),
  );

  /// The time for [token] ran out with no word from its snack. A delete
  /// that needs the app in front and finds it away is left for
  /// [appResumed] to start its time again, rather than counting a window
  /// nobody saw as one that closed.
  void _backstop(String token) {
    final pending = _waiting[token];
    if (pending == null || (pending.needsForeground && !_inFront)) return;
    unawaited(_fire(token));
  }

  Future<void> _fire(String token) async {
    final pending = _waiting[token];
    if (pending == null) return;
    pending.timer?.cancel();
    if (pending.needsForeground) {
      pending.due = true;
      return _runDuePhoneDeletes();
    }
    await _run(token, pending);
  }

  /// Runs the deletes of the phone's own copies that are due, oldest first
  /// and one at a time, checking before each that the app is in front. One
  /// whose turn comes while the app is away stays waiting, and
  /// [appResumed] carries on from it.
  Future<void> _runDuePhoneDeletes() async {
    if (_phoneDeleteRunning) return;
    _phoneDeleteRunning = true;
    try {
      while (_inFront && ref.mounted) {
        final next = _waiting.entries.where((entry) => entry.value.due).firstOrNull;
        if (next == null) break;
        await _run(next.key, next.value);
      }
    } finally {
      _phoneDeleteRunning = false;
    }
  }

  /// The items stay hidden while the delete runs, so they don't flash back
  /// before Telegram answers; they come back only if it fails.
  Future<void> _run(String token, _PendingDelete pending) async {
    _waiting.remove(token);
    _running[token] = pending;
    final generation = _generation;
    DeleteFailure? failure;
    try {
      await pending.run();
    } catch (e) {
      debugPrint('[Trash] Could not delete ${pending.label}: $e');
      failure = DeleteFailure(
        pending.failure ??
            'Couldn\'t delete ${pending.label} for good: ${describeTransferError(e)}',
      );
    } finally {
      _running.remove(token);
    }
    if (!ref.mounted || generation != _generation) return;
    state = PendingDeletesState(
      hiddenIds: _hidden(),
      lastFailure: failure ?? state.lastFailure,
    );
  }

  Set<String> _hidden() => {
    for (final pending in [..._waiting.values, ..._running.values]) ...pending.ids,
  };
}

final pendingDeletesProvider = NotifierProvider<PendingDeletes, PendingDeletesState>(
  PendingDeletes.new,
);
