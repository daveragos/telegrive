import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/files/file_kind.dart';
import '../../../core/format/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../../infrastructure/storage/preferences.dart';
import '../../drive/data/drive_repository.dart';
import '../../drive/domain/drive_models.dart';
import '../data/browse_preferences.dart';
import 'file_actions.dart';
import 'file_tiles.dart';

/// The last files this phone opened, shared or sent, most recent first.
final recentOpenedProvider = StreamProvider.autoDispose<List<RecentEntry>>(
  (ref) => ref
      .watch(driveRepositoryProvider)
      .watchRecentOpens(limit: 200)
      .map(
        (opens) => [
          for (final (file, at) in opens) RecentEntry(file, at: at, opened: true),
        ],
      ),
);

/// The last files added by hand or from another device, newest first.
/// Camera-roll backups are left to Photos.
final recentAddedProvider = StreamProvider.autoDispose<List<DriveFile>>(
  (ref) => ref
      .watch(driveRepositoryProvider)
      .watchRecent(limit: 200, excludeCameraRoll: true),
);

/// A flat list of files across folders: a category, Starred or Recent.
class FileListScreen extends ConsumerStatefulWidget {
  const FileListScreen.kind(FileKind this.kind, {super.key}) : mode = FileListMode.kind;
  const FileListScreen.starred({super.key}) : kind = null, mode = FileListMode.starred;
  const FileListScreen.recent({super.key}) : kind = null, mode = FileListMode.recent;

  final FileKind? kind;
  final FileListMode mode;

  @override
  ConsumerState<FileListScreen> createState() => _FileListScreenState();
}

class _FileListScreenState extends ConsumerState<FileListScreen> {
  /// Which half of Recent is showing. Picked once both halves have loaded,
  /// so opening something from Added doesn't flip the list underneath.
  RecentMode? _recent;

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(browsePreferencesProvider);
    final grid = prefs.viewMode == ViewMode.grid;
    final kind = widget.kind;
    final title = switch (widget.mode) {
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
      body: switch (widget.mode) {
        FileListMode.recent => _recentBody(
          ref.watch(recentOpenedProvider),
          ref.watch(recentAddedProvider),
          grid: grid,
        ),
        FileListMode.kind || FileListMode.starred => AsyncView<List<DriveFile>>(
          value: widget.mode == FileListMode.starred
              ? ref.watch(starredFilesProvider)
              : ref.watch(kindFilesProvider(kind!)),
          data: (files) {
            if (files.isEmpty) {
              return widget.mode == FileListMode.starred
                  ? const EmptyState(
                      title: 'No starred files',
                      message:
                          'Star the files you reach for often and they\'ll wait here.',
                    )
                  : EmptyState(
                      title: 'No ${kind!.label.toLowerCase()} yet',
                      message: 'Files you upload will show up here.',
                    );
            }
            return _Files(files: files, grid: grid);
          },
        ),
      },
    );
  }

  /// Both halves are watched in [build] and handed in, so neither is
  /// dropped when only one of them has loaded.
  Widget _recentBody(
    AsyncValue<List<RecentEntry>> opened,
    AsyncValue<List<DriveFile>> added, {
    required bool grid,
  }) {
    return AsyncView<List<RecentEntry>>(
      value: opened,
      data: (opened) => AsyncView<List<DriveFile>>(
        value: added,
        data: (added) {
          final mode = _recent ??= opened.isNotEmpty
              ? RecentMode.opened
              : RecentMode.added;
          final entries = switch (mode) {
            RecentMode.opened => opened,
            RecentMode.added => [
              for (final file in added)
                RecentEntry(file, at: file.createdAt, opened: false),
            ],
          };
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.gutter,
                  Space.s,
                  Space.gutter,
                  Space.xs,
                ),
                child: SegmentedButton<RecentMode>(
                  segments: const [
                    ButtonSegment(value: RecentMode.opened, label: Text('Opened')),
                    ButtonSegment(value: RecentMode.added, label: Text('Added')),
                  ],
                  selected: {mode},
                  showSelectedIcon: false,
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                  onSelectionChanged: (value) =>
                      setState(() => _recent = value.first),
                ),
              ),
              Expanded(
                child: entries.isEmpty
                    ? switch (mode) {
                        RecentMode.opened => const EmptyState(
                          title: 'Nothing opened yet',
                          message: 'Files you open, share or send show up here.',
                        ),
                        RecentMode.added => const EmptyState(
                          title: 'Nothing yet',
                          message: 'Files you upload will show up here.',
                        ),
                      }
                    // Keyed by half, so each opens at the top of its list.
                    : _Files(
                        key: ValueKey(mode),
                        files: [for (final entry in entries) entry.file],
                        subtitles: [
                          for (final entry in entries)
                            '${Formatters.bytes(entry.file.size)} · '
                                '${entry.verb} ${Formatters.date(entry.at)}',
                        ],
                        grid: grid,
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A count line, then [files] as rows or a grid.
class _Files extends ConsumerWidget {
  const _Files({super.key, required this.files, required this.grid, this.subtitles});

  final List<DriveFile> files;
  final bool grid;

  /// Each row's meta line, in place of the default "size · date". The grid
  /// keeps its size-only cards.
  final List<String>? subtitles;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
    if (grid) {
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
          subtitle: subtitles?[index - 1],
          onTap: () => FileActions.open(context, ref, file),
          onLongPress: () => FileActions.showFileSheet(context, ref, file),
          onMore: () => FileActions.showFileSheet(context, ref, file),
        );
      },
    );
  }
}

enum FileListMode { kind, starred, recent }

/// The two halves of Recent.
enum RecentMode { opened, added }
