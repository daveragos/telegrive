import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../infrastructure/database/app_database.dart';
import '../../../infrastructure/telegram/telegram_client.dart';
import '../../../infrastructure/telegram/telegram_exception.dart';
import '../../transfers/domain/transfer_error.dart';
import '../domain/drive_models.dart';
import 'drive_repository.dart';
import 'drive_session.dart';
import 'drive_sync.dart';

/// Where the changes waiting to reach Telegram stand, for Home's line,
/// Waiting changes and the sign-out warning.
@immutable
class OutboxState {
  const OutboxState({
    this.waiting = 0,
    this.failed = 0,
    this.sending = false,
    this.pausedUntil,
    this.notice,
  });

  /// Items with a change waiting, the failed ones included.
  final int waiting;

  /// Of [waiting], those that failed too often to be tried again by
  /// themselves; they wait for Try again.
  final int failed;

  /// A pass is sending them now.
  final bool sending;

  /// Telegram asked for a pause, and the next pass waits until then.
  final DateTime? pausedUntil;

  /// The latest change that reached Telegram without a part another device
  /// had changed first.
  final EditNotice? notice;

  OutboxState copyWith({
    int? waiting,
    int? failed,
    bool? sending,
    DateTime? pausedUntil,
    bool clearPause = false,
    EditNotice? notice,
  }) => OutboxState(
    waiting: waiting ?? this.waiting,
    failed: failed ?? this.failed,
    sending: sending ?? this.sending,
    pausedUntil: clearPause ? null : (pausedUntil ?? this.pausedUntil),
    notice: notice ?? this.notice,
  );
}

/// Sends the changes made while Telegram couldn't be reached, in the order
/// they were made, once it can be: when the connection comes back, when the
/// drive opens, after a sync, when the app comes back to the front and
/// shortly after each new change. Each goes through [DriveRepository.replay],
/// which reads its message again first, so another device's newer change is
/// never overwritten.
///
/// A pause Telegram asks for holds every change until it is over. A change
/// Telegram refuses for any other reason is tried again on later passes, up
/// to [maxAttempts] times, and then waits for Try again in Waiting changes,
/// while the ones after it carry on.
class EditOutbox extends Notifier<OutboxState> {
  /// Tries a change gets before it waits for Try again.
  static const int maxAttempts = 3;

  /// How long a pass waits after whatever asked for it, so a burst of
  /// changes, or a connection that comes and goes, makes one pass.
  @visibleForTesting
  static Duration settle = const Duration(seconds: 2);

  Timer? _soon;
  Timer? _resume;
  Future<void>? _pass;

  /// Asked for again while a pass ran, so another follows it for whatever
  /// the running one had already passed over.
  bool _again = false;

  AppDatabase get _db => ref.read(appDatabaseProvider);

  @override
  OutboxState build() {
    final rows = ref.watch(appDatabaseProvider).watchPendingEdits().listen((rows) {
      if (!ref.mounted) return;
      state = state.copyWith(
        waiting: rows.length,
        failed: rows.where((row) => row.attempts >= maxAttempts).length,
      );
    }, onError: (Object e) => debugPrint('[Outbox] Reading the waiting changes: $e'));
    ref.listen<AsyncValue<bool>>(telegramOnlineProvider, (previous, next) {
      if (next.value == true && previous?.value != true) soon();
    });
    ref.listen<DriveSession?>(driveSessionProvider, (_, session) {
      if (session != null) soon();
    }, fireImmediately: true);
    ref.listen<SyncState>(driveSyncProvider, (previous, next) {
      if ((previous?.running ?? false) && !next.running) soon();
    });
    ref.onDispose(() {
      rows.cancel();
      _soon?.cancel();
      _resume?.cancel();
    });
    return const OutboxState();
  }

  /// Starts a pass once [settle] has gone by with nothing more asking.
  void soon() {
    _soon?.cancel();
    _soon = Timer(settle, () {
      if (ref.mounted) unawaited(drain());
    });
  }

  /// Sends what is waiting, oldest first, one pass at a time. It does
  /// nothing while Telegram can't be reached or has asked for a pause, and
  /// waits for a sync under way, so each change is merged onto a complete
  /// index.
  Future<void> drain() async {
    if (_pass case final running?) {
      _again = true;
      return running;
    }
    final pass = _passes();
    _pass = pass;
    try {
      await pass;
    } finally {
      _pass = null;
    }
  }

  Future<void> _passes() async {
    do {
      _again = false;
      await _drainOnce();
    } while (_again && ref.mounted);
  }

  Future<void> _drainOnce() async {
    if (!_canSend) return;
    await ref.read(driveSyncProvider.notifier).whenIdle();
    if (!ref.mounted || !_canSend) return;
    final due = [
      for (final row in await _db.pendingEditList())
        if (row.attempts < maxAttempts) row,
    ];
    if (due.isEmpty || !ref.mounted) return;
    state = state.copyWith(sending: true);
    try {
      for (final row in due) {
        if (!ref.mounted || !_canSend) return;
        try {
          final notice = await ref.read(driveRepositoryProvider).replay(row);
          if (notice != null && ref.mounted) state = state.copyWith(notice: notice);
        } on TelegramException catch (e) {
          if (e.isFloodWait) {
            _pauseFor(Duration(seconds: (e.retryAfterSeconds ?? 30) + 1));
            return;
          }
          // Telegram didn't answer, so the connection is gone again; the
          // rest wait for the next pass with it.
          if (e.isNetworkProblem) return;
          await _db.failPendingEdit(row.target, row.itemId, describeTransferError(e));
        } on DriveException {
          // The drive closed under the pass, as on sign-out.
          return;
        } catch (e) {
          debugPrint('[Outbox] Sending a waiting change: $e');
          await _db.failPendingEdit(row.target, row.itemId, describeTransferError(e));
        }
      }
    } finally {
      if (ref.mounted) state = state.copyWith(sending: false);
    }
  }

  bool get _canSend {
    final until = state.pausedUntil;
    return ref.read(driveSessionProvider) != null &&
        ref.read(telegramClientProvider).isOnline &&
        (until == null || !until.isAfter(DateTime.now()));
  }

  void _pauseFor(Duration wait) {
    state = state.copyWith(pausedUntil: DateTime.now().add(wait));
    _resume?.cancel();
    _resume = Timer(wait, () {
      if (!ref.mounted) return;
      state = state.copyWith(clearPause: true);
      unawaited(drain());
    });
  }

  /// Gives the changes that failed too often their tries back and sends
  /// them.
  Future<void> retryFailed() async {
    await _db.retryPendingEdits();
    await drain();
  }

  /// Throws away the change waiting for [id]; see
  /// [DriveRepository.discardPending].
  Future<void> discard(EditTarget target, String id) =>
      ref.read(driveRepositoryProvider).discardPending(target, id);
}

final editOutboxProvider = NotifierProvider<EditOutbox, OutboxState>(EditOutbox.new);

/// The changes waiting to reach Telegram, as Waiting changes lists them.
final pendingEditsProvider = StreamProvider.autoDispose<List<PendingEditView>>(
  (ref) => ref.watch(driveRepositoryProvider).watchPendingEdits(),
);

/// Ids of the items with a change waiting, for the clock on their rows.
final pendingItemIdsProvider = StreamProvider<Set<String>>(
  (ref) => ref.watch(appDatabaseProvider).watchPendingItemIds(),
);
