import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'telegram_api.dart';

/// App-wide constants.
abstract final class AppConfig {
  static const String appName = 'Telegrive';

  /// The app's Telegram API credentials, built in so people only ever sign
  /// in with their phone. A build given TELEGRAM_API_ID and
  /// TELEGRAM_API_HASH, with `--dart-define` or `--dart-define-from-file`,
  /// uses those, as release builds do; otherwise they come from the
  /// git-ignored telegram_api.dart.
  static const int telegramApiId = int.fromEnvironment(
    'TELEGRAM_API_ID',
    defaultValue: TelegramApi.apiId,
  );
  static const String telegramApiHash = String.fromEnvironment(
    'TELEGRAM_API_HASH',
    defaultValue: TelegramApi.apiHash,
  );

  /// What the GNU GPL asks an interactive program to show: who holds the
  /// copyright, that there is no warranty, and the license, which the
  /// licenses page lists under Telegrive.
  static const String legalNotice =
      '© 2026 Dawit Beyene. Telegrive is free software under the GNU General '
      'Public License, version 3, and comes with no warranty.';

  /// Where the source code is.
  static final Uri sourceCode = Uri.parse('https://github.com/daveragos/telegrive');

  /// Dawit's tip page on Jami, where people can send a tip in birr. The
  /// payment happens there, never in the app.
  static final Uri support = Uri.parse('https://jami.bio/daveragoose');

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
