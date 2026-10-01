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

/// Telegram can't be reached because the phone has no connection. A running
/// transfer stays running, since TDLib carries on with it by itself once the
/// network is back, and one being retried after the connection dropped
/// waits for it. Either way it is still in flight.
final class WaitingForNetwork extends TransferWait {
  const WaitingForNetwork();

  @override
  bool holdsAt(DateTime now) => false;
}

/// The transfer waits for an unmetered network and does not start on mobile
/// data. It can wait for hours, so it never counts as in flight.
final class WaitingForWifi extends TransferWait {
  const WaitingForWifi();

  @override
  bool holdsAt(DateTime now) => true;
}
