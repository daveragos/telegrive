import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:telegrive/features/backup/data/desktop_folders.dart';
import 'package:telegrive/features/files/data/folder_upload_plan.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('desktop_folders_test');
    void write(String relative, [int bytes = 10]) => File(p.join(root.path, relative))
      ..createSync(recursive: true)
      ..writeAsBytesSync(List.filled(bytes, 1));
    write('notes.txt');
    write('Trip/Day 1/beach.jpg', 30);
    write('Trip/map.pdf', 20);
    write('Trip/.DS_Store');
    write('Trip/Thumbs.db');
    write('~\$report.docx');
    write('movie.mkv.part');
    write('empty.txt', 0);
    write('.hidden/secret.txt');
  });

  tearDown(() => root.delete(recursive: true));

  test('lists the files under a folder by where they sit in it, leaving clutter out', () async {
    final listed = await DesktopFolders.list(root.path);
    final byId = {for (final doc in listed.files) doc.id: doc};
    expect(listed.truncated, isFalse);
    expect(byId.keys, containsAll(['notes.txt', 'Trip/Day 1/beach.jpg', 'Trip/map.pdf']));
    expect(byId.keys.where((id) => id.contains('DS_Store') || id.contains('Thumbs') || id.contains('~\$')), isEmpty);
    expect(byId.keys.where((id) => id.endsWith('.part')), isEmpty);
    expect(byId['Trip/Day 1/beach.jpg']!.dir, 'Trip/Day 1');
    expect(byId['notes.txt']!.dir, '');
    expect(byId['Trip/map.pdf']!.size, 20);
    expect(byId['Trip/map.pdf']!.mimeType, 'application/pdf');
    expect(byId['Trip/map.pdf']!.uri, p.join(root.path, 'Trip', 'map.pdf'));
  });

  test('the upload plan makes the folders and skips the hidden and the empty', () async {
    final listed = await DesktopFolders.list(root.path);
    final plan = FolderUploadPlan.of('Holiday', listed.files);
    expect(plan.fileCount, 3);
    expect(plan.subfolderCount, 2);
    expect(plan.skipped, 2); // .hidden/secret.txt and empty.txt
    expect(plan.groups.map((g) => g.path.join('/')), ['', 'Trip', 'Trip/Day 1']);
  });

  test('stops at the limit and says the listing was cut short', () async {
    final listed = await DesktopFolders.list(root.path, limit: 2);
    expect(listed.files, hasLength(2));
    expect(listed.truncated, isTrue);
  });
}
