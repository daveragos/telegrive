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
}
