import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/files/file_kind.dart';
import '../../../core/format/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../../infrastructure/storage/preferences.dart';
import '../../drive/data/drive_repository.dart';
import '../../drive/domain/drive_models.dart';
import '../data/browse_preferences.dart';
import 'file_actions.dart';
import 'file_tiles.dart';

final _recentAllProvider = StreamProvider.autoDispose<List<DriveFile>>(
  (ref) => ref.watch(driveRepositoryProvider).watchRecent(limit: 200),
);

/// A flat list of files across folders: a category, Starred or Recent.
class FileListScreen extends ConsumerWidget {
  const FileListScreen.kind(FileKind this.kind, {super.key}) : mode = FileListMode.kind;
  const FileListScreen.starred({super.key}) : kind = null, mode = FileListMode.starred;
  const FileListScreen.recent({super.key}) : kind = null, mode = FileListMode.recent;

  final FileKind? kind;
  final FileListMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(browsePreferencesProvider);
    final value = switch (mode) {
      FileListMode.kind => ref.watch(kindFilesProvider(kind!)),
      FileListMode.starred => ref.watch(starredFilesProvider),
      FileListMode.recent => ref.watch(_recentAllProvider),
    };
    final title = switch (mode) {
      FileListMode.kind => kind!.label,
      FileListMode.starred => 'Starred',
      FileListMode.recent => 'Recent',
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            onPressed: () =>
                ref.read(browsePreferencesProvider.notifier).toggleViewMode(),
            icon: Icon(
              prefs.viewMode == ViewMode.list
                  ? Icons.grid_view_rounded
                  : Icons.view_agenda_outlined,
            ),
            tooltip: prefs.viewMode == ViewMode.list ? 'Grid view' : 'List view',
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: AsyncView<List<DriveFile>>(
        value: value,
        data: (files) {
          if (files.isEmpty) {
            return EmptyState(
              title: switch (mode) {
                FileListMode.starred => 'No starred files',
                FileListMode.recent => 'Nothing yet',
                FileListMode.kind => 'No ${kind!.label.toLowerCase()} yet',
              },
              message: mode == FileListMode.starred
                  ? 'Star the files you reach for often and they\'ll wait here.'
                  : 'Files you upload will show up here.',
            );
          }
          final total = files.fold<int>(0, (sum, f) => sum + f.size);
          final header = Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
            child: Text(
              '${Formatters.count(files.length, 'file')} · ${Formatters.bytes(total)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          );
          if (prefs.viewMode == ViewMode.grid) {
            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: header),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  sliver: SliverGrid.builder(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 200,
                      childAspectRatio: 0.84,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    itemCount: files.length,
                    itemBuilder: (context, index) {
                      final file = files[index];
                      return FileGridCard(
                        file: file,
                        onTap: () => FileActions.open(context, ref, file),
                        onLongPress: () => FileActions.showFileSheet(context, ref, file),
                        onMore: () => FileActions.showFileSheet(context, ref, file),
                      );
                    },
                  ),
                ),
              ],
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 24),
            itemCount: files.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) return header;
              final file = files[index - 1];
              return FileListTile(
                file: file,
                onTap: () => FileActions.open(context, ref, file),
                onLongPress: () => FileActions.showFileSheet(context, ref, file),
                onMore: () => FileActions.showFileSheet(context, ref, file),
              );
            },
          );
        },
      ),
    );
  }
}

enum FileListMode { kind, starred, recent }
