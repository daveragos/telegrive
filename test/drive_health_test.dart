import 'package:flutter/material.dart' show Icons;
import 'package:flutter_test/flutter_test.dart';
import 'package:telegrive/core/format/formatters.dart';
import 'package:telegrive/features/backup/data/background_health.dart';
import 'package:telegrive/features/backup/data/backup_controller.dart';
import 'package:telegrive/features/drive/data/drive_sync.dart';
import 'package:telegrive/features/drive/data/edit_outbox.dart';
import 'package:telegrive/features/drive/data/forward_filer.dart';
import 'package:telegrive/features/home/presentation/drive_health.dart';
import 'package:telegrive/features/network/data/connection_health.dart';
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
const _mb = 1 << 20;

/// A transfer queued until the phone has [needed] bytes free; it has 180 MB.
TransferItem _needsRoom(String name, int needed, {TransferOrigin origin = TransferOrigin.manual}) =>
    _transfer(
      name,
      TransferStatus.queued,
      origin: origin,
      wait: WaitingForRoom(needed, 180 * _mb),
    );

DriveHealth _top({
  BackupState backup = _upToDate,
  SyncState? sync,
  TransfersState transfers = TransfersState.empty,
  DateTime? lastFullSync,
  double backupSpeed = 0,
  int renewDay = 1,
  ConnectionHealth connection = ConnectionHealth.ok,
  String? proxy,
  DriveOpening opening = DriveOpening.open,
  String? openingError,
}) => describeDriveHealth(
  backup: backup,
  sync: sync ?? _synced,
  transfers: transfers,
  lastFullSync: lastFullSync,
  backupSpeed: backupSpeed,
  renewDay: renewDay,
  connection: connection,
  proxy: proxy,
  opening: opening,
  openingError: openingError,
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

    test('copies from chats on their own are counted by file', () {
      TransferItem copy(String name, TransferStatus status) =>
          _transfer(name, status, origin: TransferOrigin.fromChat);
      final health = _top(
        transfers: TransfersState([
          copy('Scan 1.pdf', TransferStatus.completed),
          copy('Scan 2.pdf', TransferStatus.running),
          copy('Scan 3.pdf', TransferStatus.queued),
          copy('Scan 4.pdf', TransferStatus.cancelled),
        ]),
      );
      expect(health.text, '2 transfers in progress');
      expect(health.detail, '1 of 3 saved');
      expect(health.progress, closeTo(1 / 3, 1e-9));
    });

    test('next to an upload, copies leave the share to its bytes', () {
      final health = _top(
        transfers: TransfersState([
          _transfer('a.zip', TransferStatus.running, total: 100, done: 40),
          _transfer(
            'Scan 1.pdf',
            TransferStatus.queued,
            origin: TransferOrigin.fromChat,
            total: 1000,
          ),
        ]),
      );
      expect(health.text, '2 transfers in progress');
      expect(health.detail, '40% done');
      expect(health.progress, closeTo(0.4, 1e-9));
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

    test('videos held for Wi-Fi say the photos are done, and offer mobile data', () {
      final health = _top(
        backup: const BackupState(
          phase: BackupPhase.waitingForWifi,
          total: 300,
          done: 262,
          heldVideos: 38,
        ),
      );
      expect(health.text, 'Videos wait for Wi-Fi');
      expect(health.detail, '38 videos left. Photos are backed up.');
      expect(health.action, HealthAction.useData);
    });

    test('small copies going up count only the photos with nothing in the drive yet', () {
      final health = _top(
        backup: const BackupState(
          phase: BackupPhase.uploading,
          total: 4530,
          done: 3080,
          smallCopies: 1410,
          sendingSmallCopies: true,
        ),
        backupSpeed: 1.1 * 1024 * 1024,
      );
      expect(health.text, 'Backing up small copies · 40 left');
      expect(health.detail, '1.1 MB/s');
      expect(health.tone, HealthTone.busy);
    });

    test('originals behind small copies wait for Wi-Fi, and offer mobile data', () {
      final health = _top(
        backup: const BackupState(
          phase: BackupPhase.waitingForWifi,
          total: 4530,
          done: 3120,
          smallCopies: 1410,
        ),
      );
      expect(health.text, 'Originals wait for Wi-Fi');
      expect(health.detail, '1,410 still to send. Small copies are already safe.');
      expect(health.icon, Icons.cloud_done_outlined);
      expect(health.tone, HealthTone.neutral);
      expect(health.action, HealthAction.useData);
    });

    test('the monthly data limit says when backup carries on, and offers to go past it', () {
      final health = _top(
        backup: const BackupState(
          phase: BackupPhase.waitingForBudget,
          total: 4530,
          done: 4320,
          heldForBudget: 3,
        ),
        renewDay: 3,
      );
      expect(health.text, 'Monthly data limit reached');
      expect(health.detail, '210 items left. Backup carries on over Wi-Fi, or on the 3rd.');
      expect(health.icon, Icons.data_usage_rounded);
      expect(health.tone, HealthTone.neutral);
      expect(health.action, HealthAction.useDataAnyway);
      expect(health.target, HealthTarget.backup);
    });

    test('the monthly data limit beats a long Telegram wait and transfers waiting for Wi-Fi', () {
      const backup = BackupState(phase: BackupPhase.waitingForBudget, total: 10, done: 4);
      final transfers = TransfersState([_held('a.zip'), _onWifi('b.zip')]);
      final health = _top(backup: backup, transfers: transfers);
      expect(health.text, 'Monthly data limit reached');
      expect(
        secondaryHealth(health, backup: backup, transfers: transfers, now: _now)?.action,
        HealthAction.useDataForTransfers,
      );
      expect(
        _top(backup: const BackupState(phase: BackupPhase.stopped), transfers: transfers).text,
        'Backup stopped',
      );
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
      expect(health.detail, 'See which ones and why.');
      expect(health.tone, HealthTone.bad);
      expect(health.action, HealthAction.retryFailed);
      expect(health.target, HealthTarget.notBackedUp);
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

    test('a backup pass paused for a Telegram wait says so, not that it is moving', () {
      final resumes = _now.add(const Duration(minutes: 40));
      final health = _top(
        backup: BackupState(phase: BackupPhase.uploading, total: 20, done: 3, pausedUntil: resumes),
      );
      expect(health.text, 'Telegram asked us to wait');
      expect(health.tone, HealthTone.neutral);
      expect(health.progress, isNull);
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

    test('a phone too full for a transfer says so, offers to free up space, and opens '
        'Transfers', () {
      final health = _top(
        backup: const BackupState(phase: BackupPhase.uploading, total: 10, done: 2),
        transfers: TransfersState([
          _needsRoom('movie.mp4', (1.2 * _gb).round()),
          _needsRoom('IMG_0001.mov', 400 * _mb, origin: TransferOrigin.backup),
          _transfer('a.zip', TransferStatus.running),
          _held('b.zip'),
        ]),
      );
      expect(health.text, 'This phone is nearly full');
      expect(health.detail, '2 transfers are waiting for 1.2 GB of room.');
      expect(health.icon, Icons.sd_card_alert_outlined);
      expect(health.tone, HealthTone.neutral);
      expect(health.action, HealthAction.freeUpSpace);
      expect(health.target, HealthTarget.transfers);
    });

    test('one transfer waiting for room is said in the singular', () {
      final health = _top(transfers: TransfersState([_needsRoom('movie.mp4', 300 * _mb)]));
      expect(health.detail, '1 transfer is waiting for 300 MB of room.');
    });

    test('a stopped backup keeps the line from a full phone', () {
      final transfers = TransfersState([_needsRoom('movie.mp4', 300 * _mb)]);
      const stopped = BackupState(phase: BackupPhase.stopped, error: 'Out of space.');
      expect(_top(backup: stopped, transfers: transfers).text, 'Backup stopped');
      expect(_top(transfers: transfers).text, 'This phone is nearly full');
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

    test('a connection stuck on this network beats even a failed sync, and offers a proxy', () {
      for (final backup in const [
        BackupState(phase: BackupPhase.uploading, total: 20, done: 3),
        BackupState(phase: BackupPhase.stopped),
        _off,
      ]) {
        final health = _top(
          backup: backup,
          sync: SyncState(error: 'No connection', lastSynced: _now),
          transfers: TransfersState([_needsRoom('a.zip', _gb)]),
          connection: ConnectionHealth.stuck,
        );
        expect(health.text, 'Telegram isn\'t reachable on this network');
        expect(health.detail, 'Still trying. A proxy often helps where Telegram is blocked.');
        expect(health.icon, Icons.cloud_off_rounded);
        expect(health.tone, HealthTone.neutral);
        expect(health.progress, isNull);
        expect(health.action, HealthAction.useProxy);
        expect(health.target, HealthTarget.proxy);
        expect(health.topic, HealthTopic.sync);
      }
    });

    test('a proxy that isn\'t answering is named, with Change proxy', () {
      final health = _top(connection: ConnectionHealth.proxyStuck, proxy: '1.2.3.4:443');
      expect(health.text, 'Can\'t reach the proxy');
      expect(health.detail, '1.2.3.4:443 isn\'t answering.');
      expect(health.action, HealthAction.changeProxy);
      expect(health.target, HealthTarget.proxy);
      expect(
        _top(connection: ConnectionHealth.proxyStuck).detail,
        'The proxy isn\'t answering.',
      );
    });

    test('a connection that is fine, or has no network, leaves the line to the rest', () {
      expect(_top(connection: ConnectionHealth.ok).text, 'Backed up and in sync');
      expect(_top(connection: ConnectionHealth.noNetwork).text, 'Backed up and in sync');
      expect(describeConnection(ConnectionHealth.ok), isNull);
      expect(describeConnection(ConnectionHealth.noNetwork), isNull);
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

    group('while the drive opens behind Home', () {
      const busy = [
        BackupState(phase: BackupPhase.waitingForDrive),
        BackupState(phase: BackupPhase.uploading, total: 20, done: 3),
        BackupState(phase: BackupPhase.stopped),
        _off,
      ];

      test('connecting beats everything else, in the accent with a moving bar', () {
        for (final backup in busy) {
          final health = _top(
            backup: backup,
            sync: SyncState(error: 'No connection', lastSynced: _now),
            transfers: TransfersState([
              _transfer('a.zip', TransferStatus.queued),
              _needsRoom('b.zip', _gb),
            ]),
            opening: DriveOpening.connecting,
          );
          expect(health.text, 'Connecting to Telegram');
          expect(health.detail, 'Your files are here. Changes wait until it connects.');
          expect(health.icon, Icons.cloud_sync_outlined);
          expect(health.tone, HealthTone.busy);
          expect(health.progress, lessThan(0));
          expect(health.action, HealthAction.none);
          expect(health.target, HealthTarget.none);
          expect(health.topic, HealthTopic.sync);
        }
      });

      test('a failed try at finding the drive says why, in red with Retry', () {
        final health = _top(
          backup: busy.first,
          opening: DriveOpening.failed,
          openingError: 'Telegram took too long to answer.',
        );
        expect(health.text, 'Couldn\'t reach Telegram');
        expect(health.detail, 'Telegram took too long to answer.');
        expect(health.icon, Icons.cloud_off_outlined);
        expect(health.tone, HealthTone.bad);
        expect(health.progress, isNull);
        expect(health.action, HealthAction.retryOpening);
        expect(health.target, HealthTarget.none);
      });

      test('TDLib that didn\'t start says so, in red with Try again', () {
        final health = _top(
          opening: DriveOpening.notStarted,
          openingError: 'Could not start Telegram: no library',
        );
        expect(health.text, 'Telegram didn\'t start');
        expect(health.detail, 'Could not start Telegram: no library');
        expect(health.icon, Icons.error_outline_rounded);
        expect(health.tone, HealthTone.bad);
        expect(health.action, HealthAction.restartTelegram);
      });

      test('a connection stuck on its network offers a proxy instead', () {
        for (final opening in const [DriveOpening.connecting, DriveOpening.failed]) {
          final health = _top(
            opening: opening,
            openingError: 'Telegram took too long to answer.',
            connection: ConnectionHealth.stuck,
          );
          expect(health.text, 'Telegram isn\'t reachable on this network');
          expect(health.action, HealthAction.useProxy);
        }
        // Without TDLib there is no connection for a proxy to help.
        expect(
          _top(opening: DriveOpening.notStarted, connection: ConnectionHealth.stuck).text,
          'Telegram didn\'t start',
        );
      });

      test('no network at all still says it is connecting', () {
        expect(
          _top(opening: DriveOpening.connecting, connection: ConnectionHealth.noNetwork).text,
          'Connecting to Telegram',
        );
      });

      test('an open drive leaves the line to the rest', () {
        expect(_top().text, 'Backed up and in sync');
      });

      test('the second row keeps to other concerns, such as a failed transfer', () {
        final transfers = TransfersState([
          _transfer('a.zip', TransferStatus.failed, error: 'The original file is no longer available.'),
        ]);
        final top = _top(transfers: transfers, opening: DriveOpening.connecting);
        final second = secondaryHealth(
          top,
          backup: _upToDate,
          transfers: transfers,
          now: _now,
        );
        expect(second?.text, '1 transfer failed');
      });
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

    test('forwards filed by their comment are reported, with Dismiss', () {
      DriveHealth? filed(FilingSummary summary, {BackupState backup = _upToDate}) =>
          secondaryHealth(
            _top(backup: backup, transfers: TransfersState.empty),
            backup: backup,
            transfers: TransfersState.empty,
            filed: summary,
            now: _now,
          );

      final one = filed(
        const FilingSummary(count: 12, folderNames: ['Wedding'], folderId: 'w'),
      );
      expect(one?.text, 'Filed 12 forwarded files into Wedding');
      expect(one?.detail, 'From your comment in Telegram.');
      expect(one?.icon, Icons.drive_file_move_outline);
      expect(one?.tone, HealthTone.good);
      expect(one?.action, HealthAction.dismissFiling);
      expect(one?.target, HealthTarget.filed);

      final several = filed(
        const FilingSummary(count: 1, folderNames: ['Wedding', 'Taxes', 'Work']),
      );
      expect(several?.text, 'Filed 1 forwarded file into 3 folders');

      // Under Photo backup is off as well, since it is about something else.
      expect(
        filed(const FilingSummary(count: 2, folderNames: ['Wedding']), backup: _off)?.text,
        'Filed 2 forwarded files into Wedding',
      );
      expect(filed(const FilingSummary(count: 0, folderNames: [])), isNull);
    });

    group('changes waiting to reach Telegram', () {
      DriveHealth? changes(
        OutboxState outbox, {
        TransfersState transfers = TransfersState.empty,
        FilingSummary? filed,
      }) => secondaryHealth(
        _top(backup: _upToDate, transfers: transfers),
        backup: _upToDate,
        transfers: transfers,
        changes: outbox,
        filed: filed,
        now: _now,
      );

      test('say how many wait for the network, and open Waiting changes', () {
        final row = changes(const OutboxState(waiting: 3));
        expect(row?.text, '3 changes waiting for the network');
        expect(row?.detail, 'They reach Telegram when you\'re back online.');
        expect(row?.icon, Icons.schedule_rounded);
        expect(row?.tone, HealthTone.neutral);
        expect(row?.progress, isNull);
        expect(row?.action, HealthAction.none);
        expect(row?.target, HealthTarget.changes);
        expect(changes(const OutboxState(waiting: 1))?.detail, 'It reaches Telegram when you\'re back online.');
      });

      test('are gone once nothing waits', () {
        expect(changes(const OutboxState()), isNull);
      });

      test('show a bar while they go', () {
        final row = changes(const OutboxState(waiting: 2, sending: true));
        expect(row?.text, 'Sending 2 changes to Telegram');
        expect(row?.progress, -1);
        expect(row?.tone, HealthTone.neutral);
      });

      test('say roughly when they go after a pause Telegram asked for', () {
        final row = changes(
          OutboxState(waiting: 3, sending: true, pausedUntil: _now.add(const Duration(minutes: 4))),
        );
        expect(row?.text, 'Telegram asked to wait');
        expect(row?.detail, 'Your 3 changes go in about 4 minutes.');
        // A pause that is over says they wait again.
        expect(
          changes(OutboxState(waiting: 1, pausedUntil: _now.subtract(const Duration(seconds: 1))))?.text,
          '1 change waiting for the network',
        );
      });

      test('say in red how many couldn\'t be sent', () {
        final row = changes(const OutboxState(waiting: 3, failed: 2, sending: true));
        expect(row?.text, '2 changes couldn\'t be sent');
        expect(row?.detail, 'Open to see why.');
        expect(row?.tone, HealthTone.bad);
        expect(row?.target, HealthTarget.changes);
      });

      test('come after failed transfers and before the filing report', () {
        final failed = TransfersState([_transfer('a.zip', TransferStatus.failed)]);
        expect(changes(const OutboxState(waiting: 3), transfers: failed)?.text, '1 transfer failed');
        expect(
          changes(
            const OutboxState(waiting: 3),
            filed: const FilingSummary(count: 3, folderNames: ['Wedding']),
          )?.text,
          '3 changes waiting for the network',
        );
      });

      test('sit under the line about connecting to Telegram', () {
        final top = describeDriveHealth(
          backup: const BackupState(phase: BackupPhase.waitingForDrive),
          sync: const SyncState(),
          transfers: TransfersState.empty,
          opening: DriveOpening.connecting,
          now: _now,
        );
        expect(top.text, 'Connecting to Telegram');
        final row = secondaryHealth(
          top,
          backup: const BackupState(phase: BackupPhase.waitingForDrive),
          transfers: TransfersState.empty,
          changes: const OutboxState(waiting: 2),
          now: _now,
        );
        expect(row?.text, '2 changes waiting for the network');
      });
    });

    test('a failed transfer comes before the filing report', () {
      final failed = TransfersState([_transfer('a.zip', TransferStatus.failed)]);
      final row = secondaryHealth(
        _top(backup: _upToDate, transfers: failed),
        backup: _upToDate,
        transfers: failed,
        filed: const FilingSummary(count: 3, folderNames: ['Wedding']),
        now: _now,
      );
      expect(row?.text, '1 transfer failed');
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

    test('a full phone sits under a stopped backup, with Free up space', () {
      final row = second(
        const BackupState(phase: BackupPhase.stopped),
        TransfersState([
          _needsRoom('movie.mp4', 300 * _mb),
          _transfer('b.zip', TransferStatus.failed),
        ]),
      );
      expect(row?.text, 'This phone is nearly full');
      expect(row?.action, HealthAction.freeUpSpace);
    });

    test('a full phone on the top line leaves the row to failed transfers', () {
      final row = second(
        _upToDate,
        TransfersState([
          _needsRoom('movie.mp4', 300 * _mb),
          _transfer('b.zip', TransferStatus.failed),
        ]),
      );
      expect(row?.action, HealthAction.retryTransfers);
    });

    test('a backup concern sits under a stuck connection', () {
      const backup = BackupState(phase: BackupPhase.stopped, error: 'Out of space.');
      final row = secondaryHealth(
        _top(backup: backup, connection: ConnectionHealth.stuck),
        backup: backup,
        transfers: TransfersState.empty,
        now: _now,
      );
      expect(row?.text, 'Backup stopped');
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

    group('Free up', () {
      DriveHealth? lowSpace(
        BackupState backup,
        TransfersState transfers, {
        bool low = true,
        int bytes = 9 * _gb,
      }) => secondaryHealth(
        _top(backup: backup, transfers: transfers),
        backup: backup,
        transfers: transfers,
        lowOnSpace: low,
        freeableBytes: bytes,
        now: _now,
      );

      test('sits under all good when the phone is low on space', () {
        final row = lowSpace(_upToDate, TransfersState.empty);
        expect(row?.text, '9.0 GB of backed-up photos can leave this phone');
        expect(row?.detail, 'This phone is running low on space.');
        expect(row?.icon, Icons.phonelink_erase_outlined);
        expect(row?.tone, HealthTone.neutral);
        expect(row?.action, HealthAction.freeUp);
        expect(row?.target, HealthTarget.backup);
        expect(row?.topic, HealthTopic.storage);
      });

      test('needs a phone low on space and more than 500 MB to free', () {
        expect(freeUpWorthwhile, 500 * _mb);
        expect(lowSpace(_upToDate, TransfersState.empty, low: false), isNull);
        expect(lowSpace(_upToDate, TransfersState.empty, bytes: freeUpWorthwhile), isNull);
        expect(
          lowSpace(_upToDate, TransfersState.empty, bytes: freeUpWorthwhile + 1)?.action,
          HealthAction.freeUp,
        );
      });

      test('comes after every other concern', () {
        final failed = TransfersState([_transfer('a.zip', TransferStatus.failed)]);
        expect(lowSpace(_upToDate, failed)?.action, HealthAction.retryTransfers);
        final paused = TransfersState([_transfer('a.zip', TransferStatus.paused)]);
        expect(lowSpace(_upToDate, paused)?.action, HealthAction.resumeTransfers);
        // Backup off sits under a line about transfers; with nothing else
        // going on it is the top line, and Free up takes the second.
        final busy = TransfersState([_transfer('a.zip', TransferStatus.running)]);
        expect(lowSpace(_off, busy)?.action, HealthAction.turnOn);
        expect(lowSpace(_off, TransfersState.empty)?.action, HealthAction.freeUp);
        // A backup that stopped while Telegram can't be reached keeps the row.
        const stopped = BackupState(phase: BackupPhase.stopped);
        final row = secondaryHealth(
          _top(backup: stopped, sync: const SyncState(error: 'No connection')),
          backup: stopped,
          transfers: TransfersState.empty,
          lowOnSpace: true,
          freeableBytes: 9 * _gb,
          now: _now,
        );
        expect(row?.action, HealthAction.retryBackup);
      });

      test('stays away while a transfer waits for room, which offers its own', () {
        final waiting = TransfersState([_needsRoom('movie.mp4', 300 * _mb)]);
        expect(_top(transfers: waiting).action, HealthAction.freeUpSpace);
        expect(lowSpace(_upToDate, waiting), isNull);
        const stopped = BackupState(phase: BackupPhase.stopped);
        expect(lowSpace(stopped, waiting)?.action, HealthAction.freeUpSpace);
      });
    });

    group('backup with the app closed', () {
      DriveHealth? closed(BackupState backup, {TransfersState transfers = TransfersState.empty}) =>
          secondaryHealth(
            _top(backup: backup, transfers: transfers),
            backup: backup,
            transfers: transfers,
            backgroundBlocked: true,
            now: _now,
          );

      test('shows under all good, and opens Backup', () {
        final row = closed(_upToDate);
        expect(_top(backup: _upToDate).text, 'Backed up and in sync');
        expect(row?.text, 'Backup can\'t run while the app is closed');
        expect(row?.detail, 'Open backup settings to fix it.');
        expect(row?.icon, Icons.error_outline_rounded);
        expect(row?.tone, HealthTone.bad);
        expect(row?.action, HealthAction.none);
        expect(row?.target, HealthTarget.backup);
      });

      test('comes after what needs doing now, and before Free up', () {
        final failed = TransfersState([_transfer('a.zip', TransferStatus.failed)]);
        expect(closed(_upToDate, transfers: failed)?.action, HealthAction.retryTransfers);
        final row = secondaryHealth(
          _top(),
          backup: _upToDate,
          transfers: TransfersState.empty,
          backgroundBlocked: true,
          lowOnSpace: true,
          freeableBytes: 9 * _gb,
          now: _now,
        );
        expect(row?.text, 'Backup can\'t run while the app is closed');
      });

      test('is nothing to say while the checks run', () {
        expect(
          secondaryHealth(_top(), backup: _upToDate, transfers: TransfersState.empty, now: _now),
          isNull,
        );
      });
    });
  });

  group('whether backup can run with the app closed needs attention', () {
    test('only while backup is on', () {
      const health = BackgroundHealth(watching: false);
      expect(health.needsAttention(true, now: _now), isTrue);
      expect(health.needsAttention(false, now: _now), isFalse);
    });

    test('when no check has run for two days', () {
      BackgroundHealth checkedAgo(Duration ago) =>
          BackgroundHealth(watching: true, lastChecked: _now.subtract(ago));
      expect(checkedAgo(const Duration(hours: 47)).needsAttention(true, now: _now), isFalse);
      expect(checkedAgo(const Duration(hours: 49)).needsAttention(true, now: _now), isTrue);
    });

    test('not for checks just armed that haven\'t run yet, nor for battery or notifications', () {
      const health = BackgroundHealth(watching: true, batteryOk: false, notificationsOk: false);
      expect(health.needsAttention(true, now: _now), isFalse);
    });
  });
}
