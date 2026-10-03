import 'package:flutter/material.dart';

import '../../../core/format/formatters.dart';
import '../../../infrastructure/database/app_database.dart'
    show TransferOrigin, TransferStatus;
import '../../backup/data/backup_controller.dart';
import '../../drive/data/drive_sync.dart';
import '../../transfers/data/transfer_queue.dart';
import '../../transfers/domain/transfer_wait.dart';

/// How a line is coloured. Only work in progress takes the accent, only
/// "all good" is green, and only failures are red.
enum HealthTone { neutral, busy, good, bad }

/// The one button a line carries, when pressing it would unblock something.
enum HealthAction {
  none,
  turnOn,
  allow,
  useData,
  retryBackup,
  retryFailed,
  retryTransfers,
  resumeTransfers,

  /// Lets transfers waiting for Wi-Fi go over mobile data; [useData] is the
  /// backup setting.
  useDataForTransfers,

  /// Lets backup go past the monthly mobile data limit for now.
  useDataAnyway,
}

/// Where tapping a line goes: a screen, or another try at syncing.
enum HealthTarget { backup, notBackedUp, transfers, refresh }

/// What a line is about. The second row keeps to a different topic from the
/// top line, so the two rows say different things and their buttons never
/// do the same job. Transfers in progress are the exception: saying some
/// are moving doesn't say that others failed. Lines about Telegram itself,
/// not reaching it or it asking for a pause, are [sync]; lines about the
/// phone's own connection, none at all or only mobile data, are [network].
enum HealthTopic { backup, transfers, sync, network }

/// One line of Home's Activity group, worked out from state alone so the
/// wording and its priority can be tested without a widget.
@immutable
class DriveHealth {
  const DriveHealth({
    required this.icon,
    required this.tone,
    required this.text,
    this.detail,
    this.progress,
    this.waiting = false,
    this.action = HealthAction.none,
    required this.target,
    required this.topic,
  });

  final IconData icon;
  final HealthTone tone;
  final String text;
  final String? detail;

  /// 0..1 for a bar, negative for an indeterminate one, null for none.
  final double? progress;

  /// The bar stands for work that waits rather than moves, so it is grey.
  final bool waiting;
  final HealthAction action;
  final HealthTarget target;
  final HealthTopic topic;
}

/// Home's first line: the one thing worth knowing about the drive, first
/// match wins. Not reaching Telegram comes first, since the drive then
/// shows only what it last synced and anything else the line said couldn't
/// be checked; then work in progress, what blocks backup, what didn't back
/// up, and only when none of that applies, that everything is backed up
/// and in sync.
///
/// Transfers someone started by hand rank above a stopped backup because
/// they are what that person is waiting on, and the stopped backup keeps
/// its Retry on the second row. Failed transfers never take this line,
/// since they say nothing about whether the drive is backed up and in sync;
/// they are a second-row concern, with their Retry (see [secondaryHealth]).
///
/// Telegram asking for a long pause ranks below a backup that is stopped,
/// can't see the photos, waits for Wi-Fi or is held by the monthly data
/// limit, since each of those has a button that unblocks it, and above work
/// in progress, which the pause is holding up. The phone having no network
/// at all ranks the same way and above that pause, since nothing can move
/// until it is back.
///
/// Transfers waiting for Wi-Fi take the line only when nothing else is
/// going on: no pause from Telegram, nothing moving, and backup neither
/// stopped, kept from the photos nor held by the monthly data limit.
/// Otherwise they keep the second row, with their Use data. The limit
/// ranks above them and above backup waiting for Wi-Fi, since it says when
/// backup carries on without Wi-Fi ([renewDay], the day the limit renews).
DriveHealth describeDriveHealth({
  required BackupState backup,
  required SyncState sync,
  required TransfersState transfers,
  DateTime? lastFullSync,
  double backupSpeed = 0,
  int renewDay = 1,
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  final active = _manualActive(transfers, at);

  if (sync.error != null) {
    return _unreachable(_latest([sync.lastSynced, lastFullSync]), at, retrying: sync.running);
  }
  // Held transfers no longer count as moving, so without this line a long
  // wait would read as all good, or as backup still going.
  final waits = [
    for (final item in transfers.heldAt(at))
      if (item.wait case WaitingForTelegram(:final until)) until,
  ];
  final backupBlocked = switch (backup.phase) {
    BackupPhase.stopped ||
    BackupPhase.needsPermission ||
    BackupPhase.waitingForWifi ||
    BackupPhase.waitingForBudget => true,
    _ => false,
  };
  if (!backupBlocked && _allWaitForNetwork(transfers.activeAt(at))) {
    return _waitingForNetwork(active, backup);
  }
  if (waits.isNotEmpty && !backupBlocked) {
    final resumesAt = waits.reduce((a, b) => a.isBefore(b) ? a : b);
    return DriveHealth(
      icon: Icons.hourglass_empty_rounded,
      tone: HealthTone.neutral,
      text: 'Telegram asked us to wait',
      detail: 'Transfers carry on by themselves '
          '${DateUtils.isSameDay(resumesAt, at) ? 'at' : 'on'} '
          '${Formatters.date(resumesAt, now: at)}.',
      target: HealthTarget.transfers,
      // About Telegram, so failed and paused transfers keep the second row
      // with their Retry and Resume.
      topic: HealthTopic.sync,
    );
  }
  if (backup.phase == BackupPhase.uploading) {
    return DriveHealth(
      icon: Icons.cloud_upload_outlined,
      tone: HealthTone.busy,
      text: 'Backing up · ${Formatters.number(backup.remaining)} left',
      detail: backupSpeed > 0 ? Formatters.speed(backupSpeed) : null,
      progress: backup.total == 0 ? -1 : backup.progress,
      target: HealthTarget.backup,
      topic: HealthTopic.backup,
    );
  }
  if (backup.phase == BackupPhase.scanning) {
    return const DriveHealth(
      icon: Icons.cloud_sync_outlined,
      tone: HealthTone.busy,
      text: 'Looking for new photos',
      progress: -1,
      target: HealthTarget.backup,
      topic: HealthTopic.backup,
    );
  }
  if (active.isNotEmpty) {
    if (_allWaitForNetwork(active)) return _waitingForNetwork(active, backup);
    // Copies from chats have no bytes to follow, since Telegram makes each
    // in one request, so on their own they are counted by file.
    final onlyCopies = active.every((t) => t.origin == TransferOrigin.fromChat);
    final copied = transfers.copyCount;
    final progress = onlyCopies
        ? copied.saved / copied.total
        : TransfersState.byteProgress(active);
    return DriveHealth(
      icon: Icons.swap_vert_rounded,
      tone: HealthTone.busy,
      text: '${Formatters.count(active.length, 'transfer')} in progress',
      detail: onlyCopies
          ? '${Formatters.number(copied.saved)} of ${Formatters.number(copied.total)} saved'
          : '${(progress * 100).round()}% done',
      progress: progress,
      target: HealthTarget.transfers,
      topic: HealthTopic.transfers,
    );
  }
  if (backup.phase == BackupPhase.stopped) return _stopped(backup);
  if (backup.phase == BackupPhase.needsPermission) return _needsPermission;
  if (backup.phase == BackupPhase.waitingForBudget) return _waitingForBudget(backup, renewDay);
  final heldForWifi = transfersWaitingForWifi(transfers);
  if (heldForWifi.isNotEmpty) return _transfersWaitingForWifi(heldForWifi);
  if (backup.phase == BackupPhase.waitingForWifi) return _waitingForWifi(backup);
  if (backup.enabled && backup.failed > 0) return _failedItems(backup);
  if (backup.phase == BackupPhase.waitingForDrive) {
    return const DriveHealth(
      icon: Icons.cloud_queue_rounded,
      tone: HealthTone.neutral,
      text: 'Backup is starting',
      detail: 'Reading your drive first.',
      target: HealthTarget.backup,
      topic: HealthTopic.backup,
    );
  }
  // The sync time only lives in memory, so right after launch it is
  // missing. Saying "checking" until the first sync ends keeps the line
  // from turning green on an older timestamp.
  if (sync.running && sync.lastSynced == null) {
    return const DriveHealth(
      icon: Icons.sync_rounded,
      tone: HealthTone.neutral,
      text: 'Checking with Telegram',
      progress: -1,
      target: HealthTarget.refresh,
      topic: HealthTopic.sync,
    );
  }
  if (backup.phase == BackupPhase.off) return _off;

  final checked = _latest([sync.lastSynced, backup.lastCompleted, lastFullSync]);
  return DriveHealth(
    icon: Icons.check_circle_outline_rounded,
    tone: HealthTone.good,
    text: 'Backed up and in sync',
    detail: checked == null ? null : 'checked ${Formatters.date(checked, now: at)}',
    target: HealthTarget.backup,
    topic: HealthTopic.backup,
  );
}

/// Home's optional second line: the most pressing concern that needs an
/// action and that [top] doesn't already speak for, or null. There is
/// never a third. A top line about transfers in progress still leaves the
/// row to failed ones; paused ones only count once nothing is moving.
DriveHealth? secondaryHealth(
  DriveHealth top, {
  required BackupState backup,
  required TransfersState transfers,
  int renewDay = 1,
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  final failedTransfers = transfers.failedCount;
  final heldForWifi = transfersWaitingForWifi(transfers);
  final paused = transfers.items
      .where((t) => t.status == TransferStatus.paused && t.origin != TransferOrigin.backup)
      .length;
  final candidates = [
    if (backup.phase == BackupPhase.stopped) _stopped(backup),
    if (backup.phase == BackupPhase.needsPermission) _needsPermission,
    if (backup.phase == BackupPhase.waitingForBudget) _waitingForBudget(backup, renewDay),
    if (backup.phase == BackupPhase.waitingForWifi) _waitingForWifi(backup),
    if (backup.enabled && backup.failed > 0) _failedItems(backup),
    if (failedTransfers > 0) _failedTransfers(transfers),
    if (heldForWifi.isNotEmpty) _transfersWaitingForWifi(heldForWifi),
    if (paused > 0 && _manualActive(transfers, at).isEmpty)
      DriveHealth(
        icon: Icons.pause_circle_outline_rounded,
        tone: HealthTone.neutral,
        text: '${Formatters.count(paused, 'transfer')} paused',
        action: HealthAction.resumeTransfers,
        target: HealthTarget.transfers,
        topic: HealthTopic.transfers,
      ),
    if (backup.phase == BackupPhase.off) _off,
  ];
  final moving = top.tone == HealthTone.busy && top.topic == HealthTopic.transfers;
  return candidates.where((line) => line.topic != top.topic || moving).firstOrNull;
}

/// The failure stays on the line while another try runs, with a bar to show
/// the try, so a retry that is still offline never reads as in sync.
DriveHealth _unreachable(DateTime? synced, DateTime now, {required bool retrying}) =>
    DriveHealth(
      icon: Icons.sync_problem_rounded,
      tone: HealthTone.neutral,
      text: 'Can\'t reach Telegram',
      detail: synced == null
          ? 'Pull down to try again.'
          : 'Showing what was synced ${DateUtils.isSameDay(synced, now) ? 'at' : 'on'} '
                '${Formatters.date(synced, now: now)}. Pull down to try again.',
      progress: retrying ? -1 : null,
      target: HealthTarget.refresh,
      topic: HealthTopic.sync,
    );

DriveHealth _stopped(BackupState backup) => DriveHealth(
  icon: Icons.error_outline_rounded,
  tone: HealthTone.bad,
  text: 'Backup stopped',
  detail: backup.error ?? 'Something went wrong.',
  action: HealthAction.retryBackup,
  target: HealthTarget.backup,
  topic: HealthTopic.backup,
);

const _needsPermission = DriveHealth(
  icon: Icons.no_photography_outlined,
  tone: HealthTone.neutral,
  text: 'Backup can\'t see your photos',
  detail: 'Allow photo access to continue.',
  action: HealthAction.allow,
  target: HealthTarget.backup,
  topic: HealthTopic.backup,
);

/// Before the first scan after launch nothing has been counted, so the line
/// leaves the number out instead of saying zero. With mobile data for
/// photos only, the photos are done and the videos are what waits.
DriveHealth _waitingForWifi(BackupState backup) => DriveHealth(
  icon: Icons.wifi_off_rounded,
  tone: HealthTone.neutral,
  text: backup.heldVideos > 0
      ? 'Videos wait for Wi-Fi'
      : backup.remaining > 0
      ? 'Waiting for Wi-Fi · ${Formatters.count(backup.remaining, 'item')} left'
      : 'Waiting for Wi-Fi',
  detail: backup.heldVideos > 0
      ? '${Formatters.count(backup.heldVideos, 'video')} left. Photos are backed up.'
      : 'Backup uses Wi-Fi only.',
  action: HealthAction.useData,
  target: HealthTarget.backup,
  topic: HealthTopic.backup,
);

/// What is left would pass the monthly mobile data limit; it goes on Wi-Fi,
/// or once the limit renews on [renewDay].
DriveHealth _waitingForBudget(BackupState backup, int renewDay) => DriveHealth(
  icon: Icons.data_usage_rounded,
  tone: HealthTone.neutral,
  text: 'Monthly data limit reached',
  detail:
      '${Formatters.count(backup.remaining, 'item')} left. Backup carries on over '
      'Wi-Fi, or on the ${Formatters.dayOfMonth(renewDay)}.',
  action: HealthAction.useDataAnyway,
  target: HealthTarget.backup,
  topic: HealthTopic.backup,
);

DriveHealth _failedItems(BackupState backup) => DriveHealth(
  icon: Icons.error_outline_rounded,
  tone: HealthTone.bad,
  text: '${Formatters.count(backup.failed, 'item')} didn\'t back up',
  detail: 'See which ones and why.',
  action: HealthAction.retryFailed,
  target: HealthTarget.notBackedUp,
  topic: HealthTopic.backup,
);

/// With one failure the line says why; with more, where to read why.
DriveHealth _failedTransfers(TransfersState transfers) {
  final failed = transfers.finished
      .where((t) => t.status == TransferStatus.failed && t.origin != TransferOrigin.backup)
      .toList();
  return DriveHealth(
    icon: Icons.error_outline_rounded,
    tone: HealthTone.bad,
    text: '${Formatters.count(failed.length, 'transfer')} failed',
    detail: (failed.length == 1 ? failed.single.row.error : null) ??
        'Open Transfers to see why.',
    action: HealthAction.retryTransfers,
    target: HealthTarget.transfers,
    topic: HealthTopic.transfers,
  );
}

const _off = DriveHealth(
  icon: Icons.cloud_off_outlined,
  tone: HealthTone.neutral,
  text: 'Photo backup is off',
  detail: 'Back up this phone\'s photos and videos to your drive.',
  action: HealthAction.turnOn,
  target: HealthTarget.backup,
  topic: HealthTopic.backup,
);

/// The phone has no network: everything in flight sits still until it is
/// back, and TDLib then carries on by itself. Backup says so in its own
/// words when it is the only thing moving.
DriveHealth _waitingForNetwork(List<TransferItem> manual, BackupState backup) {
  final progress = manual.isEmpty ? backup.progress : TransfersState.byteProgress(manual);
  return DriveHealth(
    icon: Icons.cloud_off_rounded,
    tone: HealthTone.neutral,
    text: 'Waiting for network',
    detail: manual.isEmpty
        ? 'Backup carries on when you\'re back online.'
        : 'Carries on when you\'re back online · ${(progress * 100).round()}%',
    progress: progress,
    waiting: true,
    target: manual.isEmpty ? HealthTarget.backup : HealthTarget.transfers,
    topic: HealthTopic.network,
  );
}

/// There is something in [items], and all of it waits for the network.
bool _allWaitForNetwork(List<TransferItem> items) =>
    items.isNotEmpty && items.every((t) => t.wait is WaitingForNetwork);

/// Uploads and downloads someone started that wait for Wi-Fi. Backup
/// uploads waiting for it are told by backup's own line.
List<TransferItem> transfersWaitingForWifi(TransfersState transfers) =>
    transfers.waitingForWifi.where((t) => t.origin != TransferOrigin.backup).toList();

DriveHealth _transfersWaitingForWifi(List<TransferItem> held) {
  final bytes = held.fold<int>(0, (sum, t) => sum + t.row.totalBytes - t.row.doneBytes);
  return DriveHealth(
    icon: Icons.wifi_off_rounded,
    tone: HealthTone.neutral,
    text: 'Waiting for Wi-Fi · ${Formatters.count(held.length, 'transfer')}',
    // A non-breaking hyphen, so a wrapped line never ends in 'Wi-'.
    detail:
        '${Formatters.bytes(bytes)}. '
        '${held.length == 1 ? 'It starts on its own' : 'They start on their own'} on Wi\u2011Fi.',
    action: HealthAction.useDataForTransfers,
    target: HealthTarget.transfers,
    topic: HealthTopic.network,
  );
}

/// Uploads and downloads someone started by hand that are in flight at
/// [at]; backup has its own line.
List<TransferItem> _manualActive(TransfersState transfers, DateTime at) =>
    transfers.activeAt(at).where((t) => t.origin != TransferOrigin.backup).toList();

DateTime? _latest(List<DateTime?> times) {
  DateTime? latest;
  for (final time in times) {
    if (time != null && (latest == null || time.isAfter(latest))) latest = time;
  }
  return latest;
}
