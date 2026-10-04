import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/files/file_kind.dart';
import '../../../core/format/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/selection_bar.dart';
import '../../../infrastructure/database/app_database.dart' show FolderSize;
import '../../../infrastructure/storage/preferences.dart';
import '../../drive/data/drive_repository.dart';
import '../../drive/domain/drive_models.dart';
import '../data/browse_preferences.dart';
import 'file_actions.dart';
import 'file_location.dart';
import 'file_selection_bar.dart';
import 'file_tiles.dart';

/// The last files this phone opened, shared or sent, most recent first.
final recentOpenedProvider = StreamProvider.autoDispose<List<RecentEntry>>(
  (ref) => ref
      .watch(driveRepositoryProvider)
      .watchRecentOpens(limit: 200)
      .map(
        (opens) => [
          for (final (file, at) in opens)
            RecentEntry(file, at: at, opened: true),
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
/// Starred lists the starred folders first, each with what it holds.
/// Long-press a file, or tap Select, to pick several and act on them at
/// once from the bar at the foot.
class FileListScreen extends ConsumerStatefulWidget {
  const FileListScreen.kind(FileKind this.kind, {super.key})
    : mode = FileListMode.kind;
  const FileListScreen.starred({super.key})
    : kind = null,
      mode = FileListMode.starred;
  const FileListScreen.recent({super.key})
    : kind = null,
      mode = FileListMode.recent;

  final FileKind? kind;
  final FileListMode mode;

  @override
  ConsumerState<FileListScreen> createState() => _FileListScreenState();
}

class _FileListScreenState extends ConsumerState<FileListScreen> {
  /// Which half of Recent is showing. Picked once both halves have loaded,
  /// so opening something from Added doesn't flip the list underneath.
  RecentMode? _recent;

  /// Selected files, by id.
  final Set<String> _selected = {};

  /// Select was tapped, so the list is selecting before anything is.
  bool _selectMode = false;

  bool get _selecting => _selectMode || _selected.isNotEmpty;

  void _toggle(DriveFile file) => setState(() {
    if (!_selected.remove(file.id)) _selected.add(file.id);
  });

  void _clearSelection() => setState(() {
    _selectMode = false;
    _selected.clear();
  });

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
    final listed = switch (widget.mode) {
      FileListMode.starred => ref.watch(starredFilesProvider),
      FileListMode.kind => ref.watch(kindFilesProvider(kind!)),
      FileListMode.recent => null,
    };
    final opened = widget.mode == FileListMode.recent
        ? ref.watch(recentOpenedProvider)
        : null;
    final added = widget.mode == FileListMode.recent
        ? ref.watch(recentAddedProvider)
        : null;
    final recent = _recentShown(opened?.value, added?.value);
    final loaded = listed?.value ?? recent?.entries.map((e) => e.file).toList();
    final shown = loaded ?? const <DriveFile>[];
    final starred = widget.mode == FileListMode.starred;
    final starredFolders = starred
        ? ref.watch(starredFoldersProvider).value ?? const <DriveFolder>[]
        : const <DriveFolder>[];
    final folderSizes = starred
        ? ref.watch(starredFolderSizesProvider).value
        : null;

    // Drop selections that vanished: unstarred, deleted, or in the other
    // half of Recent.
    if (loaded != null && _selected.isNotEmpty) {
      final ids = {for (final file in loaded) file.id};
      _selected.retainWhere(ids.contains);
    }
    final picked = [
      for (final file in shown)
        if (_selected.contains(file.id)) file,
    ];

    Widget list(List<DriveFile> files, {Key? key, List<String>? subtitles}) =>
        _Files(
          key: key,
          files: files,
          folders: starredFolders,
          folderSizes: folderSizes,
          subtitles: subtitles,
          grid: grid,
          selected: _selected,
          selecting: _selecting,
          onToggle: _toggle,
        );

    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _clearSelection();
      },
      child: Scaffold(
        appBar: _selecting
            ? selectionAppBar(
                context,
                count: picked.length,
                bytes: picked.fold(0, (sum, f) => sum + f.size),
                onClear: _clearSelection,
              )
            : AppBar(
                title: Text(title),
                actions: [
                  IconButton(
                    onPressed: () => context.push(
                      widget.mode == FileListMode.kind
                          ? '/search?kind=${kind!.name}'
                          : '/search',
                    ),
                    icon: const Icon(Icons.search_rounded),
                    tooltip: 'Search',
                  ),
                  IconButton(
                    onPressed: () => setState(() => _selectMode = true),
                    icon: const Icon(Icons.checklist_rounded),
                    tooltip: 'Select',
                  ),
                  IconButton(
                    onPressed: () => ref
                        .read(browsePreferencesProvider.notifier)
                        .toggleViewMode(),
                    icon: Icon(
                      prefs.viewMode == ViewMode.list
                          ? Icons.grid_view_rounded
                          : Icons.view_agenda_outlined,
                    ),
                    tooltip: prefs.viewMode == ViewMode.list
                        ? 'Grid view'
                        : 'List view',
                  ),
                  const SizedBox(width: 4),
                ],
              ),
        bottomNavigationBar: _selecting
            ? fileSelectionActions(
                context,
                ref,
                files: picked,
                onDone: _clearSelection,
                onSelectAll: () =>
                    setState(() => _selected.addAll(shown.map((f) => f.id))),
              )
            : null,
        body: switch (widget.mode) {
          FileListMode.recent => _recentBody(opened!, added!, recent, list),
          FileListMode.kind ||
          FileListMode.starred => AsyncView<List<DriveFile>>(
            value: listed!,
            data: (files) {
              if (files.isEmpty && starredFolders.isEmpty) {
                return starred
                    ? const EmptyState(
                        title: 'Nothing starred yet',
                        message:
                            'Star the files and folders you reach for often and '
                            'they\'ll wait here.',
                      )
                    : EmptyState(
                        title: 'No ${kind!.label.toLowerCase()} yet',
                        message: 'Files you upload will show up here.',
                      );
              }
              return list(files);
            },
          ),
        },
      ),
    );
  }

  /// The half of Recent showing and its entries, once both halves have
  /// loaded.
  ({RecentMode mode, List<RecentEntry> entries})? _recentShown(
    List<RecentEntry>? opened,
    List<DriveFile>? added,
  ) {
    if (opened == null || added == null) return null;
    final mode = _recent ??= opened.isNotEmpty
        ? RecentMode.opened
        : RecentMode.added;
    return (
      mode: mode,
      entries: switch (mode) {
        RecentMode.opened => opened,
        RecentMode.added => [
          for (final file in added)
            RecentEntry(file, at: file.createdAt, opened: false),
        ],
      },
    );
  }

  /// Both halves are watched in [build] and handed in, so neither is
  /// dropped when only one of them has loaded.
  Widget _recentBody(
    AsyncValue<List<RecentEntry>> opened,
    AsyncValue<List<DriveFile>> added,
    ({RecentMode mode, List<RecentEntry> entries})? recent,
    Widget Function(List<DriveFile> files, {Key? key, List<String>? subtitles})
    list,
  ) {
    return AsyncView<List<RecentEntry>>(
      value: opened,
      data: (_) => AsyncView<List<DriveFile>>(
        value: added,
        data: (_) {
          final (:mode, :entries) = recent!;
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
                    ButtonSegment(
                      value: RecentMode.opened,
                      label: Text('Opened'),
                    ),
                    ButtonSegment(
                      value: RecentMode.added,
                      label: Text('Added'),
                    ),
                  ],
                  selected: {mode},
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                  onSelectionChanged: (value) =>
                      setState(() => _recent = value.first),
                ),
              ),
              Expanded(
                child: entries.isEmpty
                    ? switch (mode) {
                        RecentMode.opened => const EmptyState(
                          title: 'Nothing opened yet',
                          message:
                              'Files you open, share or send show up here.',
                        ),
                        RecentMode.added => const EmptyState(
                          title: 'Nothing yet',
                          message: 'Files you upload will show up here.',
                        ),
                      }
                    // Keyed by half, so each opens at the top of its list.
                    : list(
                        [for (final entry in entries) entry.file],
                        key: ValueKey(mode),
                        subtitles: [
                          for (final entry in entries)
                            '${Formatters.bytes(entry.file.size)} · '
                                '${entry.verb} ${Formatters.date(entry.at)}',
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A count line, then [folders] and [files] as rows or a grid, the folders
/// under their own label when there are any. Each file row ends with the
/// folder its file lives in, since the list mixes files from everywhere,
/// and a folder row says what the folder holds. While [selecting], a tap
/// picks a file rather than opening it; a long-press always does. Folders
/// open where they are in Files, and sit still while selecting, since only
/// files are picked here.
class _Files extends ConsumerWidget {
  const _Files({
    super.key,
    required this.files,
    required this.grid,
    required this.selected,
    required this.selecting,
    required this.onToggle,
    this.folders = const [],
    this.folderSizes,
    this.subtitles,
  });

  final List<DriveFile> files;
  final List<DriveFolder> folders;

  /// Each folder's id to what it holds, for its row; null until counted.
  final Map<String, FolderSize>? folderSizes;
  final bool grid;
  final Set<String> selected;
  final bool selecting;
  final ValueChanged<DriveFile> onToggle;

  /// Each row's meta line before its folder, in place of the default
  /// "size · date". The grid keeps its size-only cards.
  final List<String>? subtitles;

  void _tap(BuildContext context, WidgetRef ref, DriveFile file) =>
      selecting ? onToggle(file) : FileActions.open(context, ref, file);

  VoidCallback? _openFolder(BuildContext context, DriveFolder folder) =>
      selecting ? null : () => context.go('/files/${folder.id}');

  /// The label over the folders, close under the count line.
  static const _firstHeader = EdgeInsets.fromLTRB(
    Space.gutter,
    Space.s,
    Space.m,
    Space.s,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final total = files.fold<int>(0, (sum, f) => sum + f.size);
    // With folders alone the line names just them, rather than '0 files'.
    final countFiles = files.isNotEmpty || folders.isEmpty;
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
      child: Text(
        [
          if (folders.isNotEmpty) Formatters.count(folders.length, 'folder'),
          if (countFiles) Formatters.count(files.length, 'file'),
          if (countFiles) Formatters.bytes(total),
        ].join(' · '),
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
    final labelled = folders.isNotEmpty && files.isNotEmpty;
    // Null until the folders are read; rows then go without a place rather
    // than all reading 'Files'.
    final byId = grid ? null : ref.watch(folderIndexProvider).value;
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: header),
        if (folders.isNotEmpty) ...[
          if (labelled)
            const SliverToBoxAdapter(
              child: SectionHeader('Folders', padding: _firstHeader),
            ),
          if (grid)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: Space.l),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 240,
                  mainAxisExtent: 52,
                  crossAxisSpacing: Space.s,
                  mainAxisSpacing: Space.s,
                ),
                itemCount: folders.length,
                itemBuilder: (context, index) {
                  final folder = folders[index];
                  return FolderGridCard(
                    folder: folder,
                    selecting: selecting,
                    onTap: _openFolder(context, folder),
                    onMore: () =>
                        FileActions.showFolderSheet(context, ref, folder),
                  );
                },
              ),
            )
          else
            SliverList.builder(
              itemCount: folders.length,
              itemBuilder: (context, index) {
                final folder = folders[index];
                return FolderListTile(
                  folder: folder,
                  subtitle: folderContentsLine(folderSizes?[folder.id]),
                  selecting: selecting,
                  onTap: _openFolder(context, folder),
                  onMore: () =>
                      FileActions.showFolderSheet(context, ref, folder),
                );
              },
            ),
          if (labelled) const SliverToBoxAdapter(child: SectionHeader('Files')),
        ],
        if (grid)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
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
                  selected: selected.contains(file.id),
                  selecting: selecting,
                  onTap: () => _tap(context, ref, file),
                  onLongPress: () => onToggle(file),
                  onMore: () => FileActions.showFileSheet(context, ref, file),
                );
              },
            ),
          )
        else
          SliverList.builder(
            itemCount: files.length,
            itemBuilder: (context, index) {
              final file = files[index];
              return FileListTile(
                file: file,
                subtitle: [
                  subtitles?[index] ?? fileMetaLine(file),
                  if (byId != null) locationOf(byId, file.folderId),
                ].join(' · '),
                selected: selected.contains(file.id),
                selecting: selecting,
                onTap: () => _tap(context, ref, file),
                onLongPress: () => onToggle(file),
                onMore: () => FileActions.showFileSheet(context, ref, file),
              );
            },
          ),
        // Room under the last row or card, whichever list ends the screen.
        const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
      ],
    );
  }
}

enum FileListMode { kind, starred, recent }

/// The two halves of Recent.
enum RecentMode { opened, added }
