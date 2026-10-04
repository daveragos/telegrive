import 'package:flutter_test/flutter_test.dart';
import 'package:telegrive/features/transfers/data/room.dart';
import 'package:telegrive/infrastructure/storage/device_storage.dart';

const _mb = 1 << 20;

/// A phone with [free] bytes free, or one that can't say when null.
class _Storage extends DeviceStorage {
  _Storage(this.free);

  final int? free;

  @override
  Future<int?> freeBytes() async => free;
}

void main() {
  test('a staged copy and a split part need their own size and the margin', () {
    expect(Room.margin, 64 * _mb);
    expect(Room.forStage(500 * _mb), 564 * _mb);
    expect(Room.forStage(0), 64 * _mb);
    expect(Room.forPart(512 * _mb), 576 * _mb);
  });

  group('a download needs', () {
    test('what is left of a single file, and the margin', () {
      expect(
        Room.forDownload(
          size: 300 * _mb,
          alreadyHere: 0,
          split: false,
          largestPart: 300 * _mb,
          keepsCopy: false,
        ),
        364 * _mb,
      );
    });

    test('the largest part on top for a split file, since it waits beside the stitched copy', () {
      expect(
        Room.forDownload(
          size: 1200 * _mb,
          alreadyHere: 0,
          split: true,
          largestPart: 512 * _mb,
          keepsCopy: false,
        ),
        (1200 + 512 + 64) * _mb,
      );
    });

    test('the file twice when a save copies it out of the download', () {
      expect(
        Room.forDownload(
          size: 1200 * _mb,
          alreadyHere: 0,
          split: false,
          largestPart: 1200 * _mb,
          keepsCopy: true,
        ),
        (1200 + 1200 + 64) * _mb,
      );
      expect(
        Room.forDownload(
          size: 1200 * _mb,
          alreadyHere: 0,
          split: true,
          largestPart: 512 * _mb,
          keepsCopy: true,
        ),
        (1200 + 512 + 1200 + 64) * _mb,
      );
    });

    test('less for what is already on the phone', () {
      expect(
        Room.forDownload(
          size: 1200 * _mb,
          alreadyHere: 1024 * _mb,
          split: true,
          largestPart: 512 * _mb,
          keepsCopy: true,
        ),
        (176 + 512 + 1200 + 64) * _mb,
      );
    });
  });

  group('shortfall', () {
    test('never holds back when the phone can\'t say how much it has', () async {
      expect(await Room.shortfall(_Storage(null), 900 * _mb), isNull);
    });

    test('says what is needed and what is free when there is less', () async {
      expect(await Room.shortfall(_Storage(180 * _mb), 900 * _mb), (900 * _mb, 180 * _mb));
    });

    test('is null when there is as much or more', () async {
      expect(await Room.shortfall(_Storage(900 * _mb), 900 * _mb), isNull);
      expect(await Room.shortfall(_Storage(10 << 30), 900 * _mb), isNull);
    });
  });
}
