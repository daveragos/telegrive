import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/format/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../../infrastructure/storage/preferences.dart';
import '../../network/data/mobile_data.dart';
import '../../transfers/data/transfer_queue.dart';
import '../data/backup_controller.dart';

/// Where backup stands, said in one line — on Photos and Transfers. It
/// opens the Backup screen, and carries at most one action: whatever would
/// unblock backup right now.
class BackupStatusLine extends ConsumerWidget {
  const BackupStatusLine({super.key, this.linkToSettings = true});

  final bool linkToSettings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final backup = ref.watch(backupControllerProvider);
    final speed = ref.watch(
      transferQueueProvider.select(
        (s) => s.backupActive.fold<double>(0, (sum, t) => sum + t.bytesPerSecond),
      ),
    );
    final renewDay = ref.watch(mobileDataProvider.select((d) => d.renewDay));
    final status = describeBackup(backup, speed: speed, renewDay: renewDay);

    return StatusLine(
      icon: status.icon,
      color: status.done
          ? colors.success
          : backup.phase == BackupPhase.stopped
          ? colors.danger
          : (backup.isWorking ? colors.accent : null),
      text: status.title,
      detail: status.detail,
      progress: status.progress,
      onTap: linkToSettings ? () => context.push('/backup') : null,
      trailing: _action(context, ref, backup),
    );
  }

  static Widget? _action(BuildContext context, WidgetRef ref, BackupState backup) {
    final controller = ref.read(backupControllerProvider.notifier);
    return switch (backup.phase) {
      BackupPhase.off => TextButton(
        onPressed: () => enableBackup(context, ref),
        child: const Text('Turn on'),
      ),
      BackupPhase.needsPermission => TextButton(
        onPressed: () async {
          if (!await controller.enable()) await PhotoManager.openSetting();
        },
        child: const Text('Allow'),
      ),
      BackupPhase.waitingForWifi => TextButton(
        onPressed: () => controller.setMobileData(BackupMobileData.all),
        child: const Text('Use data'),
      ),
      BackupPhase.waitingForBudget => TextButton(
        onPressed: controller.useDataAnyway,
        child: const Text('Use data anyway'),
      ),
      BackupPhase.stopped => TextButton(
        onPressed: () => controller.schedule(immediate: true),
        child: const Text('Retry'),
      ),
      _ => null,
    };
  }
}

/// The same status, larger, at the top of the Backup screen.
class BackupStatusPanel extends ConsumerWidget {
  const BackupStatusPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final backup = ref.watch(backupControllerProvider);
    final speed = ref.watch(
      transferQueueProvider.select(
        (s) => s.backupActive.fold<double>(0, (sum, t) => sum + t.bytesPerSecond),
      ),
    );
    final renewDay = ref.watch(mobileDataProvider.select((d) => d.renewDay));
    final status = describeBackup(backup, speed: speed, renewDay: renewDay);

    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.s, Space.gutter, Space.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                status.icon,
                size: 22,
                color: status.done
                    ? colors.success
                    : backup.phase == BackupPhase.stopped
                    ? colors.danger
                    : (backup.isWorking ? colors.accent : colors.text2),
              ),
              const SizedBox(width: Space.m),
              Expanded(child: Text(status.title, style: context.text.titleMedium)),
            ],
          ),
          if (status.detail != null) ...[
            const SizedBox(height: Space.xs),
            Padding(
              padding: const EdgeInsets.only(left: 34),
              child: Text(
                status.detail!,
                style: context.text.bodyMedium?.copyWith(fontFeatures: tabularFigures),
              ),
            ),
          ],
          if (status.progress != null) ...[
            const SizedBox(height: Space.m),
            Padding(
              padding: const EdgeInsets.only(left: 34),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: status.progress! < 0 ? null : status.progress,
                  minHeight: 4,
                ),
              ),
            ),
            if (backup.total > 0) ...[
              const SizedBox(height: Space.s),
              Padding(
                padding: const EdgeInsets.only(left: 34),
                child: Text(
                  '${Formatters.number(backup.done)} of ${Formatters.number(backup.total)}',
                  style: context.text.bodySmall?.copyWith(fontFeatures: tabularFigures),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// Turns backup on, explaining a refusal.
Future<void> enableBackup(BuildContext context, WidgetRef ref) async {
  final ok = await ref.read(backupControllerProvider.notifier).enable();
  if (!ok && context.mounted) {
    showSnack(
      context,
      'Backup needs access to your photos.',
      actionLabel: 'Settings',
      onAction: PhotoManager.openSetting,
    );
  }
}

/// Backup state as words. [renewDay] is the day of the month the mobile
/// data limit renews on, which a backup held by the limit waits for.
({IconData icon, String title, String? detail, double? progress, bool done})
describeBackup(BackupState backup, {double speed = 0, int renewDay = 1}) {
  return switch (backup.phase) {
    BackupPhase.off => (
      icon: Icons.cloud_off_outlined,
      title: 'Photo backup is off',
      detail: 'Back up this phone\'s photos and videos to your drive.',
      progress: null,
      done: false,
    ),
    BackupPhase.needsPermission => (
      icon: Icons.no_photography_outlined,
      title: 'Backup can\'t see your photos',
      detail: 'Allow photo access to continue.',
      progress: null,
      done: false,
    ),
    BackupPhase.waitingForDrive => (
      icon: Icons.cloud_queue_rounded,
      title: 'Backup is starting',
      detail: 'Reading your drive first, so nothing goes up twice.',
      progress: null,
      done: false,
    ),
    // Mobile data is for photos only, and they are done.
    BackupPhase.waitingForWifi when backup.heldVideos > 0 => (
      icon: Icons.wifi_off_rounded,
      title: 'Videos wait for Wi-Fi',
      detail: '${Formatters.count(backup.heldVideos, 'video')} left. Photos are backed up.',
      progress: null,
      done: false,
    ),
    BackupPhase.waitingForWifi => (
      icon: Icons.wifi_off_rounded,
      title: 'Waiting for Wi-Fi',
      detail: '${Formatters.count(backup.remaining, 'item')} left. Backup uses Wi-Fi only.',
      progress: null,
      done: false,
    ),
    BackupPhase.waitingForBudget => (
      icon: Icons.data_usage_rounded,
      title: 'Monthly data limit reached',
      detail:
          '${Formatters.count(backup.remaining, 'item')} left. Backup carries on '
          'over Wi-Fi, or on the ${Formatters.dayOfMonth(renewDay)}.',
      progress: null,
      done: false,
    ),
    BackupPhase.scanning => (
      icon: Icons.cloud_sync_outlined,
      title: 'Looking for new photos',
      detail: null,
      progress: -1,
      done: false,
    ),
    BackupPhase.uploading when backup.pausedUntil != null => (
      icon: Icons.hourglass_empty_rounded,
      title: 'Telegram asked us to wait',
      detail: _carriesOn(backup.pausedUntil!, backup.remaining),
      progress: null,
      done: false,
    ),
    BackupPhase.uploading => (
      icon: Icons.cloud_upload_outlined,
      title: 'Backing up photos',
      detail: [
        '${Formatters.count(backup.remaining, 'item')} left',
        if (speed > 0) Formatters.speed(speed),
        if (backup.heldVideos > 0) 'videos wait for Wi-Fi',
      ].join(' · '),
      progress: backup.total == 0 ? -1 : backup.progress,
      done: false,
    ),
    BackupPhase.stopped => (
      icon: Icons.error_outline_rounded,
      title: 'Backup stopped',
      detail: backup.error ?? 'Something went wrong.',
      progress: null,
      done: false,
    ),
    BackupPhase.upToDate => (
      icon: Icons.cloud_done_outlined,
      title: 'Backup is up to date',
      detail: [
        Formatters.count(backup.done, 'item'),
        if (backup.lastCompleted != null)
          'checked ${Formatters.date(backup.lastCompleted!)}',
      ].join(' · '),
      progress: null,
      done: true,
    ),
  };
}

/// When a pass paused for Telegram goes on by itself, with what is left.
String _carriesOn(DateTime until, int remaining) {
  final now = DateTime.now();
  return '${Formatters.count(remaining, 'item')} left. Backup carries on by itself '
      '${DateUtils.isSameDay(until, now) ? 'at' : 'on'} ${Formatters.date(until, now: now)}.';
}
