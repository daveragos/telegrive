import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/widgets/common.dart';
import '../../backup/data/backup_controller.dart';
import '../../backup/presentation/backup_card.dart';
import '../../backup/presentation/duplicates_sheet.dart';
import '../../backup/presentation/free_up_space_sheet.dart';
import '../../drive/data/drive_repository.dart';
import '../../drive/data/drive_sync.dart';
import '../../files/presentation/file_actions.dart';
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
    final media = ref.watch(mediaTimelineProvider);
    final backup = ref.watch(backupControllerProvider);
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
                  ],
                  empty: EmptyState(
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
