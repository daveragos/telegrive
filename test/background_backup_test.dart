import 'package:flutter_test/flutter_test.dart';
import 'package:telegrive/features/backup/data/background_backup.dart';
import 'package:telegrive/features/backup/data/backup_controller.dart';

void main() {
  group('the background job is done', () {
    bool done(BackupPhase phase, {int total = 10, int doneCount = 4, DateTime? pausedUntil}) =>
        BackgroundBackup.isDone(
          BackupState(phase: phase, total: total, done: doneCount, pausedUntil: pausedUntil),
        );

    test('when everything is in the drive', () {
      expect(done(BackupPhase.upToDate, doneCount: 10), isTrue);
    });

    test('when what is left waits for Wi-Fi, the monthly limit, access or the drive', () {
      expect(done(BackupPhase.waitingForWifi), isTrue);
      expect(done(BackupPhase.waitingForBudget), isTrue);
      expect(done(BackupPhase.needsPermission), isTrue);
      expect(done(BackupPhase.waitingForDrive), isTrue);
    });

    test('unless the pass stopped on an error', () {
      expect(done(BackupPhase.stopped, doneCount: 10), isFalse);
    });

    test('unless photos are left that its time ran out on', () {
      expect(done(BackupPhase.uploading), isFalse);
    });

    test('unless it paused for a wait Telegram asked for', () {
      expect(done(BackupPhase.uploading, pausedUntil: DateTime(2026, 10, 4, 9, 30)), isFalse);
    });
  });
}
