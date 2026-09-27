import 'package:flutter/foundation.dart';

/// Why a transfer that will carry on by itself isn't moving yet. Waiting is
/// not failing: the row stays in progress, says what it is waiting for, and
/// starts again on its own.
@immutable
sealed class TransferWait {
  const TransferWait();

  /// Whether, at [now], the wait is long enough that the transfer no longer
  /// counts as in flight, so the foreground service can stop instead of
  /// holding the phone awake for nothing.
  bool holdsAt(DateTime now);
}

/// Telegram asked for a pause before the next try, until [until].
final class WaitingForTelegram extends TransferWait {
  const WaitingForTelegram(this.until);

  final DateTime until;

  @override
  bool holdsAt(DateTime now) => until.difference(now) > const Duration(minutes: 5);
}
