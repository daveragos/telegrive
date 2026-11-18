import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Starting Telegrive when the person logs in to the computer, its window
/// hidden in the menu bar or tray: a LaunchAgent on a Mac, the Run key on
/// Windows, an autostart entry on Linux, each written for the app where it
/// is now. Windows and Linux start it with [hiddenArgument]; a Mac app's
/// arguments don't reach Dart, so its agent sets [hiddenVariable] instead.
abstract final class OpenAtLogin {
  static const String hiddenArgument = '--hidden';
  static const String hiddenVariable = 'TELEGRIVE_HIDDEN';
  static const String _id = 'dev.ragoose.telegrive';
  static const String _runKey = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';

  /// Whether this start came from logging in, and should keep the window
  /// hidden.
  static bool startedHidden(List<String> args) =>
      args.contains(hiddenArgument) || Platform.environment[hiddenVariable] == '1';

  /// Whether Telegrive starts at login.
  static Future<bool> isOn() async {
    try {
      if (Platform.isMacOS) return await File(_agentPath).exists();
      if (Platform.isWindows) {
        return (await Process.run('reg', ['query', _runKey, '/v', 'Telegrive'])).exitCode == 0;
      }
      if (Platform.isLinux) return await File(_autostartPath).exists();
    } catch (e) {
      debugPrint('[Login] $e');
    }
    return false;
  }

  /// Starts Telegrive at login, or stops doing so.
  static Future<void> set(bool on) async {
    final app = Platform.resolvedExecutable;
    if (Platform.isMacOS) {
      final agent = File(_agentPath);
      if (!on) return _delete(agent);
      await agent.parent.create(recursive: true);
      await agent.writeAsString(launchAgent(app));
    } else if (Platform.isWindows) {
      final result = await Process.run(
        'reg',
        on
            ? ['add', _runKey, '/v', 'Telegrive', '/t', 'REG_SZ', '/d', '"$app" $hiddenArgument', '/f']
            : ['delete', _runKey, '/v', 'Telegrive', '/f'],
      );
      if (on && result.exitCode != 0) throw ProcessException('reg', const [], '${result.stderr}', result.exitCode);
    } else if (Platform.isLinux) {
      final entry = File(_autostartPath);
      if (!on) return _delete(entry);
      await entry.parent.create(recursive: true);
      await entry.writeAsString(autostartEntry(app));
    }
  }

  /// Writes the entry again for the app where it is now, when it is on,
  /// so it still starts after the app was moved or updated.
  static Future<void> refresh() async {
    try {
      if (await isOn()) await set(true);
    } catch (e) {
      debugPrint('[Login] $e');
    }
  }

  static Future<void> _delete(File file) async {
    if (await file.exists()) await file.delete();
  }

  static String get _home => Platform.environment['HOME'] ?? '';

  static String get _agentPath => p.join(_home, 'Library', 'LaunchAgents', '$_id.plist');

  static String get _autostartPath {
    final config = Platform.environment['XDG_CONFIG_HOME'];
    return p.join(config == null || config.isEmpty ? p.join(_home, '.config') : config, 'autostart', '$_id.desktop');
  }

  /// The LaunchAgent that starts the app at [executable] at login, hidden.
  @visibleForTesting
  static String launchAgent(String executable) {
    String escaped(String text) =>
        text.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
    return '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$_id</string>
  <key>ProgramArguments</key>
  <array>
    <string>${escaped(executable)}</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>$hiddenVariable</key>
    <string>1</string>
  </dict>
  <key>RunAtLoad</key>
  <true/>
  <key>LimitLoadToSessionType</key>
  <string>Aqua</string>
  <key>ProcessType</key>
  <string>Interactive</string>
</dict>
</plist>
''';
  }

  /// The autostart entry that starts the app at [executable] at login,
  /// hidden, quoted as the desktop entry format asks.
  @visibleForTesting
  static String autostartEntry(String executable) {
    final quoted = executable.replaceAllMapped(RegExp(r'["`$\\]'), (m) => '\\${m[0]}');
    return '''
[Desktop Entry]
Type=Application
Name=Telegrive
Comment=Your files, kept in your own Telegram
Exec="$quoted" $hiddenArgument
Terminal=false
X-GNOME-Autostart-enabled=true
''';
  }
}
