import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:telegrive/features/space/data/phone_usage.dart';
import 'package:telegrive/features/transfers/data/leftovers.dart';

const _mb = 1 << 20;
const _gb = 1 << 30;

void main() {
  group('opened files budget', () {
    test('a roomy phone keeps up to 1 GB', () {
      expect(openedFilesBudget(free: 20 * _gb, total: 64 * _gb), _gb);
    });

    test('a phone short of room keeps a third of what is free', () {
      expect(openedFilesBudget(free: 1200 * _mb, total: 16 * _gb), 400 * _mb);
    });

    test('a small phone keeps a tenth of its storage', () {
      expect(openedFilesBudget(free: 3 * _gb, total: 8 * _gb), 8 * _gb ~/ 10);
    });

    test('a nearly full phone still keeps 100 MB', () {
      expect(openedFilesBudget(free: 250 * _mb, total: 64 * _gb), 100 * _mb);
    });

    test('a figure the phone can\'t give is left out', () {
      expect(openedFilesBudget(free: null, total: null), _gb);
      expect(openedFilesBudget(free: 600 * _mb, total: null), 200 * _mb);
    });
  });

  group('leftovers', () {
    late Directory temp;
    late List<Directory> roots;
    late File channelPhoto;

    /// The look happens an hour after the files are made, so they count
    /// as old unless a test makes one younger.
    late DateTime now;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('space_test');
      roots = [
        for (final dir in leftoverDirs) Directory(p.join(temp.path, dir))..createSync(),
      ];
      channelPhoto = File(p.join(temp.path, leftoverFiles.single));
      now = DateTime.now().add(const Duration(hours: 1));
    });

    tearDown(() => temp.deleteSync(recursive: true));

    File file(String path, int bytes) => File(p.join(temp.path, path))
      ..createSync(recursive: true)
      ..writeAsBytesSync(List.filled(bytes, 1));

    Future<Map<String, int>> look(Set<String> keep) async => {
      for (final leftover in await findLeftovers(
        roots: roots,
        files: [channelPhoto],
        keep: keep,
        now: now,
      ))
        p.relative(leftover.entry.path, from: temp.path): leftover.bytes,
    };

    test('skips what transfers use and what is still being made, and finds the rest', () async {
      final queued = file('telegrive-staging/t1/movie.mp4', 300);
      final paused = file('telegrive-parts/t2/movie.mp4.002', 200);
      file('telegrive-staging/t3/old.mp4', 120);
      file('shared/9/note.txt', 20);
      file('file_picker/1/scan.pdf', 40);
      file('telegrive-thumbs/t4.jpg', 8);
      channelPhoto.writeAsBytesSync(List.filled(5, 1));
      file('shared/10/clip.mp4.part', 70)
        // Written two minutes before the look.
        .setLastModifiedSync(now.subtract(const Duration(minutes: 2)));

      final found = await look({queued.path, paused.parent.path});

      expect(found, {
        p.join('telegrive-staging', 't3'): 120,
        p.join('shared', '9'): 20,
        p.join('file_picker', '1'): 40,
        p.join('telegrive-thumbs', 't4.jpg'): 8,
        leftoverFiles.single: 5,
      });
      // Finding them deletes nothing.
      expect(queued.existsSync(), isTrue);
      expect(File(p.join(temp.path, 'telegrive-staging/t3/old.mp4')).existsSync(), isTrue);
    });

    test('nothing there is nothing found', () async {
      for (final root in roots) {
        root.deleteSync(recursive: true);
      }

      expect(await look({}), isEmpty);
    });
  });
}
