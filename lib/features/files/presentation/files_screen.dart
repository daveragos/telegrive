import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/format/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../../infrastructure/storage/preferences.dart';
import '../../drive/data/drive_repository.dart';
import '../../drive/data/drive_sync.dart';
import '../../drive/domain/drive_models.dart';
import '../data/browse_preferences.dart';
import 'file_actions.dart';
import 'file_tiles.dart';

/// The folder browser. `folderId == null` is the drive root.
class FilesScreen extends ConsumerStatefulWidget {
  const FilesScreen({super.key, this.folderId});

  final String? folderId;

  @override
  ConsumerState<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends ConsumerState<FilesScreen> {
  /// Selected files and folders, by id.
  final Set<String> _files = {};
  final Set<String> _folders = {};

  bool get _selecting => _files.isNotEmpty || _folders.isNotEmpty;

  void _clearSelection() => setState(() {
    _files.clear();
    _folders.clear();
  });

  void _toggleFile(DriveFile file) => setState(() {
    if (!_files.remove(file.id)) _files.add(file.id);
  });

  void _toggleFolder(DriveFolder folder) => setState(() {
    if (!_folders.remove(folder.id)) _folders.add(folder.id);
  });

  @override
  Widget build(BuildContext context) {
    final contents = ref.watch(folderContentsProvider(widget.folderId));
    final prefs = ref.watch(browsePreferencesProvider);
    final crumbs = ref.watch(breadcrumbsProvider(widget.folderId)).value ?? const [];
    final title = widget.folderId == null
        ? 'Files'
        : (crumbs.isNotEmpty ? crumbs.last.name : '');
    final data = contents.value?.sorted(prefs.sort);

    // Drop selections that vanished (deleted elsewhere, moved away).
    if (data != null && _selecting) {
      _files.retainWhere((id) => data.files.any((f) => f.id == id));
      _folders.retainWhere((id) => data.folders.any((f) => f.id == id));
    }

    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _clearSelection();
      },
      child: Scaffold(
        appBar: _selecting
            ? _selectionBar(context, data)
            : AppBar(
                toolbarHeight: widget.folderId == null ? 64 : kToolbarHeight,
                title: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: widget.folderId == null ? context.text.headlineSmall : null,
                ),
                actions: [
                  IconButton(
                    onPressed: () => context.push('/search'),
                    icon: const Icon(Icons.search_rounded),
                    tooltip: 'Search',
                  ),
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
                  _SortButton(sort: prefs.sort),
                  const SizedBox(width: 4),
                ],
              ),
        floatingActionButton: _selecting
            ? null
            : FloatingActionButton.extended(
                heroTag: 'files-fab-${widget.folderId}',
                onPressed: () => FileActions.showCreateSheet(
                  context,
                  ref,
                  folderId: widget.folderId,
                ),
                icon: const Icon(Icons.add_rounded),
                label: const Text('New'),
              ),
        body: RefreshIndicator(
          onRefresh: () => ref.read(driveSyncProvider.notifier).refresh(),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              if (widget.folderId != null)
                SliverToBoxAdapter(child: _Breadcrumbs(crumbs: crumbs)),
              if (data == null)
                const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (data.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    title: widget.folderId == null
                        ? 'Nothing here yet'
                        : 'This folder is empty',
                    message: 'Upload files, or tap New to make a folder.',
                    action: FilledButton(
                      onPressed: () =>
                          FileActions.upload(context, ref, folderId: widget.folderId),
                      child: const Text('Upload files'),
                    ),
                  ),
                )
              else ...[
                SliverToBoxAdapter(child: _Summary(contents: data)),
                if (prefs.viewMode == ViewMode.list)
                  ..._listSlivers(data)
                else
                  ..._gridSlivers(data),
                const SliverToBoxAdapter(child: SizedBox(height: 112)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// The first label sits close under the summary line.
  static const _firstHeader = EdgeInsets.fromLTRB(Space.gutter, Space.s, Space.m, Space.s);

  void _openFolder(DriveFolder folder) => context.push('/files/${folder.id}');

  void _onFolderTap(DriveFolder folder) =>
      _selecting ? _toggleFolder(folder) : _openFolder(folder);

  void _onFileTap(DriveFile file) =>
      _selecting ? _toggleFile(file) : FileActions.open(context, ref, file);

  List<Widget> _listSlivers(FolderContents data) => [
    if (data.folders.isNotEmpty && data.files.isNotEmpty)
      const SliverToBoxAdapter(child: SectionHeader('Folders', padding: _firstHeader)),
    SliverList.builder(
      itemCount: data.folders.length,
      itemBuilder: (context, index) {
        final folder = data.folders[index];
        return FolderListTile(
          folder: folder,
          selected: _folders.contains(folder.id),
          selecting: _selecting,
          onTap: () => _onFolderTap(folder),
          onLongPress: () => _toggleFolder(folder),
          onMore: () => FileActions.showFolderSheet(context, ref, folder),
        );
      },
    ),
    if (data.folders.isNotEmpty && data.files.isNotEmpty)
      const SliverToBoxAdapter(child: SectionHeader('Files')),
    SliverList.builder(
      itemCount: data.files.length,
      itemBuilder: (context, index) {
        final file = data.files[index];
        return FileListTile(
          file: file,
          selected: _files.contains(file.id),
          selecting: _selecting,
          onTap: () => _onFileTap(file),
          onLongPress: () => _toggleFile(file),
          onMore: () => FileActions.showFileSheet(context, ref, file),
        );
      },
    ),
  ];

  List<Widget> _gridSlivers(FolderContents data) => [
    if (data.folders.isNotEmpty) ...[
      const SliverToBoxAdapter(child: SectionHeader('Folders', padding: _firstHeader)),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: Space.l),
        sliver: SliverGrid.builder(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 240,
            mainAxisExtent: 52,
            crossAxisSpacing: Space.s,
            mainAxisSpacing: Space.s,
          ),
          itemCount: data.folders.length,
          itemBuilder: (context, index) {
            final folder = data.folders[index];
            return FolderGridCard(
              folder: folder,
              selected: _folders.contains(folder.id),
              selecting: _selecting,
              onTap: () => _onFolderTap(folder),
              onLongPress: () => _toggleFolder(folder),
              onMore: () => FileActions.showFolderSheet(context, ref, folder),
            );
          },
        ),
      ),
    ],
    if (data.files.isNotEmpty) ...[
      if (data.folders.isNotEmpty)
        const SliverToBoxAdapter(child: SectionHeader('Files')),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: Space.l),
        sliver: SliverGrid.builder(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 200,
            childAspectRatio: 0.8,
            crossAxisSpacing: Space.m,
            mainAxisSpacing: Space.l,
          ),
          itemCount: data.files.length,
          itemBuilder: (context, index) {
            final file = data.files[index];
            return FileGridCard(
              file: file,
              selected: _files.contains(file.id),
              selecting: _selecting,
              onTap: () => _onFileTap(file),
              onLongPress: () => _toggleFile(file),
              onMore: () => FileActions.showFileSheet(context, ref, file),
            );
          },
        ),
      ),
    ],
  ];

  PreferredSizeWidget _selectionBar(BuildContext context, FolderContents? data) {
    final files = data?.files.where((f) => _files.contains(f.id)).toList() ?? [];
    final folders = data?.folders.where((f) => _folders.contains(f.id)).toList() ?? [];
    final count = files.length + folders.length;
    final allStarred = files.isNotEmpty && files.every((f) => f.starred);
    final scheme = Theme.of(context).colorScheme;

    return AppBar(
      backgroundColor: scheme.primaryContainer.withValues(alpha: 0.5),
      leading: IconButton(
        onPressed: _clearSelection,
        icon: const Icon(Icons.close_rounded),
        tooltip: 'Clear selection',
      ),
      // The count alone: five actions leave no room for "selected".
      title: Text(Formatters.number(count)),
      actions: [
        if (files.isNotEmpty && folders.isEmpty)
          IconButton(
            onPressed: () async {
              await FileActions.setStarred(context, ref, files, starred: !allStarred);
              _clearSelection();
            },
            icon: Icon(allStarred ? Icons.star_rounded : Icons.star_outline_rounded),
            tooltip: allStarred ? 'Unstar' : 'Star',
          ),
        IconButton(
          onPressed: () async {
            final saving = await FileActions.saveToDevice(
              context,
              ref,
              files: files,
              folders: folders,
            );
            if (saving) _clearSelection();
          },
          icon: const Icon(Icons.download_rounded),
          tooltip: 'Download to this phone',
        ),
        IconButton(
          onPressed: () async {
            final moved = await FileActions.move(
              context,
              ref,
              files: files,
              folders: folders,
            );
            if (moved) _clearSelection();
          },
          icon: const Icon(Icons.drive_file_move_outline),
          tooltip: 'Move',
        ),
        IconButton(
          onPressed: () async {
            final deleted = await FileActions.delete(
              context,
              ref,
              files: files,
              folders: folders,
            );
            if (deleted) _clearSelection();
          },
          icon: const Icon(Icons.delete_outline_rounded),
          tooltip: 'Delete',
        ),
        IconButton(
          onPressed: data == null
              ? null
              : () => setState(() {
                  _files.addAll(data.files.map((f) => f.id));
                  _folders.addAll(data.folders.map((f) => f.id));
                }),
          icon: const Icon(Icons.select_all_rounded),
          tooltip: 'Select all',
        ),
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.contents});

  final FolderContents contents;

  @override
  Widget build(BuildContext context) {
    final parts = [
      if (contents.folders.isNotEmpty) Formatters.count(contents.folders.length, 'folder'),
      if (contents.files.isNotEmpty) Formatters.count(contents.files.length, 'file'),
      if (contents.files.isNotEmpty) Formatters.bytes(contents.totalBytes),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.s),
      child: Text(
        parts.join(' · '),
        style: context.text.bodySmall?.copyWith(fontFeatures: tabularFigures),
      ),
    );
  }
}

class _Breadcrumbs extends StatelessWidget {
  const _Breadcrumbs({required this.crumbs});

  final List<DriveFolder> crumbs;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final entries = <(String label, String location)>[
      ('Files', '/files'),
      for (final folder in crumbs) (folder.name, '/files/${folder.id}'),
    ];
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        reverse: true,
        padding: const EdgeInsets.symmetric(horizontal: Space.m),
        itemCount: entries.length,
        separatorBuilder: (_, _) =>
            Icon(Icons.chevron_right_rounded, size: 16, color: colors.text3),
        itemBuilder: (context, reversedIndex) {
          final index = entries.length - 1 - reversedIndex;
          final (label, location) = entries[index];
          final isLast = index == entries.length - 1;
          return Center(
            child: InkWell(
              borderRadius: BorderRadius.circular(Radii.thumb),
              onTap: isLast ? null : () => context.go(location),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.s, vertical: Space.xs),
                child: Text(
                  label,
                  style: context.text.bodyMedium?.copyWith(
                    color: isLast ? colors.text : colors.text2,
                    fontWeight: isLast ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SortButton extends ConsumerWidget {
  const _SortButton({required this.sort});

  final SortOrder sort;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<SortField>(
      tooltip: 'Sort',
      icon: const Icon(Icons.sort_rounded),
      onSelected: (field) => ref.read(browsePreferencesProvider.notifier).sortBy(field),
      itemBuilder: (context) => [
        for (final field in SortField.values)
          PopupMenuItem(
            value: field,
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  child: field == sort.field
                      ? Icon(
                          sort.descending
                              ? Icons.arrow_downward_rounded
                              : Icons.arrow_upward_rounded,
                          size: 18,
                        )
                      : null,
                ),
                Text(field.label),
              ],
            ),
          ),
      ],
    );
  }
}
