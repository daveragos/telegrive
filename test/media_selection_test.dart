import 'package:flutter_test/flutter_test.dart';
import 'package:telegrive/core/files/file_kind.dart';
import 'package:telegrive/features/drive/domain/drive_models.dart';
import 'package:telegrive/features/photos/presentation/media_grid.dart';
import 'package:telegrive/features/photos/presentation/media_grid_layout.dart';

DriveFile _photo(String id, DateTime takenAt) => DriveFile(
  id: id,
  folderId: null,
  name: '$id.jpg',
  mimeType: 'image/jpeg',
  kind: FileKind.image,
  size: 1000,
  createdAt: takenAt,
  modifiedAt: takenAt,
  partCount: 1,
  starred: false,
  takenAt: takenAt,
);

void main() {
  late MediaSelection selection;
  late int notified;

  setUp(() {
    selection = MediaSelection();
    notified = 0;
    selection.addListener(() => notified++);
  });

  tearDown(() => selection.dispose());

  test('Select starts selecting with nothing picked', () {
    selection.begin();
    expect(selection.active, isTrue);
    expect(selection.ids, isEmpty);

    selection.begin();
    expect(notified, 1);
  });

  test('clearing ends the selection, whether it was begun or picked into', () {
    selection.begin();
    selection.toggle('a');
    expect(selection.ids, {'a'});

    selection.clear();
    expect(selection.active, isFalse);
    expect(selection.ids, isEmpty);

    // Clearing ends what Select began, so taking out the only pick ends the
    // selection.
    selection.toggle('b');
    selection.toggle('b');
    expect(selection.active, isFalse);

    final before = notified;
    selection.clear();
    expect(notified, before, reason: 'nothing to clear, nothing to say');
  });

  test('a begun selection stays on while its last photo is taken out', () {
    selection.begin();
    selection.toggle('a');
    selection.toggle('a');
    expect(selection.active, isTrue);
  });

  test('a month title adds whatever of the month is missing, then takes it all out', () {
    final now = DateTime(2026, 10, 4);
    final months = monthSections([
      _photo('a', DateTime(2026, 10, 2)),
      _photo('b', DateTime(2026, 9, 20)),
      _photo('c', DateTime(2026, 9, 3)),
    ], now: now);
    final september = months[1];

    selection.toggle('a');
    selection.toggle('c');
    selection.replace(toggleMonth(selection.ids, september));
    expect(selection.ids, {'a', 'b', 'c'});

    selection.replace(toggleMonth(selection.ids, september));
    expect(selection.ids, {'a'});
  });
}
