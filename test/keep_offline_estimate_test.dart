import 'package:flutter_test/flutter_test.dart';
import 'package:telegrive/core/files/file_kind.dart';
import 'package:telegrive/features/drive/domain/drive_models.dart';
import 'package:telegrive/features/offline/presentation/keep_offline_sheet.dart';

const _mb = 1 << 20;

SaveItem _item(String name, int size) {
  final now = DateTime(2026, 10, 4);
  return (
    file: DriveFile(
      id: name,
      folderId: 'trips',
      name: name,
      mimeType: 'video/mp4',
      kind: FileKind.video,
      size: size,
      createdAt: now,
      modifiedAt: now,
      partCount: 1,
      starred: false,
    ),
    folders: const ['Trips'],
    path: const ['Trips'],
  );
}

void main() {
  // 700 MB in all, the largest 400 MB.
  final items = [_item('a.mp4', 100 * _mb), _item('b.mp4', 400 * _mb), _item('c.mp4', 200 * _mb)];

  test('counts the files and adds up their size', () {
    final estimate = KeepOfflineEstimate.of(items, freeBytes: null, android: false);

    expect(estimate.count, 3);
    expect(estimate.bytes, 700 * _mb);
    expect(estimate.largest, 400 * _mb);
  });

  test('on Android the room needed includes the largest file twice', () {
    expect(KeepOfflineEstimate.of(items, freeBytes: null, android: true).needed, 1100 * _mb);
    expect(KeepOfflineEstimate.of(items, freeBytes: null, android: false).needed, 700 * _mb);
  });

  test('it is too big once the phone has less free than it needs', () {
    KeepOfflineEstimate estimate(int free) =>
        KeepOfflineEstimate.of(items, freeBytes: free, android: true);

    expect(estimate(1100 * _mb).tooBig, isFalse);
    expect(estimate(1100 * _mb - 1).tooBig, isTrue);
  });

  test('free space the phone did not report never stops it', () {
    expect(KeepOfflineEstimate.of(items, freeBytes: null, android: true).tooBig, isFalse);
  });
}
