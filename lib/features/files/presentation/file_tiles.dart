import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/format/formatters.dart';
import '../../../core/widgets/file_visuals.dart';
import '../../../infrastructure/database/app_database.dart' show FolderSize;
import '../../drive/data/edit_outbox.dart';
import '../../drive/domain/drive_models.dart';
import '../../offline/data/offline_sync.dart';

/// What a folder holds, in it and below it, as a row's meta line: '12 items
/// · 340 MB', or 'Empty folder' when nothing is in it. Null while it hasn't
/// been counted yet, so the row keeps its plain 'Folder · date' line
/// instead of calling a full folder empty for a moment.
String? folderContentsLine(FolderSize? size) => switch (size) {
  null => null,
  FolderSize(count: 0) => 'Empty folder',
  _ =>
    '${Formatters.count(size.count, 'item')} · ${Formatters.bytes(size.bytes)}',
};

/// A file's meta line: '1:12:40 · 1.2 GB · 23 Sep' for a video or audio
/// file whose length is known, 'Small copy · 312 KB · 23 Sep' for a photo
/// whose original is still to come, '1.2 GB · 23 Sep' for everything else.
String fileMetaLine(DriveFile file) => [
  if (file.isSmallCopy) 'Small copy',
  if (file.duration case final d?) Formatters.length(d),
  Formatters.bytes(file.size),
  Formatters.date(file.modifiedAt),
].join(' · ');

/// A file as a list row: picture slot, name, length, size and date, and a
/// menu.
class FileListTile extends ConsumerWidget {
  const FileListTile({
    super.key,
    required this.file,
    required this.onTap,
    this.onLongPress,
    this.onMore,
    this.selected = false,
    this.selecting = false,
    this.highlighted = false,
    this.subtitle,
    this.subtitleColor,
    this.trailing,
    this.progress,
  });

  final DriveFile file;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onMore;
  final bool selected;
  final bool selecting;

  /// Pointed out for a moment, after Show in folder.
  final bool highlighted;

  /// Replaces the default "size · date" line.
  final String? subtitle;

  /// Colours [subtitle] when it says something went wrong.
  final Color? subtitleColor;

  /// An action of the row's own, before the menu.
  final Widget? trailing;

  /// How much of the file has been played, from 0 to 1, drawn as a thin bar
  /// under the meta line. Null leaves the row as it is.
  final double? progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline = ref.watch(
      offlineCopiesProvider.select(
        (copies) => copies.value?.containsKey(file.id) ?? false,
      ),
    );
    final pending = ref.watch(
      pendingItemIdsProvider.select((ids) => ids.value?.contains(file.id) ?? false),
    );
    return _Row(
      selected: selected,
      highlighted: highlighted,
      onTap: onTap,
      onLongPress: onLongPress,
      slot: _Selectable(
        selected: selected,
        child: FileThumbnail(file: file),
      ),
      title: file.name,
      meta: subtitle ?? fileMetaLine(file),
      metaColor: subtitleColor,
      starred: file.starred,
      offline: offline,
      pending: pending,
      trailing: trailing,
      progress: progress,
      onMore: selecting ? null : onMore,
    );
  }
}

/// A folder as a list row. With no [onTap], [onLongPress] or [onMore] it
/// is inert, for a list where folders can't be picked while selecting.
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
    this.subtitleColor,
    this.trailing,
  });

  final DriveFolder folder;

  /// Replaces the default "Folder · date" line.
  final String? subtitle;

  /// Colours [subtitle] when it says something went wrong.
  final Color? subtitleColor;

  /// An action of the row's own, before the menu.
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onMore;
  final bool selected;
  final bool selecting;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline = ref.watch(
      offlinePinsProvider.select(
        (pins) => pins.value?.contains(folder.id) ?? false,
      ),
    );
    final pending = ref.watch(
      pendingItemIdsProvider.select((ids) => ids.value?.contains(folder.id) ?? false),
    );
    return _Row(
      selected: selected,
      onTap: onTap,
      onLongPress: onLongPress,
      offline: offline,
      pending: pending,
      slot: _Selectable(selected: selected, child: const FolderIconTile()),
      title: folder.name,
      meta: subtitle ?? 'Folder · ${Formatters.date(folder.modifiedAt)}',
      metaColor: subtitleColor,
      starred: folder.starred,
      trailing: trailing,
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
    this.pending = false,
    this.highlighted = false,
    this.metaColor,
    this.trailing,
    this.progress,
  });

  final bool selected;
  final bool highlighted;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget slot;
  final String title;
  final String meta;
  final Color? metaColor;
  final Widget? trailing;
  final VoidCallback? onMore;
  final bool starred;

  /// Kept on this phone for use without a connection.
  final bool offline;

  /// Changed on this phone in a way that is still to reach Telegram.
  final bool pending;

  /// How far playback is through the file, as a thin bar under the meta
  /// line, or null for no bar.
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return _Tint(
      on: highlighted,
      child: Material(
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
                          if (pending) ...[
                            Icon(
                              Icons.schedule_rounded,
                              size: 14,
                              color: colors.text2,
                            ),
                            const SizedBox(width: Space.xs),
                          ],
                          if (starred) ...[
                            Icon(
                              Icons.star_rounded,
                              size: 14,
                              color: colors.text2,
                            ),
                            const SizedBox(width: Space.xs),
                          ],
                          if (offline) ...[
                            Icon(
                              Icons.offline_pin_rounded,
                              size: 14,
                              color: colors.text2,
                            ),
                            const SizedBox(width: Space.xs),
                          ],
                          Flexible(
                            child: Text(
                              meta,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.text.bodySmall?.copyWith(
                                color: metaColor,
                                fontFeatures: tabularFigures,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (progress case final progress?) ...[
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 3,
                            color: colors.accent,
                            backgroundColor: colors.surface2,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                ?trailing,
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
              child: Icon(
                Icons.check_rounded,
                color: Theme.of(context).colorScheme.onPrimary,
              ),
            )
          : KeyedSubtree(key: const ValueKey('normal'), child: child),
    );
  }
}

/// The brief tint on the file Show in folder led to. It is a tone rather
/// than the accent, since nothing is selected, and it fades in and out.
class _Tint extends StatelessWidget {
  const _Tint({required this.on, required this.child, this.radius});

  final bool on;
  final Widget child;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final tone = context.colors.surface2;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        // Clear in the same tone, so the fade changes only how much shows.
        color: on ? tone : tone.withValues(alpha: 0),
        borderRadius: radius == null ? null : BorderRadius.circular(radius!),
      ),
      child: child,
    );
  }
}

/// A file in grid view: the picture, then its name and size under it, with
/// the same marks as the list row.
class FileGridCard extends ConsumerWidget {
  const FileGridCard({
    super.key,
    required this.file,
    required this.onTap,
    this.onLongPress,
    this.onMore,
    this.selected = false,
    this.selecting = false,
    this.highlighted = false,
  });

  final DriveFile file;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onMore;
  final bool selected;
  final bool selecting;

  /// Pointed out for a moment, after Show in folder.
  final bool highlighted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final offline = ref.watch(
      offlineCopiesProvider.select(
        (copies) => copies.value?.containsKey(file.id) ?? false,
      ),
    );
    return _Tint(
      on: highlighted,
      radius: Radii.control,
      child: InkWell(
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
                  FileThumbnail(
                    file: file,
                    expand: true,
                    radius: Radii.control,
                  ),
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
                      child: Icon(
                        Icons.check_circle_rounded,
                        color: colors.accent,
                      ),
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
                      Row(
                        children: [
                          if (offline) ...[
                            Icon(
                              Icons.offline_pin_rounded,
                              size: 14,
                              color: colors.text2,
                            ),
                            const SizedBox(width: Space.xs),
                          ],
                          Flexible(
                            child: Text(
                              [
                                if (file.duration case final d?)
                                  Formatters.length(d),
                                Formatters.bytes(file.size),
                                if (file.starred) 'starred',
                              ].join(' · '),
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
      ),
    );
  }
}

/// A folder in grid view: an outlined row, lighter than a file, with the
/// same marks as the list row when it is starred or kept offline. Inert
/// without [onTap], [onLongPress] and [onMore], like the list row.
class FolderGridCard extends ConsumerWidget {
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
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onMore;
  final bool selected;
  final bool selecting;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final offline = ref.watch(
      offlinePinsProvider.select(
        (pins) => pins.value?.contains(folder.id) ?? false,
      ),
    );
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
              if (offline) ...[
                Icon(Icons.offline_pin_rounded, size: 14, color: colors.text2),
                const SizedBox(width: Space.xs),
              ],
              Expanded(
                child: Text(
                  folder.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.titleSmall?.copyWith(fontSize: 14),
                ),
              ),
              if (folder.starred)
                Padding(
                  padding: const EdgeInsets.only(left: Space.s),
                  child: Icon(
                    Icons.star_rounded,
                    size: 14,
                    color: colors.text2,
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
