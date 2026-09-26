import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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

/// What is in the drive and what is happening to it. Where the space goes
/// first, which doubles as the way into each kind of file; then recent
/// files.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(storageSummaryProvider).value;
    final recent = ref.watch(recentFilesProvider);
    final starred = ref.watch(starredFilesProvider).value?.length ?? 0;

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
                AsyncData(value: final files) when files.isEmpty => const _NothingYet(),
                AsyncData(value: final files) => ListGroup(
                  children: [
                    for (final file in files.take(5))
                      FileListTile(
                        file: file,
                        onTap: () => FileActions.open(context, ref, file),
                        onLongPress: () => FileActions.showFileSheet(context, ref, file),
                        onMore: () => FileActions.showFileSheet(context, ref, file),
                      ),
                    if (starred > 0)
                      ListTile(
                        leading: const Icon(Icons.star_outline_rounded),
                        title: const Text('Starred'),
                        trailing: Text(
                          Formatters.number(starred),
                          style: context.text.bodyMedium?.copyWith(
                            fontFeatures: tabularFigures,
                          ),
                        ),
                        onTap: () => context.push('/starred'),
                      ),
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

/// Only here while something needs saying: transfers in flight or failed,
/// and backup when it is off, blocked or busy. Quiet once all is well.
class _Activity extends ConsumerStatefulWidget {
  const _Activity();

  @override
  ConsumerState<_Activity> createState() => _ActivityState();
}

class _ActivityState extends ConsumerState<_Activity> {
  late bool _backupHidden = () {
    final until = ref.read(preferencesProvider).backupCardHiddenUntil;
    return until != null && until.isAfter(DateTime.now());
  }();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final backup = ref.watch(backupControllerProvider);
    final transfers = ref.watch(transferQueueProvider);
    final active = transfers.active
        .where((t) => t.origin == TransferOrigin.manual)
        .toList();
    final failed = transfers.finished
        .where((t) => t.status == TransferStatus.failed && t.origin == TransferOrigin.manual)
        .length;

    final showBackup = backup.isWorking ||
        backup.phase == BackupPhase.waitingForWifi ||
        backup.phase == BackupPhase.needsPermission ||
        (backup.phase == BackupPhase.off && !_backupHidden);

    final rows = <Widget>[
      if (active.isNotEmpty)
        StatusLine(
          icon: Icons.swap_vert_rounded,
          color: colors.accent,
          text: '${Formatters.count(active.length, 'transfer')} in progress',
          detail: '${(_progress(active) * 100).round()}% done',
          progress: _progress(active),
          onTap: () => context.push('/transfers'),
        ),
      if (failed > 0)
        StatusLine(
          icon: Icons.error_outline_rounded,
          color: colors.danger,
          text: failed == 1 ? '1 transfer failed' : '$failed transfers failed',
          detail: 'Open Transfers to retry.',
          onTap: () => context.push('/transfers'),
        ),
      if (showBackup)
        BackupStatusLine(
          onDismiss: () {
            ref.read(preferencesProvider).hideBackupCard(const Duration(days: 7));
            setState(() => _backupHidden = true);
          },
        ),
    ];
    if (rows.isEmpty) return const SizedBox(height: Space.s);

    return Padding(
      padding: const EdgeInsets.only(top: Space.l),
      child: ListGroup(children: rows),
    );
  }

  static double _progress(List<TransferItem> items) {
    final total = items.fold<int>(0, (sum, t) => sum + t.row.totalBytes);
    final done = items.fold<int>(0, (sum, t) => sum + t.row.doneBytes);
    return total == 0 ? 0 : done / total;
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
