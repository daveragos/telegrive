import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:telegrive/features/player/data/stream_server.dart';

import 'support/fake_telegram.dart';

void main() {
  test('a file whole on disk, outside TDLib\'s cache, is read from there; one changed since is not', () async {
    final dir = await Directory.systemTemp.createTemp('whole_on_disk');
    addTearDown(() => dir.delete(recursive: true));
    final original = File(p.join(dir.path, 'notes.txt'))..writeAsStringSync('0123456789');

    final whole = await StreamServer.wholeOnDisk(tdFile(1, size: 10, path: original.path, downloaded: true), 10);
    expect(whole?.path, original.path);

    // Edited after it went up: another size than the drive's.
    expect(await StreamServer.wholeOnDisk(tdFile(1, size: 10, path: original.path, downloaded: true), 12), isNull);
    // Still to be fetched.
    expect(await StreamServer.wholeOnDisk(tdFile(2, size: 10), 10), isNull);
    // Moved away since.
    expect(await StreamServer.wholeOnDisk(tdFile(3, size: 10, path: p.join(dir.path, 'gone.txt'), downloaded: true), 10), isNull);
  });
}
