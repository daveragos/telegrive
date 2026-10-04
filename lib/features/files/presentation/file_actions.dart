import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme/file_style.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/files/file_kind.dart';
import '../../../core/format/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/file_visuals.dart';
import '../../../infrastructure/database/app_database.dart'
    show SaveTarget, TransferKind, TransferStatus, appDatabaseProvider;
import '../../../infrastructure/network/network_status.dart';
import '../../../infrastructure/storage/device_storage.dart';
import '../../../infrastructure/storage/preferences.dart';
import '../../../infrastructure/telegram/telegram_client.dart';
import '../../../infrastructure/telegram/telegram_exception.dart';
import '../../backup/data/backup_controller.dart';
import '../../backup/data/free_up_space.dart';
import '../../capture/data/device_capture.dart';
import '../../offline/data/offline_sync.dart';
import '../../offline/presentation/keep_offline_sheet.dart';
import '../../send/data/send_bundle.dart';
import '../../send/data/telegram_chats.dart';
import '../../share/data/recent_destinations.dart';
import '../../send/presentation/chat_picker.dart';
import '../../drive/data/channel_messenger.dart';
import '../../drive/data/drive_repository.dart';
import '../../drive/data/drive_session.dart';
import '../../drive/domain/drive_models.dart';
import '../../transfers/data/transfer_policy.dart';
import '../../transfers/data/transfer_queue.dart';
import '../../transfers/domain/transfer_error.dart';
import '../../transfers/domain/transfer_wait.dart';
import '../../transfers/presentation/mobile_data_prompt.dart';
import '../../trash/data/pending_deletes.dart';
import '../data/bulk_edits.dart';
import 'file_tiles.dart';
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
  /// remembers it either way, without holding the file up. [from] names
  /// where the file was opened, as `folder:<id>` with an empty id for the
  /// root; an audio file opened that way plays on through the folder.
  static Future<void> open(
    BuildContext context,
    WidgetRef ref,
    DriveFile file, {
    String? from,
  }) async {
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
        await context.push(
          file.kind == FileKind.audio && from != null
              ? Uri(
                  path: '/play/${file.id}',
                  queryParameters: {'from': from},
                ).toString()
              : '/play/${file.id}',
        );
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
  /// Something big on mobile data can wait for Wi-Fi instead, and big files
  /// started on Wi-Fi wait if the phone moves onto mobile data, as the
  /// setting says. Returns whether anything was queued.
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
          .collectForSaving(
            files: files,
            folders: folders,
            everything: everything,
          ),
      storage.freeBytes(),
    ).wait;
    if (!context.mounted) return false;
    if (items.isEmpty) {
      showSnack(context, 'There are no files in here yet.');
      return false;
    }

    final choice = await showModalBottomSheet<_SaveChoice>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (_) => _SaveSheet(
        items: items,
        freeBytes: free,
        preferGallery: preferGallery ?? items.every((i) => fitsGallery(i.file)),
        network: ref.read(networkStatusProvider),
      ),
    );
    if (choice == null || !context.mounted) return false;

    final useGallery = choice.gallery && items.any((i) => fitsGallery(i.file));
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

    final bigWait = ref.read(preferencesProvider).bigTransfersWifiOnly;
    bool wifiOnly(DriveFile file) =>
        choice.wifiOnly ??
        TransferPolicy.wifiOnlyFor(file.size, bigWaitForWifi: bigWait);
    final requests = [
      for (final item in items)
        if (useGallery && fitsGallery(item.file))
          SaveRequest(
            item.file,
            target: SaveTarget.gallery,
            folders: [?_backupAlbum(item.path)],
            wifiOnly: wifiOnly(item.file),
          )
        else
          SaveRequest(
            item.file,
            target: SaveTarget.files,
            folders: item.folders,
            wifiOnly: wifiOnly(item.file),
          ),
    ];
    final queued = await ref
        .read(transferQueueProvider.notifier)
        .enqueueSaves(requests);
    if (!context.mounted) return true;
    // View can be tapped after the screen that asked is gone.
    final router = GoRouter.of(context);
    showSnack(
      context,
      queued == 0
          ? 'Already downloading to this phone'
          : choice.wifiOnly == true
          ? 'Waiting for Wi-Fi to download ${Formatters.count(queued, 'file')}'
          : 'Downloading ${Formatters.count(queued, 'file')} to this phone',
      actionLabel: 'View',
      onAction: () => router.push('/transfers'),
    );
    return true;
  }

  /// Photos and videos in formats every phone's gallery takes.
  static bool fitsGallery(DriveFile file) => file.fitsGallery;

  /// `Photo backup/Camera/…` → `Camera`: the phone folder a backed-up photo
  /// came from, so it goes back there.
  static String? _backupAlbum(List<String> path) =>
      path.length >= 2 && path.first == BackupController.rootFolder
      ? path[1]
      : null;

  // ---------------------------------------------------------------------------
  // Available offline
  // ---------------------------------------------------------------------------

  /// Keeps [file] or [folder] (with everything in it, now and later) on
  /// this phone for use without a connection, or stops keeping it. A folder
  /// with files in it first says what keeping it costs, in a sheet that
  /// also holds Only over Wi-Fi. A big file on mobile data asks whether to
  /// wait for Wi-Fi, unless Only over Wi-Fi already says it does. View on
  /// the snack opens the Offline screen.
  static Future<bool> setOffline(
    BuildContext context,
    WidgetRef ref, {
    DriveFile? file,
    DriveFolder? folder,
    required bool keep,
  }) async {
    final offline = ref.read(offlineSyncProvider.notifier);
    final name = file?.name ?? folder!.name;
    if (!keep) {
      return _guard(
        context,
        () => offline.unpin(file: file, folder: folder),
        success: '"$name" is no longer kept offline',
      );
    }
    bool? wifiOnly;
    if (folder != null) {
      var items = const <SaveItem>[];
      int? free;
      final counted = await _guard(context, () async {
        (items, free) = await (
          ref.read(driveRepositoryProvider).collectForSaving(folders: [folder]),
          ref.read(deviceStorageProvider).freeBytes(),
        ).wait;
      });
      if (!counted || !context.mounted) return false;
      if (items.isNotEmpty) {
        final estimate = KeepOfflineEstimate.of(
          items,
          freeBytes: free,
          android: Platform.isAndroid,
        );
        final kept = await showModalBottomSheet<bool>(
          context: context,
          useRootNavigator: true,
          isScrollControlled: true,
          builder: (_) => KeepOfflineSheet(
            folderName: name,
            count: estimate.count,
            bytes: estimate.bytes,
            largest: estimate.largest,
            freeBytes: free,
          ),
        );
        if (kept != true || !context.mounted) return false;
        // The sheet said what this costs on mobile data, so Keep there
        // brings the copies now, unless Only over Wi-Fi holds them.
        if (ref.read(networkStatusProvider).metered) wifiOnly = false;
      }
    } else if (!ref.read(offlineSyncProvider)) {
      final network = ref.read(networkStatusProvider);
      if (TransferPolicy.shouldAsk(network: network, bytes: file!.size)) {
        final choice = await askAboutMobileData(
          context,
          bytes: file.size,
          doing: 'Keeping "$name" offline',
          files: 1,
          nowLabel: 'Keep offline now',
        );
        if (choice == null || !context.mounted) return false;
        wifiOnly = wifiOnlyFrom(choice);
      } else if (network.metered) {
        // Too small to ask about, so it comes now, as anything this size
        // does on mobile data.
        wifiOnly = false;
      }
    }
    final waits = !OfflineSync.allowed(
      wifiOnly: ref.read(offlineSyncProvider) || wifiOnly == true,
      network: ref.read(networkStatusProvider),
    );
    // View can be tapped after the screen that asked is gone.
    final router = GoRouter.of(context);
    final pinned = await _guard(
      context,
      () => offline.pin(file: file, folder: folder, wifiOnly: wifiOnly),
    );
    if (pinned && context.mounted) {
      showSnack(
        context,
        waits
            ? '"$name" will download over Wi-Fi'
            : '"$name" will be available offline',
        actionLabel: 'View',
        onAction: () => router.push('/offline'),
      );
    }
    return pinned;
  }

  // ---------------------------------------------------------------------------
  // Sending in Telegram
  // ---------------------------------------------------------------------------

  /// Sends [files] and everything inside [folders] to chats the person
  /// picks, straight from the drive, with no upload. A folder's subfolders
  /// arrive under header lines naming them. Files go in name order, or with
  /// [byMoment] in the order they were taken. A single folder, or an album
  /// named [bundleName], offers its name as the message sent first. Files
  /// picked one by one join Home's Recent; the contents of a folder or an
  /// album don't, so one send doesn't push everything else out. Returns
  /// whether they went.
  static Future<bool> sendToChats(
    BuildContext context,
    WidgetRef ref,
    List<DriveFile> files, {
    List<DriveFolder> folders = const [],
    String? bundleName,
    bool byMoment = false,
  }) async {
    if (!_connected(context, ref)) return false;
    final repository = ref.read(driveRepositoryProvider);
    final telegram = ref.read(telegramChatsProvider);
    final preferences = ref.read(preferencesProvider);
    final soleFolder = folders.length == 1 && files.isEmpty;
    final bundle = folders.isEmpty
        ? SendBundle.fromFiles(files, byMoment: byMoment)
        : SendBundle.fromItems(
            await repository.collectForSaving(files: files, folders: folders),
            stripTop: soleFolder,
            byMoment: byMoment,
          );
    if (!context.mounted) return false;
    if (bundle.fileCount == 0) {
      showSnack(context, 'There are no files in here yet.');
      return false;
    }

    final name = bundleName ?? (soleFolder ? folders.single.name : null);
    final count = Formatters.count(bundle.fileCount, 'file');
    final size = Formatters.bytes(bundle.bytes);
    final pick = await showChatPicker(
      context,
      title: name != null
          ? 'Send "$name"'
          : bundle.fileCount == 1
          ? 'Send "${bundle.firstFile!.name}"'
          : 'Send $count',
      note: [
        '${bundle.fileCount == 1 ? size : '$count · $size'}. '
            'Nothing is uploaded again, so this uses almost no data.',
        if (bundle.anySplit)
          'Files over 2 GB are kept in parts, and arrive as numbered parts.',
      ].join(' '),
      messageInitial: name,
    );
    if (pick == null || pick.chats.isEmpty || !context.mounted) return false;

    final ids = [for (final chat in pick.chats) chat.id];
    final to = pick.chats.length == 1
        ? pick.chats.single.title
        : Formatters.count(pick.chats.length, 'chat');
    if (bundle.fileCount > 100) showSnack(context, 'Sending $count to $to…');
    final sent = await _guard(context, () async {
      await telegram.sendBundle(bundle, pick.chats, message: pick.message);
      await preferences.rememberSentTo(ids);
      if (bundleName == null) {
        await repository.recordOpens([for (final f in files) f.id]);
      }
    }, success: 'Sent $count to $to');
    if (sent && context.mounted) ref.invalidate(recentChatsProvider);
    return sent;
  }

  /// Has the person pick a Telegram chat, then opens its files to save
  /// into the drive, into [folderId] unless they pick another folder. With
  /// [photos], it opens on the chat's photos and videos, which go into a
  /// folder named after the chat inside 'From Telegram'.
  static Future<void> saveFromChat(
    BuildContext context,
    WidgetRef ref, {
    String? folderId,
    bool photos = false,
  }) async {
    if (!_connected(context, ref)) return;
    final chat = await showImportChatPicker(context);
    if (chat == null || !context.mounted) return;
    await context.push(
      Uri(
        path: '/import/${chat.id}',
        queryParameters: {
          'title': chat.title,
          'folder': ?folderId,
          if (photos) 'photos': '1',
        },
      ).toString(),
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
      if (context.mounted) {
        showSnack(context, 'Couldn\'t open the file picker.');
      }
      return;
    }
    if (picked.isEmpty) return;

    final temp = (await getTemporaryDirectory()).path;
    bool owned(PlatformFile file) => file.path?.startsWith(temp) ?? false;
    final sizes = [for (final file in picked) file.lengthSync()];
    // A size the picker couldn't read counts as nothing, as the queue
    // counts it until the file is staged.
    final bytes = sizes.fold<int>(0, (sum, size) => sum + (size ?? 0));
    final what = picked.length == 1
        ? picked.single.name
        : Formatters.count(picked.length, 'file');

    DataChoice? choice;
    if (TransferPolicy.shouldAsk(
      network: ref.read(networkStatusProvider),
      bytes: bytes,
    )) {
      if (context.mounted) {
        choice = await askAboutMobileData(
          context,
          bytes: bytes,
          doing: 'Uploading $what',
          files: picked.length,
          nowLabel: 'Upload now',
        );
      }
      if (choice == null) {
        // Called off: the copies the picker made go too.
        for (final file in picked.where(owned)) {
          try {
            await File(file.path!).delete();
          } catch (_) {}
        }
        return;
      }
    }

    final bigWait = ref.read(preferencesProvider).bigTransfersWifiOnly;
    final requests = [
      for (final (index, file) in picked.indexed)
        UploadRequest(
          name: file.name,
          path: file.path,
          size: sizes[index],
          openRead: file.path == null ? file.readAsByteStream : null,
          ownsSource: owned(file),
          wifiOnly:
              wifiOnlyFrom(choice) ??
              TransferPolicy.wifiOnlyFor(
                sizes[index] ?? 0,
                bigWaitForWifi: bigWait,
              ),
        ),
    ];
    if (!context.mounted) return;
    final resolved = await resolveUploadClashes(
      context,
      ref,
      requests,
      folderId: folderId,
    );
    if (!context.mounted) return;
    if (resolved.isEmpty) {
      showSnack(context, 'Nothing to upload');
      return;
    }
    final going = resolved.length == 1
        ? resolved.single.name
        : Formatters.count(resolved.length, 'file');
    final recent = ref.read(recentDestinationsProvider.notifier);
    await ref
        .read(transferQueueProvider.notifier)
        .enqueueUploads(resolved, folderId: folderId);
    unawaited(recent.note(folderId));
    if (!context.mounted) return;
    // Transfers goes over the screen that started the upload, so back
    // returns there; View can also be tapped after that screen is gone.
    final router = GoRouter.of(context);
    showSnack(
      context,
      choice == DataChoice.later
          ? 'Waiting for Wi-Fi to upload $going'
          : 'Uploading $going',
      actionLabel: 'View',
      onAction: () => router.push('/transfers'),
    );
  }

  /// Settles [requests], bound for [folderId] (the root when null), against
  /// the files already there. One whose name a file in the folder has, in
  /// any case, asks Replace, Keep both or Skip through [showClashSheet];
  /// with several clashes the answer can stand for all of them. Replace
  /// marks the request to trash that file once it lands, Keep both gives
  /// it the first free numbered name, and Skip drops it, deleting the copy
  /// the app made of it. A name an earlier request or an upload still on
  /// its way to the folder took is numbered without asking, so a batch
  /// never carries two files of one name. Returns what is left to upload,
  /// or nothing when the screen asking went away before the batch was
  /// settled, in which case every copy the app made is deleted.
  static Future<List<UploadRequest>> resolveUploadClashes(
    BuildContext context,
    WidgetRef ref,
    List<UploadRequest> requests, {
    String? folderId,
  }) async {
    // Everything [ref] gives is read before the first wait: the screen that
    // asked may be gone by the time the folder has been read.
    final repository = ref.read(driveRepositoryProvider);
    final onTheirWay = [
      for (final item in ref.read(transferQueueProvider).items)
        if (item.kind == TransferKind.upload &&
            item.status.isPending &&
            item.row.folderId == folderId)
          item.name.toLowerCase(),
    ];
    final clashes = await repository.nameClashes(
      requests.map((r) => r.name),
      folderId,
    );
    final taken = {...await repository.takenNamesIn(folderId), ...onTheirWay};
    String? folderName;
    ClashChoice? forAll;
    final resolved = <UploadRequest>[];
    for (final (index, request) in requests.indexed) {
      final lower = request.name.toLowerCase();
      final existing = clashes[lower];
      if (existing == null) {
        final name = repository.freeName(request.name, taken);
        taken.add(name.toLowerCase());
        resolved.add(await _renamed(request, name));
        continue;
      }
      ClashChoice? choice = forAll;
      if (choice == null) {
        // Nothing of the batch goes up once the screen asking is gone.
        Future<List<UploadRequest>> abandon() async {
          for (final request in [...resolved, ...requests.skip(index)]) {
            await _discardRequest(request);
          }
          return const [];
        }

        if (!context.mounted) return abandon();
        folderName ??= await _folderName(repository, folderId);
        if (!context.mounted) return abandon();
        final answer = await showClashSheet(
          context,
          name: request.name,
          existing: existing,
          newSize: request.size ?? 0,
          folderName: folderName,
          keepBothName: repository.freeName(request.name, taken),
          // This request and the later ones still up against a file in
          // the folder: a name Replace has already settled no longer is.
          clashesLeft: requests
              .skip(index)
              .where((r) => clashes.containsKey(r.name.toLowerCase()))
              .length,
        );
        choice = answer?.$1 ?? ClashChoice.skip;
        if (answer != null && answer.$2) forAll = choice;
      }
      switch (choice) {
        case ClashChoice.replace:
          resolved.add(request.copyWith(replacesFileId: existing.id));
          // A later request of the same name is numbered, not a second
          // replacement of a file that will be in the trash by then.
          clashes.remove(lower);
        case ClashChoice.keepBoth:
          final name = repository.freeName(request.name, taken);
          taken.add(name.toLowerCase());
          resolved.add(await _renamed(request, name));
        case ClashChoice.skip:
          await _discardRequest(request);
      }
    }
    return resolved;
  }

  /// Where uploads into [folderId] are said to land: the folder's name, or
  /// My Drive for the root, as the share sheet puts it.
  static Future<String> _folderName(
    DriveRepository repository,
    String? folderId,
  ) async {
    if (folderId == null) return 'My Drive';
    return (await repository.pathTo(folderId)).lastOrNull?.name ??
        'this folder';
  }

  /// [request] as [name]: a copy the app owns takes the name on disk too,
  /// so Telegram shows the same name the drive does.
  static Future<UploadRequest> _renamed(
    UploadRequest request,
    String name,
  ) async {
    if (name == request.name) return request;
    final path = request.path;
    return request.copyWith(
      name: name,
      path: path != null && request.ownsSource
          ? await renamedOnDisk(path, name)
          : null,
    );
  }

  /// Deletes the copy the app made for [request], which won't be uploaded.
  static Future<void> _discardRequest(UploadRequest request) async {
    final path = request.path;
    if (!request.ownsSource || path == null) return;
    try {
      await File(path).delete();
    } catch (_) {}
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
      () => ref
          .read(driveRepositoryProvider)
          .createFolder(name, parentId: parentId),
    );
  }

  /// Scans a document or takes a photo, as [kind] says, and uploads it
  /// into [folderId] under the name the person gives it. Backing out of
  /// the scanner or the camera ends it without a word. The name dialog
  /// closes only through its buttons, so a long scan is never lost to a
  /// stray tap, and Discard deletes the capture. A name the folder already
  /// has gets a number, so both files are kept.
  static Future<void> capture(
    BuildContext context,
    WidgetRef ref,
    CaptureKind kind, {
    String? folderId,
  }) async {
    // Read up front: the scanner or the camera is in front for a while.
    final queue = ref.read(transferQueueProvider.notifier);
    final repository = ref.read(driveRepositoryProvider);
    final recent = ref.read(recentDestinationsProvider.notifier);
    final container = ProviderScope.containerOf(context, listen: false);
    final canPhoto = ref.read(captureSupportProvider).value?.photo ?? false;
    final scan = kind == CaptureKind.scan;
    final CapturedFile? shot;
    try {
      shot = await ref.read(deviceCaptureProvider).capture(kind);
    } on PlatformException {
      if (!context.mounted) return;
      if (scan && canPhoto) {
        showSnack(
          context,
          'This phone can\'t scan documents right now.',
          actionLabel: 'Take a photo',
          onAction: () {
            if (context.mounted) {
              capture(context, ref, CaptureKind.photo, folderId: folderId);
            }
          },
        );
      } else if (scan) {
        showSnack(context, 'This phone can\'t scan documents right now.');
      } else {
        showSnack(context, 'Couldn\'t open the camera.');
      }
      return;
    }
    if (shot == null) return;
    if (!context.mounted) {
      await _discardCapture(shot);
      return;
    }

    final chosen = await showTextInputDialog(
      context,
      title: scan ? 'Name this scan' : 'Name this photo',
      initialValue: shot.name,
      selectStem: true,
      confirmLabel: 'Upload',
      cancelLabel: 'Discard',
      dismissible: false,
    );
    if (chosen == null) {
      await _discardCapture(shot);
      if (context.mounted) {
        showSnack(context, scan ? 'Scan discarded' : 'Photo discarded');
      }
      return;
    }

    final extension = p.extension(shot.name);
    final typed = extension.isEmpty
        ? chosen
        : withExtension(chosen, extension.substring(1));
    final [name] = await namesKeepingBoth(
      repository,
      container.read(transferQueueProvider),
      [typed],
      folderId: folderId,
    );
    final path = name == shot.name
        ? shot.path
        : await renamedOnDisk(shot.path, name);
    final ids = await queue.enqueueUploads([
      UploadRequest(
        name: name,
        path: path,
        size: shot.size,
        ownsSource: true,
        takenAt: shot.takenAt,
      ),
    ], folderId: folderId);
    unawaited(recent.note(folderId));
    // Once the upload is through the queue is done with the file, so the
    // capture's own folder goes with it; a failed or cancelled one keeps
    // its file for Retry.
    if (ids.isNotEmpty) {
      final folder = File(path).parent;
      unawaited(
        queue.whenFinished(ids.single).then((row) async {
          if (row.status != TransferStatus.completed) return;
          try {
            await folder.delete(recursive: true);
          } on FileSystemException catch (_) {}
        }),
      );
    }

    final where = await repository.pathTo(folderId);
    if (!context.mounted) return;
    final router = GoRouter.of(context);
    showSnack(
      context,
      'Uploading $name to ${where.isEmpty ? 'Files' : where.last.name}',
      actionLabel: 'View',
      onAction: () => router.push('/transfers'),
    );
  }

  /// Deletes [shot] and the folder it came in, which holds nothing else.
  static Future<void> _discardCapture(CapturedFile shot) async {
    try {
      await File(shot.path).parent.delete(recursive: true);
    } catch (_) {}
  }

  /// [names], for uploads into [folderId] that keep both files on a clash:
  /// a name the folder already has gets a number, and so does one an
  /// upload in [transfers] is still taking there or an earlier one of
  /// [names] took, so uploads made close together get names of their own.
  static Future<List<String>> namesKeepingBoth(
    DriveRepository repository,
    TransfersState transfers,
    List<String> names, {
    String? folderId,
  }) async {
    final taken = {
      for (final file in (await repository.watchFolder(folderId).first).files)
        file.name.toLowerCase(),
      for (final item in transfers.items)
        if (item.kind == TransferKind.upload &&
            item.status.isPending &&
            item.row.folderId == folderId)
          item.name.toLowerCase(),
    };
    final free = <String>[];
    for (final name in names) {
      final named = repository.freeName(name, taken);
      taken.add(named.toLowerCase());
      free.add(named);
    }
    return free;
  }

  /// Gives the file at [path] the name [name] on disk, and returns where it
  /// is now. Telegram names a document after the file it is sent from, so
  /// a file the app owns takes the name the drive will show before it goes
  /// up. Should Android refuse, the upload goes ahead from the file as it
  /// is.
  static Future<String> renamedOnDisk(String path, String name) async {
    try {
      final renamed = p.join(p.dirname(path), DeviceStorage.safeName(name));
      return (await File(path).rename(renamed)).path;
    } on FileSystemException catch (e) {
      debugPrint('[Upload] Could not rename $path: $e');
      return path;
    }
  }

  /// Takes back the uploads [transferIds], from the Undo on the sentence
  /// that started them. One still on its way is cancelled and leaves the
  /// list, along with the copy the app made of its file; one that already
  /// arrived goes to Trash. Says which it was, or why the Undo failed.
  static Future<void> undoUploads(
    BuildContext context,
    WidgetRef ref,
    List<String> transferIds,
  ) async {
    final container = ProviderScope.containerOf(context, listen: false);
    final queue = ref.read(transferQueueProvider.notifier);
    final repository = ref.read(driveRepositoryProvider);
    final lasting = _lasting(context);
    var arrived = 0;
    final undone = await _guard(lasting, () async {
      final landed = <DriveFile>[];
      for (final id in transferIds) {
        // Read as it is now: an upload can arrive while the rest are undone.
        final row = container.read(transferQueueProvider).byId(id)?.row;
        if (row == null) continue;
        if (row.status == TransferStatus.completed) {
          final file = await repository.fileById(row.fileId);
          if (file != null) landed.add(file);
          await queue.remove(id);
          continue;
        }
        // The queue deletes the app's copy along with the row.
        await queue.remove(id);
      }
      if (landed.isNotEmpty) await repository.trash(files: landed);
      arrived = landed.length;
    }, failurePrefix: _undoFailed);
    if (!undone || !lasting.mounted) return;
    showSnack(
      lasting,
      arrived == 0
          ? 'Cancelled the upload'
          : 'Cancelled. What had already arrived is in Trash.',
    );
  }

  /// The sheet behind the "+" button. It says which folder things land in,
  /// and offers a scan or a photo only on a phone that can make one.
  static Future<void> showCreateSheet(
    BuildContext context,
    WidgetRef ref, {
    String? folderId,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      // The sheet takes the height of its rows, and scrolls them on a
      // screen too short for all of them.
      isScrollControlled: true,
      builder: (sheetContext) {
        // The actions run on the screen that opened the sheet, which
        // outlives it.
        void run(Future<void> Function() action) {
          Navigator.pop(sheetContext);
          action();
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(bottom: Space.s),
            child: Consumer(
              builder: (_, sheetRef, _) {
                final support =
                    sheetRef.watch(captureSupportProvider).value ??
                    CaptureSupport.none;
                final folder = sheetRef
                    .watch(breadcrumbsProvider(folderId))
                    .value
                    ?.lastOrNull
                    ?.name;
                return SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          Space.gutter,
                          Space.xs,
                          Space.gutter,
                          Space.s,
                        ),
                        child: Text(
                          'Add to ${folder ?? 'Files'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: sheetContext.text.titleSmall,
                        ),
                      ),
                      _CreateOption(
                        icon: Icons.upload_file_outlined,
                        label: 'Upload files',
                        detail: 'Anything on this phone, any size',
                        onTap: () =>
                            run(() => upload(context, ref, folderId: folderId)),
                      ),
                      _CreateOption(
                        icon: Icons.photo_library_outlined,
                        label: 'Upload photos and videos',
                        detail: 'Originals, uncompressed',
                        onTap: () => run(
                          () => upload(
                            context,
                            ref,
                            folderId: folderId,
                            mediaOnly: true,
                          ),
                        ),
                      ),
                      if (support.scan)
                        _CreateOption(
                          icon: Icons.document_scanner_outlined,
                          label: 'Scan a document',
                          detail: 'Straightened and cropped into a PDF',
                          onTap: () => run(
                            () => capture(
                              context,
                              ref,
                              CaptureKind.scan,
                              folderId: folderId,
                            ),
                          ),
                        ),
                      if (support.photo)
                        _CreateOption(
                          icon: Icons.photo_camera_outlined,
                          label: 'Take a photo',
                          detail: 'Goes straight here, not to your gallery',
                          onTap: () => run(
                            () => capture(
                              context,
                              ref,
                              CaptureKind.photo,
                              folderId: folderId,
                            ),
                          ),
                        ),
                      _CreateOption(
                        icon: Icons.create_new_folder_outlined,
                        label: 'New folder',
                        onTap: () => run(
                          () => createFolder(context, ref, parentId: folderId),
                        ),
                      ),
                      _CreateOption(
                        icon: Icons.telegram,
                        label: 'Save from a Telegram chat',
                        detail:
                            'Copies files already in Telegram, with no upload',
                        onTap: () => run(
                          () => saveFromChat(context, ref, folderId: folderId),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
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
      success: offlineAware(ref, 'Renamed to "$name"'),
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
    // Recent folders carry their names into the system share sheet, so the
    // names there follow straight away rather than after the next sync.
    final recent = ref.read(recentDestinationsProvider.notifier);
    await _guard(
      context,
      () async {
        await repository.renameFolder(folder, name);
        unawaited(recent.refresh());
      },
      success: offlineAware(ref, 'Renamed to "$name"'),
      undo: () async {
        for (final current in await _currentFolders(repository, [folder])) {
          await repository.renameFolder(current, folder.name);
        }
        unawaited(recent.refresh());
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

    // A file named like one already in the destination asks what to do.
    // Replace sends that file to the trash once the move is through, Keep
    // both moves under a numbered name, and Skip leaves the file where it
    // is. The files already in the destination are left out of it, and a
    // file named like one settled earlier in the batch is numbered without
    // asking, so the folder never ends up with two files of one name.
    final arriving = [
      for (final file in files)
        if (file.folderId != target) file,
    ];
    final clashes = await repository.nameClashes(
      arriving.map((f) => f.name),
      target,
    );
    final renames = <String, String>{};
    // Moved file id to the id of the file it replaces.
    final replacements = <String, String>{};
    final moving = [...files];
    if (arriving.isNotEmpty) {
      final taken = await repository.takenNamesIn(target);
      bool clashing(DriveFile file) {
        final existing = clashes[file.name.toLowerCase()];
        return existing != null && existing.id != file.id;
      }

      ClashChoice? forAll;
      for (final (index, file) in arriving.indexed) {
        final lower = file.name.toLowerCase();
        final existing = clashes[lower];
        // A file whose folder is gone already shows at the root under its
        // own name.
        if (existing?.id == file.id) continue;
        if (existing == null) {
          if (taken.add(lower)) continue;
          final name = repository.freeName(file.name, taken);
          taken.add(name.toLowerCase());
          renames[file.id] = name;
          continue;
        }
        ClashChoice? choice = forAll;
        if (choice == null) {
          if (!context.mounted) return false;
          final answer = await showClashSheet(
            context,
            name: file.name,
            existing: existing,
            newSize: file.size,
            folderName: destination.name,
            keepBothName: repository.freeName(file.name, taken),
            clashesLeft: arriving.skip(index).where(clashing).length,
            moving: file,
          );
          choice = answer?.$1 ?? ClashChoice.skip;
          if (answer != null && answer.$2) forAll = choice;
        }
        switch (choice) {
          case ClashChoice.replace:
            replacements[file.id] = existing.id;
            // The name is now this file's: a later file of the same name
            // is numbered rather than replacing a file bound for the
            // trash.
            clashes.remove(lower);
          case ClashChoice.keepBoth:
            final name = repository.freeName(file.name, taken);
            taken.add(name.toLowerCase());
            renames[file.id] = name;
          case ClashChoice.skip:
            moving.remove(file);
        }
      }
    }
    if (!context.mounted) return false;
    if (moving.isEmpty && folders.isEmpty) {
      showSnack(context, 'Nothing moved');
      return false;
    }

    final outcome = await runBulk<_Step>(
      context,
      ref.read(bulkEditsProvider.notifier),
      label:
          'Moving ${Formatters.count(moving.length + folders.length, 'item')}',
      icon: Icons.drive_file_move_outline,
      items: <_Step>[
        for (final file in moving)
          (
            apply: () async {
              await repository.moveFiles([file], target, renames: renames);
              if (replacements[file.id] case final replaced?) {
                await repository.replaceWith(
                  oldFileId: replaced,
                  newFileId: file.id,
                );
              }
            },
            undo: () async {
              await repository.moveFiles(
                await _current(repository, [file]),
                file.folderId,
                renames: renames.containsKey(file.id)
                    ? {file.id: file.name}
                    : const {},
              );
              // The file it replaced comes back out of the trash.
              if (replacements[file.id] case final replaced?) {
                final old = await repository.fileById(replaced);
                if (old != null && old.trashedAt != null) {
                  await repository.restore(files: [old]);
                }
              }
            },
          ),
        for (final folder in folders)
          (
            apply: () => repository.moveFolder(folder, target),
            undo: () async {
              for (final current in await _currentFolders(repository, [
                folder,
              ])) {
                await repository.moveFolder(current, folder.parentId);
              }
            },
          ),
      ],
      apply: (step) => step.apply(),
      success: offlineAware(ref, 'Moved to ${destination.name}'),
      undo: (
        label: (done) => 'Moving ${Formatters.count(done, 'item')} back',
        apply: (step) => step.undo(),
      ),
    );
    return outcome?.complete ?? false;
  }

  /// Stars or unstars [files] and [folders], with Undo. Returns whether
  /// every item changed.
  static Future<bool> setStarred(
    BuildContext context,
    WidgetRef ref,
    List<DriveFile> files, {
    List<DriveFolder> folders = const [],
    required bool starred,
  }) async {
    final repository = ref.read(driveRepositoryProvider);
    String label(int count, {required bool starring}) => starring
        ? 'Starring ${Formatters.count(count, 'item')}'
        : 'Removing ${Formatters.count(count, 'item')} from Starred';
    final items = <Object>[...files, ...folders];
    final outcome = await runBulk<Object>(
      context,
      ref.read(bulkEditsProvider.notifier),
      label: label(items.length, starring: starred),
      icon: Icons.star_outline_rounded,
      items: items,
      apply: (item) => switch (item) {
        DriveFile file => repository.setStarred([file], starred: starred),
        DriveFolder folder => repository.setFolderStarred([
          folder,
        ], starred: starred),
        _ => Future.value(),
      },
      success: offlineAware(
        ref,
        starred ? 'Added to Starred' : 'Removed from Starred',
      ),
      // Each item goes back to how it was, so one that was starred before
      // stays starred.
      undo: (
        label: (done) => label(done, starring: !starred),
        apply: (item) async => switch (item) {
          DriveFile file => repository.setStarred(
            await _current(repository, [file]),
            starred: file.starred,
          ),
          DriveFolder folder => repository.setFolderStarred(
            await _currentFolders(repository, [folder]),
            starred: folder.starred,
          ),
          _ => null,
        },
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
            undo: () async => repository.restore(
              folders: await _currentFolders(repository, [folder]),
            ),
          ),
        for (final file in files)
          (
            apply: () => repository.trash(files: [file]),
            undo: () async =>
                repository.restore(files: await _current(repository, [file])),
          ),
      ],
      apply: (step) => step.apply(),
      success: offlineAware(ref, 'Moved $what to Trash'),
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
    // A trashed folder leaves the system share sheet's targets now, rather
    // than after the next sync.
    if (folders.isNotEmpty && outcome != null) {
      unawaited(container.read(recentDestinationsProvider.notifier).refresh());
    }
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
          final going = [
            for (final id in assetIds)
              if (still.contains(id)) id,
          ];
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
      final here = [
        for (final id in assetIds)
          if (present.contains(id)) id,
      ];
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
    ref
        .read(pendingDeletesProvider.notifier)
        .keepPhoneCopies(files.map((file) => file.id));
    return _guard(
      context,
      () => repository.restore(files: files, folders: folders),
      success: offlineAware(ref, 'Restored ${_describe(files, folders)}'),
      undo: () async => repository.trash(
        files: await _current(repository, files),
        folders: await _currentFolders(repository, folders),
      ),
    );
  }

  /// Deletes [files] and [folders] for good, and everything inside the
  /// folders. They leave the list at once, and the messages go once Undo
  /// has had its time. Returns whether the delete is under way: there is
  /// nothing left to confirm.
  static Future<bool> deleteForever(
    BuildContext context,
    WidgetRef ref, {
    List<DriveFile> files = const [],
    List<DriveFolder> folders = const [],
  }) async {
    final repository = ref.read(driveRepositoryProvider);
    final what = _describe(files, folders);
    return deleteLater(
      context,
      ref,
      fileIds: {for (final file in files) file.id},
      folderIds: {for (final folder in folders) folder.id},
      label: what,
      message: 'Deleting $what for good',
      run: () => repository.delete(files: files, folders: folders),
    );
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
      run: () =>
          repository.delete(files: contents.files, folders: contents.folders),
    );
  }

  /// Hides [fileIds], [folderIds] and [albumIds] at once and runs [run],
  /// which deletes them for good, only once the Undo on [message] has had
  /// [PendingDeletes.wait]. Undo keeps them. [label] names what goes, for
  /// the sentence the shell shows if the delete fails later. While
  /// Telegram is still starting nothing is hidden, and it says so; returns
  /// whether the delete is under way.
  static bool deleteLater(
    BuildContext context,
    WidgetRef ref, {
    Set<String> fileIds = const {},
    Set<String> folderIds = const {},
    Set<String> albumIds = const {},
    required String label,
    required String message,
    required Future<void> Function() run,
  }) {
    if (!_connected(context, ref)) return false;
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
    return true;
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

  /// The file's actions. With [onMarkFinished], the sheet opens with Mark
  /// as finished, for a file Home offers to continue.
  static Future<void> showFileSheet(
    BuildContext context,
    WidgetRef ref,
    DriveFile file, {
    VoidCallback? onMarkFinished,
  }) {
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
                  subtitle: fileMetaLine(file),
                ),
                const Divider(height: 16),
                if (onMarkFinished != null)
                  _SheetAction(
                    icon: Icons.done_all_rounded,
                    label: 'Mark as finished',
                    onTap: () {
                      Navigator.pop(sheetContext);
                      onMarkFinished();
                    },
                  ),
                _SheetAction(
                  icon: Icons.open_in_new_rounded,
                  label: 'Open',
                  onTap: () => run(() => open(context, ref, file)),
                ),
                _SheetAction(
                  icon: Icons.download_rounded,
                  label: 'Download to this phone',
                  onTap: () =>
                      run(() => saveToDevice(context, ref, files: [file])),
                ),
                _SheetAction(
                  icon: Icons.send_outlined,
                  label: 'Send in Telegram',
                  onTap: () => run(() => sendToChats(context, ref, [file])),
                ),
                _OfflineAction(
                  itemId: file.id,
                  onTap: (pinned) => run(
                    () => setOffline(context, ref, file: file, keep: !pinned),
                  ),
                ),
                _SheetAction(
                  icon: Icons.ios_share_rounded,
                  label: 'Share',
                  onTap: () => run(() => share(context, ref, file)),
                ),
                _SheetAction(
                  icon: file.starred
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  label: file.starred
                      ? 'Remove from Starred'
                      : 'Add to Starred',
                  onTap: () => run(
                    () => setStarred(context, ref, [
                      file,
                    ], starred: !file.starred),
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
                  icon: Icons.folder_open_outlined,
                  label: 'Show in folder',
                  onTap: () => run(() => showInFolder(context, ref, file)),
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
                onTap: () =>
                    run(() => saveToDevice(context, ref, folders: [folder])),
              ),
              _SheetAction(
                icon: Icons.send_outlined,
                label: 'Send in Telegram',
                onTap: () => run(
                  () => sendToChats(context, ref, const [], folders: [folder]),
                ),
              ),
              _OfflineAction(
                itemId: folder.id,
                onTap: (pinned) => run(
                  () => setOffline(context, ref, folder: folder, keep: !pinned),
                ),
              ),
              _SheetAction(
                icon: folder.starred
                    ? Icons.star_rounded
                    : Icons.star_outline_rounded,
                label: folder.starred
                    ? 'Remove from Starred'
                    : 'Add to Starred',
                onTap: () => run(
                  () => setStarred(
                    context,
                    ref,
                    const [],
                    folders: [folder],
                    starred: !folder.starred,
                  ),
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

  /// The Details sheet: what the index knows about [file], and Show in
  /// Telegram. Everything it says is looked up before it opens, so it never
  /// shows a half-filled sheet.
  static Future<void> showDetails(
    BuildContext context,
    WidgetRef ref,
    DriveFile file,
  ) async {
    final db = ref.read(appDatabaseProvider);
    final repository = ref.read(driveRepositoryProvider);
    final (path, albums, assetId, previous) = await (
      repository.pathTo(file.folderId),
      db.albumNamesOf(file.id),
      db.localAssetOf(file.id),
      repository.previousVersionOf(file.id),
    ).wait;
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      builder: (sheetContext) {
        final lines = detailLines(
          file,
          path: [for (final folder in path) folder.name],
          albums: albums,
          backedUp: assetId != null,
          previous: previous,
          showFolder: () {
            Navigator.pop(sheetContext);
            showInFolder(context, ref, file);
          },
        );
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.name,
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                for (final line in lines)
                  _DetailRow(line.label, line.value, onTap: line.onTap),
                // Restoring keeps both files side by side; nothing swaps
                // back.
                if (previous != null)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.xs),
                    child: TextButton(
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        restore(context, ref, files: [previous]);
                      },
                      child: const Text('Restore previous version'),
                    ),
                  ),
                const SizedBox(height: Space.l),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      showInTelegram(context, ref, file);
                    },
                    icon: const Icon(Icons.telegram),
                    label: const Text('Show in Telegram'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// What the Details sheet says about [file], line by line. [path] names
  /// the folders it is in from the top, [albums] the albums holding it, and
  /// [backedUp] says it was backed up from a photo on this phone; a backed-up
  /// photo's phone folder is the one under Photo backup that holds it.
  /// [previous] is the file this one replaced, while it is still in the
  /// trash. [showFolder] makes Location a link to the folder.
  static List<DetailLine> detailLines(
    DriveFile file, {
    List<String> path = const [],
    List<String> albums = const [],
    bool backedUp = false,
    DriveFile? previous,
    VoidCallback? showFolder,
  }) => [
    DetailLine(
      'Type',
      file.extension.isEmpty
          ? file.mimeType
          : '${file.kind.label.replaceAll(RegExp(r's$'), '')} · ${file.extension}',
    ),
    DetailLine(
      'Size',
      '${Formatters.bytes(file.size)} (${Formatters.count(file.size, 'byte')})',
    ),
    if (file.originalSize case final original?)
      DetailLine(
        'Original',
        '${Formatters.bytes(original)}. It goes up from the phone that took it, over Wi-Fi.',
      ),
    if (file.duration case final d?)
      DetailLine('Duration', Formatters.length(d)),
    if (file.takenAt case final taken?)
      DetailLine('Taken', Formatters.fullDate(taken)),
    DetailLine('Location', ['Files', ...path].join(' › '), onTap: showFolder),
    DetailLine('Added', Formatters.fullDate(file.createdAt)),
    DetailLine('Modified', Formatters.fullDate(file.modifiedAt)),
    if (albums.isNotEmpty) DetailLine('In albums', albums.join(', ')),
    if (backedUp)
      DetailLine('Backed up from', switch (_backupAlbum(path)) {
        final album? => 'This phone · $album',
        null => 'This phone',
      }),
    if (file.isSplit)
      DetailLine(
        'Stored as',
        '${file.partCount} parts. Telegram caps one message at 2 GB.',
      ),
    if (previous?.trashedAt case final trashed?)
      DetailLine(
        'Previous version',
        'In Trash · ${Formatters.daysLeft(trashed.add(DriveRepository.trashKeepsFor))}',
      ),
  ];

  /// Opens the folder [file] lives in, where its row is tinted for a
  /// moment. When that folder isn't one Files lists, the root opens, which
  /// is where a file whose folder is gone is listed. Going rather than
  /// pushing closes a screen opened over the shell, such as Search or the
  /// viewer.
  static Future<void> showInFolder(
    BuildContext context,
    WidgetRef ref,
    DriveFile file,
  ) async {
    final folderId = file.folderId;
    final folder = folderId == null
        ? null
        : await ref.read(driveRepositoryProvider).shownFolder(folderId);
    if (!context.mounted) return;
    final highlight = Uri.encodeQueryComponent(file.id);
    context.go(
      folder == null
          ? '/files?highlight=$highlight'
          : '/files/${folder.id}?highlight=$highlight',
    );
  }

  /// Opens the file's message in the Telegram app; for a split file, its
  /// first part's.
  static Future<void> showInTelegram(
    BuildContext context,
    WidgetRef ref,
    DriveFile file,
  ) async {
    final parts = await ref.read(driveRepositoryProvider).partsOf(file.id);
    if (parts.isEmpty || !context.mounted) return;
    await openInTelegram(context, ref, parts.first.messageId);
  }

  /// Opens the drive channel's message [messageId] in the Telegram app.
  static Future<void> openInTelegram(
    BuildContext context,
    WidgetRef ref,
    int messageId,
  ) async {
    if (!_connected(context, ref)) return;
    final session = ref.read(driveSessionProvider)!;
    // Private channel links use the bare channel id and the server message id.
    final channel = -session.chatId - 1000000000000;
    final opened = await launchUrl(
      Uri.parse('https://t.me/c/$channel/${messageId >> 20}'),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && context.mounted) {
      showSnack(context, 'Couldn\'t open Telegram.');
    }
  }

  /// [success] as it is while changes go straight to Telegram. While they
  /// wait on this phone instead, because Telegram can't be reached or is
  /// still starting behind the drive Home shows, the sentence says so:
  /// renames, moves, stars, the trash and albums are kept for when the
  /// connection is back.
  static String offlineAware(WidgetRef ref, String success) {
    final waits = ref.read(driveSessionProvider) == null
        ? ref.read(driveSnapshotProvider) != null
        : !ref.read(telegramClientProvider).isOnline;
    return waits
        ? '$success. It reaches Telegram when you\'re back online.'
        : success;
  }

  /// Whether the drive is open for something that starts in Telegram. While
  /// Home shows the drive from the index and Telegram is still starting,
  /// it says so, as a change that reached the repository would, and the
  /// person tries again once it has connected.
  static bool _connected(BuildContext context, WidgetRef ref) {
    if (ref.read(driveSessionProvider) != null) return true;
    final snapshot = ref.read(driveSnapshotProvider);
    if (snapshot != null) showSnack(context, driveNotOpen(snapshot).message);
    return false;
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
            onUndo: () => _guard(
              lasting,
              undo,
              success: 'Undone',
              failurePrefix: _undoFailed,
            ),
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
  ) async => [
    for (final folder in folders) ?await repository.folderById(folder.id),
  ];

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
    ({String Function(int done) label, Future<void> Function(T item) apply})?
    undo,
    ValueChanged<SnackBarClosedReason>? onUndoClosed,
    String failurePrefix = '',
  }) async {
    BulkOutcome? outcome;
    await _guard(context, () async {
      outcome = await edits.run(
        label: label,
        icon: icon,
        items: items,
        apply: apply,
      );
    }, failurePrefix: failurePrefix);
    final ended = outcome;
    if (ended == null) return null;
    final error = ended.error;
    final wait = error == null ? null : telegramWaitOf(error);
    final done =
        '${Formatters.number(ended.done)} of ${Formatters.number(ended.total)}';
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
          showSnack(
            context,
            'Download failed: ${error is DriveException ? error.message : error}',
          );
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
      _ => null,
    };
    final offline = item?.wait is WaitingForNetwork;
    final room = switch (item?.wait) {
      final WaitingForRoom room => room,
      _ => null,
    };
    final waiting = waitingUntil != null || offline || room != null;
    final detailStyle = theme.textTheme.bodySmall?.copyWith(
      fontFeatures: tabularFigures,
    );

    // Downloads wait in the queue until the drive's session opens.
    final connecting = ref.watch(driveSessionProvider) == null;
    return AlertDialog(
      title: Text(
        connecting ? 'Connecting to Telegram' : 'Downloading',
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
              value: waiting || progress > 0 ? progress : null,
              minHeight: 4,
              color: waiting ? context.colors.text3 : null,
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
          else if (room != null)
            Text(room.sentence, style: detailStyle)
          else
            Text(
              item == null
                  ? 'Starting'
                  : [
                      if (offline) 'Waiting for network',
                      '${Formatters.bytes(item.row.doneBytes)} of ${Formatters.bytes(item.row.totalBytes)}',
                      if (!offline && item.bytesPerSecond > 0)
                        Formatters.speed(item.bytesPerSecond),
                    ].join(' · '),
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
            showSnack(
              context,
              'Still downloading. You\'ll find it in Transfers.',
            );
          },
          child: const Text('Hide'),
        ),
      ],
    );
  }
}

/// What the Download sheet settled: whether photos and videos go to the
/// gallery, and whether the downloads wait for Wi-Fi. That is null when the
/// sheet didn't ask, so the size rule decides.
typedef _SaveChoice = ({bool gallery, bool? wifiOnly});

/// What a download to this phone will do, and where things will land,
/// before it starts. On mobile data, something big says how much data it
/// uses and offers to wait for Wi-Fi. Pops with a [_SaveChoice].
class _SaveSheet extends StatefulWidget {
  const _SaveSheet({
    required this.items,
    required this.freeBytes,
    required this.preferGallery,
    required this.network,
  });

  final List<SaveItem> items;
  final int? freeBytes;
  final bool preferGallery;
  final NetworkState network;

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
    final largest = items.fold<int>(
      0,
      (max, i) => i.file.size > max ? i.file.size : max,
    );
    final media = items.where((i) => FileActions.fitsGallery(i.file)).length;
    final free = widget.freeBytes;
    // Android holds a second copy of the file being saved for a moment.
    final needed = bytes + (Platform.isAndroid ? largest : 0);
    final tooBig = free != null && needed > free;
    final onData = TransferPolicy.shouldAsk(
      network: widget.network,
      bytes: bytes,
    );
    final single = items.length == 1;
    final library = Platform.isIOS ? 'photo library' : 'gallery';
    void choose({bool? wifiOnly}) => Navigator.pop<_SaveChoice>(context, (
      gallery: _gallery,
      wifiOnly: wifiOnly,
    ));

    final String where;
    if (_gallery && media == items.length) {
      where = single
          ? 'It goes to your $library.'
          : 'They go to your $library.';
    } else if (_gallery && media > 0) {
      where =
          'Photos and videos go to your $library; everything else to '
          '${DeviceStorage.location}.';
    } else {
      where = single
          ? 'It goes to ${DeviceStorage.location}.'
          : 'They go to ${DeviceStorage.location}, in the same folders as '
                'in your drive.';
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Space.gutter,
          0,
          Space.gutter,
          Space.l,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              single
                  ? 'Download to this phone'
                  : 'Download ${Formatters.count(items.length, 'file')}',
              style: context.text.titleMedium,
            ),
            const SizedBox(height: 2),
            Text(
              single
                  ? '${items.first.file.name} · ${Formatters.bytes(bytes)}'
                  : '${Formatters.bytes(bytes)} in total',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.text.bodyMedium?.copyWith(
                fontFeatures: tabularFigures,
              ),
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
                        style: context.text.bodySmall?.copyWith(
                          fontFeatures: tabularFigures,
                        ),
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
            if (onData)
              Padding(
                padding: const EdgeInsets.only(top: Space.xs),
                child: Text(
                  'You\'re on mobile data. This uses ${Formatters.bytes(bytes)} of it.',
                  style: context.text.bodySmall?.copyWith(
                    color: colors.text2,
                    fontFeatures: tabularFigures,
                  ),
                ),
              ),
            const SizedBox(height: Space.xl),
            Row(
              children: [
                Expanded(
                  child: onData
                      ? OutlinedButton(
                          onPressed: tooBig
                              ? null
                              : () => choose(wifiOnly: true),
                          child: const Text('Later, on Wi-Fi'),
                        )
                      : OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                ),
                const SizedBox(width: Space.m),
                Expanded(
                  child: FilledButton(
                    onPressed: tooBig
                        ? null
                        : () => choose(wifiOnly: onData ? false : null),
                    child: Text(onData ? 'Download now' : 'Download'),
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
  const _SheetHeader({
    required this.leading,
    required this.title,
    required this.subtitle,
  });

  final Widget leading;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        0,
        Space.gutter,
        Space.m,
      ),
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
                  style: context.text.bodySmall?.copyWith(
                    fontFeatures: tabularFigures,
                  ),
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
    this.detail,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// What the action comes to, under its name.
  final String? detail;
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
      subtitle: detail == null
          ? null
          : Text(
              detail!,
              style: context.text.bodySmall?.copyWith(
                fontFeatures: tabularFigures,
              ),
            ),
      minVerticalPadding: 14,
      onTap: onTap,
    );
  }
}

/// What to do with a file whose name a file in the target folder already
/// has.
enum ClashChoice { replace, keepBoth, skip }

/// Asks what to do with [name], [newSize] bytes, bound for [folderName],
/// where [existing] already has that name: Replace, Keep both (as
/// [keepBothName]) or Skip. With [moving], the file is one already in the
/// drive on its way to another folder, and the rows and words say so.
/// [clashesLeft] counts this clash and those still to come; above one, the
/// sheet offers to answer for all of them. Returns the choice and whether
/// it stands for the rest, or null when the sheet was swiped away, which
/// counts as Skip for this file.
Future<(ClashChoice, bool applyToAll)?> showClashSheet(
  BuildContext context, {
  required String name,
  required DriveFile existing,
  required int newSize,
  required String folderName,
  required String keepBothName,
  required int clashesLeft,
  DriveFile? moving,
}) => showModalBottomSheet<(ClashChoice, bool)>(
  context: context,
  useRootNavigator: true,
  // The sheet takes the height of its rows, and scrolls them on a short
  // screen.
  isScrollControlled: true,
  builder: (_) => _ClashSheet(
    name: name,
    existing: existing,
    newSize: newSize,
    folderName: folderName,
    keepBothName: keepBothName,
    clashesLeft: clashesLeft,
    moving: moving,
  ),
);

/// The question [showClashSheet] asks. Nothing here is red: Replace keeps
/// the file it replaces in the trash for 30 days.
class _ClashSheet extends StatefulWidget {
  const _ClashSheet({
    required this.name,
    required this.existing,
    required this.newSize,
    required this.folderName,
    required this.keepBothName,
    required this.clashesLeft,
    this.moving,
  });

  final String name;
  final DriveFile existing;
  final int newSize;
  final String folderName;
  final String keepBothName;
  final int clashesLeft;
  final DriveFile? moving;

  @override
  State<_ClashSheet> createState() => _ClashSheetState();
}

class _ClashSheetState extends State<_ClashSheet> {
  var _applyToAll = false;

  void _choose(ClashChoice choice) =>
      Navigator.pop(context, (choice, _applyToAll));

  @override
  Widget build(BuildContext context) {
    final existing = widget.existing;
    final moving = widget.moving;
    final colors = context.colors;
    final meta = context.text.bodySmall?.copyWith(fontFeatures: tabularFigures);
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.gutter,
                0,
                Space.gutter,
                Space.m,
              ),
              child: Text(
                '"${widget.name}" is already in ${widget.folderName}',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: context.text.titleMedium,
              ),
            ),
            _ClashRow(
              slot: FileThumbnail(file: existing),
              name: existing.name,
              meta:
                  'In the drive · ${Formatters.bytes(existing.size)} · '
                  '${Formatters.date(existing.modifiedAt)}',
              style: meta,
            ),
            _ClashRow(
              slot: moving != null
                  ? FileThumbnail(file: moving)
                  : FileIconTile(
                      style: FileStyle.forFile(
                        widget.name,
                        FileKind.detect(fileName: widget.name),
                      ),
                    ),
              name: widget.name,
              meta:
                  '${moving != null ? 'Moving' : 'New'} · '
                  '${Formatters.bytes(widget.newSize)}',
              style: meta,
            ),
            const SizedBox(height: Space.s),
            const Divider(height: 1),
            _SheetAction(
              icon: Icons.sync_alt_rounded,
              label: 'Replace',
              detail: 'The copy in the drive goes to Trash for 30 days',
              onTap: () => _choose(ClashChoice.replace),
            ),
            _SheetAction(
              icon: Icons.filter_none_rounded,
              label: 'Keep both',
              detail:
                  '${moving != null ? 'Moved' : 'Saved'} as ${widget.keepBothName}',
              onTap: () => _choose(ClashChoice.keepBoth),
            ),
            _SheetAction(
              icon: Icons.skip_next_rounded,
              label: 'Skip',
              detail: moving != null
                  ? 'Leave it where it is'
                  : 'Don\'t upload this one',
              onTap: () => _choose(ClashChoice.skip),
            ),
            if (widget.clashesLeft > 1)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
                child: CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(
                    'Do this for all ${Formatters.count(widget.clashesLeft, 'name clash', 'name clashes')}',
                    style: context.text.bodyMedium?.copyWith(
                      color: colors.text,
                      fontFeatures: tabularFigures,
                    ),
                  ),
                  value: _applyToAll,
                  onChanged: (value) =>
                      setState(() => _applyToAll = value ?? false),
                ),
              ),
            const SizedBox(height: Space.s),
          ],
        ),
      ),
    );
  }
}

/// One of the two files in the clash sheet: its media slot, name and a
/// line saying which it is and how big.
class _ClashRow extends StatelessWidget {
  const _ClashRow({
    required this.slot,
    required this.name,
    required this.meta,
    required this.style,
  });

  final Widget slot;
  final String name;
  final String meta;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.gutter,
        vertical: Space.xs,
      ),
      child: Row(
        children: [
          slot,
          const SizedBox(width: Space.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodyLarge,
                ),
                const SizedBox(height: 2),
                Text(meta, style: style),
              ],
            ),
          ),
        ],
      ),
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
      offlinePinsProvider.select(
        (pins) => pins.value?.contains(itemId) ?? false,
      ),
    );
    return _SheetAction(
      icon: pinned ? Icons.offline_pin_rounded : Icons.offline_pin_outlined,
      label: pinned ? 'Stop keeping offline' : 'Make available offline',
      onTap: () => onTap(pinned),
    );
  }
}

/// A line of the Details sheet: a label, the file's value for it, and with
/// [onTap], where tapping it goes.
class DetailLine {
  const DetailLine(this.label, this.value, {this.onTap});

  final String label;
  final String value;
  final VoidCallback? onTap;
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value, {this.onTap});

  final String label;
  final String value;

  /// Makes the row a link, marked with a chevron at its end.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.s),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(label, style: context.text.bodyMedium),
          ),
          Expanded(
            child: Text(
              value,
              style: context.text.bodyMedium?.copyWith(
                color: context.colors.text,
                fontFeatures: tabularFigures,
              ),
            ),
          ),
          if (onTap != null)
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: context.colors.text3,
            ),
        ],
      ),
    );
    if (onTap == null) return row;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.thumb),
      child: row,
    );
  }
}
