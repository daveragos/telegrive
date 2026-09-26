import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';

import '../../../app/theme/file_style.dart';
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
    // Photo backup is summarised in one card rather than listed photo by photo.
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
              onPressed: () =>
                  ref.read(transferQueueProvider.notifier).clearFinished(),
              child: const Text('Clear finished'),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: active.isEmpty && finished.isEmpty && !backingUp
          ? const EmptyState(
              icon: Icons.swap_vert_rounded,
              title: 'No transfers',
              message:
                  'Uploads and downloads show up here, with their progress and speed.',
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                if (backingUp) ...[
                  const SectionHeader('Photo backup'),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: BackupStatusCard(),
                  ),
                ],
                if (active.isNotEmpty) ...[
                  SectionHeader('In progress · ${active.length}'),
                  for (final item in active) _ActiveCard(item: item),
                ],
                if (finished.isNotEmpty) ...[
                  const SectionHeader('Finished'),
                  for (final item in finished) _FinishedTile(item: item),
                ],
              ],
            ),
    );
  }
}

class _ActiveCard extends ConsumerWidget {
  const _ActiveCard({required this.item});

  final TransferItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isUpload = item.kind == TransferKind.upload;
    final queued = item.status == TransferStatus.queued;
    final eta = item.eta;

    final String detail;
    if (item.preparing) {
      detail = 'Preparing file…';
    } else if (queued) {
      detail = 'Waiting · ${Formatters.bytes(item.row.totalBytes)}';
    } else {
      detail = [
        '${Formatters.bytes(item.row.doneBytes)} of ${Formatters.bytes(item.row.totalBytes)}',
        if (item.bytesPerSecond > 0) Formatters.speed(item.bytesPerSecond),
        ?(eta == null ? null : Formatters.eta(eta)),
      ].join(' · ');
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 14),
          child: Column(
            children: [
              Row(
                children: [
                  FileIconTile(
                    style: FileStyle.forFile(item.name, item.fileKind),
                    size: 42,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(
                              isUpload
                                  ? Icons.arrow_upward_rounded
                                  : Icons.arrow_downward_rounded,
                              size: 14,
                              color: scheme.primary,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                detail,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () =>
                        ref.read(transferQueueProvider.notifier).cancel(item.id),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Cancel',
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: item.progress),
                    duration: const Duration(milliseconds: 300),
                    builder: (context, value, _) => LinearProgressIndicator(
                      value: item.preparing ? null : value,
                      minHeight: 6,
                    ),
                  ),
                ),
              ),
              if (item.row.partCount > 1) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Row(
                    children: [
                      Icon(Icons.call_split_rounded, size: 14, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 6),
                      Text(
                        'Part ${(item.row.completedParts + 1).clamp(1, item.row.partCount)} of ${item.row.partCount}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FinishedTile extends ConsumerWidget {
  const _FinishedTile({required this.item});

  final TransferItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final queue = ref.read(transferQueueProvider.notifier);
    final isUpload = item.kind == TransferKind.upload;

    final (IconData icon, Color color, String status) = switch (item.status) {
      TransferStatus.completed => (
        Icons.check_circle_rounded,
        const Color(0xFF1FA971),
        isUpload ? 'Uploaded' : 'Downloaded',
      ),
      TransferStatus.failed => (
        Icons.error_rounded,
        scheme.error,
        item.row.error ?? 'Failed',
      ),
      _ => (Icons.cancel_rounded, scheme.onSurfaceVariant, 'Cancelled'),
    };
    final when = item.row.finishedAt;

    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(24, 2, 8, 2),
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          FileIconTile(style: FileStyle.forFile(item.name, item.fileKind), size: 40),
          Positioned(
            right: -4,
            bottom: -4,
            child: DecoratedBox(
              decoration: BoxDecoration(color: scheme.surface, shape: BoxShape.circle),
              child: Icon(icon, size: 18, color: color),
            ),
          ),
        ],
      ),
      title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          status,
          Formatters.bytes(item.row.totalBytes),
          if (when != null) Formatters.date(when),
        ].join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: item.status == TransferStatus.failed ? scheme.error : scheme.onSurfaceVariant,
        ),
      ),
      onTap: item.status == TransferStatus.completed && !isUpload && item.row.resultPath != null
          ? () => OpenFilex.open(item.row.resultPath!, type: item.row.mimeType)
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (item.status != TransferStatus.completed)
            IconButton(
              onPressed: () => queue.retry(item.id),
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Retry',
            ),
          IconButton(
            onPressed: () => queue.remove(item.id),
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Remove from list',
          ),
        ],
      ),
    );
  }
}
