import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:telegrive/features/backup/data/backup_controller.dart';
import 'package:telegrive/features/takeout/data/takeout_import.dart';
import 'package:telegrive/features/takeout/presentation/takeout_status.dart';
import 'package:telegrive/features/transfers/data/transfer_keep_alive.dart';
import 'package:telegrive/features/transfers/data/transfer_queue.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';

const _idle = BackupState(phase: BackupPhase.off);
const _mb = 1 << 20;

TransferItem _upload(String id, TransferOrigin origin, {int total = 10 * _mb, int done = 0, double speed = 0}) =>
    TransferItem(
      TransferRow(
        id: id,
        kind: TransferKind.upload,
        status: TransferStatus.running,
        name: '$id.jpg',
        mimeType: 'image/jpeg',
        fileId: id,
        ownsSource: false,
        wifiOnly: false,
        totalBytes: total,
        doneBytes: done,
        partCount: 1,
        completedParts: 0,
        createdAt: DateTime(2026, 10, 9),
        origin: origin,
      ),
      bytesPerSecond: speed,
    );

/// An import 1,204 of 3,349 photos along, sending at [speed] with [left]
/// to go.
TakeoutState _importing({double speed = 2.4 * _mb, Duration? left = const Duration(minutes: 38)}) => TakeoutState(
  phase: TakeoutPhase.importing,
  running: true,
  working: true,
  speed: speed,
  timeLeft: left,
  progress: const TakeoutProgress(total: 3349, sent: 806, inDrive: 398),
);

void main() {
  group('takeoutHoldsMotion', () {
    List<int> photo(String inside) => [0xFF, 0xD8, ...latin1.encode('...$inside...'), 0xFF, 0xD9];

    test('finds the movement a Samsung or Pixel photo carries', () {
      expect(takeoutHoldsMotion(photo('MotionPhoto_Data')), isTrue);
      expect(takeoutHoldsMotion(photo('<x:xmpmeta Camera:MotionPhoto="1"')), isTrue);
      expect(takeoutHoldsMotion(photo('<Camera:MotionPhoto>1</Camera:MotionPhoto>')), isTrue);
      expect(takeoutHoldsMotion(photo('GCamera:MicroVideo="1"')), isTrue);
    });

    test('a plain photo, or one that says it has none, holds no movement', () {
      expect(takeoutHoldsMotion(photo('Exif')), isFalse);
      expect(takeoutHoldsMotion(photo('Camera:MotionPhoto="0"')), isFalse);
    });
  });

  group('takeoutPaceOf', () {
    final start = DateTime(2026, 10, 9, 12);
    (DateTime, int) at(int seconds, int bytes) => (start.add(Duration(seconds: seconds)), bytes);

    test('says nothing until it has watched long enough', () {
      expect(takeoutPaceOf([at(0, 0)], left: 100), (speed: 0.0, timeLeft: null));
      expect(takeoutPaceOf([at(0, 0), at(5, 5 * _mb)], left: 100), (speed: 0.0, timeLeft: null));
    });

    test('measures the whole import, the gaps between files included', () {
      // 10 MB went up in 20 seconds, half of which were spent between files.
      final pace = takeoutPaceOf([at(0, 0), at(10, 10 * _mb), at(20, 10 * _mb)], left: 60 * _mb);
      expect(pace.speed, closeTo(0.5 * _mb, 1));
      expect(pace.timeLeft, const Duration(minutes: 2));
    });

    test('a still import has no time left to tell', () {
      expect(takeoutPaceOf([at(0, 5), at(20, 5)], left: 100), (speed: 0.0, timeLeft: null));
    });
  });

  group('the import\'s status', () {
    test('while it imports, says how long the whole of it takes and how fast it goes', () {
      final status = describeTakeout(_importing());
      expect(status.title, 'Importing 1,204 of 3,349');
      expect(status.detail, '38 min left · 2.4 MB/s');
    });

    test('until it can tell, says it is working that out', () {
      expect(describeTakeout(_importing(speed: 0, left: null)).detail, 'Working out how long the rest takes');
    });
  });

  group('the notification', () {
    test('gives an import alone the whole notification, counted by its photos', () {
      final (title, text) = TransferKeepAlive.describe(
        TransfersState([
          _upload('a', TransferOrigin.takeout, done: 5 * _mb, speed: 3.0 * _mb),
          _upload('b', TransferOrigin.takeout, speed: 1.0 * _mb),
        ]),
        _idle,
        takeout: _importing(),
      );
      expect(title, 'Importing from Google Photos');
      expect(text, '1,204 of 3,349 · 38 min left · 2.4 MB/s');
    });

    test('names the import beside the files someone sends, and gives their share', () {
      final (title, text) = TransferKeepAlive.describe(
        TransfersState([
          _upload('a', TransferOrigin.takeout, done: 9 * _mb),
          _upload('mine', TransferOrigin.manual, done: 5 * _mb),
        ]),
        _idle,
        takeout: _importing(),
      );
      expect(title, 'Importing 1,204 of 3,349 · uploading 1 file');
      expect(text, '50%');
    });

    test('without an import, counts uploads as it always has', () {
      final (title, _) = TransferKeepAlive.describe(
        TransfersState([_upload('mine', TransferOrigin.manual)]),
        _idle,
        takeout: const TakeoutState(),
      );
      expect(title, 'Uploading 1 file');
    });
  });
}
