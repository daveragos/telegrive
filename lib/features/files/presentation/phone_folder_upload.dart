import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/format/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../../infrastructure/network/network_status.dart';
import '../../../infrastructure/storage/preferences.dart';
import '../../backup/data/phone_folders.dart';
import '../../drive/data/drive_repository.dart';
import '../../share/data/recent_destinations.dart';
import '../../transfers/data/transfer_policy.dart';
import '../../transfers/data/transfer_queue.dart';
import '../../transfers/presentation/mobile_data_prompt.dart';
import '../data/folder_upload_plan.dart';
import '../data/phone_picks.dart';
import 'file_actions.dart';

/// Uploading a folder from the phone with the folders inside it: the
/// person picks it in Android's folder picker, and it goes up as a folder
/// of its name, its folders made in the drive as they are on the phone.
/// Nothing is copied up front: each file is copied as its upload starts,
/// as Upload files does, and the folder is readable while the app runs.
abstract final class PhoneFolderUpload {
  static bool get supported => PhoneFolders.supported;

  /// Has the person pick a folder and sends it up inside [folderId], the
  /// root when null.
  static Future<void> start(
    BuildContext context,
    WidgetRef ref, {
    String? folderId,
  }) async {
    if (!FileActions.connected(context, ref)) return;
    final folders = ref.read(phoneFoldersProvider);
    final repository = ref.read(driveRepositoryProvider);
    final queue = ref.read(transferQueueProvider.notifier);
    final recent = ref.read(recentDestinationsProvider.notifier);
    final bigWait = ref.read(preferencesProvider).bigTransfersWifiOnly;

    final PickedFolder? picked;
    try {
      picked = await folders.pick(keep: false);
    } catch (e) {
      debugPrint('[Folder upload] Picking: $e');
      if (context.mounted) {
        showSnack(context, 'Couldn\'t open the folder picker.');
      }
      return;
    }
    if (picked == null || !context.mounted) return;
    final name = picked.name;

    final ({List<PhoneDocument> files, bool truncated}) listed;
    try {
      listed = await _whileReading(
        context,
        name,
        folders.list(picked.uri, recursive: true),
      );
    } catch (e) {
      debugPrint('[Folder upload] Reading "$name": $e');
      if (context.mounted) {
        showSnack(context, 'Couldn\'t read "$name" on this phone.');
      }
      return;
    }
    if (!context.mounted) return;
    final plan = FolderUploadPlan.of(name, listed.files);
    if (plan.fileCount == 0) {
      showSnack(context, '"$name" has no files to upload.');
      return;
    }

    final where = folderId == null
        ? 'Files'
        : (await repository.pathTo(folderId)).lastOrNull?.name ?? 'this folder';
    if (!context.mounted) return;
    final go = await showConfirmDialog(
      context,
      title: 'Upload "$name"?',
      message: confirmMessage(plan, where: where, truncated: listed.truncated),
      confirmLabel: 'Upload',
    );
    if (!go || !context.mounted) return;

    DataChoice? choice;
    if (TransferPolicy.shouldAsk(
      network: ref.read(networkStatusProvider),
      bytes: plan.bytes,
    )) {
      choice = await askAboutMobileData(
        context,
        bytes: plan.bytes,
        doing: 'Uploading "$name"',
        files: plan.fileCount,
        nowLabel: 'Upload now',
      );
      if (choice == null || !context.mounted) return;
    }

    // Each folder is made, then its files queued, so the first uploads
    // start while the folders after them are still being made. Into a new
    // folder nothing clashes, and it all goes even if the screen is left;
    // into one of the same name already there, files of a name already in
    // their folder ask what to do, which needs the screen.
    String? topId;
    var queued = 0;
    Object? failure;
    try {
      final siblings = (await repository.watchFolder(folderId).first).folders;
      final merging = siblings.any(
        (folder) => folder.name.toLowerCase() == name.toLowerCase(),
      );
      topId = await repository.ensureFolderPath([name], under: folderId);
      for (final group in plan.groups) {
        if (merging && !context.mounted) break;
        final id = group.path.isEmpty
            ? topId
            : await repository.ensureFolderPath(group.path, under: topId);
        final requests = [
          for (final doc in group.files)
            UploadRequest(
              name: doc.name,
              size: doc.size,
              copyTo: (String path) => PhonePicks.copy(doc.uri!, path),
              ownsSource: true,
              wifiOnly:
                  wifiOnlyFrom(choice) ??
                  TransferPolicy.wifiOnlyFor(doc.size, bigWaitForWifi: bigWait),
            ),
        ];
        final List<UploadRequest> resolved;
        if (!merging) {
          resolved = requests;
        } else if (context.mounted) {
          resolved = await FileActions.resolveUploadClashes(
            context,
            ref,
            requests,
            folderId: id,
          );
        } else {
          break;
        }
        if (resolved.isEmpty) continue;
        queued += (await queue.enqueueUploads(resolved, folderId: id)).length;
      }
    } catch (e) {
      debugPrint('[Folder upload] "$name": $e');
      failure = e;
    }
    if (queued > 0) unawaited(recent.note(topId));
    if (!context.mounted) return;

    if (failure != null) {
      showSnack(
        context,
        queued == 0
            ? 'Couldn\'t upload "$name": ${FileActions.failureOf(failure)}'
            : 'Uploading ${Formatters.count(queued, 'file')} of "$name". '
                  'The rest couldn\'t go: ${FileActions.failureOf(failure)}',
      );
      return;
    }
    if (queued == 0) {
      showSnack(context, 'Nothing to upload');
      return;
    }
    final router = GoRouter.of(context);
    showSnack(
      context,
      summary(
        name: name,
        queued: queued,
        skipped: plan.skipped,
        waitsForWifi: choice == DataChoice.later,
      ),
      actionLabel: 'View',
      onAction: () => router.push('/transfers'),
    );
  }

  /// What the confirmation says goes up, and where.
  @visibleForTesting
  static String confirmMessage(
    FolderUploadPlan plan, {
    required String where,
    required bool truncated,
  }) {
    final inside = plan.subfolderCount == 0
        ? ''
        : ', with the ${Formatters.count(plan.subfolderCount, 'folder')} '
              'inside it as they are on this phone';
    return '${Formatters.count(plan.fileCount, 'file')} '
        '(${Formatters.bytes(plan.bytes)}) go up to the folder '
        '"${plan.name}" in $where$inside.'
        '${truncated ? ' It holds more files than can be read at once, so '
                  'only the first ${Formatters.number(PhoneFolders.listLimit)} '
                  'go.' : ''}';
  }

  /// What the snack says once the folder is on its way.
  @visibleForTesting
  static String summary({
    required String name,
    required int queued,
    required int skipped,
    bool waitsForWifi = false,
  }) {
    final going =
        '${waitsForWifi ? 'Waiting for Wi-Fi to upload' : 'Uploading'} '
        '${Formatters.count(queued, 'file')} to "$name".';
    if (skipped == 0) return going;
    return '$going ${Formatters.count(skipped, 'hidden or empty file')} '
        '${skipped == 1 ? 'stays' : 'stay'} behind.';
  }

  /// Waits for [listing] behind a dialog that says the folder is being
  /// read. A listing can't be stopped part way, so the dialog has no
  /// Cancel, and Back leaves it up.
  static Future<T> _whileReading<T>(
    BuildContext context,
    String name,
    Future<T> listing,
  ) async {
    BuildContext? dialog;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          dialog = dialogContext;
          return PopScope(
            canPop: false,
            child: AlertDialog(
              content: Row(
                children: [
                  const SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                  const SizedBox(width: Space.l),
                  Expanded(
                    child: Text(
                      'Reading "$name"…',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    try {
      return await listing;
    } finally {
      // The dialog may not have been built yet when the listing ends at once.
      await WidgetsBinding.instance.endOfFrame;
      final open = dialog;
      if (open != null && open.mounted) Navigator.of(open).pop();
    }
  }
}
