import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:telegrive/core/platform/open_at_login.dart';

void main() {
  test('a start from login is told by its argument, or on a Mac by the agent\'s variable', () {
    expect(OpenAtLogin.startedHidden(['--hidden']), isTrue);
    expect(OpenAtLogin.startedHidden(const []), Platform.environment['TELEGRIVE_HIDDEN'] == '1');
  });

  test('the Mac\'s agent starts the app where it is, hidden, at login', () async {
    const app = '/Applications/Tele & grive.app/Contents/MacOS/Telegrive';
    final agent = OpenAtLogin.launchAgent(app);
    expect(agent, contains('<string>/Applications/Tele &amp; grive.app/Contents/MacOS/Telegrive</string>'));
    expect(agent, contains('<key>TELEGRIVE_HIDDEN</key>'));
    expect(agent, contains('<key>RunAtLoad</key>\n  <true/>'));
    if (Platform.isMacOS) {
      final dir = await Directory.systemTemp.createTemp('agent');
      addTearDown(() => dir.delete(recursive: true));
      final file = File(p.join(dir.path, 'agent.plist'))..writeAsStringSync(agent);
      final lint = await Process.run('plutil', ['-lint', file.path]);
      expect(lint.exitCode, 0, reason: '${lint.stdout}');
    }
  });

  test('the Linux entry quotes the app\'s path and asks for a hidden start', () {
    final entry = OpenAtLogin.autostartEntry(r'/opt/Tele grive/$telegrive');
    expect(entry, contains(r'Exec="/opt/Tele grive/\$telegrive" --hidden'));
    expect(entry, startsWith('[Desktop Entry]\nType=Application\n'));
  });
}
