import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/files/file_kind.dart';
import '../../../core/format/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/file_visuals.dart';
import '../../../infrastructure/database/app_database.dart'
    show SaveTarget, TransferKind, appDatabaseProvider;
import '../../../infrastructure/storage/device_storage.dart';
import '../../../infrastructure/storage/preferences.dart';
import '../../../infrastructure/telegram/telegram_exception.dart';
import '../../backup/data/backup_controller.dart';
import '../../backup/data/free_up_space.dart';
import '../../offline/data/offline_sync.dart';
import '../../send/data/telegram_chats.dart';
import '../../send/presentation/chat_picker.dart';
import '../../drive/data/channel_messenger.dart';
import '../../drive/data/drive_repository.dart';
import '../../drive/data/drive_session.dart';
import '../../drive/domain/drive_models.dart';
import '../../transfers/data/transfer_queue.dart';
import '../../transfers/domain/transfer_error.dart';
import '../../transfers/domain/transfer_wait.dart';
import '../../trash/data/pending_deletes.dart';
import '../data/bulk_edits.dart';
import 'folder_picker.dart';
import 'trash_sheet.dart';

/// One item of a bulk change that mixes files and folders: how to make the
/// change, and how to take it back.
typedef _Step = ({Future<void> Function() apply, Future<void> Function() undo});

/// Every action a person can take on files and folders, in one place so the
/// home screen, the browser and search all behave identically.
abstract final class FileActions {
  // ---------------------------------------------------------------------------
  // Opening & sharing
  // ---------------------------------------------------------------------------

  /// Shows [file] in the app when it can: photos in the viewer, video and
  /// audio in the player (streaming), PDFs and text in a reader. Anything
  /// else downloads and opens in whichever app handles it. Home's Recent
  /// remembers it either way, without holding the file up.
  static Future<void> open(
    BuildContext context,
    WidgetRef ref,
    DriveFile file,
  ) async {
    unawaited(ref.read(driveRepositoryProvider).recordOpen(file.id));
    switch (Preview.of(
      name: file.name,
      mimeType: file.mimeType,
      kind: file.kind,
      size: file.size,
      isSplit: file.isSplit,
    )) {
      case Preview.image:
        await context.push('/viewer/${file.id}');
      case Preview.media:
        await context.push('/play/${file.id}');
      case Preview.pdf || Preview.text:
        await context.push('/preview/${file.id}');
      case Preview.none:
        await openExternally(context, ref, file);
    }
  }

  /// Downloads [file] if need be and hands it to another app.
  static Future<void> openExternally(
    BuildContext context,
    WidgetRef ref,
    DriveFile file,
  ) async {
    final path = await _obtain(context, ref, file);
    if (path == null) return;
    final result = await OpenFilex.open(path, type: file.mimeType);
    if (result.type != ResultType.done && context.mounted) {
      showSnack(
        context,
        'No app on this device opens ${file.extension.isEmpty ? 'this file' : '.${file.extension.toLowerCase()} files'}.',
        actionLabel: 'Share',
        onAction: () => _sharePath(path, file),
      );
    }
  }

  static Future<void> share(
    BuildContext context,
    WidgetRef ref,
    DriveFile file,
  ) async {
    final repository = ref.read(driveRepositoryProvider);
    final path = await _obtain(context, ref, file);
    if (path == null) return;
    unawaited(repository.recordOpen(file.id));
    await _sharePath(path, file);
  }

  static Future<void> _sharePath(String path, DriveFile file) =>
      SharePlus.instance.share(
        ShareParams(
          files: [XFile(path, name: file.name, mimeType: file.mimeType)],
          fileNameOverrides: [file.name],
        ),
      );

  /// Downloads [file] behind a progress dialog, unless it is already here.
  static Future<String?> _obtain(
    BuildContext context,
    WidgetRef ref,
    DriveFile file,
  ) async {
    final queue = ref.read(transferQueueProvider.notifier);
    final local = await queue.localPathIfAvailable(file);
    if (local != null) return local;
    if (!context.mounted) return null;
    final download = queue.download(file);
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DownloadDialog(file: file, download: download),
    );
  }

  // ---------------------------------------------------------------------------
  // Downloading to the phone
  // ---------------------------------------------------------------------------

  /// Downloads [files] and everything inside [folders] (or, with
  /// [everything], the whole drive) to this phone, in the drive's folders.
  /// Photos and videos can go to the gallery instead; [preferGallery] is
  /// where that choice starts, by default on when everything is media.
  /// Returns whether anything was queued.
  static Future<bool> saveToDevice(
    BuildContext context,
    WidgetRef ref, {
    List<DriveFile> files = const [],
    List<DriveFolder> folders = const [],
    bool everything = false,
    bool? preferGallery,
  }) async {
    final storage = ref.read(deviceStorageProvider);
    final (items, free) = await (
      ref
          .read(driveRepositoryProvider)
          .collectForSaving(files: files, folders: folders, everything: everything),
      storage.freeBytes(),
    ).wait;
    if (!context.mounted) return false;
    if (items.isEmpty) {
      showSnack(context, 'There are no files in here yet.');
      return false;
    }

    final gallery = await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (_) => _SaveSheet(
        items: items,
        freeBytes: free,
        preferGallery: preferGallery ?? items.every((i) => fitsGallery(i.file)),
      ),
    );
    if (gallery == null || !context.mounted) return false;

    final useGallery = gallery && items.any((i) => fitsGallery(i.file));
    if (!await storage.ensureAccess(gallery: useGallery)) {
      if (context.mounted) {
        showSnack(
          context,
          useGallery
              ? 'Allow access to your photos to put them back in your library.'
              : 'Allow storage access to save files on this phone.',
        );
      }
      return false;
    }

    final requests = [
      for (final item in items)
        if (useGallery && fitsGallery(item.file))
          SaveRequest(
            item.file,
            target: SaveTarget.gallery,
            folders: [?_backupAlbum(item.path)],
          )
        else
          SaveRequest(item.file, target: SaveTarget.files, folders: item.folders),
    ];
    final queued = await ref
        .read(transferQueueProvider.notifier)
        .enqueueSaves(requests);
    if (!context.mounted) return true;
    showSnack(
      context,
      queued == 0
          ? 'Already downloading to this phone'
          : 'Downloading ${Formatters.count(queued, 'file')} to this phone',
      actionLabel: 'View',
      onAction: () => context.push('/transfers'),
    );
    return true;
  }

  /// Photos and videos in formats every phone's gallery takes.
  static bool fitsGallery(DriveFile file) => file.fitsGallery;

  /// `Photo backup/Camera/…` → `Camera`: the phone folder a backed-up photo
  /// came from, so it goes back there.
  static String? _backupAlbum(List<String> path) =>
      path.length >= 2 && path.first == BackupController.rootFolder ? path[1] : null;

  // ---------------------------------------------------------------------------
  // Available offline
  // ---------------------------------------------------------------------------

  /// Keeps [file] or [folder] (with everything in it, now and later) on
  /// this phone for use without a connection, or stops keeping it.
  static Future<bool> setOffline(
    BuildContext context,
    WidgetRef ref, {
    DriveFile? file,
    DriveFolder? folder,
    required bool keep,
  }) {
    final offline = ref.read(offlineSyncProvider.notifier);
    final name = file?.name ?? folder!.name;
    return _guard(
      context,
      () => keep
          ? offline.pin(file: file, folder: folder)
          : offline.unpin(file: file, folder: folder),
      success: keep
          ? '"$name" will be available offline'
          : '"$name" is no longer kept offline',
    );
  }

  // ---------------------------------------------------------------------------
  // Sending in Telegram
  // ---------------------------------------------------------------------------

  /// Sends [files] to chats the person picks, straight from the drive, with
  /// no upload. Returns whether they went.
  static Future<bool> sendToChats(
    BuildContext context,
    WidgetRef ref,
    List<DriveFile> files,
  ) async {
    if (files.isEmpty) return false;
    final split = files.any((f) => f.isSplit);
    final chats = await showChatPicker(
      context,
      title: files.length == 1
          ? 'Send "${files.first.name}"'
          : 'Send ${Formatters.count(files.length, 'file')}',
      note: split
          ? 'Files over 2 GB are kept in parts, and arrive as numbered parts.'
          : null,
    );
    if (chats == null || chats.isEmpty || !context.mounted) return false;
    final repository = ref.read(driveRepositoryProvider);
    final telegram = ref.read(telegramChatsProvider);
    return _guard(
      context,
      () async {
        await telegram.send(files, chats.map((c) => c.id).toList());
        await repository.recordOpens([for (final f in files) f.id]);
      },
      success: chats.length == 1
          ? 'Sent to ${chats.single.title}'
          : 'Sent to ${Formatters.count(chats.length, 'chat')}',
    );
  }

  // ---------------------------------------------------------------------------
  // Uploading & creating
  // ---------------------------------------------------------------------------

  static Future<void> upload(
    BuildContext context,
    WidgetRef ref, {
    String? folderId,
    bool mediaOnly = false,
  }) async {
    final List<PlatformFile> picked;
    try {
      picked = await FilePicker.pickFiles(
        type: mediaOnly ? FileType.media : FileType.any,
      );
    } catch (e) {
      if (context.mounted) showSnack(context, 'Couldn\'t open the file picker.');
      return;
    }
    if (picked.isEmpty) return;

    final temp = (await getTemporaryDirectory()).path;
    final requests = [
      for (final file in picked)
        UploadRequest(
          name: file.name,
          path: file.path,
          size: file.lengthSync(),
          openRead: file.path == null ? file.readAsByteStream : null,
          ownsSource: file.path?.startsWith(temp) ?? false,
        ),
    ];
    await ref
        .read(transferQueueProvider.notifier)
        .enqueueUploads(requests, folderId: folderId);
    if (context.mounted) {
      showSnack(
        context,
        requests.length == 1
            ? 'Uploading ${requests.first.name}'
            : 'Uploading ${requests.length} files',
        actionLabel: 'View',
        onAction: () => context.go('/transfers'),
      );
    }
  }

  static Future<void> createFolder(
    BuildContext context,
    WidgetRef ref, {
    String? parentId,
  }) async {
    final name = await showTextInputDialog(
      context,
      title: 'New folder',
      hint: 'Folder name',
      confirmLabel: 'Create',
    );
    if (name == null || !context.mounted) return;
    await _guard(
      context,
      () => ref.read(driveRepositoryProvider).createFolder(name, parentId: parentId),
    );
  }

  /// The sheet behind the "+" button.
  static Future<void> showCreateSheet(
    BuildContext context,
    WidgetRef ref, {
    String? folderId,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: Space.s),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _CreateOption(
                icon: Icons.upload_file_outlined,
                label: 'Upload files',
                detail: 'Anything on this phone, any size',
                onTap: () {
                  Navigator.pop(sheetContext);
                  upload(context, ref, folderId: folderId);
                },
              ),
              _CreateOption(
                icon: Icons.photo_library_outlined,
                label: 'Upload photos and videos',
                detail: 'Originals, uncompressed',
                onTap: () {
                  Navigator.pop(sheetContext);
                  upload(context, ref, folderId: folderId, mediaOnly: true);
                },
              ),
              _CreateOption(
                icon: Icons.create_new_folder_outlined,
                label: 'New folder',
                onTap: () {
                  Navigator.pop(sheetContext);
                  createFolder(context, ref, parentId: folderId);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Organising
  // ---------------------------------------------------------------------------

  static Future<void> renameFile(
    BuildContext context,
    WidgetRef ref,
    DriveFile file,
  ) async {
    final name = await showTextInputDialog(
      context,
      title: 'Rename file',
      initialValue: file.name,
      selectStem: true,
      confirmLabel: 'Rename',
    );
    if (name == null || name == file.name || !context.mounted) return;
    final repository = ref.read(driveRepositoryProvider);
    await _guard(
      context,
      () => repository.renameFile(file, name),
      success: 'Renamed to "$name"',
      undo: () async {
        for (final current in await _current(repository, [file])) {
          await repository.renameFile(current, file.name);
        }
      },
    );
  }

  static Future<void> renameFolder(
    BuildContext context,
    WidgetRef ref,
    DriveFolder folder,
  ) async {
    final name = await showTextInputDialog(
      context,
      title: 'Rename folder',
      initialValue: folder.name,
      confirmLabel: 'Rename',
    );
    if (name == null || name == folder.name || !context.mounted) return;
    final repository = ref.read(driveRepositoryProvider);
    await _guard(
      context,
      () => repository.renameFolder(folder, name),
      success: 'Renamed to "$name"',
      undo: () async {
        for (final current in await _currentFolders(repository, [folder])) {
          await repository.renameFolder(current, folder.name);
        }
      },
    );
  }

  static Future<bool> move(
    BuildContext context,
    WidgetRef ref, {
    List<DriveFile> files = const [],
    List<DriveFolder> folders = const [],
  }) async {
    final count = files.length + folders.length;
    final destination = await showFolderPicker(
      context,
      title: count == 1 ? 'Move 1 item' : 'Move $count items',
      excluded: folders.map((f) => f.id).toSet(),
      startIn: files.isNotEmpty ? files.first.folderId : folders.first.parentId,
    );
    if (destination == null || !context.mounted) return false;
    final target = destination.folderId;
    final repository = ref.read(driveRepositoryProvider);
    final outcome = await runBulk<_Step>(
      context,
      ref.read(bulkEditsProvider.notifier),
      label: 'Moving ${Formatters.count(count, 'item')}',
      icon: Icons.drive_file_move_outline,
      items: <_Step>[
        for (final file in files)
          (
            apply: () => repository.moveFiles([file], target),
            undo: () async =>
                repository.moveFiles(await _current(repository, [file]), file.folderId),
          ),
        for (final folder in folders)
          (
            apply: () => repository.moveFolder(folder, target),
            undo: () async {
              for (final current in await _currentFolders(repository, [folder])) {
                await repository.moveFolder(current, folder.parentId);
              }
            },
          ),
      ],
      apply: (step) => step.apply(),
      success: 'Moved to ${destination.name}',
      undo: (
        label: (done) => 'Moving ${Formatters.count(done, 'item')} back',
        apply: (step) => step.undo(),
      ),
    );
    return outcome?.complete ?? false;
  }

  /// Stars or unstars [files], with Undo. Returns whether every file
  /// changed.
  static Future<bool> setStarred(
    BuildContext context,
    WidgetRef ref,
    List<DriveFile> files, {
    required bool starred,
  }) async {
    final repository = ref.read(driveRepositoryProvider);
    String label(int count, {required bool starring}) => starring
        ? 'Starring ${Formatters.count(count, 'item')}'
        : 'Removing ${Formatters.count(count, 'item')} from Starred';
    final outcome = await runBulk<DriveFile>(
      context,
      ref.read(bulkEditsProvider.notifier),
      label: label(files.length, starring: starred),
      icon: Icons.star_outline_rounded,
      items: files,
      apply: (file) => repository.setStarred([file], starred: starred),
      success: starred ? 'Added to Starred' : 'Removed from Starred',
      // Each file goes back to how it was, so one that was starred before
      // stays starred.
      undo: (
        label: (done) => label(done, starring: !starred),
        apply: (file) async =>
            repository.setStarred(await _current(repository, [file]), starred: file.starred),
      ),
    );
    return outcome?.complete ?? false;
  }

  /// Moves [files] and [folders] to the trash, with an Undo on the
  /// snackbar. Over 100 items it asks first, since undoing that many is one
  /// edit per item and takes a while. Returns whether it worked.
  ///
  /// When the files include photos or videos this phone still has, and
  /// there are no folders, a sheet asks first and offers to delete the
  /// phone's copies too. Those go only once the Undo has closed unused,
  /// through [PendingDeletes], so Undo never has a phone delete to take
  /// back.
  static Future<bool> delete(
    BuildContext context,
    WidgetRef ref, {
    List<DriveFile> files = const [],
    List<DriveFolder> folders = const [],
  }) async {
    final repository = ref.read(driveRepositoryProvider);
    final edits = ref.read(bulkEditsProvider.notifier);
    final pending = ref.read(pendingDeletesProvider.notifier);
    final container = ProviderScope.containerOf(context, listen: false);
    final what = _describe(files, folders);
    final total = files.length + folders.length;
    var onPhone = const <String, List<String>>{};
    var alsoPhone = false;
    if (folders.isEmpty && files.isNotEmpty) {
      onPhone = await _phoneCopies(ref, files);
      if (!context.mounted) return false;
    }
    if (onPhone.isNotEmpty) {
      final prefs = ref.read(preferencesProvider);
      final choice = await showTrashSheet(
        context,
        what: what,
        count: files.length,
        onPhone: onPhone.length,
        initialAlsoPhone: prefs.deletePhoneCopyToo,
      );
      if (choice == null || !context.mounted) return false;
      alsoPhone = choice;
      unawaited(prefs.setDeletePhoneCopyToo(choice));
    } else if (total > 100) {
      // Only when the sheet didn't show, since it asks the same question.
      final confirmed = await showConfirmDialog(
        context,
        title: 'Move $what to Trash?',
        message: 'Undo takes a while for this many, one edit per file.',
        confirmLabel: 'Move to Trash',
      );
      if (!confirmed || !context.mounted) return false;
    }
    String? phoneDelete;
    final outcome = await runBulk<_Step>(
      context,
      edits,
      label: 'Moving ${Formatters.count(total, 'item')} to Trash',
      icon: Icons.delete_outline_rounded,
      items: <_Step>[
        for (final folder in folders)
          (
            apply: () => repository.trash(folders: [folder]),
            undo: () async =>
                repository.restore(folders: await _currentFolders(repository, [folder])),
          ),
        for (final file in files)
          (
            apply: () => repository.trash(files: [file]),
            undo: () async => repository.restore(files: await _current(repository, [file])),
          ),
      ],
      apply: (step) => step.apply(),
      success: 'Moved $what to Trash',
      undo: (
        label: (done) => 'Restoring ${Formatters.count(done, 'item')}',
        apply: (step) => step.undo(),
      ),
      onUndoClosed: (reason) {
        final token = phoneDelete;
        if (token == null) return;
        if (shouldDeletePhoneCopy(reason, alsoPhone: alsoPhone)) {
          unawaited(pending.commit(token));
        } else {
          pending.undo(token);
        }
      },
    );
    final complete = outcome?.complete ?? false;
    // Only a trash that went through takes the phone's copies with it; a
    // failed or stopped one says so and leaves the phone alone.
    if (alsoPhone && complete) {
      final phoneWhat = onPhone.length == files.length
          ? what
          : Formatters.count(onPhone.length, 'item');
      phoneDelete = pending.schedulePhoneDelete(
        copies: onPhone,
        label: '$phoneWhat from this phone',
        failure: 'Couldn\'t delete $phoneWhat from this phone',
        run: (assetIds) async {
          // Checked again, since this can run long after the sheet asked
          // and one the gallery let go meanwhile would fail them all.
          final still = await stillOnPhone(assetIds);
          final going = [for (final id in assetIds) if (still.contains(id)) id];
          if (going.isNotEmpty) await deleteFromPhone(going);
          container.invalidate(freeableProvider);
        },
      );
    }
    return complete;
  }

  /// Drive file id to phone media ids for those of [files] this phone still
  /// has: backed up from it, and not deleted from it since. A file counts
  /// when any of the phone's photos it stands for is still there, and
  /// brings every one that is. When the phone's library can't be read (its
  /// access taken back, say), none count: the trash goes ahead without
  /// offering to delete copies it can't check.
  static Future<Map<String, List<String>>> _phoneCopies(
    WidgetRef ref,
    List<DriveFile> files,
  ) async {
    final recorded = await ref
        .read(appDatabaseProvider)
        .localAssetsOf(files.map((file) => file.id));
    if (recorded.isEmpty) return const {};
    final Set<String> present;
    try {
      present = await stillOnPhone([for (final ids in recorded.values) ...ids]);
    } catch (e) {
      debugPrint('[Trash] Could not look for copies on this phone: $e');
      return const {};
    }
    final copies = <String, List<String>>{};
    for (final MapEntry(key: fileId, value: assetIds) in recorded.entries) {
      final here = [for (final id in assetIds) if (present.contains(id)) id];
      if (here.isNotEmpty) copies[fileId] = here;
    }
    return copies;
  }

  /// Takes [files] and [folders] out of the Trash, with Undo. A file whose
  /// copy on this phone was waiting to go with it keeps that copy. That is
  /// settled first, because the snack this shows takes the place of the one
  /// offering Undo on the trash, and that one closing unused lets the phone
  /// delete go.
  static Future<void> restore(
    BuildContext context,
    WidgetRef ref, {
    List<DriveFile> files = const [],
    List<DriveFolder> folders = const [],
  }) {
    final repository = ref.read(driveRepositoryProvider);
    ref.read(pendingDeletesProvider.notifier).keepPhoneCopies(files.map((file) => file.id));
    return _guard(
      context,
      () => repository.restore(files: files, folders: folders),
      success: 'Restored ${_describe(files, folders)}',
      undo: () async => repository.trash(
        files: await _current(repository, files),
        folders: await _currentFolders(repository, folders),
      ),
    );
  }

  /// Deletes [files] and [folders] for good, and everything inside the
  /// folders. They leave the list at once, and the messages go once Undo
  /// has had its time. Returns true: there is nothing left to confirm.
  static Future<bool> deleteForever(
    BuildContext context,
    WidgetRef ref, {
    List<DriveFile> files = const [],
    List<DriveFolder> folders = const [],
  }) async {
    final repository = ref.read(driveRepositoryProvider);
    final what = _describe(files, folders);
    deleteLater(
      context,
      ref,
      fileIds: {for (final file in files) file.id},
      folderIds: {for (final folder in folders) folder.id},
      label: what,
      message: 'Deleting $what for good',
      run: () => repository.delete(files: files, folders: folders),
    );
    return true;
  }

  /// Deletes what the trash holds now, [contents], for good, the same way
  /// as [deleteForever]. Whatever reaches the trash during the wait stays.
  static Future<void> emptyTrash(
    BuildContext context,
    WidgetRef ref,
    TrashContents contents,
  ) async {
    final repository = ref.read(driveRepositoryProvider);
    final count = Formatters.count(contents.count, 'item');
    deleteLater(
      context,
      ref,
      fileIds: {for (final file in contents.files) file.id},
      folderIds: {for (final folder in contents.folders) folder.id},
      label: count,
      message: 'Emptying the trash · $count',
      run: () => repository.delete(files: contents.files, folders: contents.folders),
    );
  }

  /// Hides [fileIds], [folderIds] and [albumIds] at once and runs [run],
  /// which deletes them for good, only once the Undo on [message] has had
  /// [PendingDeletes.wait]. Undo keeps them. [label] names what goes, for
  /// the sentence the shell shows if the delete fails later.
  static void deleteLater(
    BuildContext context,
    WidgetRef ref, {
    Set<String> fileIds = const {},
    Set<String> folderIds = const {},
    Set<String> albumIds = const {},
    required String label,
    required String message,
    required Future<void> Function() run,
  }) {
    final pending = ref.read(pendingDeletesProvider.notifier);
    final token = pending.schedule(
      fileIds: fileIds,
      folderIds: folderIds,
      albumIds: albumIds,
      label: label,
      run: run,
    );
    final lasting = _lasting(context);
    showUndoSnack(
      context,
      message,
      // The snack's time and the delete's both start once the snack is
      // fully in. The snack starts to leave early enough to be gone, with
      // time to spare, when the delete runs, so Undo is never offered
      // after it.
      duration: PendingDeletes.wait - snackTransition * 2,
      onVisible: () => pending.shown(token),
      onUndo: () {
        final kept = pending.undo(token);
        if (!lasting.mounted) return;
        showSnack(
          lasting,
          kept ? 'Kept' : 'Too late to undo. The delete had already started.',
        );
      },
    );
  }

  /// `"report.pdf"`, or `3 items`.
  static String _describe(List<DriveFile> files, List<DriveFolder> folders) {
    final count = files.length + folders.length;
    if (count != 1) return Formatters.count(count, 'item');
    return '"${files.isNotEmpty ? files.first.name : folders.first.name}"';
  }

  // ---------------------------------------------------------------------------
  // Sheets
  // ---------------------------------------------------------------------------

  static Future<void> showFileSheet(
    BuildContext context,
    WidgetRef ref,
    DriveFile file,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        void run(Future<void> Function() action) {
          Navigator.pop(sheetContext);
          action();
        }

        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SheetHeader(
                  leading: FileThumbnail(file: file, size: 52),
                  title: file.name,
                  subtitle:
                      '${Formatters.bytes(file.size)} · ${Formatters.date(file.modifiedAt)}',
                ),
                const Divider(height: 16),
                _SheetAction(
                  icon: Icons.open_in_new_rounded,
                  label: 'Open',
                  onTap: () => run(() => open(context, ref, file)),
                ),
                _SheetAction(
                  icon: Icons.download_rounded,
                  label: 'Download to this phone',
                  onTap: () => run(() => saveToDevice(context, ref, files: [file])),
                ),
                _SheetAction(
                  icon: Icons.send_outlined,
                  label: 'Send in Telegram',
                  onTap: () => run(() => sendToChats(context, ref, [file])),
                ),
                _OfflineAction(
                  itemId: file.id,
                  onTap: (pinned) => run(() => setOffline(context, ref, file: file, keep: !pinned)),
                ),
                _SheetAction(
                  icon: Icons.ios_share_rounded,
                  label: 'Share',
                  onTap: () => run(() => share(context, ref, file)),
                ),
                _SheetAction(
                  icon: file.starred ? Icons.star_rounded : Icons.star_outline_rounded,
                  label: file.starred ? 'Remove from Starred' : 'Add to Starred',
                  onTap: () => run(
                    () => setStarred(context, ref, [file], starred: !file.starred),
                  ),
                ),
                _SheetAction(
                  icon: Icons.drive_file_rename_outline_rounded,
                  label: 'Rename',
                  onTap: () => run(() => renameFile(context, ref, file)),
                ),
                _SheetAction(
                  icon: Icons.drive_file_move_outline,
                  label: 'Move',
                  onTap: () => run(() => move(context, ref, files: [file])),
                ),
                _SheetAction(
                  icon: Icons.info_outline_rounded,
                  label: 'Details',
                  onTap: () => run(() => showDetails(context, ref, file)),
                ),
                _SheetAction(
                  icon: Icons.telegram,
                  label: 'Show in Telegram',
                  onTap: () => run(() => showInTelegram(context, ref, file)),
                ),
                _SheetAction(
                  icon: Icons.delete_outline_rounded,
                  label: 'Move to Trash',
                  destructive: true,
                  onTap: () => run(() => delete(context, ref, files: [file])),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static Future<void> showFolderSheet(
    BuildContext context,
    WidgetRef ref,
    DriveFolder folder,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      builder: (sheetContext) {
        void run(Future<void> Function() action) {
          Navigator.pop(sheetContext);
          action();
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SheetHeader(
                leading: const FolderIconTile(size: 52),
                title: folder.name,
                subtitle: 'Folder · ${Formatters.date(folder.modifiedAt)}',
              ),
              const Divider(height: 16),
              _SheetAction(
                icon: Icons.download_rounded,
                label: 'Download to this phone',
                onTap: () => run(() => saveToDevice(context, ref, folders: [folder])),
              ),
              _OfflineAction(
                itemId: folder.id,
                onTap: (pinned) => run(
                  () => setOffline(context, ref, folder: folder, keep: !pinned),
                ),
              ),
              _SheetAction(
                icon: Icons.drive_file_rename_outline_rounded,
                label: 'Rename',
                onTap: () => run(() => renameFolder(context, ref, folder)),
              ),
              _SheetAction(
                icon: Icons.drive_file_move_outline,
                label: 'Move',
                onTap: () => run(() => move(context, ref, folders: [folder])),
              ),
              _SheetAction(
                icon: Icons.delete_outline_rounded,
                label: 'Move to Trash',
                destructive: true,
                onTap: () => run(() => delete(context, ref, folders: [folder])),
              ),
            ],
          ),
        );
      },
    );
  }

  static Future<void> showDetails(
    BuildContext context,
    WidgetRef ref,
    DriveFile file,
  ) async {
    final path = await ref.read(driveRepositoryProvider).pathTo(file.folderId);
    if (!context.mounted) return;
    final location = ['Files', ...path.map((f) => f.name)].join(' / ');
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                file.name,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              _DetailRow('Type', file.extension.isEmpty ? file.mimeType : '${file.kind.label.replaceAll(RegExp(r's$'), '')} · ${file.extension}'),
              _DetailRow('Size', '${Formatters.bytes(file.size)} (${Formatters.count(file.size, 'byte')})'),
              _DetailRow('Location', location),
              _DetailRow('Added', Formatters.fullDate(file.createdAt)),
              _DetailRow('Modified', Formatters.fullDate(file.modifiedAt)),
              if (file.isSplit)
                _DetailRow(
                  'Stored as',
                  '${file.partCount} parts. Telegram caps one message at 2 GB.',
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Opens the file's message in the Telegram app.
  static Future<void> showInTelegram(
    BuildContext context,
    WidgetRef ref,
    DriveFile file,
  ) async {
    final session = ref.read(driveSessionProvider);
    final parts = await ref.read(driveRepositoryProvider).partsOf(file.id);
    if (session == null || parts.isEmpty) return;
    // Private channel links use the bare channel id and the server message id.
    final channel = -session.chatId - 1000000000000;
    final post = parts.first.messageId >> 20;
    final opened = await launchUrl(
      Uri.parse('https://t.me/c/$channel/$post'),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && context.mounted) showSnack(context, 'Couldn\'t open Telegram.');
  }

  /// Runs [action], turning failures into a snackbar. With [undo], the
  /// [success] sentence offers Undo, which runs [undo] the same way and says
  /// how that went. Returns success.
  static Future<bool> guarded(
    BuildContext context,
    Future<void> Function() action, {
    String? success,
    Future<void> Function()? undo,
  }) => _guard(context, action, success: success, undo: undo);

  static Future<bool> _guard(
    BuildContext context,
    Future<void> Function() action, {
    String? success,
    Future<void> Function()? undo,
    String failurePrefix = '',
  }) async {
    try {
      await action();
      if (success != null && context.mounted) {
        if (undo == null) {
          showSnack(context, success);
        } else {
          final lasting = _lasting(context);
          showUndoSnack(
            context,
            success,
            onUndo: () => _guard(lasting, undo, success: 'Undone', failurePrefix: _undoFailed),
          );
        }
      }
      return true;
    } catch (e) {
      if (context.mounted) showSnack(context, '$failurePrefix${failureOf(e)}');
    }
    return false;
  }

  /// What a failed Undo leads with, before the reason.
  static const _undoFailed = 'Couldn\'t undo: ';

  /// Where an Undo says how it went. Undo can be tapped after the screen
  /// that offered it has gone (a sheet, the viewer, an album's Add photos),
  /// so it speaks through the app's root navigator, which lasts as long as
  /// the app.
  static BuildContext _lasting(BuildContext context) =>
      Navigator.maybeOf(context, rootNavigator: true)?.context ?? context;

  /// [files] as the index holds them now; those gone since are left out.
  /// An undo starts from these because moveFiles, setStarred and renameFile
  /// pass over a file whose folder, star or name already matches the one
  /// asked for, and the file in hand still shows how it was before.
  static Future<List<DriveFile>> _current(
    DriveRepository repository,
    Iterable<DriveFile> files,
  ) async => [for (final file in files) ?await repository.fileById(file.id)];

  /// [folders] as the index holds them now, for the same reason as
  /// [_current]: moveFolder passes over a folder already in its parent, and
  /// a folder is rewritten from the name and parent in hand.
  static Future<List<DriveFolder>> _currentFolders(
    DriveRepository repository,
    Iterable<DriveFolder> folders,
  ) async => [for (final folder in folders) ?await repository.folderById(folder.id)];

  /// Why [error] stopped an action, in the words every snack here uses.
  static String failureOf(Object error) => switch (error) {
    DriveException(:final message) => message,
    TelegramException e => e.friendlyMessage,
    _ => 'Something went wrong: $error',
  };

  /// Applies [apply] to each of [items] as one bulk change, which the status
  /// line above the bar follows when it is big or Telegram asks for a wait,
  /// and says how it ended: [success], where it stopped, or why it failed.
  /// With [undo], that sentence offers Undo for the items that did change,
  /// the first `done` of [items], however it ended: Undo runs undo.apply on
  /// each of them as a bulk change of its own, called undo.label, and says
  /// 'Undone' or why it couldn't. [onUndoClosed] hears once how that offer
  /// ended: [SnackBarClosedReason.action] as soon as Undo is tapped, or else
  /// why the snack closed without it. With no offer on screen it isn't
  /// called. Returns how it ended, or null when it couldn't start.
  ///
  /// [edits] is read up front because an Undo can run this after the screen
  /// that started it is gone.
  static Future<BulkOutcome?> runBulk<T>(
    BuildContext context,
    BulkEdits edits, {
    required String label,
    required IconData icon,
    required List<T> items,
    required Future<void> Function(T item) apply,
    String? success,
    ({String Function(int done) label, Future<void> Function(T item) apply})? undo,
    ValueChanged<SnackBarClosedReason>? onUndoClosed,
    String failurePrefix = '',
  }) async {
    BulkOutcome? outcome;
    await _guard(context, () async {
      outcome = await edits.run(label: label, icon: icon, items: items, apply: apply);
    }, failurePrefix: failurePrefix);
    final ended = outcome;
    if (ended == null) return null;
    final error = ended.error;
    final wait = error == null ? null : telegramWaitOf(error);
    final done = '${Formatters.number(ended.done)} of ${Formatters.number(ended.total)}';
    final String? message;
    if (ended.stopped) {
      message = 'Stopped after $done. The rest are unchanged.';
    } else if (wait != null) {
      message =
          'Telegram asked us to wait ${Formatters.inWords(wait)}. '
          '$done are done; try the rest later.';
    } else if (error != null) {
      message = '$failurePrefix${failureOf(error)}';
    } else {
      message = success;
    }
    if (message == null || !context.mounted) return ended;
    if (undo == null || ended.done == 0) {
      showSnack(context, message);
    } else {
      final lasting = _lasting(context);
      // Told once. Undo is told the moment it is tapped: the snack it then
      // shows would otherwise close this one with a reason of its own.
      var told = false;
      void tell(SnackBarClosedReason reason) {
        if (told) return;
        told = true;
        onUndoClosed?.call(reason);
      }

      final snack = showUndoSnack(
        context,
        message,
        onUndo: () {
          tell(SnackBarClosedReason.action);
          runBulk(
            lasting,
            edits,
            label: undo.label(ended.done),
            icon: Icons.undo_rounded,
            items: items.take(ended.done).toList(),
            apply: undo.apply,
            success: 'Undone',
            failurePrefix: _undoFailed,
          );
        },
      );
      if (snack != null) unawaited(snack.closed.then(tell));
    }
    return ended;
  }
}

class _DownloadDialog extends ConsumerStatefulWidget {
  const _DownloadDialog({required this.file, required this.download});

  final DriveFile file;
  final Future<String> download;

  @override
  ConsumerState<_DownloadDialog> createState() => _DownloadDialogState();
}

class _DownloadDialogState extends ConsumerState<_DownloadDialog> {
  @override
  void initState() {
    super.initState();
    widget.download.then(
      (path) {
        if (mounted) Navigator.of(context).pop(path);
      },
      onError: (Object error) {
        if (!mounted) return;
        Navigator.of(context).pop();
        if (error is SendCancelled) {
          showSnack(context, 'Cancelled ${widget.file.name}');
        } else if (error is! DriveException || error.message != 'Signed out.') {
          showSnack(context, 'Download failed: ${error is DriveException ? error.message : error}');
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = ref.watch(
      transferQueueProvider.select(
        (state) => state.items
            .where(
              (t) =>
                  t.kind == TransferKind.download &&
                  t.row.fileId == widget.file.id &&
                  t.status.isActive,
            )
            .firstOrNull,
      ),
    );
    final progress = item?.progress ?? 0;
    final waitingUntil = switch (item?.wait) {
      WaitingForTelegram(:final until) => until,
      null => null,
    };
    final detailStyle = theme.textTheme.bodySmall?.copyWith(fontFeatures: tabularFigures);

    return AlertDialog(
      title: Text(
        'Downloading',
        style: theme.textTheme.titleMedium,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FileThumbnail(file: widget.file, size: 40),
              const SizedBox(width: Space.m),
              Expanded(
                child: Text(
                  widget.file.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.l),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: waitingUntil != null || progress > 0 ? progress : null,
              minHeight: 4,
              color: waitingUntil == null ? null : context.colors.text3,
            ),
          ),
          const SizedBox(height: Space.s),
          if (waitingUntil != null)
            Countdown(
              until: waitingUntil,
              builder: (context, left) => Text(
                'Waiting for Telegram · ${Formatters.countdown(left)}',
                style: detailStyle,
              ),
            )
          else
            Text(
              item == null
                  ? 'Starting'
                  : '${Formatters.bytes(item.row.doneBytes)} of ${Formatters.bytes(item.row.totalBytes)}'
                        '${item.bytesPerSecond > 0 ? ' · ${Formatters.speed(item.bytesPerSecond)}' : ''}',
              style: detailStyle,
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            // Like × in Transfers: a cancelled download leaves no row behind.
            if (item != null) {
              ref.read(transferQueueProvider.notifier).remove(item.id);
            }
          },
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
            showSnack(context, 'Still downloading. You\'ll find it in Transfers.');
          },
          child: const Text('Hide'),
        ),
      ],
    );
  }
}

/// What a download to this phone will do, and where things will land,
/// before it starts. Pops with whether photos and videos go to the gallery.
class _SaveSheet extends StatefulWidget {
  const _SaveSheet({
    required this.items,
    required this.freeBytes,
    required this.preferGallery,
  });

  final List<SaveItem> items;
  final int? freeBytes;
  final bool preferGallery;

  @override
  State<_SaveSheet> createState() => _SaveSheetState();
}

class _SaveSheetState extends State<_SaveSheet> {
  late bool _gallery = widget.preferGallery;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final items = widget.items;
    final bytes = items.fold<int>(0, (sum, i) => sum + i.file.size);
    final largest = items.fold<int>(0, (max, i) => i.file.size > max ? i.file.size : max);
    final media = items.where((i) => FileActions.fitsGallery(i.file)).length;
    final free = widget.freeBytes;
    // Android holds a second copy of the file being saved for a moment.
    final needed = bytes + (Platform.isAndroid ? largest : 0);
    final tooBig = free != null && needed > free;
    final single = items.length == 1;
    final library = Platform.isIOS ? 'photo library' : 'gallery';

    final String where;
    if (_gallery && media == items.length) {
      where = single ? 'It goes to your $library.' : 'They go to your $library.';
    } else if (_gallery && media > 0) {
      where = 'Photos and videos go to your $library; everything else to '
          '${DeviceStorage.location}.';
    } else {
      where = single
          ? 'It goes to ${DeviceStorage.location}.'
          : 'They go to ${DeviceStorage.location}, in the same folders as '
                'in your drive.';
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              single ? 'Download to this phone' : 'Download ${Formatters.count(items.length, 'file')}',
              style: context.text.titleMedium,
            ),
            const SizedBox(height: 2),
            Text(
              single
                  ? '${items.first.file.name} · ${Formatters.bytes(bytes)}'
                  : '${Formatters.bytes(bytes)} in total',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.text.bodyMedium?.copyWith(fontFeatures: tabularFigures),
            ),
            const SizedBox(height: Space.l),
            if (media > 0)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Photos and videos to $library'),
                subtitle: media == items.length
                    ? null
                    : Text(
                        '${Formatters.number(media)} of these',
                        style: context.text.bodySmall?.copyWith(fontFeatures: tabularFigures),
                      ),
                value: _gallery,
                onChanged: (value) => setState(() => _gallery = value),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.s),
              child: Text(where, style: context.text.bodyMedium),
            ),
            if (free != null)
              Text(
                tooBig
                    ? 'Not enough space: this needs ${Formatters.bytes(needed)} '
                          'and the phone has ${Formatters.bytes(free)} free.'
                    : '${Formatters.bytes(free)} free on this phone',
                style: context.text.bodySmall?.copyWith(
                  color: tooBig ? colors.danger : null,
                  fontFeatures: tabularFigures,
                ),
              ),
            const SizedBox(height: Space.xl),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: Space.m),
                Expanded(
                  child: FilledButton(
                    onPressed: tooBig ? null : () => Navigator.pop(context, _gallery),
                    child: const Text('Download'),
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

class _CreateOption extends StatelessWidget {
  const _CreateOption({
    required this.icon,
    required this.label,
    required this.onTap,
    this.detail,
  });

  final IconData icon;
  final String label;
  final String? detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      subtitle: detail == null ? null : Text(detail!),
      onTap: onTap,
    );
  }
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.leading, required this.title, required this.subtitle});

  final Widget leading;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.m),
      child: Row(
        children: [
          leading,
          const SizedBox(width: Space.l),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: context.text.bodySmall?.copyWith(fontFeatures: tabularFigures),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetAction extends StatelessWidget {
  const _SheetAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ListTile(
      leading: Icon(icon, color: destructive ? colors.danger : colors.text2),
      title: Text(
        label,
        style: context.text.bodyLarge?.copyWith(
          color: destructive ? colors.danger : colors.text,
        ),
      ),
      minVerticalPadding: 14,
      onTap: onTap,
    );
  }
}

/// "Make available offline", or the way back, depending on the pin.
class _OfflineAction extends ConsumerWidget {
  const _OfflineAction({required this.itemId, required this.onTap});

  final String itemId;
  final void Function(bool pinned) onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pinned = ref.watch(
      offlinePinsProvider.select((pins) => pins.value?.contains(itemId) ?? false),
    );
    return _SheetAction(
      icon: pinned ? Icons.offline_pin_rounded : Icons.offline_pin_outlined,
      label: pinned ? 'Stop keeping offline' : 'Make available offline',
      onTap: () => onTap(pinned),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.s),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 96, child: Text(label, style: context.text.bodyMedium)),
          Expanded(
            child: Text(
              value,
              style: context.text.bodyMedium?.copyWith(
                color: context.colors.text,
                fontFeatures: tabularFigures,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
