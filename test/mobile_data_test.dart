import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegrive/features/network/data/mobile_data.dart';
import 'package:telegrive/features/network/domain/data_period.dart';
import 'package:telegrive/infrastructure/network/network_status.dart';
import 'package:telegrive/infrastructure/storage/preferences.dart';
import 'package:telegrive/infrastructure/telegram/telegram_client.dart';
import 'package:telegrive/infrastructure/telegram/telegram_exception.dart';

import 'support/fake_telegram.dart';

const _mb = 1024 * 1024;
const _wifi = NetworkState(online: true, metered: false);
const _hotspot = NetworkState(online: true, metered: true);

/// TDLib with its parameters set, counting what [counters] says since
/// [since] (seconds), or failing to say when [fails].
class _FakeTelegram extends FakeTelegram {
  _FakeTelegram() {
    receive(
      const td.UpdateAuthorizationState(authorizationState: td.AuthorizationStateReady()).toJson(),
    );
  }

  ({int mobile, int wifi}) counters = (mobile: 0, wifi: 0);
  int since = 0;
  bool fails = false;
  int asked = 0;

  @override
  Future<td.TdObject?> answer(td.TdFunction function) async {
    if (function is! td.GetNetworkStatistics) return null;
    asked++;
    if (fails) throw const TelegramException(500, 'Statistics are unavailable');
    return td.NetworkStatistics(
      sinceDate: since,
      entries: [
        _file(const td.NetworkTypeMobile(), counters.mobile),
        _file(const td.NetworkTypeWiFi(), counters.wifi),
      ],
    );
  }
}

td.NetworkStatisticsEntryFile _file(
  td.NetworkType network,
  int bytes, {
  td.FileType? fileType = const td.FileTypePhoto(),
}) => td.NetworkStatisticsEntryFile(
  fileType: fileType,
  networkType: network,
  sentBytes: bytes,
  receivedBytes: 0,
);

/// A phone whose connection the test moves.
class _Network extends NetworkStatus {
  _Network(this._initial);

  final NetworkState _initial;

  @override
  NetworkState build() => _initial;

  void set(NetworkState next) => state = next;
}

int _seconds(DateTime at) => at.millisecondsSinceEpoch ~/ 1000;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(ProviderContainer, _FakeTelegram)> open({
    Map<String, Object> prefs = const {},
    NetworkState network = _hotspot,
  }) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues(prefs);
    final shared = await SharedPreferences.getInstance();
    final telegram = _FakeTelegram();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(shared),
        telegramClientProvider.overrideWithValue(telegram),
        networkStatusProvider.overrideWith(() => _Network(network)),
      ],
    );
    addTearDown(container.dispose);
    return (container, telegram);
  }

  test('mobile data is mobile and roaming; Wi-Fi is Wi-Fi and the rest', () {
    final counted = MobileDataController.countersOf(
      td.NetworkStatistics(
        sinceDate: 0,
        entries: [
          _file(const td.NetworkTypeMobile(), 100),
          _file(const td.NetworkTypeMobileRoaming(), 20),
          // Traffic that isn't a file, such as messages, has no file type.
          _file(const td.NetworkTypeMobile(), 7, fileType: null),
          _file(const td.NetworkTypeWiFi(), 1000),
          _file(const td.NetworkTypeOther(), 300),
          _file(const td.NetworkTypeNone(), 9),
          const td.NetworkStatisticsEntryCall(
            networkType: td.NetworkTypeMobile(),
            sentBytes: 5000,
            receivedBytes: 5000,
            duration: 60,
          ),
          const td.NetworkStatisticsEntryFile(
            networkType: td.NetworkTypeWiFi(),
            sentBytes: 40,
            receivedBytes: 2,
          ),
        ],
      ),
    );
    expect(counted, (mobile: 127, wifi: 1342));
  });

  test('when TDLib began counting inside this period, all of it is this period\'s', () async {
    final (container, telegram) = await open();
    telegram
      ..since = _seconds(DateTime.now())
      ..counters = (mobile: 70 * _mb, wifi: 300 * _mb);

    await container.read(mobileDataProvider.notifier).refresh();

    final data = container.read(mobileDataProvider);
    expect(data.measured, isTrue);
    expect(data.mobileBytes, 70 * _mb);
    expect(data.wifiBytes, 300 * _mb);
  });

  test('when TDLib began counting before this period, the period starts from now', () async {
    final (container, telegram) = await open();
    final start = DataPeriod.startFor(DateTime.now(), 1);
    telegram
      ..since = _seconds(start.subtract(const Duration(days: 40)))
      ..counters = (mobile: 900 * _mb, wifi: 4000 * _mb);
    final mobileData = container.read(mobileDataProvider.notifier);

    await mobileData.refresh();
    expect(container.read(mobileDataProvider).mobileBytes, 0);

    telegram.counters = (mobile: 905 * _mb, wifi: 4100 * _mb);
    await mobileData.refresh();
    expect(container.read(mobileDataProvider).mobileBytes, 5 * _mb);
    expect(container.read(mobileDataProvider).wifiBytes, 100 * _mb);
  });

  test('counters that start over carry what the period had used', () async {
    final (container, telegram) = await open();
    final start = DataPeriod.startFor(DateTime.now(), 1);
    telegram
      ..since = _seconds(start.subtract(const Duration(days: 3)))
      ..counters = (mobile: 100 * _mb, wifi: 0);
    final mobileData = container.read(mobileDataProvider.notifier);
    await mobileData.refresh();
    telegram.counters = (mobile: 130 * _mb, wifi: 0);
    await mobileData.refresh();
    expect(container.read(mobileDataProvider).mobileBytes, 30 * _mb);

    // Signed out and back in: TDLib counts again from nothing.
    telegram
      ..since = _seconds(DateTime.now())
      ..counters = (mobile: 10 * _mb, wifi: 0);
    await mobileData.refresh();
    expect(container.read(mobileDataProvider).mobileBytes, 40 * _mb);
  });

  test('crossing the renewal day starts the new period from where TDLib stands', () {
    final august = DateTime(2026, 8, 3);
    final stored = (
      start: august.millisecondsSinceEpoch,
      mobileBase: 600 * _mb,
      wifiBase: 0,
      mobileCarry: 380 * _mb,
      wifiCarry: 0,
      since: _seconds(DateTime(2026, 6)),
    );

    final same = MobileDataController.advance(
      stored,
      mobile: 620 * _mb,
      wifi: 0,
      since: stored.since,
      now: DateTime(2026, 9, 2, 23),
      renewDay: 3,
    );
    expect(same.start, august.millisecondsSinceEpoch);
    expect(same.mobileCarry, 400 * _mb);

    final renewed = MobileDataController.advance(
      same,
      mobile: 630 * _mb,
      wifi: 0,
      since: stored.since,
      now: DateTime(2026, 9, 3, 0, 5),
      renewDay: 3,
    );
    expect(renewed.start, DateTime(2026, 9, 3).millisecondsSinceEpoch);
    expect(renewed.mobileBase, 630 * _mb);
    expect(renewed.mobileCarry, 0);
  });

  test('a new renewal day starts a new period without touching TDLib\'s counters', () async {
    final (container, telegram) = await open();
    const day = 15;
    telegram
      ..since = _seconds(DateTime(2020))
      ..counters = (mobile: 500 * _mb, wifi: 0);
    final mobileData = container.read(mobileDataProvider.notifier);
    await mobileData.refresh();
    telegram.counters = (mobile: 520 * _mb, wifi: 0);
    await mobileData.refresh();
    expect(container.read(mobileDataProvider).mobileBytes, 20 * _mb);

    await mobileData.setLimit(400 * _mb, day);

    final data = container.read(mobileDataProvider);
    expect(data.limit, 400 * _mb);
    expect(data.renewDay, day);
    expect(data.periodStart, DataPeriod.startFor(DateTime.now(), day));
    expect(data.mobileBytes, 0);
    expect(telegram.asked, greaterThan(0));
  });

  test('Use data anyway lets backup past the limit until an unmetered network', () async {
    final start = DataPeriod.startFor(DateTime.now(), 1);
    final (container, telegram) = await open(
      prefs: {
        'data_limit_bytes': 250 * _mb,
        'data_period_start': start.millisecondsSinceEpoch,
        'data_mobile_baseline': 0,
        'data_wifi_baseline': 0,
        'data_mobile_carry': 240 * _mb,
        'data_wifi_carry': 0,
        'data_stats_since': 0,
      },
    );
    telegram.fails = true;
    final mobileData = container.read(mobileDataProvider.notifier);
    final network = container.read(networkStatusProvider.notifier) as _Network;
    MobileDataState data() => container.read(mobileDataProvider);

    expect(data().mobileBytes, 240 * _mb);
    expect(data().fits(3 * _mb), isTrue);
    expect(data().fits(30 * _mb), isFalse);

    mobileData.useDataAnyway();
    expect(data().fits(30 * _mb), isTrue);
    expect(data().exhausted, isFalse);

    // Another mobile network keeps it going; Wi-Fi ends it.
    network.set(const NetworkState(online: true, metered: true));
    network.set(const NetworkState(online: false, metered: false));
    expect(data().overridden, isTrue);
    network.set(_wifi);
    expect(data().overridden, isFalse);
    expect(data().fits(30 * _mb), isTrue);

    network.set(_hotspot);
    expect(data().fits(30 * _mb), isFalse);
  });

  test('a count TDLib can\'t give is reported, and the saved one stays', () async {
    final (container, telegram) = await open();
    telegram.fails = true;

    await container.read(mobileDataProvider.notifier).refresh();

    final data = container.read(mobileDataProvider);
    expect(data.failed, isTrue);
    expect(data.measured, isFalse);
  });

  group('Preferences.backupMobileData', () {
    Future<Preferences> prefs(Map<String, Object> values) async {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues(values);
      return Preferences(await SharedPreferences.getInstance());
    }

    test('mobile data allowed before carries over as photos and videos', () async {
      expect((await prefs({'backup_wifi_only': false})).backupMobileData, BackupMobileData.all);
    });

    test('Wi-Fi only, or never set, carries over as off', () async {
      expect((await prefs({'backup_wifi_only': true})).backupMobileData, BackupMobileData.off);
      expect((await prefs({})).backupMobileData, BackupMobileData.off);
    });

    test('a saved choice wins, and backup_wifi_only is left as it is', () async {
      final preferences = await prefs({'backup_wifi_only': false});
      await preferences.setBackupMobileData(BackupMobileData.photos);

      expect(preferences.backupMobileData, BackupMobileData.photos);
      final shared = await SharedPreferences.getInstance();
      expect(shared.getBool('backup_wifi_only'), isFalse);
    });
  });
}
