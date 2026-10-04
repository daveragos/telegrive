import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/format/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../../infrastructure/notifications/app_notifications.dart';
import '../../../infrastructure/storage/preferences.dart';
import '../../network/data/mobile_data.dart';
import '../data/background_health.dart';
import '../data/backup_controller.dart';
import '../data/backup_worker.dart';
import '../data/phone_folders.dart';
import '../data/watched_folders.dart';
import 'backup_card.dart';
import 'duplicates_sheet.dart';
import 'free_up_space_sheet.dart';
import 'watched_folder_sheets.dart';

final _deviceFoldersProvider = FutureProvider.autoDispose<List<DeviceFolder>>(
  (ref) => ref.read(backupControllerProvider.notifier).deviceFolders(),
);

/// Everything about photo backup: where it stands, the switch, what and
/// when to back up, what happens while the app is closed, and the other
/// phone folders whose new files upload by themselves.
class BackupScreen extends ConsumerWidget {
  const BackupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final backup = ref.watch(backupControllerProvider);
    final controller = ref.read(backupControllerProvider.notifier);
    final prefs = ref.watch(preferencesProvider);
    final mobileData = prefs.backupMobileData;
    final limit = ref.watch(mobileDataProvider.select((d) => d.limit));
    final missing = ref.watch(missingCountProvider).value ?? 0;
    final folders = PhoneFolders.supported;
    final watching =
        folders && (ref.watch(watchedFolderViewsProvider).value?.isNotEmpty ?? false);

    // Photo backup's Mobile data choice governs the watched folders too, so
    // the group shows while either is in use.
    final when = [
      const SectionHeader('When'),
      ListGroup(
        children: [
          ListTile(
            title: const Text('Mobile data'),
            subtitle: Text(
              [
                mobileData.explanation(folders: watching),
                if (limit != null && mobileData != BackupMobileData.off)
                  'Stays within your ${Formatters.bytes(limit, decimals: 0)} monthly limit.',
              ].join(' '),
            ),
            trailing: PopupMenuButton<BackupMobileData>(
              initialValue: mobileData,
              onSelected: (choice) async {
                final watcher = ref.read(watchedFoldersProvider.notifier);
                await controller.setMobileData(choice);
                ref.invalidate(preferencesProvider);
                if (watching) await watcher.followMobileData();
              },
              itemBuilder: (_) => [
                for (final option in BackupMobileData.values)
                  PopupMenuItem(value: option, child: Text(option.label)),
              ],
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(mobileData.label, style: context.text.bodyMedium),
                  Icon(Icons.arrow_drop_down_rounded, color: colors.text3),
                ],
              ),
            ),
          ),
        ],
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Photo backup')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: Space.x4),
        children: [
          const BackupStatusPanel(),
          // Home's "Backup stopped" line opens this screen, so the way to
          // run the pass again is here too, not only back on Home.
          if (backup.phase
              case BackupPhase.off || BackupPhase.needsPermission || BackupPhase.stopped)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.s),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    if (backup.phase == BackupPhase.needsPermission) {
                      if (!await controller.enable()) await PhotoManager.openSetting();
                    } else if (backup.phase == BackupPhase.stopped) {
                      controller.schedule(immediate: true);
                    } else if (context.mounted) {
                      await enableBackup(context, ref);
                    }
                  },
                  child: Text(switch (backup.phase) {
                    BackupPhase.off => 'Turn on backup',
                    BackupPhase.stopped => 'Retry',
                    _ => 'Allow photo access',
                  }),
                ),
              ),
            ),
          if (!backup.enabled) ...[
            if (folders) const _WatchedFolders(),
            if (watching) ...when,
          ],
          const FreeUpSpaceTile(),
          if (backup.failed > 0 || (backup.remaining > 0 && !backup.isWorking)) ...[
            const SizedBox(height: Space.s),
            ListGroup(
              children: [
                if (backup.failed > 0)
                  StatusLine(
                    icon: Icons.error_outline_rounded,
                    color: colors.danger,
                    text: '${Formatters.count(backup.failed, 'item')} didn\'t back up',
                    detail: 'See which ones and why.',
                    onTap: () => context.push('/backup/not-backed-up'),
                  )
                else
                  StatusLine(
                    icon: Icons.schedule_rounded,
                    text: '${Formatters.count(backup.remaining, 'item')} waiting',
                    detail: 'See what\'s left.',
                    onTap: () => context.push('/backup/not-backed-up'),
                  ),
              ],
            ),
          ],
          if (missing > 0) ...[
            const SizedBox(height: Space.s),
            ListGroup(
              children: [
                StatusLine(
                  icon: Icons.cloud_off_outlined,
                  color: colors.danger,
                  text:
                      '${Formatters.count(missing, 'photo')} ${missing == 1 ? 'is' : 'are'} '
                      'no longer in your drive',
                  detail:
                      '${missing == 1 ? 'It was' : 'They were'} removed from the channel '
                      'outside this phone.',
                  trailing: TextButton(
                    onPressed: controller.retryMissing,
                    child: const Text('Back up again'),
                  ),
                ),
              ],
            ),
          ],
          if (backup.enabled) ...[
            const SectionHeader('What to back up'),
            ListGroup(
              children: [
                SwitchListTile(
                  title: const Text('Videos'),
                  subtitle: const Text('Photos are always included'),
                  value: prefs.backupVideos,
                  onChanged: (value) async {
                    await controller.setIncludeVideos(value);
                    ref.invalidate(preferencesProvider);
                    ref.invalidate(_deviceFoldersProvider);
                  },
                ),
                const _FolderList(),
              ],
            ),
            ...when,
            const _WhileClosed(),
            if (folders) const _WatchedFolders(),
            const SizedBox(height: Space.xxl),
            const DuplicateBackupsTile(),
            const SizedBox(height: Space.m),
            ListGroup(
              children: [
                ListTile(
                  title: Text(
                    'Turn off backup',
                    style: context.text.bodyLarge?.copyWith(color: colors.danger),
                  ),
                  onTap: () async {
                    final confirmed = await showConfirmDialog(
                      context,
                      title: 'Turn off backup?',
                      message:
                          'Photos already backed up stay in your drive. New '
                          'ones won\'t be, until you turn it back on.',
                      confirmLabel: 'Turn off',
                      destructive: true,
                    );
                    if (confirmed) await controller.disable();
                  },
                ),
              ],
            ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.gutter, Space.xxl, Space.gutter, 0),
            child: Text(
              [
                'Originals go up in full quality to Files › ${BackupController.rootFolder}, '
                    'in a folder named after where they came from on this phone. '
                    'Nothing is deleted from your phone.',
                if (folders)
                  'Files from other folders go to Files › ${WatchedFoldersController.rootFolder} '
                      'unless you pick a drive folder. Telegrive checks them when it opens '
                      'and while it runs. This list stays on this phone.',
              ].join(' '),
              style: context.text.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// Backup with the app closed: the switch that lets it run on its own and
/// when it last did, whether Android is letting the checks for new photos
/// run, with Fix when it isn't, and only when they need it, battery saver
/// and notifications, each with the way to put it right.
class _WhileClosed extends ConsumerWidget {
  const _WhileClosed();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final prefs = ref.watch(preferencesProvider);
    final unattended = prefs.backupUnattended;
    final health = ref.watch(backgroundHealthProvider).value;
    final lastRun = health?.lastRun ?? prefs.backgroundRun;
    final uploaded = health?.lastUploaded ?? prefs.backgroundUploaded;
    final checked = health?.lastChecked;
    void recheck() => ref.invalidate(backgroundHealthProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('While the app is closed'),
        ListGroup(
          children: [
            SwitchListTile(
              title: const Text('Back up on its own'),
              subtitle: Text(
                prefs.backupMobileData == BackupMobileData.off
                    ? 'When the phone is charging and on Wi-Fi.'
                    : 'When the phone is charging.',
              ),
              value: unattended,
              onChanged: (on) async {
                await ref.read(backupControllerProvider.notifier).setUnattended(on);
                ref.invalidate(preferencesProvider);
                recheck();
              },
            ),
            if (unattended)
              StatusLine(
                icon: Icons.history_rounded,
                text: lastRun == null
                    ? 'Hasn\'t run yet'
                    : 'Last ran ${Formatters.date(lastRun)} · ${Formatters.count(uploaded, 'item')}',
                detail: 'Checks new photos as they arrive. Looks through everything once a day.',
              ),
            if (health != null) ...[
              if (health.needsAttention(true))
                StatusLine(
                  icon: Icons.error_outline_rounded,
                  color: colors.danger,
                  text: 'Not watching for new photos',
                  detail: checked == null
                      ? null
                      : 'Last checked in the background · ${Formatters.date(checked)}',
                  trailing: TextButton(
                    onPressed: () async {
                      await BackupWorker.schedule();
                      recheck();
                    },
                    child: const Text('Fix'),
                  ),
                )
              else
                StatusLine(
                  icon: Icons.check_circle_outline_rounded,
                  color: colors.success,
                  text: 'Watching for new photos',
                  detail: checked == null
                      ? null
                      : 'Last checked in the background · ${Formatters.date(checked)}',
                ),
              if (!health.batteryOk)
                StatusLine(
                  icon: Icons.battery_alert_outlined,
                  text: 'Battery saver may stop backup',
                  detail: 'Set Telegrive to Unrestricted in battery settings.',
                  trailing: TextButton(
                    onPressed: () async {
                      await BatterySettings.open();
                      recheck();
                    },
                    child: const Text('Open'),
                  ),
                ),
              if (!health.notificationsOk)
                StatusLine(
                  icon: Icons.notifications_off_outlined,
                  text: 'Notifications are off',
                  detail: 'You won\'t hear about new photos waiting.',
                  trailing: TextButton(
                    onPressed: () async {
                      await AppNotifications.openSettings();
                      recheck();
                    },
                    child: const Text('Turn on'),
                  ),
                ),
            ],
          ],
        ),
      ],
    );
  }
}

class _FolderList extends ConsumerWidget {
  const _FolderList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final folders = ref.watch(_deviceFoldersProvider);
    // Rebuilds the rows once a choice is saved and the preferences reloaded.
    ref.watch(preferencesProvider);
    final controller = ref.read(backupControllerProvider.notifier);

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.l, Space.gutter, Space.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Folders on this phone', style: context.text.titleSmall),
          const SizedBox(height: 2),
          Text('New folders are backed up and shown in Photos.', style: context.text.bodySmall),
        ],
      ),
    );

    return switch (folders) {
      AsyncData(:final value) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          if (value.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.gutter, Space.s, Space.gutter, Space.l),
              child: Text('No photo folders found.', style: context.text.bodyMedium),
            ),
          for (final (folder, mode) in [
            for (final folder in value) (folder, controller.modeOf(folder.name)),
          ])
            ListTile(
              title: Text(folder.name),
              subtitle: Text(
                Formatters.count(folder.count, 'item'),
                style: context.text.bodySmall?.copyWith(fontFeatures: tabularFigures),
              ),
              trailing: PopupMenuButton<FolderBackupMode>(
                initialValue: mode,
                onSelected: (choice) async {
                  await controller.setFolderMode(folder.name, choice);
                  ref.invalidate(preferencesProvider);
                },
                itemBuilder: (_) => [
                  for (final option in FolderBackupMode.values)
                    PopupMenuItem(value: option, child: Text(option.label)),
                ],
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(mode.shortLabel, style: context.text.bodyMedium),
                    Icon(Icons.arrow_drop_down_rounded, color: colors.text3),
                  ],
                ),
              ),
            ),
          if (value.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.gutter, Space.xs, Space.gutter, 0),
              child: Text(
                'Kept-out folders still back up and stay in Files and Search. '
                'This choice is kept on this phone only.',
                style: context.text.bodySmall,
              ),
            ),
          const SizedBox(height: Space.s),
        ],
      ),
      AsyncError() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.gutter, Space.s, Space.gutter, Space.l),
            child: Text('Allow photo access to choose folders.', style: context.text.bodyMedium),
          ),
        ],
      ),
      _ => const Padding(
        padding: EdgeInsets.all(Space.xxl),
        child: Center(child: CircularProgressIndicator()),
      ),
    };
  }
}

/// The other folders on this phone whose new files upload by themselves,
/// one row each, and the way to add one.
class _WatchedFolders extends ConsumerWidget {
  const _WatchedFolders();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Other folders on this phone'),
        AsyncView<List<WatchedFolderView>>(
          value: ref.watch(watchedFolderViewsProvider),
          data: (views) => AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: ListGroup(
              children: [
                for (final view in views) _WatchedFolderRow(view, key: ValueKey(view.row.id)),
                ListTile(
                  leading: Icon(Icons.add_rounded, color: colors.text2),
                  title: const Text('Add a folder'),
                  subtitle: views.isEmpty
                      ? const Text(
                          'New files in it upload by themselves, like Recordings or '
                          'Download › Bank.',
                        )
                      : null,
                  onTap: () => showAddWatchedFolder(context, ref),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _WatchedFolderRow extends ConsumerWidget {
  const _WatchedFolderRow(this.view, {super.key});

  final WatchedFolderView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final status = view.status;
    void open() => showWatchedFolderSheet(context, ref, view);

    switch (status.phase) {
      case RulePhase.noAccess:
        return StatusLine(
          icon: Icons.error_outline_rounded,
          color: colors.danger,
          text: view.row.label,
          detail: 'Telegrive can\'t read this folder any more.',
          trailing: TextButton(
            onPressed: () => chooseWatchedFolderAgain(context, ref, view),
            child: const Text('Choose again'),
          ),
          onTap: open,
        );
      case RulePhase.waitingForWifi:
        return StatusLine(
          icon: Icons.folder_outlined,
          text: view.row.label,
          detail: status.waiting == 1
              ? '1 file waits for Wi-Fi.'
              : '${Formatters.count(status.waiting, 'file')} wait for Wi-Fi.',
          trailing: TextButton(
            onPressed: () async {
              await ref.read(watchedFoldersProvider.notifier).useMobileData();
              ref.invalidate(preferencesProvider);
            },
            child: const Text('Use data'),
          ),
          onTap: open,
        );
      case RulePhase.uploading:
        final going = math.min(status.done + 1, status.total);
        return TweenAnimationBuilder<double>(
          tween: Tween(end: status.progress),
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          builder: (context, progress, _) => StatusLine(
            icon: Icons.folder_outlined,
            text: view.row.label,
            detail: [
              'Uploading ${Formatters.number(going)} of ${Formatters.number(status.total)}',
              ?status.current,
            ].join(' · '),
            progress: progress,
            onTap: open,
          ),
        );
      case RulePhase.idle || RulePhase.checking:
        final checked = view.row.checkedAt;
        return StatusLine(
          icon: Icons.folder_outlined,
          text: view.row.label,
          detail: checked == null
              ? 'Not checked yet'
              : [
                  '${Formatters.number(view.uploadedCount)} uploaded to ${view.destinationLabel} · '
                      'checked ${Formatters.date(checked)}',
                  if (status.truncated)
                    'Only the first ${Formatters.number(PhoneFolders.listLimit)} files are checked.',
                ].join('. '),
          onTap: open,
        );
    }
  }
}

/// The Mobile data choice, in the words the Backup screen uses.
extension on BackupMobileData {
  String get label => switch (this) {
    BackupMobileData.off => 'Don\'t use',
    BackupMobileData.photos => 'Photos only',
    BackupMobileData.all => 'Photos and videos',
  };

  /// What the choice means, naming the files from other [folders] where
  /// it treats them apart from photos.
  String explanation({required bool folders}) => switch (this) {
    BackupMobileData.off => 'Uploads wait for Wi-Fi.',
    BackupMobileData.photos =>
      folders ? 'Videos and files from other folders wait for Wi-Fi.' : 'Videos wait for Wi-Fi.',
    BackupMobileData.all => 'Everything goes up on mobile data.',
  };
}
