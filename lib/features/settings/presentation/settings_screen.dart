import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_config.dart';
import '../../../core/format/formatters.dart';
import '../../../core/widgets/brand_mark.dart';
import '../../../core/widgets/common.dart';
import '../../../infrastructure/storage/preferences.dart';
import '../../auth/data/auth_controller.dart';
import '../../backup/data/backup_controller.dart';
import '../../drive/data/drive_repository.dart';
import '../../drive/data/drive_session.dart';
import '../../drive/data/drive_sync.dart';
import '../../files/data/browse_preferences.dart';
import '../../transfers/data/transfer_queue.dart';
import '../data/settings_providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final session = ref.watch(driveSessionProvider);
    final backup = ref.watch(backupControllerProvider);
    final sync = ref.watch(driveSyncProvider);
    final summary = ref.watch(storageSummaryProvider).value;
    final themeMode = ref.watch(themeModeProvider);
    final viewMode = ref.watch(
      browsePreferencesProvider.select((p) => p.viewMode),
    );
    final cache = ref.watch(cacheSizeProvider);
    final busyTransfers =
        ref.watch(transferQueueProvider.select((s) => s.activeCount)) > 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          if (session != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: scheme.primaryContainer,
                      child: Text(
                        session.initials,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  session.displayName.isEmpty
                                      ? 'Telegram account'
                                      : session.displayName,
                                  style: theme.textTheme.titleMedium,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (session.isPremium) ...[
                                const SizedBox(width: 6),
                                Icon(
                                  Icons.workspace_premium_rounded,
                                  size: 18,
                                  color: Colors.purple.shade300,
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            [
                              if (session.phoneNumber.isNotEmpty)
                                '+${session.phoneNumber}',
                              if (session.username != null)
                                '@${session.username}',
                            ].join(' · '),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const _GroupLabel('Drive'),
          _Group(
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Photo backup'),
                subtitle: Text(switch (backup.phase) {
                  BackupPhase.off => 'Off',
                  BackupPhase.upToDate => 'On · up to date',
                  BackupPhase.uploading =>
                    'On · ${Formatters.count(backup.remaining, 'item')} left',
                  BackupPhase.waitingForWifi => 'On · waiting for Wi-Fi',
                  BackupPhase.needsPermission => 'Needs photo access',
                  _ => 'On',
                }),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push('/backup'),
              ),
              ListTile(
                leading: const Icon(Icons.telegram),
                title: Text(session?.channelTitle ?? 'Storage channel'),
                subtitle: const Text('Private channel that holds your files'),
                trailing: const Icon(Icons.open_in_new_rounded, size: 20),
                onTap: session == null
                    ? null
                    : () {
                        // Private channels only have post links; the newest
                        // indexed post lands on the latest files.
                        final latest = ref
                            .read(preferencesProvider)
                            .lastSyncedMessageId(session.chatId);
                        final post = latest > 0 ? latest >> 20 : 1;
                        launchUrl(
                          Uri.parse(
                            'https://t.me/c/${-session.chatId - 1000000000000}/$post',
                          ),
                          mode: LaunchMode.externalApplication,
                        );
                      },
              ),
              ListTile(
                leading: const Icon(Icons.pie_chart_outline_rounded),
                title: const Text('Stored in Telegram'),
                subtitle: Text(
                  summary == null
                      ? '…'
                      : '${Formatters.bytes(summary.bytes)} in ${Formatters.count(summary.fileCount, 'file')}',
                ),
              ),
              ListTile(
                leading: sync.running
                    ? const SizedBox.square(
                        dimension: 24,
                        child: Padding(
                          padding: EdgeInsets.all(2),
                          child: CircularProgressIndicator(strokeWidth: 2.4),
                        ),
                      )
                    : const Icon(Icons.sync_rounded),
                title: const Text('Rebuild index'),
                subtitle: Text(
                  sync.running
                      ? 'Reading your channel · ${Formatters.count(sync.scanned, 'item')}'
                      : sync.error ??
                            (sync.lastSynced == null
                                ? 'Re-read everything from Telegram'
                                : 'Last synced ${Formatters.date(sync.lastSynced!)}'),
                ),
                onTap: sync.running
                    ? null
                    : () => ref.read(driveSyncProvider.notifier).rebuildIndex(),
              ),
            ],
          ),
          const _GroupLabel('Appearance'),
          _Group(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Theme', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<ThemeMode>(
                        segments: const [
                          ButtonSegment(
                            value: ThemeMode.system,
                            icon: Icon(Icons.brightness_auto_rounded),
                            label: Text('Auto'),
                          ),
                          ButtonSegment(
                            value: ThemeMode.light,
                            icon: Icon(Icons.light_mode_rounded),
                            label: Text('Light'),
                          ),
                          ButtonSegment(
                            value: ThemeMode.dark,
                            icon: Icon(Icons.dark_mode_rounded),
                            label: Text('Dark'),
                          ),
                        ],
                        selected: {themeMode},
                        showSelectedIcon: false,
                        onSelectionChanged: (value) => ref
                            .read(themeModeProvider.notifier)
                            .set(value.first),
                      ),
                    ),
                  ],
                ),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.grid_view_rounded),
                title: const Text('Show files as a grid'),
                value: viewMode == ViewMode.grid,
                onChanged: (_) => ref
                    .read(browsePreferencesProvider.notifier)
                    .toggleViewMode(),
              ),
            ],
          ),
          const _GroupLabel('This device'),
          _Group(
            children: [
              ListTile(
                leading: const Icon(Icons.cleaning_services_outlined),
                title: const Text('Clear downloaded copies'),
                subtitle: Text(
                  busyTransfers
                      ? 'Wait for transfers to finish'
                      : switch (cache) {
                          AsyncData(:final value) =>
                            '${Formatters.bytes(value)} used on this device',
                          _ => 'Calculating…',
                        },
                ),
                enabled: !busyTransfers,
                onTap: () async {
                  final ok = await showConfirmDialog(
                    context,
                    title: 'Clear downloaded copies?',
                    message: 'Files stay safe in Telegram — they\'ll download again when you open them.',
                    confirmLabel: 'Clear',
                  );
                  if (!ok) return;
                  try {
                    await clearLocalCache(ref);
                    if (context.mounted) showSnack(context, 'Cleared');
                  } catch (e) {
                    if (context.mounted) {
                      showSnack(context, 'Couldn\'t clear: $e');
                    }
                  }
                },
              ),
            ],
          ),
          const _GroupLabel('About'),
          _Group(
            children: [
              ListTile(
                leading: const Icon(Icons.help_outline_rounded),
                title: const Text('How Telegrive works'),
                onTap: () => _showHowItWorks(context),
              ),
              ListTile(
                leading: const Icon(Icons.info_outline_rounded),
                title: const Text('Version'),
                subtitle: const Text(AppConfig.appVersion),
                onTap: () => showAboutDialog(
                  context: context,
                  applicationName: AppConfig.appName,
                  applicationVersion: AppConfig.appVersion,
                  applicationIcon: const BrandMark(size: 48),
                  applicationLegalese: 'Independent app, not affiliated with Telegram. Built on TDLib.',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: scheme.error,
              side: BorderSide(color: scheme.error.withValues(alpha: 0.4)),
            ),
            onPressed: () async {
              final ok = await showConfirmDialog(
                context,
                title: 'Sign out?',
                message: 'Your files stay in your Telegram channel. Sign back in any time to get them all back.',
                confirmLabel: 'Sign out',
                destructive: true,
                icon: Icons.logout_rounded,
              );
              if (ok) await ref.read(authControllerProvider.notifier).signOut();
            },
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Sign out'),
          ),
        ],
      ),
    );
  }

  void _showHowItWorks(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (context) {
        final theme = Theme.of(context);
        Widget point(IconData icon, String title, String body) => Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: theme.colorScheme.primary),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      body,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('How Telegrive works', style: theme.textTheme.titleLarge),
                const SizedBox(height: 20),
                point(
                  Icons.telegram,
                  'A private channel is your disk',
                  'Each file is a message in a channel only you can see. Telegram '
                      'stores it for free, with no total limit.',
                ),
                point(
                  Icons.label_outline_rounded,
                  'Captions carry the details',
                  'Name, folder and star live in each message\'s caption, so your '
                      'whole drive can be rebuilt from Telegram on any device.',
                ),
                point(
                  Icons.call_split_rounded,
                  'Big files are split',
                  'Telegram caps a message at 2 GB (4 GB with Premium). Larger '
                      'files are stored as numbered parts and joined on download.',
                ),
                point(
                  Icons.forward_rounded,
                  'Forward to add',
                  'Forward any file into the channel from Telegram and it appears '
                      'in your drive — nothing is uploaded again.',
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) =>
      SectionHeader(label, padding: const EdgeInsets.fromLTRB(8, 24, 8, 8));
}

class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(child: Column(children: children));
}
