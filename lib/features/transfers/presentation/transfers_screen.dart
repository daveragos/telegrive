import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';

import '../../../app/theme/file_style.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/format/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/file_visuals.dart';
import '../../../infrastructure/database/app_database.dart';
import '../../../infrastructure/storage/device_storage.dart';
import '../../backup/data/backup_controller.dart';
import '../../backup/presentation/backup_card.dart';
import '../../offline/data/offline_sync.dart';
import '../data/transfer_queue.dart';
import '../domain/transfer_error.dart';
import '../domain/transfer_wait.dart';

class TransfersScreen extends ConsumerWidget {
  const TransfersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(transferQueueProvider);
    // Photo backup, downloads to the phone and copies from chats are
    // summarised in a line each rather than listed file by file; only their
    // failures are listed.
    final active = state.pending
        .where((t) => t.origin == TransferOrigin.manual)
        .toList();
    // Those waiting for Wi-Fi get a group of their own, with the one button
    // that lets them go now.
    final waitingForWifi = active.where((t) => t.wait is WaitingForWifi).toList();
    final inProgress = active.where((t) => t.wait is! WaitingForWifi).toList();
    final waitingBytes = waitingForWifi.fold<int>(
      0,
      (sum, t) => sum + t.row.totalBytes - t.row.doneBytes,
    );
    final anyRunning = inProgress.any((t) => t.status.isActive);
    final anyPaused = inProgress.any((t) => t.status == TransferStatus.paused);
    // When what is moving should be done, at the speed it moves now; only
    // worth saying when that is a while away.
    final now = DateTime.now();
    var left = 0;
    var speed = 0.0;
    for (final item in inProgress.where((t) => t.status == TransferStatus.running)) {
      left += item.row.totalBytes - item.row.doneBytes;
      speed += item.bytesPerSecond;
    }
    final eta = speed > 0 ? Duration(seconds: (left / speed).ceil()) : null;
    final doneAround = eta != null && eta > const Duration(minutes: 10)
        ? ' · done around ${Formatters.clock(now.add(eta), now: now)}'
        : '';
    final saves = state.saves;
    final copies = state.copies.where((t) => t.status != TransferStatus.cancelled).toList();
    final queue = ref.read(transferQueueProvider.notifier);
    final inProgressIds = {for (final t in inProgress) t.id};
    bool listed(TransferRow r) => inProgressIds.contains(r.id);
    final finished = state.finished
        .where(
          (t) =>
              !((t.origin == TransferOrigin.save || t.origin == TransferOrigin.fromChat) &&
                  t.status == TransferStatus.completed),
        )
        .toList();
    final failed = finished.where((t) => t.status == TransferStatus.failed).length;
    final backingUp = ref.watch(backupControllerProvider.select((b) => b.isWorking));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transfers'),
        actions: [
          if (state.finished.isNotEmpty)
            TextButton(
              onPressed: () => ref.read(transferQueueProvider.notifier).clearFinished(),
              child: const Text('Clear finished'),
            ),
          const SizedBox(width: Space.s),
        ],
      ),
      body: active.isEmpty && finished.isEmpty && saves.isEmpty && copies.isEmpty && !backingUp
          ? const EmptyState(
              title: 'Nothing is moving',
              message: 'Uploads and downloads show up here while they run.',
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: Space.x4),
              children: [
                if (backingUp) ...[
                  const SectionHeader('Photo backup'),
                  const ListGroup(children: [BackupStatusLine()]),
                ],
                if (saves.any((t) => t.status != TransferStatus.cancelled)) ...[
                  const SectionHeader('Download to this phone'),
                  ListGroup(children: [_SaveGroup(saves: saves)]),
                ],
                // Comes and goes as the phone moves between Wi-Fi and mobile
                // data, so it eases in and out rather than jump.
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  child: waitingForWifi.isEmpty
                      ? const SizedBox(width: double.infinity)
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SectionHeader(
                              'Waiting for Wi-Fi · '
                              '${Formatters.count(waitingForWifi.length, 'file')} · '
                              '${Formatters.bytes(waitingBytes)}',
                              trailing: TextButton(
                                onPressed: () =>
                                    queue.useMobileData(waitingForWifi.map((t) => t.id)),
                                child: const Text('Use mobile data'),
                              ),
                            ),
                            ListGroup(
                              children: [
                                for (final item in waitingForWifi) _ActiveRow(item: item),
                              ],
                            ),
                          ],
                        ),
                ),
                if (copies.any((t) => t.status != TransferStatus.failed)) ...[
                  const SectionHeader('Saving from Telegram'),
                  ListGroup(children: [_CopyGroup(copies: copies)]),
                ],
                if (inProgress.isNotEmpty) ...[
                  SectionHeader(
                    'In progress · ${inProgress.length}$doneAround',
                    trailing: inProgress.length < 2
                        ? null
                        : TextButton(
                            onPressed: anyRunning
                                ? () => queue.pauseAll(listed)
                                : () => queue.resumeAll(listed),
                            child: Text(anyRunning || !anyPaused ? 'Pause all' : 'Resume all'),
                          ),
                  ),
                  ListGroup(children: [for (final item in inProgress) _ActiveRow(item: item)]),
                ],
                if (finished.isNotEmpty) ...[
                  SectionHeader(
                    'Finished',
                    trailing: failed < 2
                        ? null
                        : TextButton(
                            onPressed: () => queue.retryAll(
                              (r) =>
                                  r.status == TransferStatus.failed &&
                                  r.origin != TransferOrigin.backup,
                            ),
                            child: const Text('Retry all'),
                          ),
                  ),
                  ListGroup(children: [for (final item in finished) _FinishedRow(item: item)]),
                ],
              ],
            ),
    );
  }
}

/// Every download to this phone as one line: how far along, what it waits
/// for, or where it all went once done.
class _SaveGroup extends ConsumerWidget {
  const _SaveGroup({required this.saves});

  final List<TransferItem> saves;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final queue = ref.read(transferQueueProvider.notifier);
    final running = saves.where((t) => t.status.isActive).toList();
    final held = running.where((t) => t.wait is WaitingForWifi).toList();
    final room = [
      for (final item in running)
        if (item.wait case final WaitingForRoom wait) wait,
    ];
    final moving = running.length > held.length + room.length;
    final paused = saves.where((t) => t.status == TransferStatus.paused).toList();
    final saved = saves.where((t) => t.status == TransferStatus.completed).toList();
    final total = saves.where((t) => t.status != TransferStatus.cancelled).length;
    final toGallery = saves.any((t) => t.row.saveTo == SaveTarget.gallery);
    final toFiles = saves.any((t) => t.row.saveTo == SaveTarget.files);
    final toOffline = saves.any((t) => t.row.saveTo == SaveTarget.offline);
    final where = [
      if (toFiles) DeviceStorage.location,
      if (toGallery) 'your photos',
      if (toOffline) 'your offline files',
    ].join(' and ');

    bool isSave(TransferRow r) => r.origin == TransferOrigin.save;
    final stop = TextButton(
      onPressed: () async {
        final confirmed = await showConfirmDialog(
          context,
          title: 'Stop downloading?',
          message: 'Files already saved stay on this phone.',
          confirmLabel: 'Stop',
        );
        if (confirmed) await queue.cancelSaves();
      },
      child: const Text('Stop'),
    );

    if (!moving && room.isNotEmpty) {
      // The biggest need says how much room lets them all go on.
      final need = room.reduce((a, b) => a.needed >= b.needed ? a : b);
      return StatusLine(
        icon: Icons.sd_card_alert_outlined,
        color: colors.text2,
        text:
            'Waiting for room · ${Formatters.number(saved.length)} of '
            '${Formatters.count(total, 'file')} saved',
        detail: need.sentence,
        trailing: stop,
      );
    }

    if (!moving && held.isNotEmpty) {
      // Held by Only over Wi-Fi on the Offline screen, which is where it
      // changes.
      final keptOnWifi =
          ref.watch(offlineSyncProvider) && held.every((t) => t.row.saveTo == SaveTarget.offline);
      return StatusLine(
        icon: Icons.wifi_off_rounded,
        color: colors.text2,
        text:
            'Waiting for Wi-Fi · ${Formatters.number(saved.length)} of '
            '${Formatters.count(total, 'file')} saved',
        detail: keptOnWifi
            ? 'Kept-offline files download over Wi-Fi. Change this in Available offline.'
            : 'They carry on over Wi-Fi.',
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: () => queue.useMobileData(held.map((t) => t.id)),
              child: const Text('Use data'),
            ),
            stop,
          ],
        ),
      );
    }

    if (!moving && paused.isNotEmpty) {
      return StatusLine(
        icon: Icons.pause_circle_outline_rounded,
        color: colors.text2,
        text: 'Paused · ${Formatters.number(saved.length)} of ${Formatters.count(total, 'file')} saved',
        detail: 'Resume to carry on where it stopped.',
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(onPressed: () => queue.resumeAll(isSave), child: const Text('Resume')),
            stop,
          ],
        ),
      );
    }

    if (!moving) {
      return StatusLine(
        icon: Icons.download_done_rounded,
        color: colors.success,
        text: 'Saved ${Formatters.count(saved.length, 'file')}',
        detail: 'In $where',
      );
    }

    var bytes = 0;
    var done = 0;
    var speed = 0.0;
    for (final item in [...running, ...paused, ...saved]) {
      // Saves held for Wi-Fi or room move nothing now, so they count
      // neither in what is left nor in when it ends; the line says how
      // many wait.
      if (item.wait is WaitingForWifi || item.wait is WaitingForRoom) continue;
      bytes += item.row.totalBytes;
      done += item.status == TransferStatus.completed ? item.row.totalBytes : item.row.doneBytes;
      speed += item.bytesPerSecond;
    }
    final left = bytes - done;
    return StatusLine(
      icon: Icons.download_rounded,
      color: colors.accent,
      text: '${Formatters.number(saved.length)} of ${Formatters.count(total, 'file')} saved',
      detail: [
        if (speed < 1)
          '${Formatters.bytes(left)} left'
        else ...[
          Formatters.bytes(left),
          Formatters.speed(speed),
          Formatters.eta(Duration(seconds: (left / speed).ceil())),
        ],
        if (held.isNotEmpty)
          '${Formatters.number(held.length)} ${held.length == 1 ? 'waits' : 'wait'} for Wi-Fi',
        if (room.isNotEmpty)
          '${Formatters.number(room.length)} ${room.length == 1 ? 'waits' : 'wait'} for room',
      ].join(' · '),
      progress: bytes == 0 ? 0 : done / bytes,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(onPressed: () => queue.pauseAll(isSave), child: const Text('Pause')),
          stop,
        ],
      ),
    );
  }
}

/// Every copy from a Telegram chat as one line, counted by file: Telegram
/// makes each in one go, so there are no bytes to follow.
class _CopyGroup extends ConsumerWidget {
  const _CopyGroup({required this.copies});

  /// None of them cancelled, and at least one not failed.
  final List<TransferItem> copies;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final queue = ref.read(transferQueueProvider.notifier);
    final active = copies.where((t) => t.status.isActive).toList();
    final saved = copies.where((t) => t.status == TransferStatus.completed).length;
    final total = copies.length;

    if (active.isEmpty) {
      return StatusLine(
        icon: Icons.telegram,
        color: colors.success,
        text: 'Saved ${Formatters.count(saved, 'file')} from Telegram',
        detail: 'Copied inside Telegram, so nothing was downloaded.',
      );
    }

    // Copies run one at a time, so while Telegram asks for a pause every
    // one of them waits for it.
    final waits = [
      for (final item in active)
        if (item.wait case WaitingForTelegram(:final until)) until,
    ];
    final resumesAt = waits.isEmpty || waits.length < active.length
        ? null
        : waits.reduce((a, b) => a.isBefore(b) ? a : b);
    final stop = TextButton(
      onPressed: () async {
        final confirmed = await showConfirmDialog(
          context,
          title: 'Stop saving from Telegram?',
          message: 'Files already saved stay in your drive.',
          confirmLabel: 'Stop',
        );
        if (confirmed) await queue.cancelCopies();
      },
      child: const Text('Stop'),
    );
    final text = 'Saving from Telegram · ${Formatters.number(saved)} of ${Formatters.number(total)}';
    final progress = total == 0 ? 0.0 : saved / total;

    if (resumesAt != null) {
      return Countdown(
        until: resumesAt,
        builder: (context, left) => StatusLine(
          icon: Icons.telegram,
          text: text,
          detail: 'Waiting for Telegram · ${Formatters.countdown(left)}',
          progress: progress,
          progressColor: colors.text3,
          trailing: stop,
        ),
      );
    }
    return StatusLine(
      icon: Icons.telegram,
      color: colors.accent,
      text: text,
      detail: 'Copied inside Telegram, nothing is downloaded.',
      progress: progress,
      trailing: stop,
    );
  }
}

class _ActiveRow extends ConsumerWidget {
  const _ActiveRow({required this.item});

  final TransferItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final isUpload = item.kind == TransferKind.upload;
    final queued = item.status == TransferStatus.queued;
    final paused = item.status == TransferStatus.paused;
    final waitingUntil = switch (item.wait) {
      WaitingForTelegram(:final until) => until,
      _ => null,
    };
    final queue = ref.read(transferQueueProvider.notifier);
    final eta = item.eta;
    final parts = item.row.partCount > 1
        ? 'part ${(item.row.completedParts + 1).clamp(1, item.row.partCount)} '
              'of ${item.row.partCount}'
        : null;

    final detailStyle = context.text.bodySmall?.copyWith(fontFeatures: tabularFigures);
    final soFar = '${Formatters.bytes(item.row.doneBytes)} of ${Formatters.bytes(item.row.totalBytes)}';
    final started = item.row.doneBytes > 0 || item.row.completedParts > 0;
    // A split upload that stopped part of the way, after a restart say,
    // carries on from the parts the drive already has.
    final sent = isUpload && item.row.partCount > 1 && item.row.completedParts > 0
        ? '${Formatters.number(item.row.completedParts)} of '
              '${Formatters.number(item.row.partCount)} parts already in your drive'
        : null;
    final String detail;
    if (item.preparing) {
      detail = 'Preparing the file';
    } else if (paused) {
      detail = sent == null ? ['Paused', soFar, ?parts].join(' · ') : 'Paused · $sent';
    } else if (item.wait case final WaitingForRoom room) {
      detail = room.sentence;
    } else if (item.wait is WaitingForWifi) {
      detail = started
          ? ['Waiting for Wi-Fi', soFar, ?parts].join(' · ')
          : 'Waiting for Wi-Fi · ${Formatters.bytes(item.row.totalBytes)}';
    } else if (item.wait is WaitingForNetwork) {
      // No speed or time left: nothing is moving until the network is back.
      detail = ['Waiting for network', soFar, ?parts].join(' · ');
    } else if (queued) {
      detail = sent == null
          ? 'Waiting · ${Formatters.bytes(item.row.totalBytes)}'
          : 'Continuing · $sent';
    } else {
      detail = [
        soFar,
        if (item.bytesPerSecond > 0) Formatters.speed(item.bytesPerSecond),
        ?(eta == null ? null : Formatters.eta(eta)),
        ?parts,
      ].join(' · ');
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.m, Space.xs, Space.m),
      child: Row(
        children: [
          FileIconTile(style: FileStyle.forFile(item.name, item.fileKind), size: 40),
          const SizedBox(width: Space.l),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.titleSmall,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(
                      isUpload ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                      size: 14,
                      color: colors.text2,
                    ),
                    const SizedBox(width: Space.xs),
                    Expanded(
                      child: waitingUntil == null
                          ? Text(
                              detail,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: detailStyle,
                            )
                          : Countdown(
                              until: waitingUntil,
                              builder: (context, left) => Text(
                                'Waiting for Telegram · ${Formatters.countdown(left)}',
                                maxLines: 1,
                                style: detailStyle,
                              ),
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: Space.s),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: item.progress),
                    duration: const Duration(milliseconds: 250),
                    builder: (context, value, _) => LinearProgressIndicator(
                      value: item.preparing ? null : value,
                      minHeight: 4,
                      // Grey while it waits rather than moves.
                      color: paused || queued || item.wait != null ? colors.text3 : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Staging a picked file can't stop halfway, so it can't pause.
          if (!item.preparing)
            IconButton(
              onPressed: () => paused ? queue.resume(item.id) : queue.pause(item.id),
              icon: Icon(
                paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                color: colors.text2,
              ),
              tooltip: paused ? 'Resume' : 'Pause',
            ),
          IconButton(
            // Cancelled transfers leave the list rather than pile up in it.
            onPressed: () {
              queue.remove(item.id);
              showSnack(context, 'Cancelled ${item.name}');
            },
            icon: Icon(Icons.close_rounded, color: colors.text3),
            tooltip: 'Cancel',
          ),
        ],
      ),
    );
  }
}

class _FinishedRow extends ConsumerWidget {
  const _FinishedRow({required this.item});

  final TransferItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final queue = ref.read(transferQueueProvider.notifier);
    final isUpload = item.kind == TransferKind.upload;
    final when = item.row.finishedAt;

    final (String status, Color color) = switch (item.status) {
      TransferStatus.completed => (isUpload ? 'Uploaded' : 'Downloaded', colors.success),
      TransferStatus.failed => (describeTransferError(item.row.error), colors.danger),
      _ => ('Cancelled', colors.text2),
    };
    final openable =
        item.status == TransferStatus.completed && !isUpload && item.row.resultPath != null;

    return InkWell(
      onTap: openable
          ? () => OpenFilex.open(item.row.resultPath!, type: item.row.mimeType)
          : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.gutter, Space.m, Space.xs, Space.m),
        child: Row(
          children: [
            FileIconTile(style: FileStyle.forFile(item.name, item.fileKind), size: 40),
            const SizedBox(width: Space.l),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: status, style: TextStyle(color: color)),
                        TextSpan(
                          text: [
                            '',
                            Formatters.bytes(item.row.totalBytes),
                            if (when != null) Formatters.date(when),
                          ].join(' · '),
                        ),
                      ],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodySmall?.copyWith(fontFeatures: tabularFigures),
                  ),
                ],
              ),
            ),
            if (item.status != TransferStatus.completed)
              IconButton(
                onPressed: () => queue.retry(item.id),
                icon: Icon(Icons.refresh_rounded, color: colors.text2),
                tooltip: 'Retry',
              ),
            IconButton(
              onPressed: () => queue.remove(item.id),
              icon: Icon(Icons.close_rounded, color: colors.text3),
              tooltip: 'Remove from list',
            ),
          ],
        ),
      ),
    );
  }
}
