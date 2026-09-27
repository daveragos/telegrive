import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../transfers/domain/transfer_error.dart';

/// Deletes for good, empties of the trash and album deletes that are
/// waiting out their Undo window.
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
  _PendingDelete({required this.ids, required this.label, required this.run});

  final Set<String> ids;
  final String label;
  final Future<void> Function() run;
  Timer? timer;
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
class PendingDeletes extends Notifier<PendingDeletesState> {
  /// How long Undo is offered before the delete runs.
  static const wait = Duration(seconds: 10);

  final _waiting = <String, _PendingDelete>{};
  final _running = <String, _PendingDelete>{};
  var _nextToken = 0;

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
  /// `"report.pdf"`, for the sentence if it fails. Returns the token that
  /// [undo] takes.
  String schedule({
    Set<String> fileIds = const {},
    Set<String> folderIds = const {},
    Set<String> albumIds = const {},
    required String label,
    required Future<void> Function() run,
  }) {
    unawaited(flush());
    final token = '${_nextToken++}';
    _waiting[token] = _PendingDelete(
      ids: {...fileIds, ...folderIds, ...albumIds},
      label: label,
      run: run,
    )..timer = Timer(wait, () => _fire(token));
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

  /// Runs every waiting delete now, one after another.
  Future<void> flush() async {
    for (final token in _waiting.keys.toList()) {
      await _fire(token);
    }
  }

  /// Says [failure] as if a delete had just failed with it.
  @visibleForTesting
  void reportFailure(String failure) =>
      state = PendingDeletesState(hiddenIds: state.hiddenIds, lastFailure: failure);

  /// The items stay hidden while the delete runs, so they don't flash back
  /// before Telegram answers; they come back only if it fails.
  Future<void> _fire(String token) async {
    final pending = _waiting.remove(token);
    if (pending == null) return;
    pending.timer?.cancel();
    _running[token] = pending;
    String? failure;
    try {
      await pending.run();
    } catch (e) {
      debugPrint('[Trash] Could not delete ${pending.label} for good: $e');
      failure = 'Couldn\'t delete ${pending.label} for good: ${describeTransferError(e)}';
    } finally {
      _running.remove(token);
    }
    if (!ref.mounted) return;
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
