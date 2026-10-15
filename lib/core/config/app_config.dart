import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// App-wide constants. Telegram API credentials live next door in the
/// git-ignored `telegram_api.dart`, so every build ships with them and people
/// only ever sign in with their phone.
abstract final class AppConfig {
  static const String appName = 'Telegrive';

  /// This build's version: `version` in pubspec.yaml without the build
  /// number, so 0.1.0 for `0.1.0+1`. Settings › About shows it, and
  /// Telegram's Devices list shows it beside the app's name. Where the
  /// platform can't say, as in tests, it reads "unknown"; TDLib takes no
  /// empty version.
  static Future<String> appVersion() async {
    try {
      final version = (await PackageInfo.fromPlatform()).version;
      if (version.isNotEmpty) return version;
    } catch (e) {
      debugPrint('[AppConfig] No app version: $e');
    }
    return 'unknown';
  }
}
