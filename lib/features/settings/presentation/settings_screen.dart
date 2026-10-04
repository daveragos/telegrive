import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/config/app_config.dart';
import '../../../core/format/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../../infrastructure/notifications/app_notifications.dart';
import '../../../infrastructure/storage/device_profile.dart';
import '../../../infrastructure/storage/preferences.dart';
import '../../auth/data/auth_controller.dart';
import '../../backup/data/backup_controller.dart';
import '../../drive/data/drive_repository.dart';
import '../../drive/data/drive_session.dart';
import '../../drive/data/drive_sync.dart';
import '../../files/data/browse_preferences.dart';
import '../../files/presentation/file_actions.dart';
import '../../lock/data/app_lock.dart';
import '../../network/data/mobile_data.dart';
import '../../network/data/proxies.dart';
import '../../network/presentation/proxy_sheet.dart';
import '../../offline/data/offline_sync.dart';
import '../../search/data/content_indexer.dart';
import '../../trash/data/pending_deletes.dart';
import '../data/settings_providers.dart';
import 'data_limit_sheet.dart';

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
    final hidden = ref.watch(pendingDeletesProvider.select((s) => s.hiddenIds));
    final trashCount = ref.watch(trashProvider).value?.without(hidden).count ?? 0;
    final lock = ref.watch(appLockProvider);
    final offline = ref.watch(offlineUsageProvider);
    final indexer = ref.watch(contentIndexerProvider);
    final indexed = ref.watch(indexedCountProvider).value ?? 0;
    final prefs = ref.watch(preferencesProvider);
    final mobileData = ref.watch(mobileDataProvider);
    final proxy = ref.watch(enabledProxyProvider);
    final saveMemory = ref.watch(saveMemoryProvider);
    final profile = ref.watch(deviceProfileProvider);
    // Said only while the phone, not the person, decides.
    final memoryReason =
        prefs.saveMemory == null && profile.suggestSaveMemory && profile.totalRamBytes > 0
        ? ' Turned on because this phone has ${Formatters.bytes(profile.totalRamBytes)} of memory.'
        : '';

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
          const _NotificationsOff(),
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
                      BackupPhase.waitingForBudget => 'Limit reached',
                      BackupPhase.needsPermission => 'Needs access',
                      BackupPhase.stopped => 'Stopped',
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
                title: const Text('Trash'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (trashCount > 0) trailingValue(Formatters.count(trashCount, 'item')),
                    Icon(Icons.chevron_right_rounded, color: colors.text3),
                  ],
                ),
                onTap: () => context.push('/trash'),
              ),
              ListTile(
                title: const Text('Stored in Telegram'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    trailingValue(
                      summary == null
                          ? ''
                          : '${Formatters.bytes(summary.bytes)} · '
                                '${Formatters.count(summary.fileCount, 'file')}',
                    ),
                    Icon(Icons.chevron_right_rounded, color: colors.text3),
                  ],
                ),
                onTap: () => context.push('/space'),
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
          const SectionHeader('Mobile data'),
          ListGroup(
            children: [
              _MonthlyLimit(data: mobileData),
              if (!mobileData.failed)
                ListTile(
                  title: Text(
                    mobileData.renewDay == 1
                        ? 'This month'
                        : 'Since the ${Formatters.dayOfMonth(mobileData.renewDay)}',
                  ),
                  subtitle: Text(
                    mobileData.measured
                        ? '${Formatters.bytes(mobileData.mobileBytes)} on mobile data · '
                              '${Formatters.bytes(mobileData.wifiBytes)} on Wi-Fi'
                        : 'Measuring',
                    style: context.text.bodySmall?.copyWith(fontFeatures: tabularFigures),
                  ),
                ),
              SwitchListTile(
                title: const Text('Big transfers wait for Wi-Fi'),
                // A non-breaking hyphen, so a wrapped line never ends in 'Wi-'.
                subtitle: const Text(
                  'Uploads and downloads of 200 MB or more pause on mobile data and '
                  'carry on over Wi\u2011Fi. A phone\'s hotspot counts as mobile data.',
                ),
                value: prefs.bigTransfersWifiOnly,
                onChanged: (on) async {
                  await prefs.setBigTransfersWifiOnly(on);
                  ref.invalidate(preferencesProvider);
                },
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
          const SectionHeader('Search'),
          ListGroup(
            children: [
              SwitchListTile(
                title: const Text('Search inside documents'),
                subtitle: Text(
                  indexer.running && indexer.left > 0
                      ? 'Reading · ${Formatters.count(indexer.left, 'file')} to go'
                      : 'Finds PDFs and text files by the words in them. Read on '
                            'this phone, on Wi-Fi. Keeps no copies'
                            '${indexed > 0 ? ' · ${Formatters.count(indexed, 'file')} read' : ''}.',
                ),
                value: indexer.enabled,
                onChanged: (on) => ref.read(contentIndexerProvider.notifier).setEnabled(on),
              ),
            ],
          ),
          const SectionHeader('Security'),
          ListGroup(
            children: [
              SwitchListTile(
                title: const Text('App lock'),
                subtitle: const Text('Ask for your fingerprint, face or screen lock to open Telegrive'),
                value: lock.enabled,
                onChanged: (on) async {
                  final done = await ref.read(appLockProvider.notifier).setEnabled(on);
                  if (!done && on && context.mounted) {
                    showSnack(context, 'Set up a screen lock on this phone first, then try again.');
                  }
                },
              ),
              if (lock.enabled)
                ListTile(
                  title: const Text('Lock'),
                  trailing: PopupMenuButton<LockAfter>(
                    initialValue: lock.after,
                    onSelected: (after) => ref.read(appLockProvider.notifier).setAfter(after),
                    itemBuilder: (_) => [
                      for (final after in LockAfter.values)
                        PopupMenuItem(value: after, child: Text(after.label)),
                    ],
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        trailingValue(lock.after.label),
                        Icon(Icons.arrow_drop_down_rounded, color: colors.text3),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SectionHeader('Connection'),
          ListGroup(
            children: [
              ListTile(
                title: const Text('Proxy'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    trailingValue(proxy?.label ?? 'Off'),
                    Icon(Icons.chevron_right_rounded, color: colors.text3),
                  ],
                ),
                onTap: () => showProxySheet(context),
              ),
            ],
          ),
          const SectionHeader('This phone'),
          ListGroup(
            children: [
              SwitchListTile(
                title: const Text('Save memory'),
                subtitle: Text(
                  'Fewer transfers at once, a smaller image cache and plain previews.$memoryReason',
                  style: context.text.bodySmall?.copyWith(fontFeatures: tabularFigures),
                ),
                value: saveMemory,
                onChanged: ref.read(saveMemoryProvider.notifier).set,
              ),
              ListTile(
                title: const Text('Available offline'),
                subtitle: Text(switch (offline) {
                  AsyncData(value: (final count, final bytes)) when count > 0 =>
                    '${Formatters.count(count, 'file')} · ${Formatters.bytes(bytes)}',
                  _ => 'Nothing yet. Choose files or folders from their menu.',
                }),
                trailing: Icon(Icons.chevron_right_rounded, color: colors.text3),
                onTap: () => context.push('/offline'),
              ),
              ListTile(
                title: const Text('Space on this phone'),
                subtitle: Text(switch (cache) {
                  AsyncData(:final value) =>
                    '${Formatters.bytes(value)} · What Telegrive keeps on this phone',
                  _ => 'Measuring',
                }),
                trailing: Icon(Icons.chevron_right_rounded, color: colors.text3),
                onTap: () => context.push('/space?focus=phone'),
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
                point(
                  'Saving from chats',
                  'Files you already have in Telegram are copied into your drive '
                      'by Telegram itself, so nothing is downloaded or uploaded.',
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The monthly mobile data limit and how much of it this period has used,
/// with a bar that turns red once it is used up. It opens the sheet that
/// sets the limit.
class _MonthlyLimit extends ConsumerWidget {
  const _MonthlyLimit({required this.data});

  final MobileDataState data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final limit = data.limit;
    final figures = context.text.bodySmall?.copyWith(fontFeatures: tabularFigures);
    return ListTile(
      title: const Text('Monthly limit'),
      subtitle: limit == null
          ? const Text('None. Set one to keep backup inside your data plan.')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${Formatters.bytes(data.mobileBytes)} of '
                  '${Formatters.bytes(limit, decimals: 0)} used · '
                  'renews on the ${Formatters.dayOfMonth(data.renewDay)}',
                  style: figures,
                ),
                const SizedBox(height: Space.s),
                Padding(
                  padding: const EdgeInsets.only(right: Space.s),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: (data.mobileBytes / limit).clamp(0.0, 1.0)),
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    builder: (context, value, _) => ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: value,
                        minHeight: 4,
                        color: data.mobileBytes >= limit ? colors.danger : colors.accent,
                      ),
                    ),
                  ),
                ),
              ],
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (limit == null)
            Text('Off', style: context.text.bodyMedium?.copyWith(fontFeatures: tabularFigures)),
          Icon(Icons.chevron_right_rounded, color: colors.text3),
        ],
      ),
      onTap: () => showDataLimitSheet(context, ref),
    );
  }
}

/// 'Notifications are off', with Turn on, while Android won't let
/// Telegrive post them; nothing otherwise. Coming back from the system's
/// settings looks again, so the row goes once they are on.
class _NotificationsOff extends ConsumerStatefulWidget {
  const _NotificationsOff();

  @override
  ConsumerState<_NotificationsOff> createState() => _NotificationsOffState();
}

class _NotificationsOffState extends ConsumerState<_NotificationsOff> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.invalidate(notificationsEnabledProvider),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(notificationsEnabledProvider).value ?? true;
    if (enabled) return const SizedBox.shrink();
    return ListGroup(
      margin: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
      children: [
        ListTile(
          leading: Icon(Icons.notifications_off_outlined, color: context.colors.text2),
          title: const Text('Notifications are off'),
          subtitle: const Text(
            'Turn them on to see upload progress and when new photos are waiting '
            'to be backed up.',
          ),
          trailing: TextButton(
            onPressed: AppNotifications.openSettings,
            child: const Text('Turn on'),
          ),
        ),
      ],
    );
  }
}
