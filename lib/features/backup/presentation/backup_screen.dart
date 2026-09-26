import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../../infrastructure/storage/preferences.dart';
import '../data/backup_controller.dart';
import 'backup_card.dart';

final _deviceFoldersProvider = FutureProvider.autoDispose<List<DeviceFolder>>(
  (ref) => ref.read(backupControllerProvider.notifier).deviceFolders(),
);

/// Everything about photo backup: status, the switch, and what and when to
/// back up.
class BackupScreen extends ConsumerWidget {
  const BackupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final backup = ref.watch(backupControllerProvider);
    final controller = ref.read(backupControllerProvider.notifier);
    // Settings live in preferences; rebuild whenever backup state moves so
    // the switches below reflect what was just changed.
    final prefs = ref.watch(preferencesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Photo backup')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          const BackupStatusCard(linkToSettings: false),
          const SizedBox(height: 8),
          _Group(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.cloud_upload_outlined),
                title: const Text('Back up photos & videos'),
                subtitle: const Text('New ones back up automatically'),
                value: backup.enabled,
                onChanged: (on) async {
                  if (on) {
                    final ok = await controller.enable();
                    if (!ok && context.mounted) {
                      showSnack(context, 'Photo access is needed to back up.');
                    }
                  } else {
                    final confirmed = await showConfirmDialog(
                      context,
                      title: 'Turn off backup?',
                      message:
                          'Photos already backed up stay in your drive. New '
                          'photos won\'t be backed up until you turn it on again.',
                      confirmLabel: 'Turn off',
                    );
                    if (confirmed) await controller.disable();
                  }
                },
              ),
            ],
          ),
          if (backup.failed > 0) ...[
            const SizedBox(height: 12),
            Card(
              color: scheme.errorContainer.withValues(alpha: 0.6),
              child: ListTile(
                leading: Icon(Icons.error_outline_rounded, color: scheme.onErrorContainer),
                title: Text(
                  '${Formatters.count(backup.failed, 'item')} couldn\'t be backed up',
                  style: TextStyle(color: scheme.onErrorContainer),
                ),
                subtitle: Text(
                  'They were skipped after a few tries.',
                  style: TextStyle(color: scheme.onErrorContainer),
                ),
                trailing: TextButton(
                  onPressed: controller.retryFailed,
                  child: const Text('Retry'),
                ),
              ),
            ),
          ],
          const _Label('What to back up'),
          _Group(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.videocam_outlined),
                title: const Text('Include videos'),
                value: prefs.backupVideos,
                onChanged: (value) async {
                  await controller.setIncludeVideos(value);
                  ref.invalidate(preferencesProvider);
                  ref.invalidate(_deviceFoldersProvider);
                },
              ),
              const Divider(indent: 16, endIndent: 16),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  'Device folders',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Text(
                  'Folders that appear later are included automatically.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              _FolderList(excluded: prefs.backupExcludedFolders),
            ],
          ),
          const _Label('When'),
          _Group(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.signal_cellular_alt_rounded),
                title: const Text('Use mobile data'),
                subtitle: const Text('Otherwise backup waits for Wi-Fi'),
                value: !prefs.backupWifiOnly,
                onChanged: (value) async {
                  await controller.setWifiOnly(!value);
                  ref.invalidate(preferencesProvider);
                },
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, size: 18, color: scheme.onSurfaceVariant),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Originals go up in full quality to My Drive › '
                  '${BackupController.rootFolder}, sorted by the folder they '
                  'came from. Nothing is ever deleted from your phone.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FolderList extends ConsumerWidget {
  const _FolderList({required this.excluded});

  final Set<String> excluded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folders = ref.watch(_deviceFoldersProvider);
    final controller = ref.read(backupControllerProvider.notifier);
    final lowerExcluded = excluded.map((f) => f.toLowerCase()).toSet();

    return switch (folders) {
      AsyncData(:final value) when value.isEmpty => const Padding(
        padding: EdgeInsets.all(16),
        child: Text('No photo folders found, or photo access is off.'),
      ),
      AsyncData(:final value) => Column(
        children: [
          for (final folder in value)
            CheckboxListTile(
              value: !lowerExcluded.contains(folder.name.toLowerCase()),
              title: Text(folder.name),
              subtitle: Text(Formatters.count(folder.count, 'item')),
              controlAffinity: ListTileControlAffinity.trailing,
              onChanged: (included) async {
                await controller.setFolderIncluded(
                  folder.name,
                  included: included ?? true,
                );
                ref.invalidate(preferencesProvider);
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
      AsyncError() => const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Allow photo access to choose folders.'),
      ),
      _ => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
    };
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      SectionHeader(text, padding: const EdgeInsets.fromLTRB(8, 24, 8, 8));
}

class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
  );
}
