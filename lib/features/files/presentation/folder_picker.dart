import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/common.dart';
import '../../../core/widgets/file_visuals.dart';
import '../../drive/data/drive_repository.dart';
import '../../drive/domain/drive_models.dart';

/// Where the person chose to move things.
class FolderChoice {
  const FolderChoice(this.folderId, this.name);

  /// Null for the drive root.
  final String? folderId;
  final String name;
}

/// A browsable folder chooser, opened in [startIn].
Future<FolderChoice?> showFolderPicker(
  BuildContext context, {
  required String title,
  Set<String> excluded = const {},
  String? startIn,
}) {
  return showModalBottomSheet<FolderChoice>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    useRootNavigator: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.85,
      child: _FolderPicker(title: title, excluded: excluded, startIn: startIn),
    ),
  );
}

class _FolderPicker extends ConsumerStatefulWidget {
  const _FolderPicker({required this.title, required this.excluded, this.startIn});

  final String title;
  final Set<String> excluded;
  final String? startIn;

  @override
  ConsumerState<_FolderPicker> createState() => _FolderPickerState();
}

class _FolderPickerState extends ConsumerState<_FolderPicker> {
  late String? _current = widget.excluded.contains(widget.startIn) ? null : widget.startIn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final contents = ref.watch(folderContentsProvider(_current));
    final crumbs = ref.watch(breadcrumbsProvider(_current)).value ?? const [];
    final currentName = crumbs.isEmpty ? 'My Drive' : crumbs.last.name;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 16, 8),
          child: Row(
            children: [
              IconButton(
                onPressed: _current == null
                    ? null
                    : () => setState(
                        () => _current = crumbs.length >= 2
                            ? crumbs[crumbs.length - 2].id
                            : null,
                      ),
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: 'Up',
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title, style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    Text(
                      currentName,
                      style: theme.textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(),
        Expanded(
          child: AsyncView<FolderContents>(
            value: contents,
            data: (data) {
              final folders = data.sorted(const SortOrder(SortField.name)).folders;
              if (folders.isEmpty) {
                return const EmptyState(
                  icon: Icons.folder_open_rounded,
                  title: 'No folders here',
                  message: 'Move your items into this folder, or go back up.',
                  compact: true,
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: folders.length,
                itemBuilder: (context, index) {
                  final folder = folders[index];
                  final disabled = widget.excluded.contains(folder.id);
                  return ListTile(
                    enabled: !disabled,
                    leading: Opacity(
                      opacity: disabled ? 0.4 : 1,
                      child: const FolderIconTile(size: 40),
                    ),
                    title: Text(folder.name, overflow: TextOverflow.ellipsis),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => setState(() => _current = folder.id),
                  );
                },
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () =>
                    Navigator.of(context).pop(FolderChoice(_current, currentName)),
                icon: const Icon(Icons.drive_file_move_rounded),
                label: Text('Move to $currentName'),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
