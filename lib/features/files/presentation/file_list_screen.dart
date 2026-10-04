import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/files/file_kind.dart';
import '../../../core/format/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/selection_bar.dart';
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
/// Long-press a file, or tap Select, to pick several and act on them at
/// once from the bar at the foot.
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
    final opened = widget.mode == FileListMode.recent ? ref.watch(recentOpenedProvider) : null;
    final added = widget.mode == FileListMode.recent ? ref.watch(recentAddedProvider) : null;
    final recent = _recentShown(opened?.value, added?.value);
    final loaded = listed?.value ?? recent?.entries.map((e) => e.file).toList();
    final shown = loaded ?? const <DriveFile>[];

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

    Widget list(List<DriveFile> files, {Key? key, List<String>? subtitles}) => _Files(
      key: key,
      files: files,
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
                      widget.mode == FileListMode.kind ? '/search?kind=${kind!.name}' : '/search',
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
        bottomNavigationBar: _selecting
            ? fileSelectionActions(
                context,
                ref,
                files: picked,
                onDone: _clearSelection,
                onSelectAll: () => setState(() => _selected.addAll(shown.map((f) => f.id))),
              )
            : null,
        body: switch (widget.mode) {
          FileListMode.recent => _recentBody(opened!, added!, recent, list),
          FileListMode.kind || FileListMode.starred => AsyncView<List<DriveFile>>(
            value: listed!,
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
    final mode = _recent ??= opened.isNotEmpty ? RecentMode.opened : RecentMode.added;
    return (
      mode: mode,
      entries: switch (mode) {
        RecentMode.opened => opened,
        RecentMode.added => [
          for (final file in added) RecentEntry(file, at: file.createdAt, opened: false),
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
    Widget Function(List<DriveFile> files, {Key? key, List<String>? subtitles}) list,
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

/// A count line, then [files] as rows or a grid. Each row ends with the
/// folder its file lives in, since the list mixes files from everywhere.
/// While [selecting], a tap picks a file rather than opening it; a
/// long-press always does.
class _Files extends ConsumerWidget {
  const _Files({
    super.key,
    required this.files,
    required this.grid,
    required this.selected,
    required this.selecting,
    required this.onToggle,
    this.subtitles,
  });

  final List<DriveFile> files;
  final bool grid;
  final Set<String> selected;
  final bool selecting;
  final ValueChanged<DriveFile> onToggle;

  /// Each row's meta line before its folder, in place of the default
  /// "size · date". The grid keeps its size-only cards.
  final List<String>? subtitles;

  void _tap(BuildContext context, WidgetRef ref, DriveFile file) =>
      selecting ? onToggle(file) : FileActions.open(context, ref, file);

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
                  selected: selected.contains(file.id),
                  selecting: selecting,
                  onTap: () => _tap(context, ref, file),
                  onLongPress: () => onToggle(file),
                  onMore: () => FileActions.showFileSheet(context, ref, file),
                );
              },
            ),
          ),
        ],
      );
    }
    // Null until the folders are read; rows then go without a place rather
    // than all reading 'Files'.
    final byId = ref.watch(folderIndexProvider).value;
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: files.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) return header;
        final file = files[index - 1];
        return FileListTile(
          file: file,
          subtitle: [
            subtitles?[index - 1] ??
                '${Formatters.bytes(file.size)} · ${Formatters.date(file.modifiedAt)}',
            if (byId != null) locationOf(byId, file.folderId),
          ].join(' · '),
          selected: selected.contains(file.id),
          selecting: selecting,
          onTap: () => _tap(context, ref, file),
          onLongPress: () => onToggle(file),
          onMore: () => FileActions.showFileSheet(context, ref, file),
        );
      },
    );
  }
}

enum FileListMode { kind, starred, recent }

/// The two halves of Recent.
enum RecentMode { opened, added }
