import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/format/formatters.dart';
import '../../../core/widgets/file_visuals.dart';
import '../../drive/domain/drive_models.dart';
import '../../offline/data/offline_sync.dart';

/// A file as a list row: picture slot, name, size and date, and a menu.
class FileListTile extends ConsumerWidget {
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

  /// Replaces the default "size · date" line.
  final String? subtitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline = ref.watch(
      offlineCopiesProvider.select((copies) => copies.value?.containsKey(file.id) ?? false),
    );
    return _Row(
      selected: selected,
      onTap: onTap,
      onLongPress: onLongPress,
      slot: _Selectable(selected: selected, child: FileThumbnail(file: file)),
      title: file.name,
      meta: subtitle ??
          '${Formatters.bytes(file.size)} · ${Formatters.date(file.modifiedAt)}',
      starred: file.starred,
      offline: offline,
      onMore: selecting ? null : onMore,
    );
  }
}

/// A folder as a list row.
class FolderListTile extends ConsumerWidget {
  const FolderListTile({
    super.key,
    required this.folder,
    required this.onTap,
    this.onLongPress,
    this.onMore,
    this.selected = false,
    this.selecting = false,
    this.subtitle,
  });

  final DriveFolder folder;

  /// Replaces the default "Folder · date" line.
  final String? subtitle;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onMore;
  final bool selected;
  final bool selecting;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline = ref.watch(
      offlinePinsProvider.select((pins) => pins.value?.contains(folder.id) ?? false),
    );
    return _Row(
      selected: selected,
      onTap: onTap,
      onLongPress: onLongPress,
      offline: offline,
      slot: _Selectable(selected: selected, child: const FolderIconTile()),
      title: folder.name,
      meta: subtitle ?? 'Folder · ${Formatters.date(folder.modifiedAt)}',
      onMore: selecting ? null : onMore,
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.selected,
    required this.onTap,
    required this.slot,
    required this.title,
    required this.meta,
    this.onLongPress,
    this.onMore,
    this.starred = false,
    this.offline = false,
  });

  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Widget slot;
  final String title;
  final String meta;
  final VoidCallback? onMore;
  final bool starred;

  /// Kept on this phone for use without a connection.
  final bool offline;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: selected ? colors.accentSoft : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            Space.gutter,
            Space.s + 2,
            onMore == null ? Space.gutter : Space.xs,
            Space.s + 2,
          ),
          child: Row(
            children: [
              slot,
              const SizedBox(width: Space.l),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (starred) ...[
                          Icon(Icons.star_rounded, size: 14, color: colors.text2),
                          const SizedBox(width: Space.xs),
                        ],
                        if (offline) ...[
                          Icon(Icons.offline_pin_rounded, size: 14, color: colors.text2),
                          const SizedBox(width: Space.xs),
                        ],
                        Flexible(
                          child: Text(
                            meta,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.bodySmall?.copyWith(
                              fontFeatures: tabularFigures,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (onMore != null)
                IconButton(
                  onPressed: onMore,
                  icon: Icon(Icons.more_vert_rounded, color: colors.text3),
                  tooltip: 'More',
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Swaps the slot for a check while selected.
class _Selectable extends StatelessWidget {
  const _Selectable({required this.selected, required this.child});

  final bool selected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 150),
      child: selected
          ? Container(
              key: const ValueKey('selected'),
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: colors.accent,
                borderRadius: BorderRadius.circular(Radii.thumb),
              ),
              child: Icon(Icons.check_rounded, color: Theme.of(context).colorScheme.onPrimary),
            )
          : KeyedSubtree(key: const ValueKey('normal'), child: child),
    );
  }
}

/// A file in grid view: the picture, then its name and size under it.
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
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(Radii.control),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                FileThumbnail(file: file, expand: true, radius: Radii.control),
                if (selected)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(Radii.control),
                      border: Border.all(color: colors.accent, width: 3),
                    ),
                  ),
                if (selected)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Icon(Icons.check_circle_rounded, color: colors.accent),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Space.s),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.titleSmall?.copyWith(fontSize: 14),
                    ),
                    Text(
                      [
                        Formatters.bytes(file.size),
                        if (file.starred) 'starred',
                      ].join(' · '),
                      style: context.text.bodySmall?.copyWith(fontFeatures: tabularFigures),
                    ),
                  ],
                ),
              ),
              if (!selecting && onMore != null)
                SizedBox.square(
                  dimension: 32,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    iconSize: 20,
                    onPressed: onMore,
                    icon: Icon(Icons.more_vert_rounded, color: colors.text3),
                    tooltip: 'More',
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A folder in grid view: an outlined row, lighter than a file.
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
    final colors = context.colors;
    return Material(
      color: selected ? colors.accentSoft : colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.control),
        side: BorderSide(color: selected ? colors.accent : colors.line),
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        customBorder: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.control),
        ),
        child: Padding(
          padding: const EdgeInsets.only(left: Space.m),
          child: Row(
            children: [
              Icon(
                selected ? Icons.check_circle_rounded : Icons.folder_outlined,
                color: selected ? colors.accent : colors.text2,
                size: 22,
              ),
              const SizedBox(width: Space.m),
              Expanded(
                child: Text(
                  folder.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.titleSmall?.copyWith(fontSize: 14),
                ),
              ),
              if (!selecting && onMore != null)
                IconButton(
                  onPressed: onMore,
                  iconSize: 20,
                  icon: Icon(Icons.more_vert_rounded, color: colors.text3),
                  tooltip: 'More',
                )
              else
                const SizedBox(width: Space.m),
            ],
          ),
        ),
      ),
    );
  }
}
