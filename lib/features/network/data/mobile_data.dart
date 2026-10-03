import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;

import '../../../infrastructure/network/network_status.dart';
import '../../../infrastructure/storage/preferences.dart';
import '../../../infrastructure/telegram/telegram_client.dart';
import '../domain/data_period.dart';

/// The monthly mobile data limit and what this period has used of it.
@immutable
class MobileDataState {
  const MobileDataState({
    required this.metered,
    required this.limit,
    required this.renewDay,
    required this.periodStart,
    required this.periodEnd,
    this.mobileBytes = 0,
    this.wifiBytes = 0,
    this.overridden = false,
    this.measured = false,
    this.failed = false,
  });

  /// The phone is on mobile data, a phone's hotspot included.
  final bool metered;

  /// The monthly mobile data limit in bytes, or null for none.
  final int? limit;

  /// The day of the month the period renews on, 1 to 28.
  final int renewDay;
  final DateTime periodStart;
  final DateTime periodEnd;

  /// What Telegram sent and received this period over mobile data, and over
  /// Wi-Fi or any other unmetered network.
  final int mobileBytes;
  final int wifiBytes;

  /// 'Use data anyway': backup goes past the limit until the phone is on an
  /// unmetered network again, or the app restarts.
  final bool overridden;

  /// TDLib has said what it counted since the app started. Until then the
  /// numbers are the ones saved at the last count.
  final bool measured;

  /// The last time TDLib was asked, it couldn't say.
  final bool failed;

  /// What is left of [limit] this period, or null without one.
  int? get remaining => switch (limit) {
    final limit? => math.max(0, limit - mobileBytes),
    null => null,
  };

  /// The limit is used up, and nobody said to go past it.
  bool get exhausted => !overridden && limit != null && mobileBytes >= limit!;

  /// Whether [bytes] more can go now without passing the limit: always on
  /// an unmetered network, without a limit, or once told to go past it.
  bool fits(int bytes) => !metered || overridden || limit == null || mobileBytes + bytes <= limit!;

  MobileDataState copyWith({
    bool? metered,
    int? mobileBytes,
    int? wifiBytes,
    DateTime? periodStart,
    DateTime? periodEnd,
    bool? overridden,
    bool? measured,
    bool? failed,
  }) => MobileDataState(
    metered: metered ?? this.metered,
    limit: limit,
    renewDay: renewDay,
    periodStart: periodStart ?? this.periodStart,
    periodEnd: periodEnd ?? this.periodEnd,
    mobileBytes: mobileBytes ?? this.mobileBytes,
    wifiBytes: wifiBytes ?? this.wifiBytes,
    overridden: overridden ?? this.overridden,
    measured: measured ?? this.measured,
    failed: failed ?? this.failed,
  );

  @override
  bool operator ==(Object other) =>
      other is MobileDataState &&
      other.metered == metered &&
      other.limit == limit &&
      other.renewDay == renewDay &&
      other.periodStart == periodStart &&
      other.periodEnd == periodEnd &&
      other.mobileBytes == mobileBytes &&
      other.wifiBytes == wifiBytes &&
      other.overridden == overridden &&
      other.measured == measured &&
      other.failed == failed;

  @override
  int get hashCode => Object.hash(
    metered,
    limit,
    renewDay,
    periodStart,
    periodEnd,
    mobileBytes,
    wifiBytes,
    overridden,
    measured,
    failed,
  );
}

/// Counts this period's mobile data from what TDLib itself sent and
/// received, for the monthly limit photo backup keeps inside.
///
/// TDLib books every byte under the network type it was last told, which
/// [NetworkStatus] keeps right from the start, so a hotspot's traffic counts
/// as mobile. Its counters run from when its database was made, so each
/// period keeps a baseline of where they stood. They restart after a
/// sign-out or a reset of that database, which shows as a new start date,
/// and what the period had used by then is carried over. TDLib's own
/// statistics are never reset.
class MobileDataController extends Notifier<MobileDataState> {
  /// How often the count is brought up to date while the app runs, which
  /// is also how a new period is noticed.
  static const Duration refreshEvery = Duration(seconds: 30);

  Future<void>? _refreshing;

  Preferences get _prefs => ref.read(preferencesProvider);

  @override
  MobileDataState build() {
    ref.listen<NetworkState>(networkStatusProvider, (_, next) => _onNetwork(next));
    final timer = Timer.periodic(refreshEvery, (_) => unawaited(refresh()));
    ref.onDispose(timer.cancel);
    unawaited(Future.microtask(refresh));
    return _saved(DateTime.now(), metered: ref.read(networkStatusProvider).metered);
  }

  /// Asks TDLib what it has counted and brings this period up to date,
  /// starting the next period once the renewal day has passed. Callers at
  /// the same time share one request.
  Future<void> refresh() => _refreshing ??= _refresh().whenComplete(() => _refreshing = null);

  /// Sets the limit, or none, and the renewal day. A different renewal day
  /// starts a new period from now.
  Future<void> setLimit(int? bytes, int renewDay) async {
    final newDay = renewDay != _prefs.dataRenewDay;
    await _prefs.setDataLimit(bytes, renewDay);
    if (newDay) await _prefs.clearDataPeriod();
    if (!ref.mounted) return;
    final now = DateTime.now();
    final saved = _saved(now, metered: state.metered);
    state = saved.copyWith(overridden: state.overridden, measured: state.measured);
    await refresh();
  }

  /// Lets backup go past the limit until the phone is on an unmetered
  /// network again.
  void useDataAnyway() => state = state.copyWith(overridden: true);

  /// The state as the preferences hold it at [now], before TDLib is asked.
  MobileDataState _saved(DateTime now, {required bool metered}) {
    final renewDay = _prefs.dataRenewDay;
    final start = DataPeriod.startFor(now, renewDay);
    final period = _prefs.dataPeriod;
    final current = period != null && period.start == start.millisecondsSinceEpoch;
    return MobileDataState(
      metered: metered,
      limit: _prefs.dataLimitBytes,
      renewDay: renewDay,
      periodStart: start,
      periodEnd: DataPeriod.endFor(start, renewDay),
      mobileBytes: current ? period.mobileCarry : 0,
      wifiBytes: current ? period.wifiCarry : 0,
    );
  }

  /// Joining an unmetered network ends 'Use data anyway'.
  void _onNetwork(NetworkState network) {
    final unmetered = network.online && !network.metered;
    state = state.copyWith(metered: network.metered, overridden: unmetered ? false : null);
  }

  Future<void> _refresh() async {
    if (!ref.mounted) return;
    _onNetwork(ref.read(networkStatusProvider));
    final client = ref.read(telegramClientProvider);
    // TDLib answers only once it has its parameters.
    final auth = client.authState;
    if (auth == null || auth is td.AuthorizationStateWaitTdlibParameters) return;
    final td.NetworkStatistics statistics;
    try {
      statistics = await client.send<td.NetworkStatistics>(
        const td.GetNetworkStatistics(onlyCurrent: false),
      );
    } catch (e) {
      debugPrint('[MobileData] $e');
      if (ref.mounted) state = state.copyWith(failed: true);
      return;
    }
    if (!ref.mounted) return;
    final counters = countersOf(statistics);
    final now = DateTime.now();
    final renewDay = _prefs.dataRenewDay;
    final stored = _prefs.dataPeriod;
    final period = advance(
      stored,
      mobile: counters.mobile,
      wifi: counters.wifi,
      since: statistics.sinceDate,
      now: now,
      renewDay: renewDay,
    );
    if (period != stored) await _prefs.setDataPeriod(period);
    if (!ref.mounted) return;
    final start = DateTime.fromMillisecondsSinceEpoch(period.start);
    state = state.copyWith(
      periodStart: start,
      periodEnd: DataPeriod.endFor(start, renewDay),
      mobileBytes: period.mobileCarry,
      wifiBytes: period.wifiCarry,
      measured: true,
      failed: false,
    );
  }

  /// TDLib's cumulative bytes over mobile data (roaming included) and over
  /// Wi-Fi or any other network, counting every file entry, the ones with
  /// no file type too, which carry everything that isn't a file.
  @visibleForTesting
  static ({int mobile, int wifi}) countersOf(td.NetworkStatistics statistics) {
    var mobile = 0;
    var wifi = 0;
    for (final entry in statistics.entries) {
      if (entry is! td.NetworkStatisticsEntryFile) continue;
      final bytes = entry.sentBytes + entry.receivedBytes;
      switch (entry.networkType) {
        case td.NetworkTypeMobile() || td.NetworkTypeMobileRoaming():
          mobile += bytes;
        case td.NetworkTypeWiFi() || td.NetworkTypeOther():
          wifi += bytes;
        default:
          break;
      }
    }
    return (mobile: mobile, wifi: wifi);
  }

  /// [stored] brought up to TDLib's [mobile] and [wifi] counters, which it
  /// has kept since [since] (seconds), at [now].
  ///
  /// Each count folds what moved since the last one into the carry, so the
  /// carry always holds what the period has used. A period that is over, or
  /// none at all, starts afresh: from nothing when TDLib began counting
  /// inside it, since all it counted belongs there, and otherwise from where
  /// its counters stand. Counters that restarted (a new [since]) count from
  /// nothing on top of what was carried.
  @visibleForTesting
  static DataPeriodSnapshot advance(
    DataPeriodSnapshot? stored, {
    required int mobile,
    required int wifi,
    required int since,
    required DateTime now,
    required int renewDay,
  }) {
    final storedStart = stored == null ? null : DateTime.fromMillisecondsSinceEpoch(stored.start);
    final over =
        storedStart == null ||
        now.isBefore(storedStart) ||
        !now.isBefore(DataPeriod.endFor(storedStart, renewDay));
    final DataPeriodSnapshot from;
    if (over) {
      final start = DataPeriod.startFor(now, renewDay);
      final fresh = since * 1000 >= start.millisecondsSinceEpoch;
      from = (
        start: start.millisecondsSinceEpoch,
        mobileBase: fresh ? 0 : mobile,
        wifiBase: fresh ? 0 : wifi,
        mobileCarry: 0,
        wifiCarry: 0,
        since: since,
      );
    } else if (stored!.since != since) {
      from = (
        start: stored.start,
        mobileBase: 0,
        wifiBase: 0,
        mobileCarry: stored.mobileCarry,
        wifiCarry: stored.wifiCarry,
        since: since,
      );
    } else {
      from = stored;
    }
    return (
      start: from.start,
      mobileBase: mobile,
      wifiBase: wifi,
      mobileCarry: DataPeriod.spent(
        counter: mobile,
        baseline: from.mobileBase,
        carry: from.mobileCarry,
      ),
      wifiCarry: DataPeriod.spent(counter: wifi, baseline: from.wifiBase, carry: from.wifiCarry),
      since: since,
    );
  }
}

final mobileDataProvider = NotifierProvider<MobileDataController, MobileDataState>(
  MobileDataController.new,
);
