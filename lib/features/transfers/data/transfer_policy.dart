import '../../../infrastructure/database/app_database.dart' show TransferRow;
import '../../../infrastructure/network/network_status.dart';

/// When a transfer runs and when it waits, in one place. The queue asks
/// [mayRun] before it starts a row, so nothing starts that one of the rules
/// would hold, and the places a transfer begins use the sizes to decide what
/// to ask a person on mobile data. Pure, so each rule is tested on its own.
abstract final class TransferPolicy {
  /// From this size, starting a transfer on mobile data asks first.
  static const int askOnDataFrom = 50 << 20;

  /// From this size, a transfer nobody was asked about waits for Wi-Fi when
  /// the setting says big transfers do.
  static const int bigFrom = 200 << 20;

  /// A file that a folder kept offline gains later comes over mobile data
  /// when it is under this size; from it, it waits for Wi-Fi.
  static const int followUpOnDataBelow = 20 << 20;

  /// Whether starting [bytes] on [network] is worth a question first.
  static bool shouldAsk({required NetworkState network, required int bytes}) =>
      network.metered && bytes >= askOnDataFrom;

  /// Whether a transfer of [bytes] nobody was asked about waits for Wi-Fi.
  static bool wifiOnlyFor(int bytes, {required bool bigWaitForWifi}) =>
      bigWaitForWifi && bytes >= bigFrom;

  /// Whether [row] has to wait for Wi-Fi on [network]: it is marked Wi-Fi
  /// only, and the phone is not [onWifi].
  static bool waitsForWifi(TransferRow row, NetworkState network) =>
      row.wifiOnly && !onWifi(network);

  /// Whether [network] lets a Wi-Fi-only transfer run: online, and not on
  /// mobile data. Without a network it doesn't start either, since the next
  /// one may well be mobile data and TDLib would be sending on it before the
  /// phone said so.
  static bool onWifi(NetworkState network) => network.online && !network.metered;

  /// Whether a queued [row] may start at [now]. It may not before its next
  /// try is due ([notBefore]: Telegram's pause, or a retry after a dropped
  /// connection), while it is being retried and Telegram still waits for a
  /// network ([waitsForNetwork]), while it waits for Wi-Fi on [network] (see
  /// [waitsForWifi]), while the phone lacks the room it needs ([hasRoom]),
  /// or while Android has ended the background time for transfers and
  /// Telegrive isn't on screen yet ([waitsForApp]).
  static bool mayRun(
    TransferRow row, {
    required DateTime now,
    required NetworkState network,
    DateTime? notBefore,
    bool waitsForNetwork = false,
    bool hasRoom = true,
    bool waitsForApp = false,
  }) =>
      !(notBefore?.isAfter(now) ?? false) &&
      !waitsForNetwork &&
      !waitsForWifi(row, network) &&
      hasRoom &&
      !waitsForApp;
}
