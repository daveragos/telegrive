import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/format/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../../infrastructure/storage/preferences.dart';
import '../../network/data/mobile_data.dart';
import '../data/backup_controller.dart';
import 'backup_card.dart';
import 'duplicates_sheet.dart';

final _deviceFoldersProvider = FutureProvider.autoDispose<List<DeviceFolder>>(
  (ref) => ref.read(backupControllerProvider.notifier).deviceFolders(),
);

/// Everything about photo backup: where it stands, the switch, and what and
/// when to back up.
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
            const SectionHeader('When'),
            ListGroup(
              children: [
                ListTile(
                  title: const Text('Mobile data'),
                  subtitle: Text(
                    [
                      mobileData.explanation,
                      if (limit != null && mobileData != BackupMobileData.off)
                        'Stays within your ${Formatters.bytes(limit, decimals: 0)} monthly limit.',
                    ].join(' '),
                  ),
                  trailing: PopupMenuButton<BackupMobileData>(
                    initialValue: mobileData,
                    onSelected: (choice) async {
                      await controller.setMobileData(choice);
                      ref.invalidate(preferencesProvider);
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
              'Originals go up in full quality to Files › ${BackupController.rootFolder}, '
              'in a folder named after where they came from on this phone. '
              'Nothing is deleted from your phone.',
              style: context.text.bodySmall,
            ),
          ),
        ],
      ),
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

/// The Mobile data choice, in the words the Backup screen uses.
extension on BackupMobileData {
  String get label => switch (this) {
    BackupMobileData.off => 'Don\'t use',
    BackupMobileData.photos => 'Photos only',
    BackupMobileData.all => 'Photos and videos',
  };

  String get explanation => switch (this) {
    BackupMobileData.off => 'Backup waits for Wi-Fi.',
    BackupMobileData.photos => 'Videos wait for Wi-Fi.',
    BackupMobileData.all => 'Everything goes up on mobile data.',
  };
}
