import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/async/combine.dart';
import '../../../core/files/file_kind.dart';
import '../../../core/format/date_query.dart';
import '../../../core/widgets/common.dart';
import '../../drive/data/drive_repository.dart';
import '../../drive/domain/drive_models.dart';
import '../../files/presentation/file_actions.dart';
import '../../files/presentation/file_location.dart';
import '../../files/presentation/file_tiles.dart';
import '../../photos/presentation/media_grid.dart';

/// [rest] is what is left of the query once a date is taken off it, and
/// [literal] the query as typed.
typedef _SearchKey = ({
  String rest,
  String literal,
  FileKind? kind,
  bool media,
  DateRange? range,
  String? folderId,
});

final _searchResultsProvider = StreamProvider.autoDispose
    .family<(List<DriveFolder>, List<DriveFile>), _SearchKey>((ref, key) async* {
      final repository = ref.watch(driveRepositoryProvider);
      // The folders under the scope are read once per query, so a folder
      // moved in while the results show joins them at the next keystroke.
      final scope = key.folderId;
      final ids = scope == null ? null : await repository.descendantFolderIds(scope);
      final range = key.range;
      final kinds = key.kind != null
          ? {key.kind!}
          : key.media
          ? {FileKind.image, FileKind.video}
          : null;
      final files = repository.watchSearch(
        key.rest,
        kinds: kinds,
        range: range == null
            ? null
            : (range.start, range.end.subtract(const Duration(milliseconds: 1))),
        folderIds: ids,
        literal: key.literal,
        // The grid groups by month, newest moment first.
        byMoment: key.media,
      );
      // Folders have no date, so a query that is only a date matches their
      // names as typed. The scope's own folder isn't one of its results.
      final folderQuery = key.rest.isNotEmpty ? key.rest : key.literal.trim();
      final folders = folderQuery.isNotEmpty && key.kind == null && !key.media
          ? repository.watchFolderSearch(folderQuery, within: ids?.difference({scope}))
          : Stream.value(const <DriveFolder>[]);
      yield* combineLatest2(folders, files, (a, b) => (a, b));
    });

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({
    super.key,
    this.initialKind,
    this.media = false,
    this.initialFolderId,
  });

  /// Kind filter to start with, as when searching from a category list.
  final FileKind? initialKind;

  /// Photos and videos only, shown as the photo grid, as when searching
  /// from Photos.
  final bool media;

  /// The folder a search from inside it starts limited to, with everything
  /// below it.
  final String? initialFolderId;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  final _selection = MediaSelection();
  Timer? _debounce;
  String _query = '';
  late FileKind? _kind = widget.initialKind;
  late bool _scoped = widget.initialFolderId != null;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _selection.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 180), () {
      if (mounted) setState(() => _query = value.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final folderId = widget.initialFolderId;
    // Gone when the folder was deleted elsewhere; the search is then
    // unscoped.
    final scopeFolder = folderId == null
        ? null
        : ref.watch(folderInfoProvider(folderId)).value;
    final scope = _scoped ? scopeFolder : null;
    final split = DateQuery.split(_query);
    final range = split.range;
    final active = split.rest.isNotEmpty || range != null || _kind != null;
    final results = active
        ? ref.watch(
            _searchResultsProvider((
              rest: split.rest,
              literal: _query,
              kind: _kind,
              media: widget.media,
              range: range,
              folderId: scope?.id,
            )),
          )
        : null;
    // Null until the folders are read; rows then go without a place rather
    // than all reading 'Files'.
    final byId = widget.media ? null : ref.watch(folderIndexProvider).value;

    final chips = [
      if (scopeFolder != null)
        FilterChip(
          avatar: const Icon(Icons.folder_outlined, size: 16),
          label: Text('In ${scopeFolder.name}'),
          selected: _scoped,
          showCheckmark: false,
          onSelected: (selected) => setState(() => _scoped = selected),
        ),
      for (final kind in widget.media ? const [FileKind.image, FileKind.video] : FileKind.values)
        FilterChip(
          label: Text(kind.label),
          selected: _kind == kind,
          showCheckmark: false,
          onSelected: (selected) => setState(() => _kind = selected ? kind : null),
        ),
    ];

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          // Without a border the text sits at the top of the 48 px box the
          // clear button reserves, above the back arrow.
          textAlignVertical: TextAlignVertical.center,
          onChanged: _onChanged,
          decoration: InputDecoration(
            hintText: scope != null
                ? 'Search in ${scope.name}'
                : widget.media
                ? 'Search photos and videos'
                : 'Search files and folders',
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: EdgeInsets.zero,
            suffixIcon: ValueListenableBuilder(
              valueListenable: _controller,
              builder: (context, value, _) => value.text.isEmpty
                  ? const SizedBox.shrink()
                  : IconButton(
                      onPressed: () {
                        _controller.clear();
                        _onChanged('');
                      },
                      icon: const Icon(Icons.close_rounded),
                      tooltip: 'Clear',
                    ),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          SizedBox(
            height: 52,
            // The strip fades out at its right edge, so a chip cut off
            // there reads as more to scroll to; the trailing space lets the
            // last one clear the fade.
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (bounds) => LinearGradient(
                colors: const [Colors.black, Colors.black, Colors.transparent],
                stops: [0, (1 - Space.xxl / bounds.width).clamp(0, 1), 1],
              ).createShader(bounds),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.xxl, Space.s),
                itemCount: chips.length,
                separatorBuilder: (_, _) => const SizedBox(width: Space.s),
                itemBuilder: (_, index) => chips[index],
              ),
            ),
          ),
          if (range != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.s),
              child: Row(
                children: [
                  Icon(Icons.event_outlined, size: 18, color: scheme.onSurfaceVariant),
                  const SizedBox(width: Space.s),
                  Expanded(
                    child: Text(
                      split.rest.isEmpty
                          ? 'Everything from ${range.label}'
                          : '"${split.rest}" from ${range.label}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: results == null
                ? EmptyState(
                    title: scope != null
                        ? 'Search in ${scope.name}'
                        : widget.media
                        ? 'Search your photos and videos'
                        : 'Search your drive',
                    message: widget.media
                        ? 'Type part of a name, or a date like "march 2024".'
                        : 'Type part of a name, words in a PDF, or a date like '
                              '"march 2024". Or pick a kind above.',
                    compact: true,
                  )
                : AsyncView(
                    value: results,
                    data: (data) {
                      final (folders, files) = data;
                      if (folders.isEmpty && files.isEmpty) {
                        return EmptyState(
                          title: 'No matches',
                          message: _query.isEmpty
                              ? 'Nothing of this type yet.'
                              : 'Nothing matches "$_query".',
                          compact: true,
                        );
                      }
                      // A list as long as the limit was cut off.
                      final count = files.length >= DriveRepository.searchLimit
                          ? 'first ${DriveRepository.searchLimit}'
                          : '${files.length}';
                      if (widget.media) {
                        return MediaGrid(
                          files: files,
                          selection: _selection,
                          selectable: false,
                          onOpen: (file) => context.push('/viewer/${file.id}'),
                          header: [
                            SliverToBoxAdapter(
                              child: SectionHeader(
                                '${_kind?.label ?? 'Photos and videos'} · $count',
                              ),
                            ),
                          ],
                        );
                      }
                      return ListView(
                        padding: const EdgeInsets.only(bottom: Space.xxl),
                        children: [
                          if (folders.isNotEmpty) ...[
                            const SectionHeader('Folders'),
                            for (final folder in folders)
                              FolderListTile(
                                folder: folder,
                                onTap: () => context.go('/files/${folder.id}'),
                                onMore: () =>
                                    FileActions.showFolderSheet(context, ref, folder),
                              ),
                          ],
                          if (files.isNotEmpty) ...[
                            SectionHeader('Files · $count'),
                            for (final file in files)
                              FileListTile(
                                file: file,
                                onTap: () => FileActions.open(context, ref, file),
                                onMore: () =>
                                    FileActions.showFileSheet(context, ref, file),
                                subtitle: [
                                  fileMetaLine(file),
                                  // Inside the scoped folder itself the
                                  // place goes without saying.
                                  if (byId != null &&
                                      (scope == null || file.folderId != scope.id))
                                    locationOf(byId, file.folderId),
                                ].join(' · '),
                              ),
                          ],
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
      backgroundColor: scheme.surface,
    );
  }
}
