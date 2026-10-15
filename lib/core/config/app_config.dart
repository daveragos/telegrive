import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// App-wide constants. Telegram API credentials live next door in the
/// git-ignored `telegram_api.dart`, so every build ships with them and people
/// only ever sign in with their phone.
abstract final class AppConfig {
  static const String appName = 'Telegrive';

  /// Where the source code is.
  static final Uri sourceCode = Uri.parse('https://github.com/daveragos/telegrive');

  /// A new issue on GitHub from .github/ISSUE_TEMPLATE/bug_report.yml, with
  /// this build's [version] filled in.
  static Uri problemReport(String version) => Uri.https(
    'github.com',
    '/daveragos/telegrive/issues/new',
    {'template': 'bug_report.yml', if (version.isNotEmpty) 'version': version},
  );

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
