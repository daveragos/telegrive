import 'package:flutter_test/flutter_test.dart';
import 'package:telegrive/features/backup/data/phone_folders.dart';
import 'package:telegrive/features/files/data/folder_upload_plan.dart';
import 'package:telegrive/features/files/presentation/phone_folder_upload.dart';

PhoneDocument _doc(String name, {String dir = '', int size = 100, bool readable = true}) => PhoneDocument(
  id: '$dir/$name',
  name: name,
  mimeType: '',
  size: size,
  modifiedAt: DateTime(2026, 11, 7),
  dir: dir,
  uri: readable ? 'content://tree/$dir/$name' : null,
);

List<String> _names(FolderUploadGroup group) => [for (final file in group.files) file.name];

void main() {
  group('FolderUploadPlan', () {
    test('groups the files by folder, parents before the folders inside them', () {
      final plan = FolderUploadPlan.of('Trip', [
        _doc('beach.jpg', dir: 'Day 2'),
        _doc('notes.txt'),
        _doc('dinner.jpg', dir: 'Day 1/Evening'),
        _doc('sunrise.jpg', dir: 'Day 1'),
        _doc('map.pdf'),
      ]);
      expect([for (final group in plan.groups) group.path], [
        <String>[],
        ['Day 1'],
        ['Day 2'],
        ['Day 1', 'Evening'],
      ]);
      expect(_names(plan.groups.first), ['notes.txt', 'map.pdf']);
      expect(plan.fileCount, 5);
      expect(plan.bytes, 500);
      expect(plan.subfolderCount, 3);
      expect(plan.skipped, 0);
    });

    test('a folder with no files of its own is still counted, as it is made '
        'to hold the ones inside it', () {
      final plan = FolderUploadPlan.of('Music', [_doc('song.mp3', dir: 'Artist/Album')]);
      expect([for (final group in plan.groups) group.path], [
        ['Artist', 'Album'],
      ]);
      expect(plan.subfolderCount, 2);
    });

    test('leaves out hidden files and folders, empty files and ones it can\'t read', () {
      final plan = FolderUploadPlan.of('Camera', [
        _doc('a.jpg'),
        _doc('.nomedia'),
        _doc('.pending-123-b.jpg'),
        _doc('c.jpg', dir: '.thumbnails'),
        _doc('d.jpg', dir: 'Edits/.trash'),
        _doc('e.jpg', size: 0),
        _doc('f.jpg', readable: false),
      ]);
      expect(plan.fileCount, 1);
      expect(_names(plan.groups.single), ['a.jpg']);
      expect(plan.skipped, 6);
      expect(plan.subfolderCount, 0);
    });
  });

  group('PhoneFolderUpload.confirmMessage', () {
    test('says how much goes where, and the folders inside it', () {
      final plan = FolderUploadPlan.of('Trip', [
        _doc('a.jpg', size: 1500000),
        _doc('b.jpg', dir: 'Day 1', size: 1500000),
      ]);
      final message = PhoneFolderUpload.confirmMessage(plan, where: 'Files', truncated: false);
      expect(message, startsWith('2 files ('));
      expect(message, contains('go up to the folder "Trip" in Files, with the 1 folder inside it'));
      expect(message, isNot(contains('only the first')));
    });

    test('a folder of files alone says nothing of folders inside it', () {
      final plan = FolderUploadPlan.of('Scans', [_doc('a.pdf')]);
      final message = PhoneFolderUpload.confirmMessage(plan, where: 'Work', truncated: false);
      expect(message, endsWith('go up to the folder "Scans" in Work.'));
    });

    test('says when the folder was too big to read in full', () {
      final plan = FolderUploadPlan.of('Everything', [_doc('a.pdf')]);
      final message = PhoneFolderUpload.confirmMessage(plan, where: 'Files', truncated: true);
      expect(message, contains('only the first 20,000 go'));
    });
  });

  group('PhoneFolderUpload.summary', () {
    test('says how many go up, and what stayed behind', () {
      expect(PhoneFolderUpload.summary(name: 'Trip', queued: 12, skipped: 0), 'Uploading 12 files to "Trip".');
      expect(
        PhoneFolderUpload.summary(name: 'Trip', queued: 1, skipped: 1),
        'Uploading 1 file to "Trip". 1 hidden or empty file stays behind.',
      );
      expect(
        PhoneFolderUpload.summary(name: 'Trip', queued: 3, skipped: 2, waitsForWifi: true),
        'Waiting for Wi-Fi to upload 3 files to "Trip". 2 hidden or empty files stay behind.',
      );
    });
  });
}
