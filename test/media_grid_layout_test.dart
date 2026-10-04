import 'package:flutter_test/flutter_test.dart';
import 'package:telegrive/core/files/file_kind.dart';
import 'package:telegrive/features/drive/domain/drive_models.dart';
import 'package:telegrive/features/photos/presentation/media_grid.dart';
import 'package:telegrive/features/photos/presentation/media_grid_layout.dart';

DriveFile _photo(String id, DateTime taken) => DriveFile(
  id: id,
  folderId: null,
  name: '$id.jpg',
  mimeType: 'image/jpeg',
  kind: FileKind.image,
  size: 1000,
  createdAt: DateTime(2026, 9, 30),
  modifiedAt: DateTime(2026, 9, 30),
  partCount: 1,
  starred: false,
  takenAt: taken,
);

void main() {
  final now = DateTime(2026, 9, 20);

  test('months run newest first, titled the way the headers spell them', () {
    final files = [
      _photo('a', DateTime(2026, 9, 18)),
      _photo('b', DateTime(2026, 9, 2)),
      _photo('c', DateTime(2026, 8, 30)),
      _photo('d', DateTime(2026, 8, 3)),
      _photo('e', DateTime(2026, 8, 1)),
      _photo('f', DateTime(2024, 8, 12)),
    ];

    final sections = monthSections(files, now: now);

    expect([for (final s in sections) s.title], ['This month', 'August', 'August 2024']);
    expect([for (final s in sections) s.start], [0, 2, 5]);
    expect([for (final s in sections) s.files.map((f) => f.id).join()], ['ab', 'cde', 'f']);
  });

  test('a photo without a capture date goes by when it was added', () {
    final added = DriveFile(
      id: 'x',
      folderId: null,
      name: 'x.jpg',
      mimeType: 'image/jpeg',
      kind: FileKind.image,
      size: 1000,
      createdAt: DateTime(2025, 3, 4),
      modifiedAt: DateTime(2025, 3, 4),
      partCount: 1,
      starred: false,
    );

    expect(monthSections([added], now: now).single.title, 'March 2025');
  });

  test('a month is selected whole, then cleared whole', () {
    final sections = monthSections([
      _photo('a', DateTime(2026, 9, 18)),
      _photo('b', DateTime(2026, 8, 30)),
      _photo('c', DateTime(2026, 8, 3)),
    ], now: now);
    final august = sections[1];

    final picked = toggleMonth({'a'}, august);
    expect(picked, {'a', 'b', 'c'});
    expect(august.allSelected(picked), isTrue);

    // Part of the month in: the tap adds the rest.
    expect(toggleMonth({'b'}, august), {'b', 'c'});

    // All of it in: the tap takes out exactly that month.
    expect(toggleMonth(picked, august), {'a'});
  });

  group('grid layout at 360 wide', () {
    final sections = monthSections([
      for (var i = 0; i < 9; i++) _photo('sep$i', DateTime(2026, 9, 18 - i)),
      for (var i = 0; i < 14; i++) _photo('aug$i', DateTime(2026, 8, 28 - i)),
      for (var i = 0; i < 5; i++) _photo('old$i', DateTime(2024, 8, 20 - i)),
    ], now: now);

    for (final columns in PhotoColumns.steps) {
      test('$columns across', () {
        final layout = GridLayout(
          columns: columns,
          width: 360,
          headerHeight: 52,
          leading: 88,
          sections: sections,
        );
        final tile = (360 - (columns - 1) * 2) / columns;
        double extent(int n) => (n / columns).ceil() * (tile + 2) - 2;

        expect(layout.tileSize, tile);
        expect(layout.extentOf(9), extent(9));
        expect(layout.extentOf(columns), tile);
        expect(layout.extentOf(columns + 1), 2 * tile + 2);

        // Each month starts where the one before it, header and rows, ends.
        final offsets = <double>[];
        var at = 88.0;
        for (final count in [9, 14, 5]) {
          offsets.add(at);
          at += 52 + extent(count);
        }
        expect(layout.offsets, offsets);
        expect(layout.total, offsets.last + 52 + extent(5) + 32);

        expect(layout.sectionAt(0), 0);
        for (var i = 0; i < offsets.length; i++) {
          expect(layout.sectionAt(offsets[i]), i);
          if (i > 0) expect(layout.sectionAt(offsets[i] - 1), i - 1);
        }
        expect(layout.sectionAt(layout.total + 500), 2);
      });
    }
  });
}
