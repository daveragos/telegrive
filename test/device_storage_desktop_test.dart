import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:telegrive/core/platform/app_platform.dart';
import 'package:telegrive/infrastructure/storage/device_storage.dart';

void main() {
  late Directory root;
  late Directory source;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('downloads');
    source = await Directory.systemTemp.createTemp('fetched');
    AppPlatform.debugDesktop = true;
    DeviceStorage.desktopFolder = root.path;
  });

  tearDown(() async {
    AppPlatform.debugDesktop = false;
    DeviceStorage.desktopFolder = null;
    await root.delete(recursive: true);
    await source.delete(recursive: true);
  });

  File fetched(String name, int bytes) =>
      File(p.join(source.path, name))..writeAsBytesSync(List.filled(bytes, 1));

  test('a computer saves into the chosen folder, in the drive folders the file is in', () async {
    final saved = await DeviceStorage().saveFile(
      fetched('a.pdf', 10).path,
      folders: ['Work', 'Taxes'],
      name: 'a.pdf',
      mimeType: 'application/pdf',
    );
    expect(saved, p.join(root.path, 'Work', 'Taxes', 'a.pdf'));
    expect(File(saved).lengthSync(), 10);
  });

  test('the same file again is the one there, and another of its name is numbered', () async {
    final storage = DeviceStorage();
    final first = await storage.saveFile(fetched('a.pdf', 10).path, folders: const [], name: 'a.pdf', mimeType: '');
    final again = await storage.saveFile(fetched('b.pdf', 10).path, folders: const [], name: 'a.pdf', mimeType: '');
    final other = await storage.saveFile(fetched('c.pdf', 20).path, folders: const [], name: 'a.pdf', mimeType: '');
    expect(again, first);
    expect(other, p.join(root.path, 'a (1).pdf'));
  });

  test('the location names the chosen folder', () {
    expect(DeviceStorage.location, isNot(contains('Download ›')));
    DeviceStorage.desktopFolder = null;
    expect(DeviceStorage.location, 'Downloads › Telegrive');
  });
}
