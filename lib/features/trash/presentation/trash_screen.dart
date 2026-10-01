import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/format/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../drive/data/drive_repository.dart';
import '../../drive/domain/drive_models.dart';
import '../../files/presentation/file_actions.dart';
import '../../files/presentation/file_location.dart';
import '../../files/presentation/file_tiles.dart';
import '../data/pending_deletes.dart';

/// What was deleted in the last 30 days, to restore or delete for good.
class TrashScreen extends ConsumerWidget {
  const TrashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // What is being deleted for good is gone from here at once, while its
    // Undo lasts.
    final hidden = ref.watch(pendingDeletesProvider.select((s) => s.hiddenIds));
    final trash = ref.watch(trashProvider).whenData((c) => c.without(hidden));
    final contents = trash.value;
    // Where each item goes back to on Restore. Null until the folders are
    // read; rows then go without a place rather than all reading 'Files'.
    final byId = ref.watch(folderIndexProvider).value;
    String place(String? folderId) =>
        byId == null ? '' : ' · ${locationOf(byId, folderId)}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trash'),
        actions: [
          if (contents != null && !contents.isEmpty)
            TextButton(
              onPressed: () => FileActions.emptyTrash(context, ref, contents),
              child: const Text('Empty trash'),
            ),
          const SizedBox(width: Space.s),
        ],
      ),
      body: AsyncView(
        value: trash,
        data: (contents) => contents.isEmpty
            ? const EmptyState(
                icon: Icons.delete_outline_rounded,
                title: 'Trash is empty',
                message: 'Deleted files stay here for 30 days, then go for good.',
              )
            : ListView(
                padding: const EdgeInsets.only(bottom: Space.x4),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Space.gutter,
                      Space.s,
                      Space.gutter,
                      Space.l,
                    ),
                    child: Text(
                      'Items are deleted for good 30 days after they were moved '
                      'here. Folders keep everything that was in them.',
                      style: context.text.bodyMedium,
                    ),
                  ),
                  ListGroup(
                    children: [
                      for (final folder in contents.folders)
                        FolderListTile(
                          folder: folder,
                          subtitle: '${_left(folder.trashedAt)}${place(folder.parentId)}',
                          onTap: () => _showSheet(context, ref, folders: [folder]),
                          onMore: () => _showSheet(context, ref, folders: [folder]),
                        ),
                      for (final file in contents.files)
                        FileListTile(
                          file: file,
                          subtitle:
                              '${Formatters.bytes(file.size)} · ${_left(file.trashedAt)}'
                              '${place(file.folderId)}',
                          onTap: () => _showSheet(context, ref, files: [file]),
                          onMore: () => _showSheet(context, ref, files: [file]),
                        ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  static String _left(DateTime? trashedAt) {
    if (trashedAt == null) return 'In the trash';
    final gone = trashedAt.add(DriveRepository.trashKeepsFor);
    final days = gone.difference(DateTime.now()).inDays;
    return days <= 0
        ? 'Goes for good today'
        : 'Goes for good in ${Formatters.count(days, 'day')}';
  }

  static Future<void> _showSheet(
    BuildContext context,
    WidgetRef ref, {
    List<DriveFile> files = const [],
    List<DriveFolder> folders = const [],
  }) {
    final name = files.isNotEmpty ? files.first.name : folders.first.name;
    return showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      builder: (sheetContext) {
        void run(Future<void> Function() action) {
          Navigator.pop(sheetContext);
          action();
        }

        final colors = context.colors;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.m),
                child: Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.titleSmall,
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(Icons.restore_rounded, color: colors.text2),
                title: const Text('Restore'),
                onTap: () => run(
                  () => FileActions.restore(context, ref, files: files, folders: folders),
                ),
              ),
              ListTile(
                leading: Icon(Icons.delete_forever_outlined, color: colors.danger),
                title: Text(
                  'Delete for good',
                  style: context.text.bodyLarge?.copyWith(color: colors.danger),
                ),
                onTap: () => run(
                  () => FileActions.deleteForever(context, ref, files: files, folders: folders),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
