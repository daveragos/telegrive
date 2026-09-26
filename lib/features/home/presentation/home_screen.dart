import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/file_style.dart';
import '../../../core/files/file_kind.dart';
import '../../../core/format/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../../infrastructure/database/app_database.dart' show KindTotal;
import '../../../infrastructure/storage/preferences.dart';
import '../../backup/data/backup_controller.dart';
import '../../backup/presentation/backup_card.dart';
import '../../drive/data/drive_repository.dart';
import '../../drive/data/drive_session.dart';
import '../../drive/data/drive_sync.dart';
import '../../drive/domain/drive_models.dart';
import '../../files/presentation/file_actions.dart';
import '../../files/presentation/file_tiles.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(driveSessionProvider);
    final summary = ref.watch(storageSummaryProvider).value;
    final recent = ref.watch(recentFilesProvider);
    final starredCount = ref.watch(starredFilesProvider).value?.length ?? 0;
    final syncing = ref.watch(driveSyncProvider.select((s) => s.running));

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'home-fab',
        onPressed: () => FileActions.showCreateSheet(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New'),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(driveSyncProvider.notifier).refresh(),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverSafeArea(
              bottom: false,
              sliver: SliverToBoxAdapter(
                child: _Header(
                  greeting: _greeting(session?.firstName),
                  initials: session?.initials ?? '?',
                  syncing: syncing,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: _SearchField(onTap: () => context.push('/search')),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: _StorageCard(summary: summary),
              ),
            ),
            const SliverToBoxAdapter(child: _HomeBackupCard()),
            const SliverToBoxAdapter(child: SectionHeader('Browse')),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverGrid.count(
                crossAxisCount: 3,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.02,
                children: [
                  for (final kind in const [
                    FileKind.image,
                    FileKind.video,
                    FileKind.document,
                    FileKind.audio,
                    FileKind.archive,
                    FileKind.other,
                  ])
                    _CategoryTile(
                      kind: kind,
                      total: summary?.totalFor(kind),
                      onTap: () => context.push('/category/${kind.name}'),
                    ),
                ],
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: _QuickLink(
                        icon: Icons.star_rounded,
                        color: Colors.amber.shade600,
                        label: 'Starred',
                        detail: Formatters.count(starredCount, 'file'),
                        onTap: () => context.push('/starred'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _QuickLink(
                        icon: Icons.folder_rounded,
                        color: FileStyle.folder.color,
                        label: 'My Drive',
                        detail: 'All folders',
                        onTap: () => context.go('/files'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SectionHeader(
              'Recent',
              trailing: TextButton(
                onPressed: () => context.push('/recent'),
                child: const Text('See all'),
              ),
            ).asSliver(),
            ...switch (recent) {
              AsyncData(value: final files) when files.isEmpty => [
                SliverToBoxAdapter(
                  child: EmptyState(
                    icon: Icons.cloud_upload_outlined,
                    title: 'Nothing here yet',
                    message:
                        'Upload a file, or forward any file into your Telegrive '
                        'channel in Telegram — it shows up here.',
                    compact: true,
                    action: FilledButton.tonalIcon(
                      onPressed: () => FileActions.upload(context, ref),
                      icon: const Icon(Icons.upload_rounded),
                      label: const Text('Upload files'),
                    ),
                  ),
                ),
              ],
              AsyncData(value: final files) => [
                SliverList.builder(
                  itemCount: files.length,
                  itemBuilder: (context, index) {
                    final file = files[index];
                    return FileListTile(
                      file: file,
                      onTap: () => FileActions.open(context, ref, file),
                      onLongPress: () => FileActions.showFileSheet(context, ref, file),
                      onMore: () => FileActions.showFileSheet(context, ref, file),
                    );
                  },
                ),
              ],
              _ => [
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
              ],
            },
            const SliverToBoxAdapter(child: SizedBox(height: 96)),
          ],
        ),
      ),
    );
  }

  static String _greeting(String? name) {
    final hour = DateTime.now().hour;
    final part = hour < 12
        ? 'Good morning'
        : hour < 18
        ? 'Good afternoon'
        : 'Good evening';
    return name == null || name.isEmpty ? part : '$part, $name';
  }
}

/// Suggests backup while it's off (until "Not now" hides it for a week) and
/// shows progress while it runs. Quiet once everything is backed up.
class _HomeBackupCard extends ConsumerStatefulWidget {
  const _HomeBackupCard();

  @override
  ConsumerState<_HomeBackupCard> createState() => _HomeBackupCardState();
}

class _HomeBackupCardState extends ConsumerState<_HomeBackupCard> {
  late bool _hidden = () {
    final until = ref.read(preferencesProvider).backupCardHiddenUntil;
    return until != null && until.isAfter(DateTime.now());
  }();

  @override
  Widget build(BuildContext context) {
    final backup = ref.watch(backupControllerProvider);
    final show = backup.isWorking ||
        backup.phase == BackupPhase.waitingForWifi ||
        backup.phase == BackupPhase.needsPermission ||
        (backup.phase == BackupPhase.off && !_hidden);
    if (!show) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: BackupStatusCard(
        onDismiss: () {
          ref.read(preferencesProvider).hideBackupCard(const Duration(days: 7));
          setState(() => _hidden = true);
        },
      ),
    );
  }
}

extension on Widget {
  Widget asSliver() => SliverToBoxAdapter(child: this);
}

class _Header extends StatelessWidget {
  const _Header({required this.greeting, required this.initials, required this.syncing});

  final String greeting;
  final String initials;
  final bool syncing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(greeting, style: theme.textTheme.headlineSmall),
                const SizedBox(height: 2),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Text(
                    syncing ? 'Syncing with Telegram…' : 'Everything is backed up in Telegram',
                    key: ValueKey(syncing),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          InkWell(
            customBorder: const CircleBorder(),
            onTap: () => context.go('/settings'),
            child: CircleAvatar(
              radius: 22,
              backgroundColor: scheme.primaryContainer,
              child: Text(
                initials,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: scheme.onPrimaryContainer,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surfaceContainer,
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
          child: Row(
            children: [
              Icon(Icons.search_rounded, color: scheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Text(
                'Search your drive',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StorageCard extends StatelessWidget {
  const _StorageCard({required this.summary});

  final StorageSummary? summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bytes = summary?.bytes ?? 0;
    final count = summary?.fileCount ?? 0;
    final segments = [
      for (final total in summary?.totals ?? const [])
        if (total.bytes > 0) (FileStyle.forKind(total.kind).color, total.bytes),
    ]..sort((a, b) => b.$2.compareTo(a.$2));

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2F6FED), Color(0xFF3F83F8), Color(0xFF22B8E6)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2F6FED).withValues(alpha: 0.25),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.cloud_done_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(
                'Your drive',
                style: theme.textTheme.titleSmall?.copyWith(color: Colors.white),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.all_inclusive_rounded, size: 14, color: Colors.white),
                    const SizedBox(width: 4),
                    Text(
                      'Unlimited',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            Formatters.bytes(bytes),
            style: theme.textTheme.displaySmall?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 2),
          Text(
            '${Formatters.count(count, 'file')} stored · no quota, ever',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 8,
              width: double.infinity,
              child: segments.isEmpty
                  ? ColoredBox(color: Colors.white.withValues(alpha: 0.25))
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final (index, (color, size)) in segments.indexed) ...[
                          if (index > 0) const SizedBox(width: 2),
                          Expanded(
                            flex: (size * 1000 ~/ (bytes == 0 ? 1 : bytes)).clamp(8, 1000),
                            child: ColoredBox(
                              color: Color.lerp(color, Colors.white, 0.35)!,
                            ),
                          ),
                        ],
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.kind, required this.total, required this.onTap});

  final FileKind kind;
  final KindTotal? total;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final style = FileStyle.forKind(kind);
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: style.background(theme.brightness),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(style.icon, color: style.color, size: 21),
              ),
              const Spacer(),
              Text(kind.label, style: theme.textTheme.titleSmall),
              Text(
                total == null || total!.count == 0
                    ? 'Empty'
                    : Formatters.bytes(total!.bytes),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickLink extends StatelessWidget {
  const _QuickLink({
    required this.icon,
    required this.color,
    required this.label,
    required this.detail,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: theme.textTheme.titleSmall),
                    Text(
                      detail,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
