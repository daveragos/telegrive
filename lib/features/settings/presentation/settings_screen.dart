import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/config/app_config.dart';
import '../../../core/format/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../../infrastructure/storage/preferences.dart';
import '../../auth/data/auth_controller.dart';
import '../../backup/data/backup_controller.dart';
import '../../drive/data/drive_repository.dart';
import '../../drive/data/drive_session.dart';
import '../../drive/data/drive_sync.dart';
import '../../files/data/browse_preferences.dart';
import '../../files/presentation/file_actions.dart';
import '../../transfers/data/transfer_queue.dart';
import '../data/settings_providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final session = ref.watch(driveSessionProvider);
    final backup = ref.watch(backupControllerProvider);
    final sync = ref.watch(driveSyncProvider);
    final summary = ref.watch(storageSummaryProvider).value;
    final themeMode = ref.watch(themeModeProvider);
    final viewMode = ref.watch(browsePreferencesProvider.select((p) => p.viewMode));
    final cache = ref.watch(cacheSizeProvider);
    final busyTransfers = ref.watch(transferQueueProvider.select((s) => s.activeCount)) > 0;

    Text trailingValue(String value) => Text(
      value,
      style: context.text.bodyMedium?.copyWith(fontFeatures: tabularFigures),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: Space.x4),
        children: [
          if (session != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.gutter, Space.s, Space.gutter, Space.s),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: colors.surface2,
                    child: Text(
                      session.initials,
                      style: context.text.titleSmall?.copyWith(color: colors.text),
                    ),
                  ),
                  const SizedBox(width: Space.l),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          session.displayName.isEmpty
                              ? 'Telegram account'
                              : session.displayName,
                          style: context.text.titleMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          [
                            if (session.phoneNumber.isNotEmpty) '+${session.phoneNumber}',
                            if (session.username != null) '@${session.username}',
                            if (session.isPremium) 'Premium',
                          ].join(' · '),
                          style: context.text.bodyMedium?.copyWith(fontFeatures: tabularFigures),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SectionHeader('Drive'),
          ListGroup(
            children: [
              ListTile(
                title: const Text('Photo backup'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    trailingValue(switch (backup.phase) {
                      BackupPhase.off => 'Off',
                      BackupPhase.upToDate => 'Up to date',
                      BackupPhase.uploading =>
                        '${Formatters.number(backup.remaining)} left',
                      BackupPhase.waitingForWifi => 'Waiting for Wi-Fi',
                      BackupPhase.needsPermission => 'Needs access',
                      _ => 'On',
                    }),
                    Icon(Icons.chevron_right_rounded, color: colors.text3),
                  ],
                ),
                onTap: () => context.push('/backup'),
              ),
              ListTile(
                title: const Text('Transfers'),
                trailing: Icon(Icons.chevron_right_rounded, color: colors.text3),
                onTap: () => context.push('/transfers'),
              ),
              ListTile(
                title: const Text('Stored in Telegram'),
                trailing: trailingValue(
                  summary == null
                      ? ''
                      : '${Formatters.bytes(summary.bytes)} · '
                            '${Formatters.count(summary.fileCount, 'file')}',
                ),
              ),
              ListTile(
                title: const Text('Download everything'),
                subtitle: const Text('Every file, onto this phone'),
                trailing: Icon(Icons.download_rounded, size: 20, color: colors.text3),
                onTap: summary == null || summary.fileCount == 0
                    ? null
                    : () => FileActions.saveToDevice(
                        context,
                        ref,
                        everything: true,
                        preferGallery: true,
                      ),
              ),
              ListTile(
                title: Text(session?.channelTitle ?? 'Drive channel'),
                subtitle: const Text('The private channel that holds your files'),
                trailing: Icon(Icons.open_in_new_rounded, size: 20, color: colors.text3),
                onTap: session == null ? null : () => _openChannel(ref, session),
              ),
              ListTile(
                title: const Text('Rebuild index'),
                subtitle: Text(
                  sync.running
                      ? 'Reading the channel · ${Formatters.count(sync.scanned, 'item')}'
                      : sync.error ??
                            (sync.lastSynced == null
                                ? 'Read everything again from Telegram'
                                : 'Last checked ${Formatters.date(sync.lastSynced!)}'),
                ),
                trailing: sync.running
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
                onTap: sync.running
                    ? null
                    : () => ref.read(driveSyncProvider.notifier).rebuildIndex(),
              ),
            ],
          ),
          const SectionHeader('Appearance'),
          ListGroup(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.gutter, Space.l, Space.gutter, Space.l),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Theme', style: context.text.titleSmall),
                    const SizedBox(height: Space.m),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<ThemeMode>(
                        segments: const [
                          ButtonSegment(value: ThemeMode.system, label: Text('System')),
                          ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                          ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                        ],
                        selected: {themeMode},
                        showSelectedIcon: false,
                        onSelectionChanged: (value) =>
                            ref.read(themeModeProvider.notifier).set(value.first),
                      ),
                    ),
                  ],
                ),
              ),
              SwitchListTile(
                title: const Text('Show files as a grid'),
                value: viewMode == ViewMode.grid,
                onChanged: (_) => ref.read(browsePreferencesProvider.notifier).toggleViewMode(),
              ),
            ],
          ),
          const SectionHeader('This phone'),
          ListGroup(
            children: [
              ListTile(
                enabled: !busyTransfers,
                title: const Text('Clear downloaded copies'),
                subtitle: Text(
                  busyTransfers
                      ? 'Available when transfers finish'
                      : switch (cache) {
                          AsyncData(:final value) => '${Formatters.bytes(value)} on this phone',
                          _ => 'Measuring',
                        },
                ),
                onTap: () async {
                  final ok = await showConfirmDialog(
                    context,
                    title: 'Clear downloaded copies?',
                    message:
                        'Your files stay in Telegram and download again when '
                        'you open them.',
                    confirmLabel: 'Clear',
                  );
                  if (!ok) return;
                  try {
                    await clearLocalCache(ref);
                    if (context.mounted) showSnack(context, 'Downloaded copies cleared');
                  } catch (e) {
                    if (context.mounted) showSnack(context, 'Couldn\'t clear them: $e');
                  }
                },
              ),
            ],
          ),
          const SectionHeader('About'),
          ListGroup(
            children: [
              ListTile(
                title: const Text('How Telegrive works'),
                trailing: Icon(Icons.chevron_right_rounded, color: colors.text3),
                onTap: () => _showHowItWorks(context),
              ),
              ListTile(
                title: const Text('Version'),
                subtitle: const Text('Independent, not affiliated with Telegram'),
                trailing: trailingValue(AppConfig.appVersion),
              ),
            ],
          ),
          const SizedBox(height: Space.xxl),
          ListGroup(
            children: [
              ListTile(
                title: Text(
                  'Sign out',
                  style: context.text.bodyLarge?.copyWith(color: colors.danger),
                ),
                onTap: () async {
                  final ok = await showConfirmDialog(
                    context,
                    title: 'Sign out?',
                    message:
                        'Your files stay in your Telegram channel. Sign in '
                        'again any time to see them.',
                    confirmLabel: 'Sign out',
                    destructive: true,
                  );
                  if (ok) await ref.read(authControllerProvider.notifier).signOut();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Private channels only have post links; the newest indexed post lands
  /// on the latest files.
  static void _openChannel(WidgetRef ref, DriveSession session) {
    final latest = ref.read(preferencesProvider).lastSyncedMessageId(session.chatId);
    final post = latest > 0 ? latest >> 20 : 1;
    launchUrl(
      Uri.parse('https://t.me/c/${-session.chatId - 1000000000000}/$post'),
      mode: LaunchMode.externalApplication,
    );
  }

  void _showHowItWorks(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (context) {
        Widget point(String title, String body) => Padding(
          padding: const EdgeInsets.only(bottom: Space.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: context.text.titleSmall),
              const SizedBox(height: 2),
              Text(body, style: context.text.bodyMedium),
            ],
          ),
        );
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.xxl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('How Telegrive works', style: context.text.titleMedium),
                const SizedBox(height: Space.l),
                point(
                  'Your drive is a private channel',
                  'Each file is a message in a channel only you can see. '
                      'Telegram stores it, and there is no total limit.',
                ),
                point(
                  'Names and folders live in captions',
                  'So the whole drive can be rebuilt from Telegram on any phone '
                      'you sign in on.',
                ),
                point(
                  'Big files are stored in parts',
                  'Telegram takes up to 2 GB per message (4 GB with Premium). '
                      'Larger files go up as numbered parts and are joined '
                      'again when you download them.',
                ),
                point(
                  'Forwarding adds files',
                  'Forward any file to the channel in Telegram and it appears '
                      'here, without uploading it again.',
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
