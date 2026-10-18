import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/format/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../../infrastructure/database/app_database.dart';
import '../../../infrastructure/network/network_status.dart';
import '../../../infrastructure/storage/device_storage.dart';
import '../../../infrastructure/storage/preferences.dart';
import '../../backup/data/backup_controller.dart';
import '../../backup/data/local_media.dart';
import '../../drive/data/drive_repository.dart';
import '../../drive/domain/drive_models.dart';
import '../../files/presentation/file_actions.dart';
import '../../photos/presentation/album_actions.dart';
import '../../share/data/recent_destinations.dart';
import '../../transfers/data/transfer_policy.dart';
import '../../transfers/data/transfer_queue.dart';
import '../../transfers/presentation/mobile_data_prompt.dart';
import '../../trash/data/pending_deletes.dart';
import '../data/phone_albums.dart';

/// Uploading an album from the phone's gallery: its photos and videos go
/// up as originals into a folder of the album's name, and into a drive
/// album of that name, one already in the drive or a new one. A photo the
/// drive has already joins the album where it is, with nothing sent.
abstract final class PhoneAlbumUpload {
  /// Has the person pick an album in the gallery and sends it up into a
  /// folder of its name inside [folderId], the root when null.
  static Future<void> start(
    BuildContext context,
    WidgetRef ref, {
    String? folderId,
  }) async {
    if (!FileActions.connected(context, ref)) return;
    final permission = await PhotoManager.requestPermissionExtend(
      requestOption: BackupController.permissionOption,
    );
    if (!context.mounted) return;
    if (!permission.hasAccess) {
      showSnack(
        context,
        'Telegrive needs access to your photos to upload an album.',
        actionLabel: 'Settings',
        onAction: PhotoManager.openSetting,
      );
      return;
    }

    // Everything [ref] gives is read before the long waits: the screen
    // that asked may be gone by the time the album has been read.
    final repository = ref.read(driveRepositoryProvider);
    final queue = ref.read(transferQueueProvider.notifier);
    final db = ref.read(appDatabaseProvider);
    final storage = ref.read(deviceStorageProvider);
    final recent = ref.read(recentDestinationsProvider.notifier);
    final where = folderId == null
        ? 'Files'
        : (await repository.pathTo(folderId)).lastOrNull?.name ?? 'this folder';
    if (!context.mounted) return;

    final album = await showModalBottomSheet<PhoneAlbum>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (_) => _PhoneAlbumPicker(where: where),
    );
    if (album == null || !context.mounted) return;
    final name = album.name;
    final go = await showConfirmDialog(
      context,
      title: 'Upload "$name"?',
      message:
          '${Formatters.count(album.count, 'item')} go up in full quality to '
          'the folder "$name" in $where, and into the album "$name" in '
          'Photos. Any already in your drive are added to the album without '
          'uploading again.',
      confirmLabel: 'Upload',
    );
    if (!go || !context.mounted) return;

    final hidden = ref.read(pendingDeletesProvider).hiddenIds;
    final uploads = [
      for (final item in ref.read(transferQueueProvider).items)
        if (item.kind == TransferKind.upload && item.status.isPending) item.row,
    ];
    final existing = (await repository.watchAlbums().first)
        .where((a) => !hidden.contains(a.id) && a.name.toLowerCase() == name.toLowerCase())
        .firstOrNull;
    final pending = {
      for (final row in uploads)
        ?row.assetId: (
          transferId: row.id,
          inAlbum:
              existing != null &&
              (row.albumIds?.split(',').contains(existing.id) ?? false),
        ),
    };
    final local = await db.watchLocalAssets().first;
    final fingerprints = await repository.mediaFingerprints();
    if (!context.mounted) return;
    final planner = AlbumUploadPlanner(
      backedUp: {
        for (final MapEntry(key: fileId, value: assetId) in local.entries)
          assetId: fileId,
      },
      fingerprints: fingerprints,
      pending: pending,
      isLive: (fileId) async {
        final file = await repository.fileById(fileId);
        return file != null && file.trashedAt == null;
      },
    );
    if (!context.mounted) return;

    final AlbumUploadPlan? plan;
    try {
      plan = await _read(context, album, planner, storage);
    } catch (e) {
      debugPrint('[Albums] Reading "$name": $e');
      if (context.mounted) showSnack(context, 'Couldn\'t read "$name" on this phone.');
      return;
    }
    if (plan == null) return;
    if (!context.mounted) return _discard(plan.uploads);
    if (plan.uploads.isEmpty && plan.inDrive.isEmpty && plan.joinOnLanding.isEmpty) {
      showSnack(
        context,
        summary(
              album: name,
              uploading: 0,
              inDrive: 0,
              joining: 0,
              alreadyGoing: plan.alreadyGoing,
              unreadable: plan.unreadable,
              outOfRoom: plan.outOfRoom,
            ) ??
            '"$name" has no photos or videos.',
      );
      return;
    }

    DataChoice? choice;
    if (plan.uploads.isNotEmpty &&
        TransferPolicy.shouldAsk(
          network: ref.read(networkStatusProvider),
          bytes: plan.bytes,
        )) {
      choice = await askAboutMobileData(
        context,
        bytes: plan.bytes,
        doing: 'Uploading "$name"',
        files: plan.uploads.length,
        nowLabel: 'Upload now',
      );
      if (choice == null) return _discard(plan.uploads);
    }
    if (!context.mounted) return _discard(plan.uploads);

    var albumId = existing?.id;
    final made = albumId == null;
    String? albumFolderId;
    try {
      albumId ??= await repository.createAlbum(name);
      if (plan.uploads.isNotEmpty) {
        albumFolderId = await repository.ensureFolderPath([name], under: folderId);
      }
    } catch (e) {
      await _discard(plan.uploads);
      if (context.mounted) {
        showSnack(context, 'Couldn\'t upload "$name": ${FileActions.failureOf(e)}');
      }
      return;
    }
    if (!context.mounted) return _discard(plan.uploads);

    final bigWait = ref.read(preferencesProvider).bigTransfersWifiOnly;
    final requests = [
      for (final upload in plan.uploads)
        UploadRequest(
          name: upload.name,
          path: upload.path,
          size: upload.size,
          ownsSource: upload.ownsSource,
          assetId: upload.assetId,
          takenAt: upload.takenAt,
          thumbnailPath: upload.thumbnailPath,
          durationSeconds: upload.durationSeconds,
          albumIds: [albumId],
          wifiOnly:
              wifiOnlyFrom(choice) ??
              TransferPolicy.wifiOnlyFor(upload.size, bigWaitForWifi: bigWait),
        ),
    ];
    final resolved = requests.isEmpty
        ? const <UploadRequest>[]
        : await FileActions.resolveUploadClashes(
            context,
            ref,
            requests,
            folderId: albumFolderId,
          );
    // Thumbnails of the photos skipped there go with them.
    final going = {for (final request in resolved) request.assetId};
    for (final upload in plan.uploads) {
      if (going.contains(upload.assetId)) continue;
      await upload.discardThumbnail();
    }

    final inDrive = plan.inDrive.toSet();
    if (resolved.isEmpty && inDrive.isEmpty && plan.joinOnLanding.isEmpty) {
      if (made) unawaited(repository.deleteAlbum(albumId).catchError((_) {}));
      if (context.mounted && requests.isNotEmpty) showSnack(context, 'Nothing to upload');
      return;
    }

    final ids = resolved.isEmpty
        ? const <String>[]
        : await queue.enqueueUploads(resolved, folderId: albumFolderId);
    if (ids.isNotEmpty) unawaited(recent.note(albumFolderId));
    for (final id in plan.joinOnLanding) {
      unawaited(_joinOnLanding(queue, repository, id, albumId));
    }

    final files = [
      for (final id in inDrive)
        if (await repository.fileById(id) case final DriveFile file) file,
    ];
    if (!context.mounted) {
      if (files.isNotEmpty) {
        unawaited(
          repository.addToAlbum(files, albumId).catchError((Object e) {
            debugPrint('[Albums] Adding to "$name": $e');
          }),
        );
      }
      return;
    }
    final router = GoRouter.of(context);
    final message = summary(
      album: name,
      uploading: ids.length,
      inDrive: files.length,
      joining: plan.joinOnLanding.length,
      alreadyGoing: plan.alreadyGoing,
      unreadable: plan.unreadable,
      outOfRoom: plan.outOfRoom,
      waitsForWifi: choice == DataChoice.later,
    );
    if (message != null) {
      showSnack(
        context,
        message,
        actionLabel: ids.isEmpty ? null : 'View',
        onAction: ids.isEmpty ? null : () => router.push('/transfers'),
      );
    }
    // Those in the drive already go in as one change with Undo, which says
    // so when it is done.
    if (files.isNotEmpty) {
      await AlbumActions.add(context, ref, files, albumId: albumId, name: name);
    }
  }

  /// What the snack says once [album] is on its way: how many go up, how
  /// many of the drive's files join it, how many of the uploads already
  /// under way join it as they land, and what couldn't be done. Null when
  /// nothing but files in the drive join it, which the album's own change
  /// says.
  @visibleForTesting
  static String? summary({
    required String album,
    required int uploading,
    required int inDrive,
    required int joining,
    required int alreadyGoing,
    required int unreadable,
    required bool outOfRoom,
    bool waitsForWifi = false,
  }) {
    String items(int count) => Formatters.count(count, 'item');
    final sentences = <String>[
      if (uploading > 0)
        '${waitsForWifi ? 'Waiting for Wi-Fi to upload' : 'Uploading'} '
            '${items(uploading)} to "$album".',
      if (uploading > 0 && inDrive > 0)
        '${items(inDrive)} already in your drive join it where they are.',
      if (joining > 0)
        uploading > 0
            ? '${items(joining)} already going up join it as they land.'
            : '${items(joining)} already going up join "$album" as they land.',
      if (unreadable > 0)
        unreadable == 1
            ? '1 item couldn\'t be read.'
            : '${items(unreadable)} couldn\'t be read.',
      if (outOfRoom)
        'The phone ran low on room, so the rest wait: upload the album again '
            'once these are up.',
    ];
    if (sentences.isEmpty) {
      return alreadyGoing > 0 ? '"$album" is already on its way to your drive.' : null;
    }
    return sentences.join(' ');
  }

  /// Reads [album] behind a dialog that counts the photos looked at and can
  /// call it off, which answers null.
  static Future<AlbumUploadPlan?> _read(
    BuildContext context,
    PhoneAlbum album,
    AlbumUploadPlanner planner,
    DeviceStorage storage,
  ) async {
    final progress = ValueNotifier<(int, int)>((0, album.count));
    var cancelled = false;
    BuildContext? dialog;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          dialog = dialogContext;
          return _Reading(
            name: album.name,
            progress: progress,
            onCancel: () => cancelled = true,
          );
        },
      ),
    );
    try {
      return await prepareAlbumUpload(
        album: album,
        planner: planner,
        storage: storage,
        onProgress: (done, total) => progress.value = (done, total),
        cancelled: () => cancelled,
      );
    } finally {
      // The dialog may not have been built yet when reading ends at once.
      await WidgetsBinding.instance.endOfFrame;
      final open = dialog;
      if (open != null && open.mounted) Navigator.of(open).pop();
      progress.dispose();
    }
  }

  static Future<void> _discard(List<PreparedUpload> uploads) async {
    for (final upload in uploads) {
      await upload.discard();
    }
  }

  /// Puts the file upload [id] makes into album [albumId] once it lands.
  static Future<void> _joinOnLanding(
    TransferQueue queue,
    DriveRepository repository,
    String id,
    String albumId,
  ) async {
    try {
      final row = await queue.whenFinished(id);
      if (row.status != TransferStatus.completed) return;
      final file = await repository.fileById(row.fileId);
      if (file != null) await repository.addToAlbum([file], albumId);
    } catch (e) {
      debugPrint('[Albums] Adding upload $id to its album: $e');
    }
  }
}

/// The gallery's albums to pick from, each with its newest photo and how
/// many it holds. Pops with the album picked.
class _PhoneAlbumPicker extends ConsumerWidget {
  const _PhoneAlbumPicker({required this.where});

  /// The folder each album's own folder goes into, by name.
  final String where;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albums = ref.watch(phoneAlbumsProvider);
    Widget note(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.l, Space.gutter, Space.xl),
      child: Text(text, style: context.text.bodyMedium?.copyWith(color: context.colors.text2)),
    );
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.xs),
              child: Text('Upload an album', style: context.text.titleMedium),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.s),
              child: Text(
                'It goes up as a folder in $where and an album in Photos.',
                style: context.text.bodySmall,
              ),
            ),
            Flexible(
              child: switch (albums) {
                AsyncData(value: final albums) when albums.isEmpty => note(
                  'There are no albums on this phone yet.',
                ),
                AsyncData(value: final albums) => ListView(
                  shrinkWrap: true,
                  children: [
                    for (final album in albums)
                      ListTile(
                        leading: _Cover(assetId: album.coverAssetId),
                        title: Text(album.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          Formatters.count(album.count, 'item'),
                          style: const TextStyle(fontFeatures: tabularFigures),
                        ),
                        onTap: () => Navigator.pop(context, album),
                      ),
                  ],
                ),
                AsyncError() => note('Couldn\'t read the albums on this phone.'),
                _ => const Padding(
                  padding: EdgeInsets.all(Space.xl),
                  child: Center(child: CircularProgressIndicator()),
                ),
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// An album's newest photo, or a placeholder while there is none.
class _Cover extends ConsumerWidget {
  const _Cover({required this.assetId});

  final String? assetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = assetId;
    final bytes = id == null ? null : ref.watch(assetThumbnailProvider(id)).value;
    return SizedBox.square(
      dimension: 44,
      child: bytes != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(Radii.thumb),
              child: Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true),
            )
          : DecoratedBox(
              decoration: BoxDecoration(
                color: context.colors.surface2,
                borderRadius: BorderRadius.circular(Radii.thumb),
              ),
              child: Icon(Icons.photo_library_outlined, color: context.colors.text3),
            ),
    );
  }
}

/// Counts the photos looked at while an album is read, with Cancel. Back
/// cancels too.
class _Reading extends StatefulWidget {
  const _Reading({required this.name, required this.progress, required this.onCancel});

  final String name;
  final ValueListenable<(int, int)> progress;
  final VoidCallback onCancel;

  @override
  State<_Reading> createState() => _ReadingState();
}

class _ReadingState extends State<_Reading> {
  var _cancelling = false;

  void _cancel() {
    if (_cancelling) return;
    widget.onCancel();
    setState(() => _cancelling = true);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: AlertDialog(
        title: Text('Getting "${widget.name}" ready'),
        content: ValueListenableBuilder<(int, int)>(
          valueListenable: widget.progress,
          builder: (context, progress, _) {
            final (done, total) = progress;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _cancelling
                      ? 'Stopping…'
                      : '${Formatters.count(done, 'item')} of '
                            '${NumberFormat.decimalPattern().format(total)} looked at',
                  style: const TextStyle(fontFeatures: tabularFigures),
                ),
                const SizedBox(height: Space.m),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: total == 0 ? null : done / total,
                    minHeight: 4,
                  ),
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: _cancelling ? null : _cancel,
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}
