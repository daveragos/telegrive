import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/format/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/file_visuals.dart';
import '../../drive/data/drive_repository.dart';
import '../../drive/domain/drive_models.dart';
import '../../files/presentation/file_actions.dart';

/// Making, filling and tidying photo albums.
abstract final class AlbumActions {
  static const _newAlbum = '';

  /// Asks which album, or for a new one, and adds [files] to it. Returns
  /// whether they went in.
  static Future<bool> addTo(
    BuildContext context,
    WidgetRef ref,
    List<DriveFile> files,
  ) async {
    if (files.isEmpty) return false;
    final choice = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (_) => const _AlbumPicker(),
    );
    if (choice == null || !context.mounted) return false;

    final repository = ref.read(driveRepositoryProvider);
    var albumId = choice;
    var name = ref.read(albumsProvider).value?.where((a) => a.id == choice).firstOrNull?.name;
    if (choice == _newAlbum) {
      name = await _askName(context, title: 'New album', confirm: 'Create');
      if (name == null || !context.mounted) return false;
      final created = await FileActions.guarded(
        context,
        () async => albumId = await repository.createAlbum(name!),
      );
      if (!created || !context.mounted) return false;
    }
    return FileActions.guarded(
      context,
      () => repository.addToAlbum(files, albumId),
      success: 'Added ${Formatters.count(files.length, 'item')} to "$name"',
    );
  }

  /// A new, empty album, opened straight away.
  static Future<void> create(BuildContext context, WidgetRef ref) async {
    final name = await _askName(context, title: 'New album', confirm: 'Create');
    if (name == null || !context.mounted) return;
    String? id;
    final created = await FileActions.guarded(
      context,
      () async => id = await ref.read(driveRepositoryProvider).createAlbum(name),
    );
    if (created && id != null && context.mounted) context.push('/albums/$id');
  }

  static Future<void> rename(BuildContext context, WidgetRef ref, DriveAlbum album) async {
    final name = await _askName(
      context,
      title: 'Rename album',
      confirm: 'Rename',
      initial: album.name,
    );
    if (name == null || !context.mounted) return;
    await FileActions.guarded(
      context,
      () => ref.read(driveRepositoryProvider).renameAlbum(album.id, name),
    );
  }

  /// Returns whether the album went.
  static Future<bool> delete(BuildContext context, WidgetRef ref, DriveAlbum album) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete "${album.name}"?',
      message: 'Only the album goes. Its photos and videos stay in your drive.',
      confirmLabel: 'Delete album',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return false;
    return FileActions.guarded(
      context,
      () => ref.read(driveRepositoryProvider).deleteAlbum(album.id),
      success: 'Album deleted',
    );
  }

  static Future<bool> removeFrom(
    BuildContext context,
    WidgetRef ref,
    List<DriveFile> files,
    String albumId,
  ) => FileActions.guarded(
    context,
    () => ref.read(driveRepositoryProvider).removeFromAlbum(files, albumId),
    success: 'Removed ${Formatters.count(files.length, 'item')} from the album',
  );

  static Future<String?> _askName(
    BuildContext context, {
    required String title,
    required String confirm,
    String initial = '',
  }) async {
    final name = await showTextInputDialog(
      context,
      title: title,
      initialValue: initial,
      hint: 'Album name',
      confirmLabel: confirm,
    );
    final clean = name?.trim();
    return clean == null || clean.isEmpty ? null : clean;
  }
}

/// Existing albums to pick from, with "New album" on top. Pops with the
/// album's id, or '' for a new one.
class _AlbumPicker extends ConsumerWidget {
  const _AlbumPicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albums = ref.watch(albumsProvider).value ?? const <DriveAlbum>[];
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.s),
              child: Text('Add to album', style: context.text.titleMedium),
            ),
            ListTile(
              leading: SizedBox.square(
                dimension: 44,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: context.colors.surface2,
                    borderRadius: BorderRadius.circular(Radii.thumb),
                  ),
                  child: Icon(Icons.add_rounded, color: context.colors.text2),
                ),
              ),
              title: const Text('New album'),
              onTap: () => Navigator.pop(context, AlbumActions._newAlbum),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final album in albums)
                    ListTile(
                      leading: AlbumCover(album: album, size: 44),
                      title: Text(album.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(Formatters.count(album.count, 'item')),
                      onTap: () => Navigator.pop(context, album.id),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// An album's newest photo, or a placeholder while it has none.
class AlbumCover extends ConsumerWidget {
  const AlbumCover({super.key, required this.album, this.size, this.cover});

  final DriveAlbum? album;

  /// Square side; null fills the space given.
  final double? size;

  /// The cover file itself, when the caller already has it.
  final DriveFile? cover;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coverId = album?.coverFileId;
    final file = cover ??
        (coverId == null ? null : ref.watch(fileInfoProvider(coverId)).value);
    final radius = BorderRadius.circular(size != null && size! < 64 ? Radii.thumb : Radii.card);
    final child = file == null
        ? DecoratedBox(
            decoration: BoxDecoration(color: context.colors.surface2, borderRadius: radius),
            child: Icon(Icons.photo_library_outlined, color: context.colors.text3),
          )
        : ClipRRect(
            borderRadius: radius,
            child: FileThumbnail(file: file, expand: true, radius: 0, size: 40),
          );
    return size == null ? child : SizedBox.square(dimension: size, child: child);
  }
}
