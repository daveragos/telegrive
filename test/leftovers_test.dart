import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:telegrive/features/transfers/data/leftovers.dart';

void main() {
  late Directory temp;
  late Directory staging;
  late Directory shared;

  /// The sweep runs an hour after the files are made, so they count as old
  /// unless a test makes one younger.
  late DateTime now;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('leftovers_test');
    staging = Directory(p.join(temp.path, 'telegrive-staging'))..createSync();
    shared = Directory(p.join(temp.path, 'shared'))..createSync();
    now = DateTime.now().add(const Duration(hours: 1));
  });

  tearDown(() => temp.deleteSync(recursive: true));

  /// A file of [bytes] at [path] under the temporary folder.
  File file(String path, int bytes) => File(p.join(temp.path, path))
    ..createSync(recursive: true)
    ..writeAsBytesSync(List.filled(bytes, 1));

  Future<int> sweep(Set<String> keep) => sweepLeftovers(
    roots: [staging, shared, Directory(p.join(temp.path, 'file_picker'))],
    keep: keep,
    now: now,
  );

  test('an old copy nothing needs is deleted, and what it held is counted', () async {
    final orphan = file('telegrive-staging/t1/movie.mp4', 300);
    final loose = file('shared/note.txt', 20);

    expect(await sweep({}), 320);
    expect(orphan.parent.existsSync(), isFalse);
    expect(loose.existsSync(), isFalse);
    expect(staging.existsSync(), isTrue);
  });

  test('a young copy stays, as it may still be being made', () async {
    final copying = file('shared/1/clip.mp4.part', 50)
      // Written two minutes before the sweep, in a folder made long before.
      ..setLastModifiedSync(now.subtract(const Duration(minutes: 2)));

    expect(await sweep({}), 0);
    expect(copying.existsSync(), isTrue);
  });

  test('the folder of a copy a transfer still needs stays, and so does the copy', () async {
    final needed = file('telegrive-staging/t2/report.pdf', 100);
    final orphan = file('telegrive-staging/t3/report.pdf', 40);

    expect(await sweep({needed.path}), 40);
    expect(needed.existsSync(), isTrue);
    expect(orphan.parent.existsSync(), isFalse);
  });

  test('a folder named like the start of a needed one is not taken for it', () async {
    final needed = file('shared/12/a.txt', 10);
    final orphan = file('shared/1/b.txt', 30);

    expect(await sweep({needed.path}), 30);
    expect(needed.existsSync(), isTrue);
    expect(orphan.existsSync(), isFalse);
  });

  test('a folder that isn\'t there is passed over', () async {
    staging.deleteSync(recursive: true);

    expect(await sweep({}), 0);
  });

  group('the iOS temporary folder', () {
    late Directory tmp;

    setUp(() => tmp = Directory(p.join(temp.path, 'tmp'))..createSync());

    Future<int> sweepFiles(Set<String> keep) =>
        sweepLeftovers(roots: const [], fileRoots: [tmp], keep: keep, now: now);

    test('each gallery copy goes on its own, beside one a backup still sends', () async {
      final sent = file('tmp/.image/A_o_IMG_0001.HEIC', 500);
      final sending = file('tmp/.image/B_o_IMG_0002.HEIC', 70);
      final video = file('tmp/.video/C_o_IMG_0003.MOV', 900);

      expect(await sweepFiles({sending.path}), 1400);
      expect(sent.existsSync(), isFalse);
      expect(video.existsSync(), isFalse);
      expect(sending.existsSync(), isTrue);
      // The plugin writes into its folders again.
      expect(Directory(p.join(tmp.path, '.video')).existsSync(), isTrue);
    });

    test('a picked copy goes, and one just made stays', () async {
      final picked = file('tmp/9F2C/report.pdf', 40);
      final copying = file('tmp/.video/D_o_IMG_0004.MOV', 60)
        ..setLastModifiedSync(now.subtract(const Duration(minutes: 2)));

      expect(await sweepFiles({}), 40);
      expect(picked.existsSync(), isFalse);
      expect(copying.existsSync(), isTrue);
    });
  });

  group('the app\'s own copies', () {
    const container = '/var/mobile/Containers/Data/Application/AB12';
    const ios = CopyFolders(cache: '$container/Library/Caches', iosTemp: '$container/tmp');
    const android = CopyFolders(cache: '/data/user/0/app/cache');

    test('an iOS app\'s temporary folder is tmp, beside Library', () {
      expect(iosTempBeside('$container/Library/Caches'), '$container/tmp');
      expect(iosTempBeside('/data/user/0/app/cache'), isNull);
    });

    test('on iOS, what the gallery or the picker hands over is a copy', () {
      expect(ios.holds('$container/tmp/.image/A_o_IMG_0001.HEIC'), isTrue);
      expect(ios.holds('$container/tmp/9F2C/report.pdf'), isTrue);
      expect(ios.holds('$container/Library/Caches/file_picker/a.txt'), isTrue);
      expect(ios.holds('$container/Documents/notes.txt'), isFalse);
    });

    test('on Android, the photo itself is not', () {
      expect(android.holds('/storage/emulated/0/DCIM/Camera/IMG_1.jpg'), isFalse);
      expect(android.holds('/data/user/0/app/cache/file_picker/a.txt'), isTrue);
    });

    test('only iOS has a temporary folder swept file by file', () {
      expect(leftoverPlaces(ios).fileRoots.map((d) => d.path), ['$container/tmp']);
      expect(leftoverPlaces(android).fileRoots, isEmpty);
      expect(
        leftoverPlaces(android).roots.map((d) => d.path),
        contains('/data/user/0/app/cache/telegrive-album-thumbs'),
      );
    });
  });
}
