import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../drive/data/drive_repository.dart';
import '../../drive/data/telegram_wait.dart';

/// A change to many items that is under way: what it is, and how far along.
@immutable
class BulkEdit {
  const BulkEdit({
    required this.label,
    required this.icon,
    required this.done,
    required this.total,
    this.stopping = false,
  });

  /// What is happening, e.g. `Moving 500 items`.
  final String label;
  final IconData icon;
  final int done;
  final int total;

  /// Stop was pressed; the change ends after the item in hand.
  final bool stopping;

  BulkEdit copyWith({int? done, bool? stopping}) => BulkEdit(
    label: label,
    icon: icon,
    done: done ?? this.done,
    total: total,
    stopping: stopping ?? this.stopping,
  );
}

/// How a bulk change ended: all of it, stopped part way, or failed on an
/// item with [error]. The items before it stay changed either way.
@immutable
class BulkOutcome {
  const BulkOutcome({
    required this.done,
    required this.total,
    this.stopped = false,
    this.error,
  });

  final int done;
  final int total;
  final bool stopped;
  final Object? error;

  /// Every item was changed.
  bool get complete => !stopped && error == null;
}

/// Runs a change over many items one at a time, so the status line above
/// the bar can say how far it got and Stop can end it between items. Stop
/// also cuts short a Telegram wait the item in hand is sitting out or runs
/// into later, but only before any of it has changed: a split file whose
/// first part is gone, which takes the change on each part it has left,
/// finishes them first, so stopping never leaves one half changed. One
/// change runs at a time. Nothing is kept across a restart.
class BulkEdits extends Notifier<BulkEdit?> {
  @override
  BulkEdit? build() => null;

  /// Applies [apply] to each of [items] in order, as the change [label].
  Future<BulkOutcome> run<T>({
    required String label,
    required IconData icon,
    required List<T> items,
    required Future<void> Function(T item) apply,
  }) async {
    if (state != null) {
      throw const DriveException('Wait for the current change to finish.');
    }
    state = BulkEdit(label: label, icon: icon, done: 0, total: items.length);
    var done = 0;
    try {
      for (final item in items) {
        if (state!.stopping) break;
        await apply(item);
        done++;
        state = state!.copyWith(done: done);
      }
      return BulkOutcome(
        done: done,
        total: items.length,
        stopped: done < items.length,
      );
    } catch (e) {
      return BulkOutcome(
        done: done,
        total: items.length,
        stopped: e == TelegramWait.stopped,
        error: e == TelegramWait.stopped ? null : e,
      );
    } finally {
      state = null;
      ref.read(telegramWaitProvider.notifier).reset();
    }
  }

  /// Ends the change after the item in hand, and any Telegram wait it is
  /// sitting out now or comes up against before then.
  void stop() {
    final current = state;
    final wait = ref.read(telegramWaitProvider.notifier)..cutShort();
    if (current != null) {
      state = current.copyWith(stopping: true);
    } else {
      // No change is running that would clear the stop when it ends, so
      // only the waits under way now are cut short.
      wait.reset();
    }
  }
}

final bulkEditsProvider = NotifierProvider<BulkEdits, BulkEdit?>(BulkEdits.new);
