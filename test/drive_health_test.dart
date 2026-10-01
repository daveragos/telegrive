import 'package:flutter/material.dart' show Icons;
import 'package:flutter_test/flutter_test.dart';
import 'package:telegrive/core/format/formatters.dart';
import 'package:telegrive/features/backup/data/backup_controller.dart';
import 'package:telegrive/features/drive/data/drive_sync.dart';
import 'package:telegrive/features/home/presentation/drive_health.dart';
import 'package:telegrive/features/transfers/data/transfer_queue.dart';
import 'package:telegrive/features/transfers/domain/transfer_wait.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';

final _now = DateTime(2026, 9, 27, 19, 32);

TransferItem _transfer(
  String name,
  TransferStatus status, {
  TransferOrigin origin = TransferOrigin.manual,
  int total = 100,
  int done = 0,
  String? error,
  TransferWait? wait,
}) => TransferItem(
  TransferRow(
    id: name,
    kind: TransferKind.upload,
    status: status,
    name: name,
    mimeType: 'application/octet-stream',
    fileId: name,
    ownsSource: false,
    wifiOnly: false,
    totalBytes: total,
    doneBytes: done,
    partCount: 1,
    completedParts: 0,
    createdAt: _now,
    origin: origin,
    error: error,
  ),
  wait: wait,
);

const _upToDate = BackupState(phase: BackupPhase.upToDate, total: 10, done: 10);
const _off = BackupState(phase: BackupPhase.off);
final _synced = SyncState(lastSynced: _now);

/// A transfer Telegram asked to wait 40 minutes, long enough to be held.
TransferItem _held(String name, {TransferOrigin origin = TransferOrigin.manual}) => _transfer(
  name,
  TransferStatus.queued,
  origin: origin,
  wait: WaitingForTelegram(_now.add(const Duration(minutes: 40))),
);

/// A transfer running while the phone has no network.
TransferItem _offline(
  String name, {
  TransferOrigin origin = TransferOrigin.manual,
  int total = 100,
  int done = 0,
}) => _transfer(
  name,
  TransferStatus.running,
  origin: origin,
  total: total,
  done: done,
  wait: const WaitingForNetwork(),
);

/// A transfer queued until the phone is on Wi-Fi.
TransferItem _onWifi(String name, {TransferOrigin origin = TransferOrigin.manual, int total = 100}) =>
    _transfer(
      name,
      TransferStatus.queued,
      origin: origin,
      total: total,
      wait: const WaitingForWifi(),
    );

const _gb = 1 << 30;

DriveHealth _top({
  BackupState backup = _upToDate,
  SyncState? sync,
  TransfersState transfers = TransfersState.empty,
  DateTime? lastFullSync,
  double backupSpeed = 0,
}) => describeDriveHealth(
  backup: backup,
  sync: sync ?? _synced,
  transfers: transfers,
  lastFullSync: lastFullSync,
  backupSpeed: backupSpeed,
  now: _now,
);

void main() {
  group('describeDriveHealth', () {
    test('uploading beats active transfers', () {
      final health = _top(
        backup: const BackupState(phase: BackupPhase.uploading, total: 2000, done: 273),
        transfers: TransfersState([_transfer('a.zip', TransferStatus.running)]),
        backupSpeed: 2.1 * 1024 * 1024,
      );
      expect(health.text, 'Backing up · 1,727 left');
      expect(health.detail, '2.1 MB/s');
      expect(health.tone, HealthTone.busy);
      expect(health.progress, closeTo(273 / 2000, 1e-9));
      expect(health.target, HealthTarget.backup);
    });

    test('active transfers beat waiting for Wi-Fi', () {
      final health = _top(
        backup: const BackupState(phase: BackupPhase.waitingForWifi, total: 300, done: 88),
        transfers: TransfersState([
          _transfer('a.zip', TransferStatus.running, total: 100, done: 40),
          _transfer('b.zip', TransferStatus.queued, total: 100),
          _transfer('c.zip', TransferStatus.failed),
        ]),
      );
      expect(health.text, '2 transfers in progress');
      expect(health.detail, '20% done');
      expect(health.progress, closeTo(0.2, 1e-9));
      expect(health.tone, HealthTone.busy);
      expect(health.target, HealthTarget.transfers);
    });

    test('backup uploads are not counted as transfers', () {
      final health = _top(
        transfers: TransfersState([
          _transfer('IMG_1.jpg', TransferStatus.running, origin: TransferOrigin.backup),
          _transfer('IMG_2.jpg', TransferStatus.failed, origin: TransferOrigin.backup),
        ]),
      );
      expect(health.text, 'Backed up and in sync');
    });

    test('waiting for Wi-Fi says how much is left and offers mobile data', () {
      final health = _top(
        backup: const BackupState(phase: BackupPhase.waitingForWifi, total: 300, done: 88),
      );
      expect(health.text, 'Waiting for Wi-Fi · 212 items left');
      expect(health.detail, 'Backup uses Wi-Fi only.');
      expect(health.tone, HealthTone.neutral);
      expect(health.action, HealthAction.useData);
    });

    test('stopped beats per-item failures, in red with Retry', () {
      final health = _top(
        backup: const BackupState(
          phase: BackupPhase.stopped,
          failed: 3,
          error: 'Telegram took too long to answer.',
        ),
      );
      expect(health.text, 'Backup stopped');
      expect(health.detail, 'Telegram took too long to answer.');
      expect(health.tone, HealthTone.bad);
      expect(health.action, HealthAction.retryBackup);
    });

    test('stopped is never reported as all good', () {
      for (final backup in const [
        BackupState(phase: BackupPhase.stopped),
        BackupState(phase: BackupPhase.stopped, total: 10, done: 10),
      ]) {
        final health = _top(backup: backup, lastFullSync: _now);
        expect(health.tone, isNot(HealthTone.good));
        expect(health.text, 'Backup stopped');
        expect(health.detail, isNotNull);
      }
    });

    test('per-item failures beat failed transfers', () {
      final health = _top(
        backup: const BackupState(phase: BackupPhase.upToDate, total: 10, done: 7, failed: 3),
        transfers: TransfersState([_transfer('a.zip', TransferStatus.failed)]),
      );
      expect(health.text, '3 items didn\'t back up');
      expect(health.detail, 'Skipped after three tries.');
      expect(health.tone, HealthTone.bad);
      expect(health.action, HealthAction.retryFailed);
    });

    test('failed transfers never take the main line', () {
      final failed = TransfersState([_transfer('a.zip', TransferStatus.failed)]);
      expect(_top(transfers: failed).text, 'Backed up and in sync');
      expect(_top(transfers: failed).tone, HealthTone.good);
      expect(_top(backup: _off, transfers: failed).text, 'Photo backup is off');
      expect(
        _top(backup: const BackupState(phase: BackupPhase.waitingForDrive), transfers: failed)
            .text,
        'Backup is starting',
      );
      expect(
        _top(sync: const SyncState(running: true), transfers: failed).text,
        'Checking with Telegram',
      );
    });

    test('a long Telegram wait is said, not taken for all good', () {
      final resumes = _now.add(const Duration(minutes: 40));
      final health = _top(
        backup: const BackupState(phase: BackupPhase.uploading, total: 20, done: 3),
        transfers: TransfersState([
          _transfer('a.zip', TransferStatus.queued, wait: WaitingForTelegram(resumes)),
        ]),
      );
      expect(health.text, 'Telegram asked us to wait');
      expect(
        health.detail,
        'Transfers carry on by themselves at ${Formatters.date(resumes, now: _now)}.',
      );
      expect(health.tone, HealthTone.neutral);
      expect(health.target, HealthTarget.transfers);
    });

    test('a long Telegram wait beats transfers in progress', () {
      final health = _top(
        backup: _off,
        transfers: TransfersState([
          _held('a.zip'),
          _transfer('b.zip', TransferStatus.running),
        ]),
      );
      expect(health.text, 'Telegram asked us to wait');
    });

    test('a backup that needs the person beats a long Telegram wait', () {
      final transfers = TransfersState([
        _held('a.zip'),
        _held('IMG_1.jpg', origin: TransferOrigin.backup),
      ]);
      expect(
        _top(backup: const BackupState(phase: BackupPhase.stopped), transfers: transfers).text,
        'Backup stopped',
      );
      expect(
        _top(backup: const BackupState(phase: BackupPhase.needsPermission), transfers: transfers)
            .text,
        'Backup can\'t see your photos',
      );
      expect(
        _top(
          backup: const BackupState(phase: BackupPhase.waitingForWifi),
          transfers: transfers,
        ).text,
        'Waiting for Wi-Fi',
      );
    });

    test('a short Telegram wait still counts as in progress', () {
      final health = _top(
        backup: _off,
        transfers: TransfersState([
          _transfer(
            'a.zip',
            TransferStatus.queued,
            wait: WaitingForTelegram(_now.add(const Duration(seconds: 72))),
          ),
        ]),
      );
      expect(health.text, '1 transfer in progress');
    });

    test('a paused transfer is never held by a wait', () {
      final health = _top(
        backup: _off,
        transfers: TransfersState([
          _transfer(
            'a.zip',
            TransferStatus.paused,
            wait: WaitingForTelegram(_now.add(const Duration(minutes: 40))),
          ),
        ]),
      );
      expect(health.text, isNot('Telegram asked us to wait'));
    });

    test('not reaching Telegram beats everything else', () {
      final error = SyncState(error: 'No connection', lastSynced: _now);
      for (final backup in const [
        BackupState(phase: BackupPhase.uploading, total: 20, done: 3),
        BackupState(phase: BackupPhase.stopped),
        BackupState(phase: BackupPhase.upToDate, total: 10, done: 7, failed: 3),
        _off,
      ]) {
        final health = _top(
          backup: backup,
          sync: error,
          transfers: TransfersState([_transfer('a.zip', TransferStatus.failed)]),
        );
        expect(health.text, 'Can\'t reach Telegram');
        expect(health.tone, HealthTone.neutral);
        expect(health.target, HealthTarget.refresh);
      }
    });

    test('not reaching Telegram stays while another try runs', () {
      final retrying = _top(
        sync: SyncState(error: 'No connection', running: true, lastSynced: _now),
      );
      expect(retrying.text, 'Can\'t reach Telegram');
      expect(retrying.progress, lessThan(0));
      expect(retrying.tone, HealthTone.neutral);
      expect(_top(sync: SyncState(error: 'No connection', lastSynced: _now)).progress, isNull);
    });

    test('not reaching Telegram says what the drive shows', () {
      final earlier = DateTime(2026, 9, 27, 7, 5);
      expect(
        _top(sync: SyncState(error: 'No connection', lastSynced: earlier)).detail,
        'Showing what was synced at ${Formatters.date(earlier, now: _now)}. '
        'Pull down to try again.',
      );
      final yesterday = DateTime(2026, 9, 26, 22);
      expect(
        _top(sync: const SyncState(error: 'No connection'), lastFullSync: yesterday).detail,
        'Showing what was synced on ${Formatters.date(yesterday, now: _now)}. '
        'Pull down to try again.',
      );
      expect(
        _top(sync: const SyncState(error: 'No connection')).detail,
        'Pull down to try again.',
      );
    });

    test('off beats all good', () {
      final health = _top(backup: _off);
      expect(health.text, 'Photo backup is off');
      expect(health.tone, HealthTone.neutral);
      expect(health.action, HealthAction.turnOn);
    });

    test('all good says when it was checked, from the latest time known', () {
      final synced = DateTime(2026, 9, 27, 19, 30);
      final completed = DateTime(2026, 9, 27, 18);
      final fullSync = DateTime(2026, 9, 27, 9);
      final health = _top(
        sync: SyncState(lastSynced: synced),
        backup: BackupState(phase: BackupPhase.upToDate, lastCompleted: completed),
        lastFullSync: fullSync,
      );
      expect(health.text, 'Backed up and in sync');
      expect(health.icon, Icons.check_circle_outline_rounded);
      expect(health.tone, HealthTone.good);
      expect(health.progress, isNull);
      expect(health.detail, 'checked ${Formatters.date(synced, now: _now)}');

      // After a cold start the sync time is gone; the backup's and the last
      // full read's stand in, and with none known nothing is invented.
      expect(
        _top(
          sync: const SyncState(),
          backup: BackupState(phase: BackupPhase.upToDate, lastCompleted: completed),
          lastFullSync: fullSync,
        ).detail,
        'checked ${Formatters.date(completed, now: _now)}',
      );
      expect(
        _top(sync: const SyncState(), lastFullSync: fullSync).detail,
        'checked ${Formatters.date(fullSync, now: _now)}',
      );
      expect(_top(sync: const SyncState()).detail, isNull);
    });

    test('checking with Telegram only while the first sync of a launch runs', () {
      final cold = _top(
        sync: const SyncState(running: true),
        lastFullSync: DateTime(2026, 9, 27, 9),
      );
      expect(cold.text, 'Checking with Telegram');
      expect(cold.progress, lessThan(0));
      expect(cold.tone, HealthTone.neutral);

      expect(
        _top(sync: SyncState(running: true, lastSynced: _now)).text,
        'Backed up and in sync',
      );
      expect(_top(sync: const SyncState()).text, 'Backed up and in sync');
    });

    test('without a network, transfers say they wait, with a grey bar', () {
      final health = _top(
        backup: _off,
        transfers: TransfersState([
          _offline('a.zip', total: 100, done: 50),
          _offline('b.zip', total: 100, done: 30),
        ]),
      );
      expect(health.text, 'Waiting for network');
      expect(health.detail, 'Carries on when you\'re back online · 40%');
      expect(health.icon, Icons.cloud_off_rounded);
      expect(health.tone, HealthTone.neutral);
      expect(health.progress, closeTo(0.4, 1e-9));
      expect(health.waiting, isTrue);
      expect(health.target, HealthTarget.transfers);
    });

    test('one transfer still moving keeps the line in progress', () {
      final health = _top(
        backup: _off,
        transfers: TransfersState([
          _offline('a.zip'),
          _transfer('b.zip', TransferStatus.running),
        ]),
      );
      expect(health.text, '2 transfers in progress');
      expect(health.waiting, isFalse);
    });

    test('without a network beats backing up and a Telegram wait', () {
      final health = _top(
        backup: const BackupState(phase: BackupPhase.uploading, total: 20, done: 5),
        transfers: TransfersState([
          _offline('IMG_1.jpg', origin: TransferOrigin.backup),
          _held('a.zip'),
        ]),
      );
      expect(health.text, 'Waiting for network');
      // Backup is all that moves, so it says so in backup's words.
      expect(health.detail, 'Backup carries on when you\'re back online.');
      expect(health.progress, closeTo(0.25, 1e-9));
      expect(health.target, HealthTarget.backup);
    });

    test('transfers without a network say so over a stopped backup, which keeps its row', () {
      final health = _top(
        backup: const BackupState(phase: BackupPhase.stopped),
        transfers: TransfersState([_offline('a.zip')]),
      );
      expect(health.text, 'Waiting for network');
      expect(
        secondaryHealth(
          health,
          backup: const BackupState(phase: BackupPhase.stopped),
          transfers: TransfersState([_offline('a.zip')]),
          now: _now,
        )?.text,
        'Backup stopped',
      );
    });

    test('transfers waiting for Wi-Fi say so when nothing moves, and offer data', () {
      final health = _top(
        backup: _off,
        transfers: TransfersState([
          _onWifi('a.zip', total: _gb),
          _onWifi('b.zip', total: _gb),
        ]),
      );
      expect(health.text, 'Waiting for Wi-Fi · 2 transfers');
      expect(health.detail, '2.0 GB. They start on their own on Wi\u2011Fi.');
      expect(health.icon, Icons.wifi_off_rounded);
      expect(health.tone, HealthTone.neutral);
      expect(health.action, HealthAction.useDataForTransfers);
      expect(health.target, HealthTarget.transfers);

      expect(
        _top(backup: _off, transfers: TransfersState([_onWifi('a.zip', total: _gb)])).detail,
        '1.0 GB. It starts on its own on Wi\u2011Fi.',
      );
    });

    test('transfers waiting for Wi-Fi never read as all good', () {
      expect(
        _top(transfers: TransfersState([_onWifi('a.zip')])).text,
        'Waiting for Wi-Fi · 1 transfer',
      );
    });

    test('backup uploads waiting for Wi-Fi are left to backup\'s own line', () {
      final transfers = TransfersState([_onWifi('IMG_1.jpg', origin: TransferOrigin.backup)]);
      const backup = BackupState(phase: BackupPhase.waitingForWifi, total: 300, done: 88);
      final health = _top(backup: backup, transfers: transfers);
      expect(health.text, 'Waiting for Wi-Fi · 212 items left');
      expect(health.action, HealthAction.useData);
      expect(
        secondaryHealth(health, backup: backup, transfers: transfers, now: _now),
        isNull,
      );
    });

    test('backup waiting for the drive says it is starting', () {
      final health = _top(backup: const BackupState(phase: BackupPhase.waitingForDrive));
      expect(health.text, 'Backup is starting');
      expect(health.tone, HealthTone.neutral);
    });
  });

  group('secondaryHealth', () {
    DriveHealth? second(BackupState backup, TransfersState transfers, {SyncState? sync}) =>
        secondaryHealth(
          _top(backup: backup, transfers: transfers, sync: sync),
          backup: backup,
          transfers: transfers,
          now: _now,
        );

    final paused = TransfersState([_transfer('a.zip', TransferStatus.paused)]);

    test('shows paused transfers under a backup line, with Resume', () {
      final row = second(const BackupState(phase: BackupPhase.stopped), paused);
      expect(row?.text, '1 transfer paused');
      expect(row?.detail, isNull);
      expect(row?.action, HealthAction.resumeTransfers);
      expect(row?.target, HealthTarget.transfers);

      expect(second(_upToDate, paused)?.text, '1 transfer paused');
    });

    test('is null when the top line already is that concern', () {
      expect(second(const BackupState(phase: BackupPhase.stopped), TransfersState.empty), isNull);
      expect(second(_upToDate, TransfersState.empty), isNull);
    });

    test('a failed transfer sits under all good, and retries in place', () {
      final failed = TransfersState([
        _transfer('a.zip', TransferStatus.failed, error: 'Not enough space on this phone.'),
        _transfer('IMG_1.jpg', TransferStatus.failed, origin: TransferOrigin.backup),
      ]);
      expect(_top(transfers: failed).text, 'Backed up and in sync');
      final row = second(_upToDate, failed);
      expect(row?.text, '1 transfer failed');
      expect(row?.detail, 'Not enough space on this phone.');
      expect(row?.tone, HealthTone.bad);
      expect(row?.action, HealthAction.retryTransfers);
      expect(row?.target, HealthTarget.transfers);
    });

    test('several failed transfers say where to read why', () {
      final failed = TransfersState([
        _transfer('a.zip', TransferStatus.failed, error: 'Not enough space on this phone.'),
        _transfer('b.zip', TransferStatus.failed),
      ]);
      final row = second(_off, failed);
      expect(_top(backup: _off, transfers: failed).text, 'Photo backup is off');
      expect(row?.text, '2 transfers failed');
      expect(row?.detail, 'Open Transfers to see why.');
      expect(row?.action, HealthAction.retryTransfers);
    });

    test('shows failed transfers under transfers in progress', () {
      final busy = TransfersState([
        _transfer('a.zip', TransferStatus.running),
        _transfer('b.zip', TransferStatus.failed),
      ]);
      expect(_top(backup: _off, transfers: busy).text, '1 transfer in progress');
      final row = second(_off, busy);
      expect(row?.text, '1 transfer failed');
      expect(row?.tone, HealthTone.bad);
      expect(row?.action, HealthAction.retryTransfers);
      expect(row?.target, HealthTarget.transfers);

      // A stopped backup still comes first, with its Retry.
      expect(second(const BackupState(phase: BackupPhase.stopped), busy)?.text, 'Backup stopped');
    });

    test('failed and paused transfers keep their row under a Telegram wait', () {
      final failed = TransfersState([
        _held('a.zip'),
        _transfer('b.zip', TransferStatus.failed),
        _transfer('c.zip', TransferStatus.failed),
      ]);
      expect(_top(backup: _upToDate, transfers: failed).text, 'Telegram asked us to wait');
      final row = second(_upToDate, failed);
      expect(row?.text, '2 transfers failed');
      expect(row?.action, HealthAction.retryTransfers);

      final paused = TransfersState([
        _held('a.zip'),
        _transfer('b.zip', TransferStatus.paused),
      ]);
      expect(second(_upToDate, paused)?.action, HealthAction.resumeTransfers);
    });

    test('never repeats the top line, and never shows progress', () {
      final busy = TransfersState([
        _transfer('a.zip', TransferStatus.running),
        _transfer('b.zip', TransferStatus.failed),
      ]);
      final states = [
        for (final phase in BackupPhase.values)
          BackupState(phase: phase, total: 10, done: 5, failed: phase == BackupPhase.off ? 0 : 2),
      ];
      final transferMixes = [
        TransfersState.empty,
        paused,
        busy,
        TransfersState([_transfer('a.zip', TransferStatus.failed), ...paused.items]),
        TransfersState([_held('w.zip'), ...busy.items, ...paused.items]),
        TransfersState([_onWifi('h.zip'), ...busy.items]),
        TransfersState([_onWifi('h.zip'), _offline('o.zip'), ...paused.items]),
        TransfersState([_offline('o.zip'), _transfer('f.zip', TransferStatus.failed)]),
      ];
      final syncs = [_synced, const SyncState(error: 'No connection'), const SyncState(running: true)];
      for (final backup in states) {
        for (final transfers in transferMixes) {
          for (final sync in syncs) {
            final top = _top(backup: backup, transfers: transfers, sync: sync);
            final row = secondaryHealth(top, backup: backup, transfers: transfers, now: _now);
            if (row == null) continue;
            expect(row.text, isNot(top.text));
            // The two buttons never do the same job, and only the top row
            // can be accent-coloured.
            expect(
              row.action == HealthAction.none || row.action != top.action,
              isTrue,
            );
            expect(row.tone, isNot(HealthTone.busy));
            expect(row.progress, isNull);
          }
        }
      }
    });

    test('transfers waiting for Wi-Fi sit under work in progress', () {
      final mixed = TransfersState([
        _transfer('a.zip', TransferStatus.running),
        _onWifi('b.zip', total: _gb),
      ]);
      expect(_top(backup: _off, transfers: mixed).text, '1 transfer in progress');
      final row = second(_off, mixed);
      expect(row?.text, 'Waiting for Wi-Fi · 1 transfer');
      expect(row?.action, HealthAction.useDataForTransfers);

      const uploading = BackupState(phase: BackupPhase.uploading, total: 10, done: 2);
      final waiting = TransfersState([_onWifi('b.zip')]);
      expect(_top(backup: uploading, transfers: waiting).text, 'Backing up · 8 left');
      expect(second(uploading, waiting)?.action, HealthAction.useDataForTransfers);
    });

    test('failed transfers keep their row under transfers waiting for Wi-Fi', () {
      final mixed = TransfersState([
        _onWifi('a.zip'),
        _transfer('b.zip', TransferStatus.failed),
      ]);
      expect(_top(transfers: mixed).text, 'Waiting for Wi-Fi · 1 transfer');
      expect(second(_upToDate, mixed)?.action, HealthAction.retryTransfers);
    });

    test('backup waiting for Wi-Fi and transfers waiting for it each keep their button', () {
      const backup = BackupState(phase: BackupPhase.waitingForWifi, total: 300, done: 88);
      final transfers = TransfersState([_onWifi('a.zip')]);
      expect(_top(backup: backup, transfers: transfers).action, HealthAction.useDataForTransfers);
      expect(second(backup, transfers)?.action, HealthAction.useData);
    });

    test('paused transfers wait while others are running', () {
      final mixed = TransfersState([
        _transfer('a.zip', TransferStatus.running),
        _transfer('b.zip', TransferStatus.paused),
      ]);
      const backup = BackupState(phase: BackupPhase.uploading, total: 10, done: 2);
      expect(second(backup, mixed), isNull);
    });

    test('a backup concern sits under a sync line', () {
      final row = second(
        const BackupState(phase: BackupPhase.stopped, error: 'Out of space.'),
        TransfersState.empty,
        sync: const SyncState(error: 'No connection'),
      );
      expect(row?.text, 'Backup stopped');
      expect(row?.action, HealthAction.retryBackup);
    });
  });
}
