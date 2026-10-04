import 'package:flutter/material.dart';

import '../../../core/format/formatters.dart';
import '../../../infrastructure/database/app_database.dart'
    show TransferOrigin, TransferStatus;
import '../../backup/data/backup_controller.dart';
import '../../drive/data/drive_sync.dart';
import '../../drive/data/edit_outbox.dart';
import '../../drive/data/forward_filer.dart';
import '../../network/data/connection_health.dart';
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

  /// Offers to delete the phone's copies of photos and videos that are
  /// backed up, for transfers waiting for room.
  freeUpSpace,

  /// The same offer for a phone low on space, whose line already says how
  /// much could go, so the button needs fewer words.
  freeUp,

  /// Opens the proxy sheet where Telegram can't be reached directly.
  useProxy,

  /// Opens the proxy sheet where the proxy in use isn't answering.
  changeProxy,

  /// Takes the report of forwards filed by their comment off Home.
  dismissFiling,

  /// Tries again to open the drive behind Home, after finding it in
  /// Telegram failed.
  retryOpening,

  /// Starts TDLib again after it failed to start.
  restartTelegram,
}

/// How far opening the drive has got while Home shows it from the index,
/// which a returning person sees before Telegram has started.
enum DriveOpening {
  /// The drive's session is open, or Home isn't showing a saved drive.
  open,

  /// Telegram is starting, or the drive is being found in it.
  connecting,

  /// Finding the drive in Telegram failed, often for want of a connection.
  failed,

  /// TDLib itself didn't start.
  notStarted,
}

/// Where tapping a line goes: a screen, another try at syncing, the proxy
/// sheet, or the folder forwards were just filed into ([filed]; Files
/// itself when there were several). [changes] is Waiting changes. A line
/// about opening the drive goes nowhere ([none]): it says what is
/// happening, and its button, when it has one, is the one thing to do.
enum HealthTarget { backup, notBackedUp, transfers, refresh, proxy, filed, changes, none }

/// What a line is about. The second row keeps to a different topic from the
/// top line, so the two rows say different things and their buttons never
/// do the same job. Transfers in progress are the exception: saying some
/// are moving doesn't say that others failed. Lines about Telegram itself,
/// not reaching it or it asking for a pause, are [sync]; lines about the
/// phone's own connection, none at all or only mobile data, are [network];
/// the line about the phone's free space is [storage]; the report of
/// forwards filed by their comment is [filing]; changes made without a
/// connection that are still to reach Telegram are [changes].
enum HealthTopic { backup, transfers, sync, network, storage, filing, changes }

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
/// While Home shows the drive from the index before its session is open
/// ([opening]), the line says so, since nothing else it could say has
/// been checked: TDLib that didn't start first, with [openingError] and
/// Try again; then a connection stuck on its network, whose proxy is what
/// unblocks it; then a failed try at finding the drive, with its
/// [openingError] and Retry; otherwise that Telegram is connecting.
///
/// Of the ways of not reaching Telegram, a [connection] stuck on a network
/// that has internet goes first, with its proxy, since a proxy is the one
/// thing that unblocks it; [proxy] names the proxy in use, if known. A
/// sync that failed comes next.
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
///
/// Transfers waiting for room on the phone come straight after not
/// reaching Telegram, unless backup is stopped or can't see the photos,
/// which keep the line for their own button. Nothing they wait for comes
/// by itself unless something on the phone is deleted, and waiting for the
/// network, for Telegram or on work in progress would not change that.
DriveHealth describeDriveHealth({
  required BackupState backup,
  required SyncState sync,
  required TransfersState transfers,
  DateTime? lastFullSync,
  double backupSpeed = 0,
  int renewDay = 1,
  ConnectionHealth connection = ConnectionHealth.ok,
  String? proxy,
  DriveOpening opening = DriveOpening.open,
  String? openingError,
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  final active = _manualActive(transfers, at);

  if (opening == DriveOpening.notStarted) return _notStarted(openingError);
  final blocked = describeConnection(connection, proxy: proxy);
  if (blocked != null) return blocked;
  if (opening == DriveOpening.failed) return _openingFailed(openingError);
  if (opening == DriveOpening.connecting) return _connecting;
  if (sync.error != null) {
    return _unreachable(_latest([sync.lastSynced, lastFullSync]), at, retrying: sync.running);
  }
  final backupStuck =
      backup.phase == BackupPhase.stopped || backup.phase == BackupPhase.needsPermission;
  final needRoom = transfers.waitingForRoom;
  if (needRoom.isNotEmpty && !backupStuck) return _nearlyFull(needRoom);
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
///
/// Changes made without a connection that are still to reach Telegram
/// ([changes]) come after what needs doing about transfers, and so does
/// the report of forwards the filer just put where their comment said
/// ([filed]), after them; both come before the offers, since neither asks
/// for more than a look.
///
/// Last of all, when the phone is [lowOnSpace] and more than
/// [freeUpWorthwhile] of backed-up photos ([freeableBytes]) could leave it,
/// the line offers Free up. A phone too full for a transfer says so with
/// its own Free up space instead, on either row, since both are about
/// [HealthTopic.storage].
DriveHealth? secondaryHealth(
  DriveHealth top, {
  required BackupState backup,
  required TransfersState transfers,
  int renewDay = 1,
  bool lowOnSpace = false,
  int freeableBytes = 0,
  OutboxState? changes,
  FilingSummary? filed,
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  final failedTransfers = transfers.failedCount;
  final waitingChanges = changes == null ? null : _waitingChanges(changes, at);
  final heldForWifi = transfersWaitingForWifi(transfers);
  final paused = transfers.items
      .where((t) => t.status == TransferStatus.paused && t.origin != TransferOrigin.backup)
      .length;
  final needRoom = transfers.waitingForRoom;
  final candidates = [
    if (backup.phase == BackupPhase.stopped) _stopped(backup),
    if (backup.phase == BackupPhase.needsPermission) _needsPermission,
    if (needRoom.isNotEmpty) _nearlyFull(needRoom),
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
    ?waitingChanges,
    if (filed != null && filed.count > 0) _filed(filed),
    if (backup.phase == BackupPhase.off) _off,
    if (lowOnSpace && freeableBytes > freeUpWorthwhile) _freeUp(freeableBytes),
  ];
  final moving = top.tone == HealthTone.busy && top.topic == HealthTopic.transfers;
  return candidates.where((line) => line.topic != top.topic || moving).firstOrNull;
}

/// The line for a connection that is stuck, or null when [health] says
/// nothing is wrong that a proxy could help with. Home's first line and the
/// sign-in and setup screens' notice both say it. [proxy] is the proxy in
/// use, for a proxy that isn't answering.
DriveHealth? describeConnection(ConnectionHealth health, {String? proxy}) => switch (health) {
  ConnectionHealth.stuck => const DriveHealth(
    icon: Icons.cloud_off_rounded,
    tone: HealthTone.neutral,
    text: 'Telegram isn\'t reachable on this network',
    detail: 'Still trying. A proxy often helps where Telegram is blocked.',
    action: HealthAction.useProxy,
    target: HealthTarget.proxy,
    topic: HealthTopic.sync,
  ),
  ConnectionHealth.proxyStuck => DriveHealth(
    icon: Icons.cloud_off_rounded,
    tone: HealthTone.neutral,
    text: 'Can\'t reach the proxy',
    detail: '${proxy ?? 'The proxy'} isn\'t answering.',
    action: HealthAction.changeProxy,
    target: HealthTarget.proxy,
    topic: HealthTopic.sync,
  ),
  ConnectionHealth.ok || ConnectionHealth.noNetwork => null,
};

/// Home shows the drive from the index while Telegram starts behind it.
/// Uploads and downloads wait in the queue meanwhile; other changes say
/// to try again in a moment.
const _connecting = DriveHealth(
  icon: Icons.cloud_sync_outlined,
  tone: HealthTone.busy,
  text: 'Connecting to Telegram',
  detail: 'Your files are here. Changes wait until it connects.',
  progress: -1,
  target: HealthTarget.none,
  topic: HealthTopic.sync,
);

/// Finding the drive in Telegram failed; [error] says why.
DriveHealth _openingFailed(String? error) => DriveHealth(
  icon: Icons.cloud_off_outlined,
  tone: HealthTone.bad,
  text: 'Couldn\'t reach Telegram',
  detail: error,
  action: HealthAction.retryOpening,
  target: HealthTarget.none,
  topic: HealthTopic.sync,
);

/// TDLib failed to start, which the splash says for everyone else.
DriveHealth _notStarted(String? error) => DriveHealth(
  icon: Icons.error_outline_rounded,
  tone: HealthTone.bad,
  text: 'Telegram didn\'t start',
  detail: error,
  action: HealthAction.restartTelegram,
  target: HealthTarget.none,
  topic: HealthTopic.sync,
);

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

/// Transfers that wait for room on the phone, with how much the biggest of
/// them needs free: room for it is room for each, one at a time.
DriveHealth _nearlyFull(List<TransferItem> waiting) {
  final needed = waiting
      .map((t) => (t.wait! as WaitingForRoom).needed)
      .reduce((a, b) => a > b ? a : b);
  return DriveHealth(
    icon: Icons.sd_card_alert_outlined,
    tone: HealthTone.neutral,
    text: 'This phone is nearly full',
    detail:
        '${Formatters.count(waiting.length, 'transfer')} '
        '${waiting.length == 1 ? 'is' : 'are'} waiting for ${Formatters.bytes(needed)} of room.',
    action: HealthAction.freeUpSpace,
    target: HealthTarget.transfers,
    topic: HealthTopic.storage,
  );
}

/// Less than this to free isn't worth a line on Home.
const freeUpWorthwhile = 500 * 1024 * 1024;

/// The phone is low on space and [bytes] of backed-up photos could leave
/// it. Only the photos older than the window Free up space keeps count.
DriveHealth _freeUp(int bytes) => DriveHealth(
  icon: Icons.phonelink_erase_outlined,
  tone: HealthTone.neutral,
  text: '${Formatters.bytes(bytes)} of backed-up photos can leave this phone',
  detail: 'This phone is running low on space.',
  action: HealthAction.freeUp,
  target: HealthTarget.backup,
  topic: HealthTopic.storage,
);

/// Changes made on this phone that are still to reach Telegram, or null
/// when none are: any that failed too often first, in red; then a pause
/// Telegram asked for, with roughly how long it has to go at [at]; then
/// the ones being sent, with the one accent there is on the bar; and
/// otherwise how many wait for the connection.
DriveHealth? _waitingChanges(OutboxState outbox, DateTime at) {
  if (outbox.failed > 0) {
    return DriveHealth(
      icon: Icons.error_outline_rounded,
      tone: HealthTone.bad,
      text: '${Formatters.count(outbox.failed, 'change')} couldn\'t be sent',
      detail: 'Open to see why.',
      target: HealthTarget.changes,
      topic: HealthTopic.changes,
    );
  }
  if (outbox.waiting == 0) return null;
  final count = Formatters.count(outbox.waiting, 'change');
  final one = outbox.waiting == 1;
  final pausedUntil = outbox.pausedUntil;
  if (pausedUntil != null && pausedUntil.isAfter(at)) {
    return DriveHealth(
      icon: Icons.hourglass_empty_rounded,
      tone: HealthTone.neutral,
      text: 'Telegram asked to wait',
      detail:
          'Your $count ${one ? 'goes' : 'go'} in about '
          '${Formatters.inWords(pausedUntil.difference(at))}.',
      target: HealthTarget.changes,
      topic: HealthTopic.changes,
    );
  }
  if (outbox.sending) {
    return DriveHealth(
      icon: Icons.schedule_rounded,
      tone: HealthTone.neutral,
      text: 'Sending $count to Telegram',
      progress: -1,
      target: HealthTarget.changes,
      topic: HealthTopic.changes,
    );
  }
  return DriveHealth(
    icon: Icons.schedule_rounded,
    tone: HealthTone.neutral,
    text: '$count waiting for the network',
    detail: '${one ? 'It reaches' : 'They reach'} Telegram when you\'re back online.',
    target: HealthTarget.changes,
    topic: HealthTopic.changes,
  );
}

/// Forwards went into the folder their comment named, or into several;
/// tapping opens the folder, or Files when there were several.
DriveHealth _filed(FilingSummary filed) => DriveHealth(
  icon: Icons.drive_file_move_outline,
  tone: HealthTone.good,
  text:
      'Filed ${Formatters.count(filed.count, 'forwarded file')} into '
      '${filed.folderNames.length == 1 ? filed.folderNames.single : Formatters.count(filed.folderNames.length, 'folder')}',
  detail: 'From your comment in Telegram.',
  action: HealthAction.dismissFiling,
  target: HealthTarget.filed,
  topic: HealthTopic.filing,
);

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
