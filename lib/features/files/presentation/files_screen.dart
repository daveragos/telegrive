import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderSliver;
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
  const FilesScreen({super.key, this.folderId, this.highlight});

  final String? folderId;

  /// The id of a file to point out on arrival, from Show in folder: its
  /// row is brought into view and tinted for a moment.
  final String? highlight;

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

  /// How long a pointed-out row stays tinted before it fades.
  static const _highlightFor = Duration(milliseconds: 1500);

  /// How far down the screen a pointed-out row is brought, when it has to
  /// be brought at all.
  static const _highlightAt = 1 / 3;

  /// The file being pointed out. Its row keeps [_highlightKey] after the
  /// tint is gone, so the row is the same one while the tint fades out.
  String? _highlightId;
  bool _tinted = false;
  bool _scrolledToHighlight = false;
  Timer? _highlightTimer;
  final _highlightKey = GlobalKey();
  final _filesListKey = GlobalKey();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _startHighlight();
  }

  @override
  void didUpdateWidget(FilesScreen old) {
    super.didUpdateWidget(old);
    // Showing this folder again for another file keeps this screen, so the
    // new file is pointed out here.
    if (widget.highlight != old.highlight) _startHighlight();
  }

  @override
  void dispose() {
    _highlightTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _startHighlight() {
    _highlightTimer?.cancel();
    _highlightId = widget.highlight;
    _tinted = false;
    _scrolledToHighlight = false;
  }

  /// Brings the pointed-out row into view and tints it. The tint goes on
  /// once the folder has been read rather than when the screen opens, so a
  /// slow first read doesn't use up its moment. A file that isn't here
  /// leaves the folder as it is, with nothing tinted.
  void _showHighlight(FolderContents data, ViewMode mode) {
    if (!mounted) return;
    final index = data.files.indexWhere((f) => f.id == _highlightId);
    if (index < 0) return;
    setState(() => _tinted = true);
    _highlightTimer?.cancel();
    _highlightTimer = Timer(_highlightFor, () {
      if (mounted) setState(() => _tinted = false);
    });
    // Rows are built only near the screen, so in a long list the row may
    // not exist yet: jump to about where it is, then ease it into place
    // once it has been built.
    final offset = mode == ViewMode.list && _highlightKey.currentContext == null
        ? _listOffsetOf(index, data.files.length)
        : null;
    if (offset == null || !_scroll.hasClients) {
      _easeToHighlight();
      return;
    }
    final position = _scroll.position;
    _scroll.jumpTo(
      (offset - position.viewportDimension * _highlightAt)
          .clamp(0.0, position.maxScrollExtent),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _easeToHighlight());
  }

  /// Where the row of the file at [index] starts in list view. The files'
  /// list knows where it begins and, from the rows it has built, how tall
  /// a row is, so this holds at any text size.
  double? _listOffsetOf(int index, int count) {
    final sliver = _filesListKey.currentContext?.findRenderObject();
    if (sliver is! RenderSliver || sliver.geometry == null) return null;
    final row = sliver.geometry!.scrollExtent / count;
    return sliver.constraints.precedingScrollExtent + index * row;
  }

  /// Eases the pointed-out row onto the screen. A row already wholly on
  /// it stays where it is, so the list doesn't shift under the person.
  void _easeToHighlight() {
    final row = _highlightKey.currentContext;
    if (row == null || _whollyInView(row)) return;
    Scrollable.ensureVisible(
      row,
      alignment: _highlightAt,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  bool _whollyInView(BuildContext row) {
    final box = row.findRenderObject();
    final view = Scrollable.maybeOf(row)?.context.findRenderObject();
    if (box is! RenderBox || view is! RenderBox || !box.hasSize) return false;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    final visible = view.localToGlobal(Offset.zero) & view.size;
    return rect.top >= visible.top && rect.bottom <= visible.bottom;
  }

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
    if (data != null && _highlightId != null && !_scrolledToHighlight) {
      _scrolledToHighlight = true;
      final mode = prefs.viewMode;
      WidgetsBinding.instance.addPostFrameCallback((_) => _showHighlight(data, mode));
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
                    onPressed: () => context.push(
                      widget.folderId == null
                          ? '/search'
                          : '/search?folder=${Uri.encodeQueryComponent(widget.folderId!)}',
                    ),
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
                  if (widget.folderId == null)
                    IconButton(
                      onPressed: () => context.push('/trash'),
                      icon: const Icon(Icons.delete_outline_rounded),
                      tooltip: 'Trash',
                    ),
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
            controller: _scroll,
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
      key: _filesListKey,
      itemCount: data.files.length,
      itemBuilder: (context, index) {
        final file = data.files[index];
        final pointed = file.id == _highlightId;
        return FileListTile(
          key: pointed ? _highlightKey : null,
          file: file,
          highlighted: pointed && _tinted,
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
            final pointed = file.id == _highlightId;
            return FileGridCard(
              key: pointed ? _highlightKey : null,
              file: file,
              highlighted: pointed && _tinted,
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
    final onlyFiles = files.isNotEmpty && folders.isEmpty;
    final scheme = Theme.of(context).colorScheme;

    Future<void> then(Future<bool> action) async {
      if (await action) _clearSelection();
    }

    return AppBar(
      backgroundColor: scheme.primaryContainer.withValues(alpha: 0.5),
      leading: IconButton(
        onPressed: _clearSelection,
        icon: const Icon(Icons.close_rounded),
        tooltip: 'Clear selection',
      ),
      // The count alone: the actions leave no room for "selected".
      title: Text(Formatters.number(count)),
      actions: [
        IconButton(
          onPressed: () => then(
            FileActions.saveToDevice(context, ref, files: files, folders: folders),
          ),
          icon: const Icon(Icons.download_rounded),
          tooltip: 'Download to this phone',
        ),
        if (onlyFiles)
          IconButton(
            onPressed: () => then(FileActions.sendToChats(context, ref, files)),
            icon: const Icon(Icons.send_outlined),
            tooltip: 'Send in Telegram',
          ),
        IconButton(
          onPressed: () => then(FileActions.move(context, ref, files: files, folders: folders)),
          icon: const Icon(Icons.drive_file_move_outline),
          tooltip: 'Move',
        ),
        IconButton(
          onPressed: () => then(FileActions.delete(context, ref, files: files, folders: folders)),
          icon: const Icon(Icons.delete_outline_rounded),
          tooltip: 'Move to Trash',
        ),
        PopupMenuButton<_SelectionMore>(
          tooltip: 'More',
          onSelected: (choice) async {
            switch (choice) {
              case _SelectionMore.star:
                await FileActions.setStarred(context, ref, files, starred: !allStarred);
                _clearSelection();
              case _SelectionMore.selectAll:
                if (data == null) return;
                setState(() {
                  _files.addAll(data.files.map((f) => f.id));
                  _folders.addAll(data.folders.map((f) => f.id));
                });
            }
          },
          itemBuilder: (_) => [
            if (onlyFiles)
              PopupMenuItem(
                value: _SelectionMore.star,
                child: Text(allStarred ? 'Remove from Starred' : 'Add to Starred'),
              ),
            const PopupMenuItem(value: _SelectionMore.selectAll, child: Text('Select all')),
          ],
        ),
      ],
    );
  }
}

enum _SelectionMore { star, selectAll }

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
