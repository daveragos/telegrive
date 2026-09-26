import 'package:flutter/material.dart';

import '../../../core/format/formatters.dart';
import '../../../core/widgets/file_visuals.dart';
import '../../drive/domain/drive_models.dart';

/// Row for a file in list view.
class FileListTile extends StatelessWidget {
  const FileListTile({
    super.key,
    required this.file,
    required this.onTap,
    this.onLongPress,
    this.onMore,
    this.selected = false,
    this.selecting = false,
    this.subtitle,
  });

  final DriveFile file;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onMore;
  final bool selected;
  final bool selecting;

  /// Replaces the default "size · date" line (search shows the folder).
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return _SelectableSurface(
      selected: selected,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
        child: Row(
          children: [
            _SelectionOverlay(
              selected: selected,
              child: FileThumbnail(file: file, size: 44),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (file.starred) ...[
                        Icon(Icons.star_rounded, size: 14, color: Colors.amber.shade600),
                        const SizedBox(width: 4),
                      ],
                      Flexible(
                        child: Text(
                          subtitle ??
                              '${Formatters.bytes(file.size)} · ${Formatters.date(file.modifiedAt)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (!selecting && onMore != null)
              IconButton(
                onPressed: onMore,
                icon: const Icon(Icons.more_vert_rounded),
                color: scheme.onSurfaceVariant,
                tooltip: 'More',
              )
            else
              const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }
}

/// Row for a folder in list view.
class FolderListTile extends StatelessWidget {
  const FolderListTile({
    super.key,
    required this.folder,
    required this.onTap,
    this.onLongPress,
    this.onMore,
    this.selected = false,
    this.selecting = false,
  });

  final DriveFolder folder;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onMore;
  final bool selected;
  final bool selecting;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return _SelectableSurface(
      selected: selected,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
        child: Row(
          children: [
            _SelectionOverlay(
              selected: selected,
              child: const FolderIconTile(size: 44),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    folder.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Folder · ${Formatters.date(folder.modifiedAt)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (!selecting && onMore != null)
              IconButton(
                onPressed: onMore,
                icon: const Icon(Icons.more_vert_rounded),
                color: scheme.onSurfaceVariant,
                tooltip: 'More',
              )
            else
              const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }
}

/// Card for a file in grid view: a big preview with the name underneath.
class FileGridCard extends StatelessWidget {
  const FileGridCard({
    super.key,
    required this.file,
    required this.onTap,
    this.onLongPress,
    this.onMore,
    this.selected = false,
    this.selecting = false,
  });

  final DriveFile file;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onMore;
  final bool selected;
  final bool selecting;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return _SelectableSurface(
      selected: selected,
      onTap: onTap,
      onLongPress: onLongPress,
      filled: true,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  FileThumbnail(file: file, expand: true, radius: 14, size: 64),
                  if (selected)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Icon(Icons.check_circle_rounded, color: scheme.primary),
                    ),
                  if (file.starred)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Icon(Icons.star_rounded, size: 18, color: Colors.amber.shade600),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          file.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          Formatters.bytes(file.size),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (!selecting && onMore != null)
                  SizedBox.square(
                    dimension: 32,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      iconSize: 20,
                      onPressed: onMore,
                      icon: const Icon(Icons.more_vert_rounded),
                      color: scheme.onSurfaceVariant,
                      tooltip: 'More',
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact folder chip for grid view.
class FolderGridCard extends StatelessWidget {
  const FolderGridCard({
    super.key,
    required this.folder,
    required this.onTap,
    this.onLongPress,
    this.onMore,
    this.selected = false,
    this.selecting = false,
  });

  final DriveFolder folder;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onMore;
  final bool selected;
  final bool selecting;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _SelectableSurface(
      selected: selected,
      onTap: onTap,
      onLongPress: onLongPress,
      filled: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 0, 8),
        child: Row(
          children: [
            _SelectionOverlay(
              selected: selected,
              child: const FolderIconTile(size: 36),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                folder.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            if (!selecting && onMore != null)
              IconButton(
                onPressed: onMore,
                iconSize: 20,
                icon: const Icon(Icons.more_vert_rounded),
                color: theme.colorScheme.onSurfaceVariant,
                tooltip: 'More',
              )
            else
              const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }
}

class _SelectableSurface extends StatelessWidget {
  const _SelectableSurface({
    required this.selected,
    required this.onTap,
    required this.child,
    this.onLongPress,
    this.filled = false,
  });

  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Widget child;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected
        ? scheme.primaryContainer.withValues(alpha: 0.5)
        : filled
        ? scheme.surfaceContainerLow
        : Colors.transparent;
    return Padding(
      padding: filled ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 8),
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(filled ? 18 : 16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, onLongPress: onLongPress, child: child),
      ),
    );
  }
}

class _SelectionOverlay extends StatelessWidget {
  const _SelectionOverlay({required this.selected, required this.child});

  final bool selected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 160),
      transitionBuilder: (child, animation) =>
          ScaleTransition(scale: animation, child: child),
      child: selected
          ? Container(
              key: const ValueKey('selected'),
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(Icons.check_rounded, color: scheme.onPrimary),
            )
          : KeyedSubtree(key: const ValueKey('normal'), child: child),
    );
  }
}
