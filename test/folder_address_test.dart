import 'package:flutter_test/flutter_test.dart';
import 'package:telegrive/features/drive/domain/drive_models.dart';
import 'package:telegrive/features/drive/domain/folder_address.dart';

DriveFolder _folder(String id, String name, {String? parentId, bool trashed = false}) {
  final at = DateTime(2026, 9, 1);
  return DriveFolder(
    id: id,
    parentId: parentId,
    name: name,
    createdAt: at,
    modifiedAt: at,
    trashedAt: trashed ? at : null,
  );
}

void main() {
  group('parse', () {
    test('a plain name is one segment at the root', () {
      final address = FolderAddress.parse('Wedding')!;
      expect(address.segments, ['Wedding']);
      expect(address.create, isFalse);
    });

    test('a leading # asks for the folders to be made, and is dropped', () {
      final address = FolderAddress.parse('  #Taxes/2026 ')!;
      expect(address.segments, ['Taxes', '2026']);
      expect(address.create, isTrue);
    });

    test('empty segments and spaces around names go', () {
      expect(FolderAddress.parse('a//b')!.segments, ['a', 'b']);
      expect(FolderAddress.parse('/ a / b /')!.segments, ['a', 'b']);
    });

    test('more than one line, too long, # alone and nothing are not addresses', () {
      expect(FolderAddress.parse('Wedding\nphotos'), isNull);
      expect(FolderAddress.parse('x' * 129), isNull);
      expect(FolderAddress.parse('#'), isNull);
      expect(FolderAddress.parse('#/'), isNull);
      expect(FolderAddress.parse(''), isNull);
      expect(FolderAddress.parse('   '), isNull);
      expect(FolderAddress.parse('x' * 128), isNotNull);
    });
  });

  group('resolve', () {
    final folders = [
      _folder('taxes', 'Taxes'),
      _folder('2026', '2026', parentId: 'taxes'),
      _folder('wedding', 'Wedding', parentId: '2026'),
      _folder('work', 'Work'),
      _folder('receipts', 'Receipts', parentId: 'work'),
      _folder('receipts-home', 'Receipts', parentId: 'taxes'),
    ];

    test('a path from the root matches each name regardless of case', () {
      expect(FolderAddress.parse('taxes/2026')!.resolve(folders), '2026');
      expect(FolderAddress.parse('TAXES/2026/wedding')!.resolve(folders), 'wedding');
      expect(FolderAddress.parse('#taxes/2026')!.resolve(folders), '2026');
    });

    test('a single name finds the one folder with it anywhere', () {
      expect(FolderAddress.parse('wedding')!.resolve(folders), 'wedding');
    });

    test('a name two folders share is nobody\'s', () {
      expect(FolderAddress.parse('Receipts')!.resolve(folders), isNull);
    });

    test('a path that breaks off is not found, nor a single name to be made', () {
      expect(FolderAddress.parse('Work/2026')!.resolve(folders), isNull);
      expect(FolderAddress.parse('#wedding')!.resolve(folders), isNull);
      expect(FolderAddress.parse('Holiday')!.resolve(folders), isNull);
    });

    test('only the folders handed over count, so one in the trash never does', () {
      final old = _folder('old', 'Old', trashed: true);
      final shown = [...folders, old].where((f) => f.trashedAt == null).toList();
      expect(FolderAddress.parse('Old')!.resolve(shown), isNull);
      expect(FolderAddress.parse('Old')!.resolve([...folders, old]), 'old');
    });
  });
}
