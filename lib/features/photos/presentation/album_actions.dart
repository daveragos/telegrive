import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/format/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/file_visuals.dart';
import '../../drive/data/drive_repository.dart';
import '../../drive/domain/drive_models.dart';
import '../../files/data/bulk_edits.dart';
import '../../files/presentation/file_actions.dart';
import '../../trash/data/pending_deletes.dart';

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
    return add(context, ref, files, albumId: albumId, name: name ?? 'album');
  }

  /// Adds [files] to the album [albumId], called [name], as one bulk change
  /// with Undo, then lifts the album to the top. Returns whether they all
  /// went in.
  static Future<bool> add(
    BuildContext context,
    WidgetRef ref,
    List<DriveFile> files, {
    required String albumId,
    required String name,
  }) async {
    final repository = ref.read(driveRepositoryProvider);
    final edits = ref.read(bulkEditsProvider.notifier);
    // Undo takes out only what this change put in; a photo that was in the
    // album already stays. The repository reads membership from the index,
    // so the files in hand serve as they are.
    final members = {for (final file in await repository.watchAlbumFiles(albumId).first) file.id};
    if (!context.mounted) return false;
    final count = Formatters.count(files.length, 'item');
    final outcome = await FileActions.runBulk<DriveFile>(
      context,
      edits,
      label: 'Adding $count to "$name"',
      icon: Icons.photo_album_outlined,
      items: files,
      apply: (file) => repository.addToAlbum([file], albumId, touch: false),
      success: 'Added $count to "$name"',
      undo: (
        label: (done) => 'Removing ${Formatters.count(done, 'item')} from "$name"',
        apply: (file) async {
          if (!members.contains(file.id)) await repository.removeFromAlbum([file], albumId);
        },
      ),
    );
    if (outcome == null || outcome.done == 0) return false;
    // Lifting the album to the top is one edit of its own, made once for
    // however many files went in, even when the change stopped part way or
    // the screen that asked for it is gone. If it fails, that is said after
    // the snack offering Undo, which stays.
    try {
      await repository.touchAlbum(albumId);
    } catch (e) {
      debugPrint('[Albums] Could not lift "$name" to the top: $e');
      if (context.mounted) {
        showSnack(
          context,
          'Couldn\'t move "$name" to the top of Albums: ${FileActions.failureOf(e)}',
          queue: true,
        );
      }
    }
    return outcome.complete;
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
    if (name == null || name == album.name || !context.mounted) return;
    final repository = ref.read(driveRepositoryProvider);
    await FileActions.guarded(
      context,
      () => repository.renameAlbum(album.id, name),
      success: 'Renamed to "$name"',
      undo: () => repository.renameAlbum(album.id, album.name),
    );
  }

  /// Takes the album off the list at once and deletes it once its Undo has
  /// had its time; its photos and videos stay in the drive. Returns whether
  /// the delete is under way, so the album's screen closes.
  static Future<bool> delete(BuildContext context, WidgetRef ref, DriveAlbum album) async {
    final repository = ref.read(driveRepositoryProvider);
    return FileActions.deleteLater(
      context,
      ref,
      albumIds: {album.id},
      label: '"${album.name}"',
      message: 'Deleting "${album.name}"',
      run: () => repository.deleteAlbum(album.id),
    );
  }

  static Future<bool> removeFrom(
    BuildContext context,
    WidgetRef ref,
    List<DriveFile> files,
    String albumId,
  ) async {
    final repository = ref.read(driveRepositoryProvider);
    final count = Formatters.count(files.length, 'item');
    final outcome = await FileActions.runBulk<DriveFile>(
      context,
      ref.read(bulkEditsProvider.notifier),
      label: 'Removing $count from the album',
      icon: Icons.photo_album_outlined,
      items: files,
      apply: (file) => repository.removeFromAlbum([file], albumId),
      success: 'Removed $count from the album',
      undo: (
        label: (done) => 'Adding ${Formatters.count(done, 'item')} back to the album',
        apply: (file) => repository.addToAlbum([file], albumId, touch: false),
      ),
    );
    return outcome?.complete ?? false;
  }

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
    final hidden = ref.watch(pendingDeletesProvider.select((s) => s.hiddenIds));
    final albums = [
      for (final album in ref.watch(albumsProvider).value ?? const <DriveAlbum>[])
        if (!hidden.contains(album.id)) album,
    ];
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
