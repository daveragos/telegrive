import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format/formatters.dart';
import '../../drive/domain/drive_models.dart';
import '../../files/presentation/file_actions.dart';
import 'album_actions.dart';
import 'media_grid.dart';

enum _More { star, removeFromAlbum, selectAll }

/// The app bar while photos are selected, on the Photos tab and in albums.
PreferredSizeWidget mediaSelectionBar(
  BuildContext context,
  WidgetRef ref, {
  required MediaSelection selection,
  required List<DriveFile> files,
  String? albumId,
}) {
  final picked = selection.pick(files);
  final allStarred = picked.isNotEmpty && picked.every((f) => f.starred);

  Future<void> then(Future<bool> action) async {
    if (await action) selection.clear();
  }

  return AppBar(
    backgroundColor: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5),
    leading: IconButton(
      onPressed: selection.clear,
      icon: const Icon(Icons.close_rounded),
      tooltip: 'Clear selection',
    ),
    title: Text(Formatters.number(selection.length)),
    actions: [
      IconButton(
        onPressed: () => then(AlbumActions.addTo(context, ref, picked)),
        icon: const Icon(Icons.library_add_outlined),
        tooltip: 'Add to album',
      ),
      IconButton(
        onPressed: () => then(FileActions.sendToChats(context, ref, picked, byMoment: true)),
        icon: const Icon(Icons.send_outlined),
        tooltip: 'Send in Telegram',
      ),
      IconButton(
        onPressed: () => then(
          FileActions.saveToDevice(context, ref, files: picked, preferGallery: true),
        ),
        icon: const Icon(Icons.download_rounded),
        tooltip: 'Download to this phone',
      ),
      IconButton(
        onPressed: () => then(FileActions.delete(context, ref, files: picked)),
        icon: const Icon(Icons.delete_outline_rounded),
        tooltip: 'Move to Trash',
      ),
      PopupMenuButton<_More>(
        tooltip: 'More',
        onSelected: (choice) => switch (choice) {
          _More.star => then(
            FileActions.setStarred(context, ref, picked, starred: !allStarred),
          ),
          _More.removeFromAlbum => then(AlbumActions.removeFrom(context, ref, picked, albumId!)),
          _More.selectAll => selection.replace({for (final f in files) f.id}),
        },
        itemBuilder: (_) => [
          PopupMenuItem(
            value: _More.star,
            child: Text(allStarred ? 'Remove from Starred' : 'Add to Starred'),
          ),
          if (albumId != null)
            const PopupMenuItem(value: _More.removeFromAlbum, child: Text('Remove from album')),
          const PopupMenuItem(value: _More.selectAll, child: Text('Select all')),
        ],
      ),
    ],
  );
}
