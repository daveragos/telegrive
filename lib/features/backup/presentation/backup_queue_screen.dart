import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/format/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../../infrastructure/database/app_database.dart' show TransferStatus;
import '../../files/presentation/file_actions.dart';
import '../../photos/presentation/media_grid.dart';
import '../../photos/presentation/media_selection_bar.dart';
import '../../transfers/data/transfer_queue.dart';
import '../../transfers/domain/transfer_wait.dart';
import '../data/backup_controller.dart';
import '../data/local_media.dart';
import 'backup_card.dart';
import 'phone_asset_row.dart';
import 'phone_media_viewer.dart';

/// What photo backup is working through, live. Waiting has what is going
/// up now, each with how far it has got, then everything still to go,
/// newest first: a tap opens one, and the cross takes it out of backup,
/// with Undo. Backed up has what this run of the app sent up, as Photos
/// shows it, to open, or select and act on as there, while the rest
/// follow.
class BackupQueueScreen extends ConsumerStatefulWidget {
  const BackupQueueScreen({super.key});

  @override
  ConsumerState<BackupQueueScreen> createState() => _BackupQueueScreenState();
}

class _BackupQueueScreenState extends ConsumerState<BackupQueueScreen> {
  final _selection = MediaSelection();

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final backedUp = ref.watch(recentBackupsProvider).value;
    // Trash, or a file leaving the drive, takes selected photos off screen.
    ref.listen(recentBackupsProvider, (_, next) {
      if (next.value case final files?) _selection.keepOnly(files);
    });

    return DefaultTabController(
      length: 2,
      child: ListenableBuilder(
        listenable: _selection,
        builder: (context, _) => PopScope(
          canPop: !_selection.active,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _selection.clear();
          },
          child: Scaffold(
            appBar: _selection.active
                ? mediaSelectionAppBar(context, selection: _selection, files: backedUp ?? const [])
                : AppBar(
                    title: const Text('Backup queue'),
                    actions: [
                      IconButton(
                        onPressed: () => context.push('/backup'),
                        tooltip: 'Backup settings',
                        icon: const Icon(Icons.settings_outlined),
                      ),
                    ],
                    bottom: TabBar(
                      tabs: [
                        const Tab(text: 'Waiting'),
                        Tab(
                          text: backedUp == null || backedUp.isEmpty
                              ? 'Backed up'
                              : 'Backed up · ${Formatters.number(backedUp.length)}',
                        ),
                      ],
                    ),
                  ),
            bottomNavigationBar: _selection.active
                ? mediaSelectionActions(context, ref, selection: _selection, files: backedUp ?? const [])
                : null,
            body: TabBarView(
              // A selection belongs to Backed up, so the tabs stay put.
              physics: _selection.active ? const NeverScrollableScrollPhysics() : null,
              children: [
                const _Waiting(),
                backedUp == null
                    ? const Center(child: CircularProgressIndicator())
                    : MediaGrid(
                        files: backedUp,
                        selection: _selection,
                        onOpen: (file) => context.push('/viewer/${file.id}?from=backed-up'),
                        header: [
                          if (backedUp.isNotEmpty)
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(Space.gutter, Space.m, Space.gutter, 0),
                                child: Text(
                                  '${Formatters.count(backedUp.length, 'item')} backed up since '
                                  'Telegrive opened',
                                  style: context.text.bodySmall?.copyWith(fontFeatures: tabularFigures),
                                ),
                              ),
                            ),
                        ],
                        empty: const EmptyState(
                          title: 'Nothing backed up yet',
                          message: 'Photos show up here as they go up, to look through or '
                              'move to Trash while the rest follow.',
                          compact: true,
                        ),
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// What is going up now, then what is still to go, under where backup
/// stands.
class _Waiting extends ConsumerWidget {
  const _Waiting();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final backup = ref.watch(backupControllerProvider);
    final uploads = ref.watch(backupUploadsProvider);
    final going = {for (final item in uploads) item.row.assetId!};
    final next = [
      for (final asset in backup.waiting)
        if (!going.contains(asset.assetId)) asset,
    ];
    // A photo opens among the rest as listed, so a swipe goes on to the next.
    final order = [...going, for (final asset in next) asset.assetId];
    void open(String assetId) => openPhoneMedia(context, order, assetId);

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: Space.l),
            child: ListGroup(
              children: [
                const BackupStatusLine(linked: false),
                if (backup.failed > 0)
                  StatusLine(
                    icon: Icons.error_outline_rounded,
                    color: colors.danger,
                    text: '${Formatters.count(backup.failed, 'item')} didn\'t back up',
                    detail: 'See which ones and why.',
                    onTap: () => context.push('/backup/not-backed-up'),
                  ),
              ],
            ),
          ),
        ),
        if (uploads.isEmpty && next.isEmpty && backup.phase == BackupPhase.upToDate)
          const SliverToBoxAdapter(
            child: EmptyState(
              title: 'Nothing waiting',
              message: 'New photos and videos go up as they arrive.',
              compact: true,
            ),
          ),
        if (uploads.isNotEmpty) ...[
          SliverToBoxAdapter(child: SectionHeader('Now · ${Formatters.number(uploads.length)}')),
          SliverToBoxAdapter(
            child: ListGroup(
              children: [
                for (final item in uploads) _GoingUpRow(item: item, onOpen: open, key: ValueKey(item.id)),
              ],
            ),
          ),
        ],
        if (next.isNotEmpty) ...[
          SliverToBoxAdapter(child: SectionHeader('Up next · ${Formatters.number(next.length)}')),
          _SliverGroup(
            count: next.length,
            itemBuilder: (context, i) => PhoneAssetRow(
              key: ValueKey(next[i].assetId),
              assetId: next[i].assetId,
              subtitle: '${next[i].folder} · ${Formatters.date(next[i].takenAt)}',
              onTap: () => open(next[i].assetId),
              trailing: _SkipButton(assetId: next[i].assetId),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.gutter, Space.s, Space.gutter, 0),
              child: Text(
                'Newest first. Photos you take out are skipped, and Not backed up '
                'can bring them back.',
                style: context.text.bodySmall,
              ),
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: Space.x4)),
      ],
    );
  }
}

/// A backup upload under way or waiting its turn in the transfer queue,
/// with how far it has got.
class _GoingUpRow extends ConsumerWidget {
  const _GoingUpRow({super.key, required this.item, required this.onOpen});

  final TransferItem item;
  final void Function(String assetId) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final row = item.row;
    final assetId = row.assetId!;
    final small = ref.read(transferQueueProvider.notifier).sendsSmallCopy(item.id);
    final soFar = '${Formatters.bytes(row.doneBytes)} of ${Formatters.bytes(row.totalBytes)}';
    final moving = item.status == TransferStatus.running && item.wait == null && !item.preparing;

    Widget line(String detail) => PhoneAssetRow(
      assetId: assetId,
      subtitle: [if (small) 'Small copy', detail].join(' · '),
      progress: item.preparing ? -1 : item.progress,
      // Grey while it waits rather than moves.
      progressColor: moving || item.preparing ? null : colors.text3,
      onTap: () => onOpen(assetId),
      trailing: _SkipButton(assetId: assetId),
    );

    if (item.wait case WaitingForTelegram(:final until)) {
      return Countdown(
        until: until,
        builder: (context, left) => line('Waiting for Telegram · ${Formatters.countdown(left)}'),
      );
    }
    final eta = item.eta;
    return line(switch (item.wait) {
      _ when item.preparing => 'Getting it ready',
      _ when item.status == TransferStatus.paused => 'Paused · $soFar',
      WaitingForRoom(:final sentence) => sentence,
      WaitingForWifi() => 'Waiting for Wi-Fi · ${Formatters.bytes(row.totalBytes)}',
      WaitingForNetwork() => 'Waiting for network · $soFar',
      _ when item.status == TransferStatus.queued => 'Waiting · ${Formatters.bytes(row.totalBytes)}',
      _ => [
        soFar,
        if (item.bytesPerSecond > 0) Formatters.speed(item.bytesPerSecond),
        ?(eta == null ? null : Formatters.eta(eta)),
      ].join(' · '),
    });
  }
}

/// The cross at the end of a waiting photo's row, which takes it out of
/// backup.
class _SkipButton extends ConsumerWidget {
  const _SkipButton({required this.assetId});

  final String assetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => IconButton(
    onPressed: () => skipWaitingPhoto(context, ref, assetId),
    icon: Icon(Icons.close_rounded, color: context.colors.text3),
    tooltip: 'Don\'t back up',
  );
}

/// [count] rows on one surface split by hairlines, as [ListGroup] lays
/// them out, built only as they scroll into view.
class _SliverGroup extends StatelessWidget {
  const _SliverGroup({required this.count, required this.itemBuilder});

  final int count;
  final IndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    const radius = Radius.circular(Radii.card);
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: Space.l),
      sliver: DecoratedSliver(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.all(radius),
        ),
        sliver: SliverList.separated(
          itemCount: count,
          separatorBuilder: (_, _) => Divider(indent: Space.gutter, endIndent: 0, color: colors.line),
          // Each row inks on its own, above the surface, and the first and
          // last keep to its rounded corners.
          itemBuilder: (context, i) => ClipRRect(
            borderRadius: BorderRadius.vertical(
              top: i == 0 ? radius : Radius.zero,
              bottom: i == count - 1 ? radius : Radius.zero,
            ),
            child: Material(type: MaterialType.transparency, child: itemBuilder(context, i)),
          ),
        ),
      ),
    );
  }
}

/// Opens the phone's own copy of [assetId] full screen, to swipe on
/// through [order].
void openPhoneMedia(BuildContext context, List<String> order, String assetId) {
  context.push('/phone-media', extra: PhoneMediaArgs(assetIds: order, initial: assetId));
}

/// Takes the waiting photo [assetId] out of backup, saying so with Undo.
/// Nothing is said when it had stopped waiting meanwhile: gone up, or
/// skipped by a tap a moment ago.
Future<void> skipWaitingPhoto(BuildContext context, WidgetRef ref, String assetId) async {
  final controller = ref.read(backupControllerProvider.notifier);
  final name = ref.read(assetTitleProvider(assetId)).value;
  SkippedWaiting? skipped;
  await FileActions.guarded(context, () async => skipped = await controller.skipWaiting(assetId));
  final taken = skipped;
  if (taken == null || !context.mounted) return;
  // Undo can be tapped after this screen has closed, so it reports
  // through the root navigator, which lasts as long as the app.
  final lasting = Navigator.of(context, rootNavigator: true).context;
  showUndoSnack(
    context,
    name == null ? 'Skipped 1 item' : 'Skipped $name',
    onUndo: () => FileActions.guarded(lasting, () => controller.undoSkip(taken), success: 'Undone'),
  );
}
