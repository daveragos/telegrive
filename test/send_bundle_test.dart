import 'package:flutter_test/flutter_test.dart';
import 'package:telegrive/core/files/file_kind.dart';
import 'package:telegrive/features/drive/domain/drive_models.dart';
import 'package:telegrive/features/send/data/send_bundle.dart';

DriveFile _file(
  String name, {
  int size = 10,
  int parts = 1,
  DateTime? takenAt,
  DateTime? createdAt,
}) {
  final at = createdAt ?? DateTime(2026, 9, 1);
  return DriveFile(
    id: name,
    folderId: null,
    name: name,
    mimeType: 'application/octet-stream',
    kind: FileKind.other,
    size: size,
    createdAt: at,
    modifiedAt: at,
    partCount: parts,
    starred: false,
    takenAt: takenAt,
  );
}

/// [file] as collectForSaving finds it, under [folders] from the sent
/// folder down.
SaveItem _item(DriveFile file, List<String> folders) =>
    (file: file, folders: folders, path: folders);

List<String?> _headers(SendBundle bundle) => [for (final g in bundle.groups) g.header];

List<List<String>> _names(SendBundle bundle) => [
  for (final g in bundle.groups) [for (final f in g.files) f.name],
];

void main() {
  group('SendBundle.fromItems', () {
    test('one folder sends its own files first, then each subfolder under its path', () {
      final bundle = SendBundle.fromItems([
        _item(_file('gondar 2.jpg'), ['Trip', 'Day 2', 'Gondar']),
        _item(_file('b.jpg'), ['Trip']),
        _item(_file('Day1.jpg'), ['Trip', 'Day 1']),
        _item(_file('A.jpg'), ['Trip']),
        _item(_file('gondar 1.jpg'), ['Trip', 'Day 2', 'Gondar']),
      ], stripTop: true);

      expect(_headers(bundle), [null, 'Day 1', 'Day 2 › Gondar']);
      expect(_names(bundle), [
        ['A.jpg', 'b.jpg'],
        ['Day1.jpg'],
        ['gondar 1.jpg', 'gondar 2.jpg'],
      ]);
    });

    test('folders sent together keep their own names as headers', () {
      final bundle = SendBundle.fromItems([
        _item(_file('plan.txt'), ['work']),
        _item(_file('loose.txt'), const []),
        _item(_file('q3.pdf'), ['Taxes', '2025']),
        _item(_file('w2.pdf'), ['Taxes']),
      ]);

      expect(_headers(bundle), [null, 'Taxes', 'Taxes › 2025', 'work']);
      expect(_names(bundle), [
        ['loose.txt'],
        ['w2.pdf'],
        ['q3.pdf'],
        ['plan.txt'],
      ]);
    });

    test('byMoment sends the oldest first, by capture time where known', () {
      final bundle = SendBundle.fromItems(
        [
          _item(_file('c.jpg', takenAt: DateTime(2026, 3, 3)), ['Lalibela']),
          _item(_file('a.jpg', createdAt: DateTime(2026, 9, 1)), ['Lalibela']),
          _item(_file('b.jpg', takenAt: DateTime(2026, 3, 1)), ['Lalibela']),
        ],
        stripTop: true,
        byMoment: true,
      );

      expect(_names(bundle), [
        ['b.jpg', 'c.jpg', 'a.jpg'],
      ]);
    });
  });

  group('SendBundle.fromFiles', () {
    test('gives one group with no header', () {
      final bundle = SendBundle.fromFiles([_file('b.pdf'), _file('a.pdf')]);

      expect(_headers(bundle), [null]);
      expect(_names(bundle), [
        ['a.pdf', 'b.pdf'],
      ]);
    });

    test('of no files is empty', () {
      final bundle = SendBundle.fromFiles(const []);

      expect(bundle.groups, isEmpty);
      expect(bundle.fileCount, 0);
      expect(bundle.firstFile, isNull);
    });
  });

  test('count, size and split add up across groups', () {
    final whole = SendBundle.fromItems([
      _item(_file('a.jpg', size: 100), const []),
      _item(_file('b.jpg', size: 250), ['Trip']),
      _item(_file('c.jpg', size: 50), ['Trip', 'Day 1']),
    ]);
    final split = SendBundle.fromItems([
      _item(_file('a.jpg', size: 100), const []),
      _item(_file('movie.mkv', size: 3000, parts: 2), ['Trip']),
    ]);

    expect(whole.fileCount, 3);
    expect(whole.bytes, 400);
    expect(whole.anySplit, isFalse);
    expect(whole.firstFile?.name, 'a.jpg');
    expect(split.fileCount, 2);
    expect(split.bytes, 3100);
    expect(split.anySplit, isTrue);
  });
}
