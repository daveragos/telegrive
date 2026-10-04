import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/selection_bar.dart';
import '../../drive/domain/drive_models.dart';
import '../../files/presentation/file_actions.dart';
import 'album_actions.dart';
import 'media_grid.dart';

enum _More { star, removeFromAlbum, selectAll }

/// The app bar while photos are selected, on the Photos tab and in albums:
/// '6 selected · 48 MB', or 'Select photos' before any are picked.
PreferredSizeWidget mediaSelectionAppBar(
  BuildContext context, {
  required MediaSelection selection,
  required List<DriveFile> files,
}) {
  final picked = selection.pick(files);
  return selectionAppBar(
    context,
    count: picked.length,
    bytes: picked.fold(0, (sum, f) => sum + f.size),
    onClear: selection.clear,
    noun: 'photos',
  );
}

/// What can be done with the selected photos, in the bar at the foot of
/// the Photos tab and of albums. [albumId] is the album on screen, when it
/// is one people made, which the photos can then be taken out of.
Widget mediaSelectionActions(
  BuildContext context,
  WidgetRef ref, {
  required MediaSelection selection,
  required List<DriveFile> files,
  String? albumId,
}) {
  final picked = selection.pick(files);
  final none = picked.isEmpty;
  final allStarred = !none && picked.every((f) => f.starred);

  Future<void> then(Future<bool> action) async {
    if (await action) selection.clear();
  }

  VoidCallback? unlessNone(Future<bool> Function() action) =>
      none ? null : () => then(action());

  return SelectionActionBar(
    actions: [
      SelectionAction(
        icon: Icons.library_add_outlined,
        label: 'Album',
        onTap: unlessNone(() => AlbumActions.addTo(context, ref, picked)),
      ),
      SelectionAction(
        icon: Icons.send_outlined,
        label: 'Send',
        onTap: unlessNone(() => FileActions.sendToChats(context, ref, picked, byMoment: true)),
      ),
      SelectionAction(
        icon: Icons.download_rounded,
        label: 'Download',
        onTap: unlessNone(
          () => FileActions.saveToDevice(context, ref, files: picked, preferGallery: true),
        ),
      ),
      SelectionAction(
        icon: Icons.delete_outline_rounded,
        label: 'Trash',
        onTap: unlessNone(() => FileActions.delete(context, ref, files: picked)),
      ),
    ],
    more: [
      if (!none)
        PopupMenuItem(
          value: _More.star,
          child: Text(allStarred ? 'Remove from Starred' : 'Add to Starred'),
        ),
      if (!none && albumId != null)
        const PopupMenuItem(value: _More.removeFromAlbum, child: Text('Remove from album')),
      const PopupMenuItem(value: _More.selectAll, child: Text('Select all')),
    ],
    onMore: (choice) {
      switch (choice) {
        case _More.star:
          then(FileActions.setStarred(context, ref, picked, starred: !allStarred));
        case _More.removeFromAlbum:
          then(AlbumActions.removeFrom(context, ref, picked, albumId!));
        case _More.selectAll:
          selection.replace({for (final f in files) f.id});
      }
    },
  );
}
