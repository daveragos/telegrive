import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:telegrive/infrastructure/storage/disk_space.dart';

void main() {
  test("reads free and total bytes from df's POSIX listing", () {
    const output = 'Filesystem     1024-blocks      Used Available Capacity  Mounted on\n'
        '/dev/disk3s5     482797652 432205056  16544288      97%    /System/Volumes/Data\n';
    expect(DiskSpace.parseDf(output), (free: 16544288 * 1024, total: 482797652 * 1024));
  });

  test('reads them when a long device name pushes the figures onto a line of their own', () {
    const output = 'Filesystem 1024-blocks Used Available Capacity Mounted on\n'
        '/dev/mapper/a-very-long-volume-group-name\n'
        '   1000 400 600 40% /home\n';
    expect(DiskSpace.parseDf(output), (free: 600 * 1024, total: 1000 * 1024));
  });

  test('says nothing for a listing without figures', () {
    expect(DiskSpace.parseDf('df: /nowhere: No such file or directory'), isNull);
  });

  test('reads this computer', () async {
    final space = await DiskSpace.of(Directory.systemTemp.path);
    expect(space, isNotNull);
    expect(space!.total, greaterThan(space.free));
  }, skip: Platform.isWindows ? 'df is for macOS and Linux' : false);
}
