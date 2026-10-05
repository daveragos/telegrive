import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/selection_bar.dart';
import '../../drive/domain/drive_models.dart';
import 'file_actions.dart';

enum _More { star, selectAll, deselectAll }

/// What can be done with the selected [files] and [folders], in the bar at
/// the foot of Files and of Starred, Recent and the categories. Starring is
/// offered for files and folders alike, and reads Remove from Starred once
/// everything picked is starred. [onDone] ends the selection once an action
/// has gone through, and [onSelectAll] selects everything on screen. Once
/// [allSelected], the menu offers Deselect all instead, which ends it too.
Widget fileSelectionActions(
  BuildContext context,
  WidgetRef ref, {
  required List<DriveFile> files,
  List<DriveFolder> folders = const [],
  required VoidCallback onDone,
  required VoidCallback onSelectAll,
  bool allSelected = false,
}) {
  final none = files.isEmpty && folders.isEmpty;
  final allStarred =
      !none && files.every((f) => f.starred) && folders.every((f) => f.starred);

  Future<void> then(Future<bool> action) async {
    if (await action && context.mounted) onDone();
  }

  VoidCallback? unlessNone(Future<bool> Function() action) =>
      none ? null : () => then(action());

  return SelectionActionBar(
    actions: [
      SelectionAction(
        icon: Icons.download_rounded,
        label: 'Download',
        onTap: unlessNone(
          () => FileActions.saveToDevice(
            context,
            ref,
            files: files,
            folders: folders,
          ),
        ),
      ),
      SelectionAction(
        icon: Icons.send_outlined,
        label: 'Send',
        onTap: unlessNone(
          () => FileActions.sendToChats(context, ref, files, folders: folders),
        ),
      ),
      SelectionAction(
        icon: Icons.drive_file_move_outline,
        label: 'Move',
        onTap: unlessNone(
          () => FileActions.move(context, ref, files: files, folders: folders),
        ),
      ),
      SelectionAction(
        icon: Icons.delete_outline_rounded,
        label: 'Trash',
        onTap: unlessNone(
          () =>
              FileActions.delete(context, ref, files: files, folders: folders),
        ),
      ),
    ],
    more: [
      if (!none)
        PopupMenuItem(
          value: _More.star,
          child: Text(allStarred ? 'Remove from Starred' : 'Add to Starred'),
        ),
      if (allSelected)
        const PopupMenuItem(value: _More.deselectAll, child: Text('Deselect all'))
      else
        const PopupMenuItem(value: _More.selectAll, child: Text('Select all')),
    ],
    onMore: (choice) {
      switch (choice) {
        case _More.star:
          then(
            FileActions.setStarred(
              context,
              ref,
              files,
              folders: folders,
              starred: !allStarred,
            ),
          );
        case _More.selectAll:
          onSelectAll();
        case _More.deselectAll:
          onDone();
      }
    },
  );
}
