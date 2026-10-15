import 'package:flutter_test/flutter_test.dart';
import 'package:telegrive/features/takeout/data/takeout_import.dart';
import 'package:telegrive/features/takeout/presentation/takeout_status.dart';

const _fresh = TakeoutProgress(total: 12430, photos: 11220, videos: 1210, bytes: 92 << 30, albums: 41, alreadyThere: 3120, leftBytes: 70 << 30);

void main() {
  test('while the parts are read, it says so with a moving bar', () {
    final status = describeTakeout(const TakeoutState(phase: TakeoutPhase.reading, reading: 'takeout-001.zip'));
    expect(status.title, 'Reading the parts');
    expect(status.detail, 'takeout-001.zip');
    expect(status.progress, lessThan(0));
    expect(describeTakeout(const TakeoutState()).title, 'Reading the parts');
  });

  test('before it starts, it says what the export holds', () {
    final status = describeTakeout(const TakeoutState(progress: _fresh));
    expect(status.title, '11,220 photos and 1,210 videos');
    expect(describeTakeout(const TakeoutState(progress: TakeoutProgress(total: 3, photos: 3))).title, '3 photos');
    expect(describeTakeout(const TakeoutState(progress: TakeoutProgress(total: 1, videos: 1))).title, '1 video');
    expect(status.detail, '92.0 GB · 41 albums. 3,120 are already in your drive.');
    expect(status.progress, isNull);
  });

  test('while it imports, it counts what is settled and says how long the rest takes', () {
    const progress = TakeoutProgress(total: 100, sent: 30, inDrive: 10);
    final status = describeTakeout(
      const TakeoutState(
        phase: TakeoutPhase.importing,
        running: true,
        progress: progress,
        current: 'IMG_1.jpg',
        speed: 1048576,
        timeLeft: Duration(minutes: 12),
      ),
    );
    expect(status.title, 'Importing 40 of 100');
    expect(status.detail, '12 min left · 1.0 MB/s');
    expect(status.progress, 0.4);
    expect(status.tone, TakeoutTone.busy);
  });

  test('waiting for Wi-Fi or for room says what it waits for', () {
    const progress = TakeoutProgress(total: 10, sent: 4);
    final wifi = describeTakeout(const TakeoutState(phase: TakeoutPhase.waitingForWifi, running: true, progress: progress));
    expect(wifi.title, 'Waiting for Wi-Fi');
    expect(wifi.detail, '6 photos and videos left. Imports follow Photo backup\'s Mobile data choice.');
    expect(wifi.waiting, isTrue);
    final room = describeTakeout(
      const TakeoutState(phase: TakeoutPhase.waitingForRoom, running: true, progress: progress, roomNeeded: 300 << 20),
    );
    expect(room.title, 'Not enough room on this phone');
    expect(room.detail, 'Free up 300 MB to carry on.');
    expect(room.tone, TakeoutTone.bad);
  });

  test('paused, it says how far it got and what is left', () {
    const progress = TakeoutProgress(total: 10, sent: 4, leftBytes: 6 << 20);
    final status = describeTakeout(const TakeoutState(progress: progress));
    expect(status.title, 'Paused · 4 of 10');
    expect(status.detail, '6 photos and videos left, 6.0 MB.');
  });

  test('when the rest are only in parts that can\'t be read, it says that', () {
    const progress = TakeoutProgress(total: 10, sent: 8, blocked: 2);
    final status = describeTakeout(const TakeoutState(running: true, progress: progress));
    expect(status.title, 'Waiting for parts');
    expect(status.detail, 'The 2 photos and videos left are in parts Telegrive can\'t read.');
  });

  test('done, it says how many went up, and owns up to the ones that didn\'t', () {
    final done = describeTakeout(const TakeoutState(progress: TakeoutProgress(total: 5, sent: 4, inDrive: 1)));
    expect(done.title, 'Imported from Google Photos');
    expect(done.detail, '4 imported. 1 was already in your drive.');
    expect(done.tone, TakeoutTone.good);
    final failed = describeTakeout(const TakeoutState(progress: TakeoutProgress(total: 5, sent: 4, failed: 1)));
    expect(failed.title, '1 photo or video didn\'t import');
    expect(failed.detail, '4 imported.');
    expect(failed.tone, TakeoutTone.bad);
  });

  test('an export with nothing to import says so', () {
    expect(describeTakeout(const TakeoutState(progress: TakeoutProgress())).title, 'No photos or videos found');
  });

  test('Home and Transfers mention the import while it runs or is paused partway', () {
    expect(takeoutWorthShowing(const TakeoutState(progress: TakeoutProgress(total: 10, sent: 4))), isTrue);
    expect(takeoutWorthShowing(const TakeoutState()), isFalse);
    expect(takeoutWorthShowing(const TakeoutState(phase: TakeoutPhase.reading)), isTrue);
    expect(takeoutWorthShowing(const TakeoutState(progress: _fresh)), isFalse);
    expect(takeoutWorthShowing(const TakeoutState(running: true, progress: _fresh)), isTrue);
    expect(
      takeoutWorthShowing(const TakeoutState(running: true, progress: TakeoutProgress(total: 1, sent: 1))),
      isFalse,
    );
  });
}
