import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/format/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../backup/data/backup_controller.dart';
import '../../backup/presentation/backup_card.dart';
import '../../backup/presentation/duplicates_sheet.dart';
import '../../backup/presentation/free_up_space_sheet.dart';
import '../../drive/data/drive_sync.dart';
import '../../files/presentation/file_actions.dart';
import '../data/photos_visibility.dart';
import 'media_grid.dart';
import 'media_selection_bar.dart';

enum _PhotosMenu { download, freeUp, duplicates }

/// Every photo and video in the drive as one timeline, newest moment first,
/// with backup status on top.
class PhotosScreen extends ConsumerStatefulWidget {
  const PhotosScreen({super.key});

  @override
  ConsumerState<PhotosScreen> createState() => _PhotosScreenState();
}

class _PhotosScreenState extends ConsumerState<PhotosScreen> {
  final _selection = MediaSelection();

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = ref.watch(photosTimelineProvider);
    // Hide, or a file going away, can take selected photos off screen.
    ref.listen(photosTimelineProvider, (_, next) {
      if (next.value case final files?) _selection.keepOnly(files);
    });
    final backup = ref.watch(backupControllerProvider);
    final keptOut = ref.watch(keptOutSummaryProvider);
    final files = media.value;

    return ListenableBuilder(
      listenable: _selection,
      builder: (context, _) => PopScope(
        canPop: !_selection.active,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _selection.clear();
        },
        child: Scaffold(
          appBar: _selection.active
              ? mediaSelectionBar(context, ref, selection: _selection, files: files ?? const [])
              : AppBar(
                  toolbarHeight: 64,
                  title: Text('Photos', style: context.text.headlineSmall),
                  actions: [
                    IconButton(
                      onPressed: () => context.push('/search?kind=image'),
                      tooltip: 'Search photos',
                      icon: const Icon(Icons.search_rounded),
                    ),
                    IconButton(
                      onPressed: () => context.push('/albums'),
                      tooltip: 'Albums',
                      icon: const Icon(Icons.photo_album_outlined),
                    ),
                    IconButton(
                      onPressed: () => context.push('/backup'),
                      tooltip: 'Backup settings',
                      icon: Icon(switch (backup.phase) {
                        BackupPhase.off => Icons.cloud_off_outlined,
                        BackupPhase.upToDate => Icons.cloud_done_outlined,
                        BackupPhase.needsPermission => Icons.cloud_off_outlined,
                        BackupPhase.stopped => Icons.cloud_off_outlined,
                        _ => Icons.cloud_sync_outlined,
                      }),
                    ),
                    PopupMenuButton<_PhotosMenu>(
                      tooltip: 'More',
                      onSelected: (choice) => switch (choice) {
                        _PhotosMenu.download => FileActions.saveToDevice(
                          context,
                          ref,
                          files: files ?? const [],
                          preferGallery: true,
                        ),
                        _PhotosMenu.freeUp => showFreeUpSpace(context, ref),
                        _PhotosMenu.duplicates => removeDuplicateBackups(context, ref),
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: _PhotosMenu.freeUp,
                          child: Text('Free up space on this phone'),
                        ),
                        const PopupMenuItem(
                          value: _PhotosMenu.duplicates,
                          child: Text('Remove duplicate backups'),
                        ),
                        if (files != null && files.isNotEmpty)
                          const PopupMenuItem(
                            value: _PhotosMenu.download,
                            child: Text('Download all to this phone'),
                          ),
                      ],
                    ),
                  ],
                ),
          body: files == null
              ? const Center(child: CircularProgressIndicator())
              : MediaGrid(
                  files: files,
                  selection: _selection,
                  onOpen: (file) => context.push('/viewer/${file.id}?from=photos'),
                  onRefresh: () async {
                    await ref.read(driveSyncProvider.notifier).refresh();
                    ref.read(backupControllerProvider.notifier).schedule(immediate: true);
                  },
                  header: [
                    SliverToBoxAdapter(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border(bottom: BorderSide(color: context.colors.line)),
                        ),
                        child: const BackupStatusLine(),
                      ),
                    ),
                    const SliverToBoxAdapter(child: _StuckRow()),
                    const SliverToBoxAdapter(child: _KeptOutRow()),
                  ],
                  empty: keptOut.count > 0
                      ? const EmptyState(
                          title: 'No photos to show',
                          message: 'Everything here is in folders kept out of this view. '
                              'Tap Show above to see them.',
                          compact: true,
                        )
                      : EmptyState(
                          title: 'No photos yet',
                          message: backup.enabled
                              ? 'Photos show up here as they back up.'
                              : 'Turn on backup, or upload photos and videos.',
                          compact: true,
                        ),
                ),
        ),
      ),
    );
  }
}

/// Points to Not backed up while something is stuck: photos out of tries,
/// or photos waiting while backup isn't moving. While backup is moving, the
/// status line above already counts what is left, so the row names only
/// the failures.
class _StuckRow extends ConsumerWidget {
  const _StuckRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final backup = ref.watch(backupControllerProvider);
    final waiting = backup.remaining > 0 && !backup.isWorking;
    if (backup.failed == 0 && !waiting) return const SizedBox.shrink();

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.line)),
      ),
      child: InkWell(
        onTap: () => context.push('/backup/not-backed-up'),
        child: SizedBox(
          height: 40,
          child: Padding(
            padding: const EdgeInsets.only(left: Space.gutter, right: Space.m),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    [
                      if (waiting) '${Formatters.number(backup.remaining)} waiting',
                      if (backup.failed > 0)
                        '${Formatters.number(backup.failed)} didn\'t back up',
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodySmall?.copyWith(fontFeatures: tabularFigures),
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: colors.text3),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Says which folders the timeline leaves out, with Show to bring them in
/// until the app closes. Only there while one of them has something in it.
class _KeptOutRow extends ConsumerWidget {
  const _KeptOutRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final keptOut = ref.watch(keptOutSummaryProvider);
    final revealed = ref.watch(revealHiddenProvider);
    if (keptOut.count == 0) return const SizedBox.shrink();
    void toggle() => ref.read(revealHiddenProvider.notifier).toggle();

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.line)),
      ),
      child: InkWell(
        onTap: toggle,
        child: SizedBox(
          height: 44,
          child: Padding(
            padding: const EdgeInsets.only(left: Space.gutter, right: Space.s),
            child: Row(
              children: [
                Icon(
                  revealed ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  size: 20,
                  color: colors.text3,
                ),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Text(
                    keptOutSentence(keptOut.names, revealed: revealed),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodySmall,
                  ),
                ),
                TextButton(
                  onPressed: toggle,
                  child: Text(revealed ? 'Hide' : 'Show'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
