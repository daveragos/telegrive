import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/async/combine.dart';
import '../../../core/files/file_kind.dart';
import '../../../core/format/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../drive/data/drive_repository.dart';
import '../../drive/domain/drive_models.dart';
import '../../files/presentation/file_actions.dart';
import '../../files/presentation/file_tiles.dart';

typedef _SearchKey = ({String query, FileKind? kind});

final _searchResultsProvider = StreamProvider.autoDispose
    .family<(List<DriveFolder>, List<DriveFile>), _SearchKey>((ref, key) {
      final repository = ref.watch(driveRepositoryProvider);
      final files = repository.watchSearch(key.query, kind: key.kind);
      final folders = key.kind == null
          ? repository.watchFolderSearch(key.query)
          : Stream.value(const <DriveFolder>[]);
      return combineLatest2(folders, files, (a, b) => (a, b));
    });

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';
  FileKind? _kind;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
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
    final active = _query.isNotEmpty || _kind != null;
    final results = active
        ? ref.watch(_searchResultsProvider((query: _query, kind: _kind)))
        : null;

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
            hintText: 'Search files and folders',
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
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                for (final kind in FileKind.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(kind.label),
                      selected: _kind == kind,
                      showCheckmark: false,
                      onSelected: (selected) =>
                          setState(() => _kind = selected ? kind : null),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: results == null
                ? const EmptyState(
                    title: 'Search your drive',
                    message: 'Type part of a name, or pick a kind above.',
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
                              : 'Nothing is named like "$_query".',
                          compact: true,
                        );
                      }
                      return ListView(
                        padding: const EdgeInsets.only(bottom: 24),
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
                            SectionHeader(
                              files.length >= 300
                                  ? 'Files · first 300'
                                  : 'Files · ${files.length}',
                            ),
                            for (final file in files)
                              FileListTile(
                                file: file,
                                onTap: () => FileActions.open(context, ref, file),
                                onMore: () =>
                                    FileActions.showFileSheet(context, ref, file),
                                subtitle:
                                    '${Formatters.bytes(file.size)} · ${Formatters.date(file.modifiedAt)}',
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
