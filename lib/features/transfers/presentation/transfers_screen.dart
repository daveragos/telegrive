import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';

import '../../../app/theme/file_style.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/format/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/file_visuals.dart';
import '../../../infrastructure/database/app_database.dart';
import '../../backup/data/backup_controller.dart';
import '../../backup/presentation/backup_card.dart';
import '../data/transfer_queue.dart';

class TransfersScreen extends ConsumerWidget {
  const TransfersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(transferQueueProvider);
    // Photo backup is summarised in one line rather than listed photo by photo.
    final active = state.active
        .where((t) => t.origin == TransferOrigin.manual)
        .toList();
    final finished = state.finished;
    final backingUp = ref.watch(backupControllerProvider.select((b) => b.isWorking));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transfers'),
        actions: [
          if (finished.isNotEmpty)
            TextButton(
              onPressed: () => ref.read(transferQueueProvider.notifier).clearFinished(),
              child: const Text('Clear finished'),
            ),
          const SizedBox(width: Space.s),
        ],
      ),
      body: active.isEmpty && finished.isEmpty && !backingUp
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
