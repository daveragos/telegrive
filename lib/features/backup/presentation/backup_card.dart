import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../core/format/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../transfers/data/transfer_queue.dart';
import '../data/backup_controller.dart';

/// Where backup stands, in one glance — the same card on Home, Photos and
/// the Backup screen. Tapping it opens the Backup screen (unless it *is*
/// the Backup screen).
class BackupStatusCard extends ConsumerWidget {
  const BackupStatusCard({super.key, this.onDismiss, this.linkToSettings = true});

  /// Shown as "Not now" while backup is off (Home uses it).
  final VoidCallback? onDismiss;
  final bool linkToSettings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final backup = ref.watch(backupControllerProvider);
    final controller = ref.read(backupControllerProvider.notifier);
    final speed = ref.watch(
      transferQueueProvider.select(
        (s) => s.backupActive.fold<double>(0, (sum, t) => sum + t.bytesPerSecond),
      ),
    );

    final (IconData icon, Color tint, String title, String? body) = switch (backup.phase) {
      BackupPhase.off => (
        Icons.cloud_upload_outlined,
        scheme.primary,
        'Back up your photos',
        'Keep every photo and video safe in Telegram, in full quality, '
            'with no storage limit.',
      ),
      BackupPhase.needsPermission => (
        Icons.no_photography_outlined,
        scheme.error,
        'Allow photo access',
        'Telegrive needs access to your photos and videos to back them up.',
      ),
      BackupPhase.waitingForDrive => (
        Icons.cloud_sync_outlined,
        scheme.primary,
        'Getting ready',
        'Backup starts as soon as your drive is open.',
      ),
      BackupPhase.waitingForWifi => (
        Icons.wifi_off_rounded,
        scheme.tertiary,
        'Waiting for Wi-Fi',
        '${Formatters.count(backup.remaining, 'item')} to back up. '
            'Backup is set to use Wi-Fi only.',
      ),
      BackupPhase.scanning => (
        Icons.manage_search_rounded,
        scheme.primary,
        'Checking for new photos',
        null,
      ),
      BackupPhase.uploading => (
        Icons.cloud_upload_rounded,
        scheme.primary,
        'Backing up · ${Formatters.count(backup.remaining, 'item')} left',
        [
          if (backup.current != null) backup.current!,
          if (speed > 0) Formatters.speed(speed),
        ].join(' · '),
      ),
      BackupPhase.upToDate => (
        Icons.cloud_done_rounded,
        const Color(0xFF1FA971),
        'Backup complete',
        [
          '${Formatters.count(backup.done, 'item')} backed up',
          if (backup.lastCompleted != null)
            'checked ${Formatters.date(backup.lastCompleted!)}',
        ].join(' · '),
      ),
    };

    final action = switch (backup.phase) {
      BackupPhase.off => FilledButton(
        style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
        onPressed: () async {
          final ok = await controller.enable();
          if (!ok && context.mounted) {
            showSnack(
              context,
              'Photo access is needed to back up.',
              actionLabel: 'Settings',
              onAction: PhotoManager.openSetting,
            );
          }
        },
        child: const Text('Turn on backup'),
      ),
      BackupPhase.needsPermission => FilledButton(
        style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
        onPressed: () async {
          final ok = await controller.enable();
          if (!ok) await PhotoManager.openSetting();
        },
        child: const Text('Allow access'),
      ),
      BackupPhase.waitingForWifi => FilledButton.tonal(
        style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
        onPressed: () => controller.setWifiOnly(false),
        child: const Text('Use mobile data'),
      ),
      _ => null,
    };

    return Card(
      child: InkWell(
        onTap: linkToSettings ? () => context.push('/backup') : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: tint.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, color: tint),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: theme.textTheme.titleMedium),
                        if (body != null && body.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            body,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (linkToSettings)
                    Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
                ],
              ),
              if (backup.isWorking) ...[
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: backup.phase == BackupPhase.scanning || backup.total == 0
                        ? null
                        : backup.progress,
                    minHeight: 6,
                  ),
                ),
                if (backup.total > 0) ...[
                  const SizedBox(height: 6),
                  Text(
                    '${Formatters.number(backup.done)} of '
                    '${Formatters.number(backup.total)}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
              if (action != null || (onDismiss != null && !backup.enabled)) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    const SizedBox(width: 58),
                    ?action,
                    if (onDismiss != null && !backup.enabled) ...[
                      const SizedBox(width: 8),
                      TextButton(onPressed: onDismiss, child: const Text('Not now')),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
