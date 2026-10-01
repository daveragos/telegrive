import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../app/theme/file_style.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/files/file_kind.dart';
import '../../../core/format/formatters.dart';
import '../../../core/widgets/brand_mark.dart';
import '../../../core/widgets/common.dart';
import '../../../infrastructure/database/app_database.dart'
    show KindTotal, TransferOrigin, TransferStatus;
import '../../../infrastructure/storage/preferences.dart';
import '../../backup/data/backup_controller.dart';
import '../../backup/presentation/backup_card.dart';
import '../../drive/data/drive_repository.dart';
import '../../drive/data/drive_session.dart';
import '../../drive/data/drive_sync.dart';
import '../../drive/domain/drive_models.dart';
import '../../files/presentation/file_actions.dart';
import '../../files/presentation/file_tiles.dart';
import '../../transfers/data/transfer_queue.dart';
import 'drive_health.dart';

/// What is in the drive and what is happening to it. Where the space goes
/// first, which doubles as the way into each kind of file; then the files
/// this phone opened or added lately.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(storageSummaryProvider).value;
    final recent = ref.watch(recentActivityProvider(12));
    final starred = ref.watch(starredFilesProvider).value?.length ?? 0;
    final starredRow = starred > 0
        ? ListTile(
            leading: const Icon(Icons.star_outline_rounded),
            title: const Text('Starred'),
            trailing: Text(
              Formatters.number(starred),
              style: context.text.bodyMedium?.copyWith(
                fontFeatures: tabularFigures,
              ),
            ),
            onTap: () => context.push('/starred'),
          )
        : null;

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
            const SliverSafeArea(bottom: false, sliver: SliverToBoxAdapter(child: _Header())),
            const SliverToBoxAdapter(child: _Activity()),
            if (summary != null && summary.fileCount > 0) ...[
              const SliverToBoxAdapter(child: SectionHeader('Storage')),
              SliverToBoxAdapter(child: _Storage(summary: summary)),
            ],
            SliverToBoxAdapter(
              child: SectionHeader(
                'Recent',
                trailing: TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: Space.s),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => context.push('/recent'),
                  child: const Text('See all'),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: switch (recent) {
                // Until the drive has been counted it isn't known to be
                // empty, so nothing is said yet.
                AsyncData(value: final entries) when entries.isEmpty => switch (summary) {
                  null => const SizedBox.shrink(),
                  StorageSummary(fileCount: 0) => const _NothingYet(),
                  _ => Column(
                    children: [
                      const EmptyState(
                        title: 'Nothing opened yet',
                        message: 'Files you open, share or add show up here.',
                        compact: true,
                      ),
                      if (starredRow != null) ListGroup(children: [starredRow]),
                    ],
                  ),
                },
                AsyncData(value: final entries) => ListGroup(
                  children: [
                    for (final entry in entries.take(5))
                      FileListTile(
                        file: entry.file,
                        subtitle:
                            '${Formatters.bytes(entry.file.size)} · '
                            '${entry.verb} ${Formatters.date(entry.at)}',
                        onTap: () => FileActions.open(context, ref, entry.file),
                        onLongPress: () =>
                            FileActions.showFileSheet(context, ref, entry.file),
                        onMore: () => FileActions.showFileSheet(context, ref, entry.file),
                      ),
                    ?starredRow,
                  ],
                ),
                _ => const Padding(
                  padding: EdgeInsets.all(Space.x3),
                  child: Center(child: CircularProgressIndicator()),
                ),
              },
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 112)),
          ],
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final session = ref.watch(driveSessionProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.m, Space.m, 0),
      child: Column(
        children: [
          Row(
            children: [
              const BrandMark(size: 28),
              const SizedBox(width: Space.m),
              Expanded(child: Text('Telegrive', style: context.text.titleLarge)),
              IconButton(
                onPressed: () => context.push('/transfers'),
                icon: const Icon(Icons.swap_vert_rounded),
                tooltip: 'Transfers',
              ),
              const SizedBox(width: Space.xs),
              Tooltip(
                message: 'Settings',
                child: InkResponse(
                  onTap: () => context.push('/settings'),
                  radius: 24,
                  child: CircleAvatar(
                    radius: 17,
                    backgroundColor: colors.surface2,
                    child: Text(
                      session?.initials ?? '?',
                      style: context.text.labelMedium?.copyWith(color: colors.text),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: Space.s),
            ],
          ),
          const SizedBox(height: Space.l),
          Padding(
            padding: const EdgeInsets.only(right: Space.s),
            child: Material(
              color: colors.surface2,
              borderRadius: BorderRadius.circular(Radii.control),
              child: InkWell(
                borderRadius: BorderRadius.circular(Radii.control),
                onTap: () => context.push('/search'),
                child: SizedBox(
                  height: 44,
                  child: Row(
                    children: [
                      const SizedBox(width: Space.m),
                      Icon(Icons.search_rounded, color: colors.text3, size: 22),
                      const SizedBox(width: Space.m),
                      Text(
                        'Search files and folders',
                        style: context.text.bodyLarge?.copyWith(color: colors.text3),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One line that says whether the drive is safe, always there, plus at most
/// one more for a different concern that needs doing. What they say is
/// worked out in [describeDriveHealth] and [secondaryHealth]; this only
/// draws them.
class _Activity extends ConsumerWidget {
  const _Activity();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backup = ref.watch(backupControllerProvider);
    final sync = ref.watch(driveSyncProvider);
    final transfers = ref.watch(transferQueueProvider);
    final chatId = ref.watch(driveSessionProvider)?.chatId;

    final top = describeDriveHealth(
      backup: backup,
      sync: sync,
      transfers: transfers,
      lastFullSync: chatId == null ? null : ref.read(preferencesProvider).lastFullSync(chatId),
      backupSpeed: transfers.backupActive.fold<double>(0, (sum, t) => sum + t.bytesPerSecond),
    );
    final second = secondaryHealth(top, backup: backup, transfers: transfers);

    return Padding(
      padding: const EdgeInsets.only(top: Space.l),
      child: ListGroup(
        children: [
          _line(context, ref, top),
          if (second != null) _line(context, ref, second),
        ],
      ),
    );
  }

  static Widget _line(BuildContext context, WidgetRef ref, DriveHealth health) {
    final colors = context.colors;
    final controller = ref.read(backupControllerProvider.notifier);
    final queue = ref.read(transferQueueProvider.notifier);
    return StatusLine(
      icon: health.icon,
      color: switch (health.tone) {
        HealthTone.busy => colors.accent,
        HealthTone.good => colors.success,
        HealthTone.bad => colors.danger,
        HealthTone.neutral => null,
      },
      text: health.text,
      detail: health.detail,
      progress: health.progress,
      progressColor: health.waiting ? colors.text3 : null,
      trailing: switch (health.action) {
        HealthAction.turnOn => TextButton(
          onPressed: () => enableBackup(context, ref),
          child: const Text('Turn on'),
        ),
        HealthAction.allow => TextButton(
          onPressed: () async {
            if (!await controller.enable()) await PhotoManager.openSetting();
          },
          child: const Text('Allow'),
        ),
        HealthAction.useData => TextButton(
          onPressed: () => controller.setWifiOnly(false),
          child: const Text('Use data'),
        ),
        HealthAction.retryBackup => TextButton(
          onPressed: () => controller.schedule(immediate: true),
          child: const Text('Retry'),
        ),
        HealthAction.retryFailed => TextButton(
          onPressed: controller.retryFailed,
          child: const Text('Retry'),
        ),
        HealthAction.retryTransfers => TextButton(
          onPressed: () => queue.retryAll(
            (r) => r.status == TransferStatus.failed && r.origin != TransferOrigin.backup,
          ),
          child: const Text('Retry'),
        ),
        HealthAction.resumeTransfers => TextButton(
          onPressed: () => queue.resumeAll((r) => r.origin != TransferOrigin.backup),
          child: const Text('Resume'),
        ),
        HealthAction.useDataForTransfers => TextButton(
          onPressed: () => queue.useMobileData(
            transfersWaitingForWifi(ref.read(transferQueueProvider)).map((t) => t.id),
          ),
          child: const Text('Use data'),
        ),
        HealthAction.none => null,
      },
      onTap: switch (health.target) {
        HealthTarget.backup => () => context.push('/backup'),
        HealthTarget.transfers => () => context.push('/transfers'),
        HealthTarget.refresh => () => ref.read(driveSyncProvider.notifier).refresh(),
      },
    );
  }
}

class _NothingYet extends ConsumerWidget {
  const _NothingYet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return EmptyState(
      title: 'Your drive is empty',
      message:
          'Upload files here, or forward any file to your Telegrive channel '
          'in Telegram and it will show up.',
      compact: true,
      action: FilledButton(
        onPressed: () => FileActions.upload(context, ref),
        child: const Text('Upload files'),
      ),
    );
  }
}

/// Total, one proportional bar, then a row per kind that opens it.
class _Storage extends StatelessWidget {
  const _Storage({required this.summary});

  final StorageSummary summary;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final kinds = [...summary.totals.where((t) => t.count > 0)]
      ..sort((a, b) => b.bytes.compareTo(a.bytes));

    return ListGroup(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, Space.l, Space.gutter, Space.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: Formatters.bytes(summary.bytes),
                      style: context.text.titleMedium,
                    ),
                    TextSpan(
                      text: '  in ${Formatters.count(summary.fileCount, 'file')}',
                      style: context.text.bodyMedium,
                    ),
                  ],
                ),
                style: const TextStyle(fontFeatures: tabularFigures),
              ),
              const SizedBox(height: Space.m),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: SizedBox(
                  height: 6,
                  width: double.infinity,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (index, total) in kinds.indexed) ...[
                        if (index > 0) SizedBox(width: 2, child: ColoredBox(color: colors.surface)),
                        Expanded(
                          flex: (total.bytes * 1000 ~/ summary.bytes).clamp(6, 1000),
                          child: ColoredBox(
                            color: FileStyle.forKind(total.kind).resolve(context, colors.text3),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        for (final total in kinds) _KindRow(total: total),
      ],
    );
  }
}

class _KindRow extends StatelessWidget {
  const _KindRow({required this.total});

  final KindTotal total;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style = FileStyle.forKind(total.kind);
    return InkWell(
      onTap: () => context.push('/category/${total.kind.name}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.gutter, vertical: 14),
        child: Row(
          children: [
            Icon(style.icon, size: 22, color: style.resolve(context, colors.text2)),
            const SizedBox(width: Space.l),
            Expanded(child: Text(total.kind.label, style: context.text.titleSmall)),
            Text(
              '${Formatters.count(total.count, _noun(total.kind))} · '
              '${Formatters.bytes(total.bytes)}',
              style: context.text.bodyMedium?.copyWith(fontFeatures: tabularFigures),
            ),
            const SizedBox(width: Space.xs),
            Icon(Icons.chevron_right_rounded, color: colors.text3, size: 20),
          ],
        ),
      ),
    );
  }

  static String _noun(FileKind kind) => switch (kind) {
    FileKind.image => 'photo',
    FileKind.video => 'video',
    FileKind.audio => 'track',
    FileKind.app => 'app',
    _ => 'file',
  };
}
