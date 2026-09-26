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
import '../data/transfer_queue.dart';

class TransfersScreen extends ConsumerWidget {
  const TransfersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(transferQueueProvider);
    // Photo backup and downloads to the phone are summarised in a line each
    // rather than listed file by file; only their failures are listed.
    final active = state.active
        .where((t) => t.origin == TransferOrigin.manual)
        .toList();
    final saves = state.saves;
    final finished = state.finished
        .where(
          (t) => !(t.origin == TransferOrigin.save && t.status == TransferStatus.completed),
        )
        .toList();
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
      body: active.isEmpty && finished.isEmpty && saves.isEmpty && !backingUp
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
                if (active.isNotEmpty) ...[
                  SectionHeader('In progress · ${active.length}'),
                  ListGroup(children: [for (final item in active) _ActiveRow(item: item)]),
                ],
                if (finished.isNotEmpty) ...[
                  const SectionHeader('Finished'),
                  ListGroup(children: [for (final item in finished) _FinishedRow(item: item)]),
                ],
              ],
            ),
    );
  }
}

/// Every download to this phone as one line: how far along, or where it
/// all went once done.
class _SaveGroup extends ConsumerWidget {
  const _SaveGroup({required this.saves});

  final List<TransferItem> saves;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final running = saves.where((t) => t.status.isActive).toList();
    final saved = saves.where((t) => t.status == TransferStatus.completed).toList();
    final total = saves.where((t) => t.status != TransferStatus.cancelled).length;
    final toGallery = saves.any((t) => t.row.saveTo == SaveTarget.gallery);
    final toFiles = saves.any((t) => t.row.saveTo == SaveTarget.files);
    final where = [
      if (toFiles) DeviceStorage.location,
      if (toGallery) 'your photos',
    ].join(' and ');

    if (running.isEmpty) {
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
    for (final item in [...running, ...saved]) {
      bytes += item.row.totalBytes;
      done += item.status == TransferStatus.completed ? item.row.totalBytes : item.row.doneBytes;
      speed += item.bytesPerSecond;
    }
    final left = bytes - done;
    return StatusLine(
      icon: Icons.download_rounded,
      color: colors.accent,
      text: '${Formatters.number(saved.length)} of ${Formatters.count(total, 'file')} saved',
      detail: speed < 1
          ? '${Formatters.bytes(left)} left'
          : [
              Formatters.bytes(left),
              Formatters.speed(speed),
              Formatters.eta(Duration(seconds: (left / speed).ceil())),
            ].join(' · '),
      progress: bytes == 0 ? 0 : done / bytes,
      trailing: TextButton(
        onPressed: () async {
          final stop = await showConfirmDialog(
            context,
            title: 'Stop downloading?',
            message: 'Files already saved stay on this phone.',
            confirmLabel: 'Stop',
          );
          if (stop) await ref.read(transferQueueProvider.notifier).cancelSaves();
        },
        child: const Text('Stop'),
      ),
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
    final eta = item.eta;
    final parts = item.row.partCount > 1
        ? 'part ${(item.row.completedParts + 1).clamp(1, item.row.partCount)} '
              'of ${item.row.partCount}'
        : null;

    final String detail;
    if (item.preparing) {
      detail = 'Preparing the file';
    } else if (queued) {
      detail = 'Waiting · ${Formatters.bytes(item.row.totalBytes)}';
    } else {
      detail = [
        '${Formatters.bytes(item.row.doneBytes)} of ${Formatters.bytes(item.row.totalBytes)}',
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
                      child: Text(
                        detail,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.bodySmall?.copyWith(fontFeatures: tabularFigures),
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
                    ),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => ref.read(transferQueueProvider.notifier).cancel(item.id),
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
      TransferStatus.failed => (item.row.error ?? 'Failed', colors.danger),
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
