import 'package:flutter_test/flutter_test.dart';
import 'package:telegrive/core/files/file_kind.dart';
import 'package:telegrive/core/format/formatters.dart';
import 'package:telegrive/features/drive/domain/drive_models.dart';
import 'package:telegrive/features/files/presentation/file_actions.dart';

void main() {
  final added = DateTime(2026, 9, 26, 10, 12);
  final taken = DateTime(2026, 9, 20, 7, 45);

  DriveFile photo({DateTime? takenAt, int parts = 1}) => DriveFile(
    id: 'p',
    folderId: 'camera',
    name: 'IMG_0001.jpg',
    mimeType: 'image/jpeg',
    kind: FileKind.image,
    size: 1200000,
    createdAt: added,
    modifiedAt: added,
    partCount: parts,
    starred: false,
    takenAt: takenAt,
  );

  Map<String, String> asMap(List<DetailLine> lines) => {
    for (final line in lines) line.label: line.value,
  };

  test('a backed-up photo says when it was taken, its albums and its phone folder', () {
    final lines = FileActions.detailLines(
      photo(takenAt: taken),
      path: const ['Photo backup', 'Camera'],
      albums: const ['Family', 'Lalibela 2026'],
      backedUp: true,
    );
    expect(lines.map((line) => line.label), [
      'Type',
      'Size',
      'Taken',
      'Location',
      'Added',
      'Modified',
      'In albums',
      'Backed up from',
    ]);
    final values = asMap(lines);
    expect(values['Taken'], Formatters.fullDate(taken));
    expect(values['Location'], 'Files › Photo backup › Camera');
    expect(values['In albums'], 'Family, Lalibela 2026');
    expect(values['Backed up from'], 'This phone · Camera');
  });

  test('a file with no capture time, albums or phone copy leaves those lines out', () {
    final lines = FileActions.detailLines(photo(), path: const ['Work']);
    expect(lines.map((line) => line.label), [
      'Type',
      'Size',
      'Location',
      'Added',
      'Modified',
    ]);
    expect(asMap(lines)['Location'], 'Files › Work');
  });

  test('a photo from this phone kept outside Photo backup names no folder', () {
    final lines = FileActions.detailLines(photo(), path: const ['Trips'], backedUp: true);
    expect(asMap(lines)['Backed up from'], 'This phone');
    expect(asMap(FileActions.detailLines(photo(), backedUp: true))['Backed up from'], 'This phone');
  });

  test('a split file ends with how it is stored', () {
    final lines = FileActions.detailLines(photo(parts: 3));
    expect(lines.last.label, 'Stored as');
    expect(lines.last.value, '3 parts. Telegram caps one message at 2 GB.');
  });

  test('only Location leads somewhere, and only when asked', () {
    var shown = 0;
    final lines = FileActions.detailLines(
      photo(takenAt: taken),
      albums: const ['Family'],
      backedUp: true,
      showFolder: () => shown++,
    );
    for (final line in lines) {
      expect(line.onTap != null, line.label == 'Location', reason: line.label);
    }
    lines.firstWhere((line) => line.label == 'Location').onTap!();
    expect(shown, 1);
    expect(FileActions.detailLines(photo()).every((line) => line.onTap == null), isTrue);
  });
}
