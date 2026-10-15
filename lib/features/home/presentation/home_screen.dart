import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../app/app_phase.dart';
import '../../../app/theme/file_style.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/files/file_kind.dart';
import '../../../core/format/formatters.dart';
import '../../../core/widgets/brand_mark.dart';
import '../../../core/widgets/common.dart';
import '../../../infrastructure/database/app_database.dart'
    show KindTotal, TransferOrigin, TransferStatus;
import '../../../infrastructure/storage/preferences.dart';
import '../../../infrastructure/telegram/telegram_client.dart';
import '../../backup/data/background_health.dart';
import '../../backup/data/backup_controller.dart';
import '../../backup/data/free_up_space.dart';
import '../../backup/presentation/backup_card.dart';
import '../../backup/presentation/free_up_space_sheet.dart';
import '../../drive/data/drive_repository.dart';
import '../../drive/data/drive_session.dart';
import '../../drive/data/drive_sync.dart';
import '../../drive/data/edit_outbox.dart';
import '../../drive/data/forward_filer.dart';
import '../../drive/domain/drive_models.dart';
import '../../files/presentation/file_actions.dart';
import '../../files/presentation/file_tiles.dart';
import '../../network/data/connection_health.dart';
import '../../network/data/mobile_data.dart';
import '../../network/data/proxies.dart';
import '../../network/presentation/proxy_sheet.dart';
import '../../offline/data/offline_sync.dart';
import '../../player/data/play_positions.dart';
import '../../setup/data/drive_setup.dart';
import '../../takeout/data/takeout_import.dart';
import '../../takeout/presentation/takeout_status.dart';
import '../../transfers/data/transfer_queue.dart';
import 'drive_health.dart';

/// What is in the drive and what is happening to it. What this phone was
/// partway through playing first, when there is anything; then where the
/// space goes, which doubles as the way into each kind of file and, once
/// something is kept offline, into what this phone keeps; then the starred
/// folders, each a tap from wherever it sits; then the files this phone
/// opened or added lately.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(storageSummaryProvider).value;
    final recent = ref.watch(recentActivityProvider(12));
    final starredFolders =
        ref.watch(starredFoldersProvider).value ?? const <DriveFolder>[];
    final starredSizes = ref.watch(starredFolderSizesProvider).value;
    final starred =
        (ref.watch(starredFilesProvider).value?.length ?? 0) +
        starredFolders.length;
    final pinned = ref.watch(offlinePinsProvider).value?.isNotEmpty ?? false;
    final offline = ref.watch(offlineUsageProvider).value;
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
      floatingActionButton: FloatingActionButton(
        heroTag: 'home-fab',
        onPressed: () => FileActions.showCreateSheet(context, ref),
        tooltip: 'New',
        child: const Icon(Icons.add_rounded),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(driveSyncProvider.notifier).refresh(),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            const SliverSafeArea(
              bottom: false,
              sliver: SliverToBoxAdapter(child: _Header()),
            ),
            const SliverToBoxAdapter(child: _Activity()),
            const SliverToBoxAdapter(child: _ContinuePlaying()),
            if (summary != null && summary.fileCount > 0) ...[
              const SliverToBoxAdapter(child: SectionHeader('Storage')),
              SliverToBoxAdapter(
                child: _Storage(
                  summary: summary,
                  offline: pinned ? offline ?? (0, 0) : null,
                ),
              ),
            ],
            if (starredFolders.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: SectionHeader(
                  'Starred',
                  trailing: _SeeAll(onPressed: () => context.push('/starred')),
                ),
              ),
              SliverToBoxAdapter(
                child: ListGroup(
                  children: [
                    for (final folder in starredFolders.take(5))
                      FolderListTile(
                        folder: folder,
                        subtitle: folderContentsLine(starredSizes?[folder.id]),
                        onTap: () => context.go('/files/${folder.id}'),
                        onLongPress: () =>
                            FileActions.showFolderSheet(context, ref, folder),
                        onMore: () =>
                            FileActions.showFolderSheet(context, ref, folder),
                      ),
                  ],
                ),
              ),
            ],
            SliverToBoxAdapter(
              child: SectionHeader(
                'Recent',
                trailing: _SeeAll(onPressed: () => context.push('/recent')),
              ),
            ),
            SliverToBoxAdapter(
              child: switch (recent) {
                // Until the drive has been counted it isn't known to be
                // empty, so nothing is said yet.
                AsyncData(value: final entries) when entries.isEmpty =>
                  switch (summary) {
                    null => const SizedBox.shrink(),
                    StorageSummary(fileCount: 0) => const _NothingYet(),
                    _ => Column(
                      children: [
                        const EmptyState(
                          title: 'Nothing opened yet',
                          message: 'Files you open, share or add show up here.',
                          compact: true,
                        ),
                        if (starredRow != null)
                          ListGroup(children: [starredRow]),
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
                        onMore: () =>
                            FileActions.showFileSheet(context, ref, entry.file),
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

/// The small button at the end of a section header that opens the whole
/// list.
class _SeeAll extends StatelessWidget {
  const _SeeAll({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 32),
        padding: const EdgeInsets.symmetric(horizontal: Space.s),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: onPressed,
      child: const Text('See all'),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final session = ref.watch(visibleSessionProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.m, Space.m, 0),
      child: Column(
        children: [
          Row(
            children: [
              const BrandMark(size: 28),
              const SizedBox(width: Space.m),
              Expanded(
                child: Text('Telegrive', style: context.text.titleLarge),
              ),
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
                      style: context.text.labelMedium?.copyWith(
                        color: colors.text,
                      ),
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
                        style: context.text.bodyLarge?.copyWith(
                          color: colors.text3,
                        ),
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
/// draws them, and lets the group grow and shrink as they change, so the
/// line about connecting folds away once the drive opens.
class _Activity extends ConsumerWidget {
  const _Activity();

  /// How far opening the drive has got while Home shows the one this phone
  /// saved, before its session opens, and what went wrong if it failed.
  static (DriveOpening, String?) _opening(WidgetRef ref) {
    if (ref.watch(driveSessionProvider) != null ||
        ref.watch(driveSnapshotProvider) == null) {
      return (DriveOpening.open, null);
    }
    final fatal = ref.watch(fatalErrorProvider);
    if (fatal != null) return (DriveOpening.notStarted, fatal);
    final failed = ref.watch(driveSetupProvider.select((s) => s.error));
    if (failed != null) return (DriveOpening.failed, failed);
    return (DriveOpening.connecting, null);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backup = ref.watch(backupControllerProvider);
    final sync = ref.watch(driveSyncProvider);
    final transfers = ref.watch(transferQueueProvider);
    final chatId = ref.watch(driveSessionProvider)?.chatId;
    final renewDay = ref.watch(mobileDataProvider.select((d) => d.renewDay));
    final connection = ref.watch(connectionHealthProvider);
    final (opening, openingError) = _opening(ref);

    final top = describeDriveHealth(
      backup: backup,
      sync: sync,
      transfers: transfers,
      lastFullSync: chatId == null
          ? null
          : ref.read(preferencesProvider).lastFullSync(chatId),
      backupSpeed: transfers.backupActive.fold<double>(
        0,
        (sum, t) => sum + t.bytesPerSecond,
      ),
      renewDay: renewDay,
      connection: connection,
      // Read only when the line names it, so Home doesn't ask TDLib for
      // the saved proxies on every visit.
      proxy: connection == ConnectionHealth.proxyStuck
          ? ref.watch(enabledProxyProvider)?.label
          : null,
      opening: opening,
      openingError: openingError,
    );
    // What could be freed is only worked out while the phone is low on
    // space, since it reads the whole photo library.
    final lowOnSpace = ref.watch(lowSpaceProvider).value ?? false;
    final second = secondaryHealth(
      top,
      backup: backup,
      transfers: transfers,
      renewDay: renewDay,
      lowOnSpace: lowOnSpace,
      freeableBytes: lowOnSpace
          ? ref.watch(freeUpCandidatesProvider).value?.bytes ?? 0
          : 0,
      changes: ref.watch(editOutboxProvider),
      filed: ref.watch(forwardFilerProvider),
      backgroundBlocked:
          ref.watch(backgroundHealthProvider).value?.needsAttention(backup.enabled) ?? false,
    );

    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      child: Padding(
        padding: const EdgeInsets.only(top: Space.l),
        child: ListGroup(
          children: [
            _line(context, ref, top),
            if (second != null) _line(context, ref, second),
            if (takeoutWorthShowing(ref.watch(takeoutImportProvider))) const TakeoutStatusLine(),
          ],
        ),
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
          onPressed: () => controller.setMobileData(BackupMobileData.all),
          child: const Text('Use data'),
        ),
        HealthAction.useDataAnyway => TextButton(
          onPressed: controller.useDataAnyway,
          child: const Text('Use data anyway'),
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
            (r) =>
                r.status == TransferStatus.failed &&
                r.origin != TransferOrigin.backup,
          ),
          child: const Text('Retry'),
        ),
        HealthAction.resumeTransfers => TextButton(
          onPressed: () => queue.resumeAll(
            (r) => r.origin != TransferOrigin.backup && r.origin != TransferOrigin.takeout,
          ),
          child: const Text('Resume'),
        ),
        HealthAction.useDataForTransfers => TextButton(
          onPressed: () => queue.useMobileData(
            transfersWaitingForWifi(ref.read(transferQueueProvider))
                .map((t) => t.id),
          ),
          child: const Text('Use data'),
        ),
        HealthAction.freeUpSpace => TextButton(
          onPressed: () => showFreeUpSpace(context, ref),
          child: const Text('Free up space'),
        ),
        HealthAction.freeUp => TextButton(
          onPressed: () => showFreeUpSpace(context, ref),
          child: const Text('Free up'),
        ),
        HealthAction.useProxy => TextButton(
          onPressed: () => showProxySheet(context),
          child: const Text('Use a proxy'),
        ),
        HealthAction.changeProxy => TextButton(
          onPressed: () => showProxySheet(context),
          child: const Text('Change proxy'),
        ),
        HealthAction.dismissFiling => IconButton(
          onPressed: ref.read(forwardFilerProvider.notifier).clear,
          icon: const Icon(Icons.close_rounded),
          tooltip: 'Dismiss',
        ),
        HealthAction.retryOpening => TextButton(
          onPressed: ref.read(driveSetupProvider.notifier).run,
          child: const Text('Retry'),
        ),
        HealthAction.restartTelegram => TextButton(
          onPressed: () {
            final client = ref.read(telegramClientProvider);
            client.fatalError.value = null;
            // A failure comes back on this line through fatalError.
            client.start().ignore();
          },
          child: const Text('Try again'),
        ),
        HealthAction.none => null,
      },
      onTap: switch (health.target) {
        HealthTarget.backup => () => context.push('/backup'),
        HealthTarget.notBackedUp => () => context.push('/backup/not-backed-up'),
        HealthTarget.transfers => () => context.push('/transfers'),
        HealthTarget.refresh =>
          () => ref.read(driveSyncProvider.notifier).refresh(),
        HealthTarget.proxy => () => showProxySheet(context),
        HealthTarget.changes => () => context.push('/changes'),
        HealthTarget.filed => () {
          // The folder opens in the Files tab, the way a starred folder
          // does from Home; a folder is a place in that tab, not a screen
          // over this one.
          final folderId = ref.read(forwardFilerProvider)?.folderId;
          context.go(folderId == null ? '/files' : '/files/$folderId');
          ref.read(forwardFilerProvider.notifier).clear();
        },
        HealthTarget.none => null,
      },
    );
  }
}

/// Up to three videos or recordings this phone stopped partway through,
/// most recent first, each with how much is left and where it lives. The
/// group is there only while it has rows: nothing is said while they load,
/// when there are none or when they can't be read.
class _ContinuePlaying extends ConsumerWidget {
  const _ContinuePlaying();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = switch (ref.watch(continuePlayingProvider)) {
      AsyncData(value: final items) when items.isNotEmpty => items,
      _ => null,
    };
    if (items == null) return const SizedBox.shrink();
    final allVideo = items.every((i) => i.file.kind == FileKind.video);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(allVideo ? 'Continue watching' : 'Continue playing'),
        ListGroup(
          children: [
            for (final item in items)
              FileListTile(
                file: item.file,
                subtitle: '${Formatters.left(item.left)} · ${item.place}',
                progress: item.progress,
                onTap: () => FileActions.open(
                  context,
                  ref,
                  item.file,
                  from: item.file.kind == FileKind.audio
                      ? 'folder:${item.file.folderId ?? ''}'
                      : null,
                ),
                onLongPress: () => _showSheet(context, ref, item),
                onMore: () => _showSheet(context, ref, item),
              ),
          ],
        ),
      ],
    );
  }

  static Future<void> _showSheet(
    BuildContext context,
    WidgetRef ref,
    ContinueItem item,
  ) => FileActions.showFileSheet(
    context,
    ref,
    item.file,
    onMarkFinished: () async {
      await ref.read(playPositionsProvider).forget(item.file.id);
      if (context.mounted) {
        showSnack(context, '"${item.file.name}" marked as finished');
      }
    },
  );
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
      action: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton(
            onPressed: () => FileActions.upload(context, ref),
            child: const Text('Upload files'),
          ),
          const SizedBox(height: Space.s),
          TextButton(
            onPressed: () => FileActions.saveFromChat(context, ref),
            child: const Text('Save from a Telegram chat'),
          ),
        ],
      ),
    );
  }
}

/// Total, which opens Space, one proportional bar, then a row per kind that
/// opens it, and the way into what this phone keeps offline.
class _Storage extends StatelessWidget {
  const _Storage({required this.summary, required this.offline});

  final StorageSummary summary;

  /// How many files are kept offline and their size, or null while nothing
  /// is, which leaves the row out.
  final (int, int)? offline;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final kinds = [...summary.totals.where((t) => t.count > 0)]
      ..sort((a, b) => b.bytes.compareTo(a.bytes));

    return ListGroup(
      children: [
        InkWell(
          onTap: () => context.push('/space'),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.gutter,
              Space.l,
              Space.gutter,
              Space.l,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: Formatters.bytes(summary.bytes),
                              style: context.text.titleMedium,
                            ),
                            TextSpan(
                              text:
                                  '  in ${Formatters.count(summary.fileCount, 'file')}',
                              style: context.text.bodyMedium,
                            ),
                          ],
                        ),
                        style: const TextStyle(fontFeatures: tabularFigures),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: colors.text3,
                      size: 20,
                    ),
                  ],
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
                          if (index > 0)
                            SizedBox(
                              width: 2,
                              child: ColoredBox(color: colors.surface),
                            ),
                          Expanded(
                            flex: (total.bytes * 1000 ~/ summary.bytes).clamp(
                              6,
                              1000,
                            ),
                            child: ColoredBox(
                              color: FileStyle.forKind(total.kind)
                                  .resolve(context, colors.text3),
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
        ),
        for (final total in kinds) _KindRow(total: total),
        if (offline case (final count, final bytes)?)
          _OfflineRow(count: count, bytes: bytes),
      ],
    );
  }
}

/// Files kept on this phone for use without a connection, laid out as a
/// kind row is, opening the Offline screen.
class _OfflineRow extends StatelessWidget {
  const _OfflineRow({required this.count, required this.bytes});

  final int count;
  final int bytes;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: () => context.push('/offline'),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.gutter,
          vertical: 14,
        ),
        child: Row(
          children: [
            Icon(Icons.offline_pin_outlined, size: 22, color: colors.text2),
            const SizedBox(width: Space.l),
            Expanded(
              child: Text('Available offline', style: context.text.titleSmall),
            ),
            Text(
              '${Formatters.count(count, 'file')} · ${Formatters.bytes(bytes)}',
              style: context.text.bodyMedium?.copyWith(
                fontFeatures: tabularFigures,
              ),
            ),
            const SizedBox(width: Space.xs),
            Icon(Icons.chevron_right_rounded, color: colors.text3, size: 20),
          ],
        ),
      ),
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
        padding: const EdgeInsets.symmetric(
          horizontal: Space.gutter,
          vertical: 14,
        ),
        child: Row(
          children: [
            Icon(
              style.icon,
              size: 22,
              color: style.resolve(context, colors.text2),
            ),
            const SizedBox(width: Space.l),
            Expanded(
              child: Text(total.kind.label, style: context.text.titleSmall),
            ),
            Text(
              '${Formatters.count(total.count, _noun(total.kind))} · '
              '${Formatters.bytes(total.bytes)}',
              style: context.text.bodyMedium?.copyWith(
                fontFeatures: tabularFigures,
              ),
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
