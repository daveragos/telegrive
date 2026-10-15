import 'package:flutter/foundation.dart';

import '../../../core/format/formatters.dart';

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

/// Android ended the time it gives Telegrive's transfers in the background,
/// six hours a day, and nothing moves until Telegrive is on screen again,
/// which gives that time back. A queued transfer doesn't start meanwhile,
/// and a running one keeps what TDLib has sent or fetched and carries on
/// from there. It can wait for hours, so it never counts as in flight.
final class WaitingForApp extends TransferWait {
  const WaitingForApp();

  @override
  bool holdsAt(DateTime now) => true;
}

/// The phone has [free] bytes and the transfer [needed] bytes free before
/// it writes anything. It starts by itself once there is room, which may
/// take until someone deletes something, so it never counts as in flight.
final class WaitingForRoom extends TransferWait {
  const WaitingForRoom(this.needed, this.free);

  final int needed;
  final int free;

  /// 'Needs 1.3 GB free · 180 MB free on this phone'.
  String get sentence =>
      'Needs ${Formatters.bytes(needed)} free · ${Formatters.bytes(free)} free on this phone';

  @override
  bool holdsAt(DateTime now) => true;
}
