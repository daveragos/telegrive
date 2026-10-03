import 'dart:math' as math;

/// The month a mobile data plan counts in, from one renewal day to the
/// next, and what was spent in it. Pure, so the calendar edges (January,
/// February, the renewal day itself) are tested on their own.
///
/// Renewal days stop at the 28th, so every month has the day and a period
/// never skips one.
abstract final class DataPeriod {
  static const int lastRenewDay = 28;

  /// The start of the period [now] falls in: local midnight on the latest
  /// [renewDay] that isn't after [now].
  static DateTime startFor(DateTime now, int renewDay) {
    final day = renewDay.clamp(1, lastRenewDay);
    final thisMonth = DateTime(now.year, now.month, day);
    // DateTime carries month 0 back into December of the year before.
    return thisMonth.isAfter(now) ? DateTime(now.year, now.month - 1, day) : thisMonth;
  }

  /// When the period that began at [start] ends: the same day a month on.
  static DateTime endFor(DateTime start, int renewDay) =>
      DateTime(start.year, start.month + 1, renewDay.clamp(1, lastRenewDay));

  /// Bytes spent in the period: what was counted before TDLib's counters
  /// last restarted ([carry]), plus how far [counter] has moved past
  /// [baseline] since. A counter below its baseline adds nothing.
  static int spent({required int counter, required int baseline, required int carry}) =>
      carry + math.max(0, counter - baseline);
}
