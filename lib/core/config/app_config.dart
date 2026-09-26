/// App-wide constants. Telegram API credentials live next door in the
/// git-ignored `telegram_api.dart`, so every build ships with them and people
/// only ever sign in with their phone.
abstract final class AppConfig {
  static const String appName = 'Telegrive';
  static const String appVersion = '1.0.0';
}
