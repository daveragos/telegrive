import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/files/file_kind.dart';
import '../../../core/format/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../drive/data/drive_repository.dart';
import '../../drive/domain/drive_models.dart';
import '../../files/presentation/file_actions.dart';
import '../../trash/data/pending_deletes.dart';
import '../data/photos_visibility.dart';
import 'album_actions.dart';
import 'media_grid.dart';
import 'media_selection_bar.dart';

/// Favorites and Videos, then the albums people made, newest first.
class AlbumsScreen extends ConsumerWidget {
  const AlbumsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albums = ref.watch(albumsProvider);
    // An album being deleted leaves the list at once, while its Undo lasts.
    final hidden = ref.watch(pendingDeletesProvider.select((s) => s.hiddenIds));
    // Favorites and Videos leave out what the Photos tab keeps out.
    final media = ref.watch(photosTimelineProvider).value ?? const <DriveFile>[];
    final favorites = media.where((f) => f.starred).toList();
    final videos = media.where((f) => f.kind == FileKind.video).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Albums')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'albums-fab',
        onPressed: () => AlbumActions.create(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New album'),
      ),
      body: AsyncView(
        value: albums,
        data: (albums) => GridView(
          padding: const EdgeInsets.fromLTRB(Space.gutter, Space.s, Space.gutter, 112),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 220,
            mainAxisSpacing: Space.l,
            crossAxisSpacing: Space.l,
            childAspectRatio: 0.8,
          ),
          children: [
            _AlbumCard(
              name: 'Favorites',
              count: favorites.length,
              cover: favorites.firstOrNull,
              onTap: () => context.push('/albums/${SmartAlbum.favorites}'),
            ),
            _AlbumCard(
              name: 'Videos',
              count: videos.length,
              cover: videos.firstOrNull,
              onTap: () => context.push('/albums/${SmartAlbum.videos}'),
            ),
            for (final album in albums)
              if (!hidden.contains(album.id))
                _AlbumCard(
                  name: album.name,
                  count: album.count,
                  album: album,
                  onTap: () => context.push('/albums/${album.id}'),
                ),
          ],
        ),
      ),
    );
  }
}

/// Albums the app keeps by itself.
abstract final class SmartAlbum {
  static const favorites = 'favorites';
  static const videos = 'videos';
}

class _AlbumCard extends StatelessWidget {
  const _AlbumCard({
    required this.name,
    required this.count,
    required this.onTap,
    this.album,
    this.cover,
  });

  final String name;
  final int count;
  final VoidCallback onTap;
  final DriveAlbum? album;
  final DriveFile? cover;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.card),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: AlbumCover(album: album, cover: cover)),
          const SizedBox(height: Space.s),
          Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall),
          Text(
            Formatters.count(count, 'item'),
            style: context.text.bodySmall?.copyWith(fontFeatures: tabularFigures),
          ),
        ],
      ),
    );
  }
}

/// One album, or Favorites or Videos, as a photo grid.
class AlbumScreen extends ConsumerStatefulWidget {
  const AlbumScreen({super.key, required this.albumId});

  final String albumId;

  @override
  ConsumerState<AlbumScreen> createState() => _AlbumScreenState();
}

enum _AlbumMenu { select, send, rename, delete }

class _AlbumScreenState extends ConsumerState<AlbumScreen> {
  final _selection = MediaSelection();

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.albumId;
    final media = ref.watch(photosTimelineProvider).value;
    final album = ref.watch(albumsProvider).value?.where((a) => a.id == id).firstOrNull;
    final (String title, List<DriveFile>? files) = switch (id) {
      SmartAlbum.favorites => ('Favorites', media?.where((f) => f.starred).toList()),
      SmartAlbum.videos => ('Videos', media?.where((f) => f.kind == FileKind.video).toList()),
      _ => (album?.name ?? 'Album', ref.watch(albumFilesProvider(id)).value),
    };
    // What the album holds, as the menu and the selection bar name it.
    final noun = id == SmartAlbum.videos ? 'videos' : 'photos';
    final source = album != null ? 'album:$id' : id;

    return ListenableBuilder(
      listenable: _selection,
      builder: (context, _) => PopScope(
        canPop: !_selection.active,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _selection.clear();
        },
        child: Scaffold(
          appBar: _selection.active
              ? mediaSelectionAppBar(
                  context,
                  selection: _selection,
                  files: files ?? const [],
                  noun: noun,
                )
              : AppBar(
                  title: Text(title, overflow: TextOverflow.ellipsis),
                  actions: [
                    if (album != null)
                      IconButton(
                        onPressed: () => context.push('/albums/$id/add'),
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                        tooltip: 'Add photos',
                      ),
                    PopupMenuButton<_AlbumMenu>(
                      tooltip: 'More',
                      onSelected: (choice) async {
                        switch (choice) {
                          case _AlbumMenu.select:
                            _selection.begin();
                          case _AlbumMenu.send:
                            if (files == null || files.isEmpty) {
                              showSnack(context, 'This album is empty.');
                            } else {
                              await FileActions.sendToChats(
                                context,
                                ref,
                                files,
                                bundleName: album!.name,
                                byMoment: true,
                              );
                            }
                          case _AlbumMenu.rename:
                            await AlbumActions.rename(context, ref, album!);
                          case _AlbumMenu.delete:
                            if (await AlbumActions.delete(context, ref, album!) &&
                                context.mounted) {
                              context.pop();
                            }
                        }
                      },
                      // Favorites and Videos are the app's own, so they
                      // offer only Select.
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: _AlbumMenu.select,
                          child: Text('Select $noun'),
                        ),
                        if (album != null) ...const [
                          PopupMenuItem(
                            value: _AlbumMenu.send,
                            child: Text('Send album in Telegram'),
                          ),
                          PopupMenuItem(value: _AlbumMenu.rename, child: Text('Rename album')),
                          PopupMenuItem(value: _AlbumMenu.delete, child: Text('Delete album')),
                        ],
                      ],
                    ),
                  ],
                ),
          bottomNavigationBar: _selection.active
              ? mediaSelectionActions(
                  context,
                  ref,
                  selection: _selection,
                  files: files ?? const [],
                  albumId: album?.id,
                )
              : null,
          body: files == null
              ? const Center(child: CircularProgressIndicator())
              : MediaGrid(
                  files: files,
                  selection: _selection,
                  onOpen: (file) => context.push('/viewer/${file.id}?from=$source'),
                  empty: EmptyState(
                    title: 'Nothing here yet',
                    message: switch (id) {
                      SmartAlbum.favorites => 'Star photos and videos to see them here.',
                      SmartAlbum.videos => 'Videos in your drive show up here.',
                      _ => 'Add photos with the button above, or select them on the '
                          'Photos tab.',
                    },
                    compact: true,
                  ),
                ),
        ),
      ),
    );
  }
}

/// Every photo, to pick some for an album.
class AddToAlbumScreen extends ConsumerStatefulWidget {
  const AddToAlbumScreen({super.key, required this.albumId});

  final String albumId;

  @override
  ConsumerState<AddToAlbumScreen> createState() => _AddToAlbumScreenState();
}

class _AddToAlbumScreenState extends ConsumerState<AddToAlbumScreen> {
  final _selection = MediaSelection();
  bool _adding = false;

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Every photo, kept-out folders too: a screenshot can belong in an album.
    final media = ref.watch(mediaTimelineProvider).value;
    final album = ref.watch(albumsProvider).value?.where((a) => a.id == widget.albumId).firstOrNull;

    return ListenableBuilder(
      listenable: _selection,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          leading: IconButton(
            onPressed: () => context.pop(),
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Cancel',
          ),
          title: Text(
            _selection.active
                ? '${Formatters.number(_selection.length)} selected'
                : 'Add to ${album?.name ?? 'album'}',
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            TextButton(
              onPressed: !_selection.active || _adding || media == null
                  ? null
                  : () async {
                      setState(() => _adding = true);
                      final added = await AlbumActions.add(
                        context,
                        ref,
                        _selection.pick(media),
                        albumId: widget.albumId,
                        name: album?.name ?? 'album',
                      );
                      if (!context.mounted) return;
                      if (added) {
                        context.pop();
                      } else {
                        setState(() => _adding = false);
                      }
                    },
              child: const Text('Add'),
            ),
            const SizedBox(width: Space.s),
          ],
        ),
        body: media == null
            ? const Center(child: CircularProgressIndicator())
            : MediaGrid(
                files: media,
                selection: _selection,
                alwaysSelecting: true,
                onOpen: (_) {},
              ),
      ),
    );
  }
}
