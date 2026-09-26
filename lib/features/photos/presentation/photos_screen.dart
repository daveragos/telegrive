import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/file_visuals.dart';
import '../../backup/data/backup_controller.dart';
import '../../backup/presentation/backup_card.dart';
import '../../drive/data/drive_repository.dart';
import '../../drive/data/drive_sync.dart';
import '../../drive/domain/drive_models.dart';
import '../../files/presentation/file_actions.dart';

/// Every photo and video in the drive as one timeline, newest moment first,
/// with backup status on top.
class PhotosScreen extends ConsumerWidget {
  const PhotosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final media = ref.watch(mediaTimelineProvider);
    final backup = ref.watch(backupControllerProvider);
    final sections = media.value == null ? null : _byMonth(media.value!);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        title: Text('Photos', style: context.text.headlineSmall),
        actions: [
          if (media.value case final all? when all.isNotEmpty)
            IconButton(
              onPressed: () => FileActions.saveToDevice(
                context,
                ref,
                files: all,
                preferGallery: true,
              ),
              tooltip: 'Download all to this phone',
              icon: const Icon(Icons.download_rounded),
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
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await ref.read(driveSyncProvider.notifier).refresh();
          ref.read(backupControllerProvider.notifier).schedule(immediate: true);
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: context.colors.line),
                  ),
                ),
                child: const BackupStatusLine(),
              ),
            ),
            if (sections == null)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (sections.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  title: 'No photos yet',
                  message: backup.enabled
                      ? 'Photos show up here as they back up.'
                      : 'Turn on backup, or upload photos and videos.',
                  compact: true,
                ),
              )
            else
              for (final section in sections) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Space.gutter,
                      Space.xxl,
                      Space.gutter,
                      Space.s,
                    ),
                    child: Text(section.title, style: context.text.titleSmall),
                  ),
                ),
                SliverGrid.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 128,
                    mainAxisSpacing: 2,
                    crossAxisSpacing: 2,
                  ),
                  itemCount: section.files.length,
                  itemBuilder: (context, index) {
                    final file = section.files[index];
                    return _PhotoTile(
                      file: file,
                      onTap: () =>
                          context.push('/viewer/${file.id}?from=photos'),
                      onLongPress: () =>
                          FileActions.showFileSheet(context, ref, file),
                    );
                  },
                ),
              ],
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }

  static List<_Section> _byMonth(List<DriveFile> files) {
    final now = DateTime.now();
    final sections = <_Section>[];
    for (final file in files) {
      final moment = file.momentAt;
      final title = moment.year == now.year && moment.month == now.month
          ? 'This month'
          : moment.year == now.year
          ? DateFormat.MMMM().format(moment)
          : DateFormat.yMMMM().format(moment);
      if (sections.isEmpty || sections.last.title != title) {
        sections.add(_Section(title, []));
      }
      sections.last.files.add(file);
    }
    return sections;
  }
}

class _Section {
  _Section(this.title, this.files);

  final String title;
  final List<DriveFile> files;
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({
    required this.file,
    required this.onTap,
    required this.onLongPress,
  });

  final DriveFile file;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Stack(
        fit: StackFit.expand,
        children: [
          FileThumbnail(file: file, expand: true, radius: 0, size: 40),
          if (file.starred)
            const Positioned(
              right: 4,
              top: 4,
              child: Icon(
                Icons.star_rounded,
                size: 16,
                color: Colors.white,
                shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
              ),
            ),
        ],
      ),
    );
  }
}
