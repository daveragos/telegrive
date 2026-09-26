import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/files/file_kind.dart';
import '../../../core/format/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/file_visuals.dart';
import '../../../infrastructure/database/app_database.dart' show TransferKind;
import '../../../infrastructure/telegram/telegram_exception.dart';
import '../../drive/data/drive_repository.dart';
import '../../drive/data/drive_session.dart';
import '../../drive/domain/drive_models.dart';
import '../../transfers/data/transfer_queue.dart';
import 'folder_picker.dart';

/// Every action a person can take on files and folders, in one place so the
/// home screen, the browser and search all behave identically.
abstract final class FileActions {
  // ---------------------------------------------------------------------------
  // Opening & sharing
  // ---------------------------------------------------------------------------

  static Future<void> open(
    BuildContext context,
    WidgetRef ref,
    DriveFile file,
  ) async {
    if (file.kind == FileKind.image && !file.isSplit) {
      context.push('/viewer/${file.id}');
      return;
    }
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
    final path = await _obtain(context, ref, file);
    if (path == null) return;
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
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Row(
            children: [
              _CreateOption(
                icon: Icons.upload_file_rounded,
                label: 'Upload files',
                onTap: () {
                  Navigator.pop(sheetContext);
                  upload(context, ref, folderId: folderId);
                },
              ),
              _CreateOption(
                icon: Icons.photo_library_rounded,
                label: 'Photos & videos',
                onTap: () {
                  Navigator.pop(sheetContext);
                  upload(context, ref, folderId: folderId, mediaOnly: true);
                },
              ),
              _CreateOption(
                icon: Icons.create_new_folder_rounded,
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
    if (name == null || !context.mounted) return;
    await _guard(context, () => ref.read(driveRepositoryProvider).renameFile(file, name));
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
    if (name == null || !context.mounted) return;
    await _guard(
      context,
      () => ref.read(driveRepositoryProvider).renameFolder(folder, name),
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
    return _guard(context, () async {
      final repository = ref.read(driveRepositoryProvider);
      await repository.moveFiles(files, target);
      for (final folder in folders) {
        await repository.moveFolder(folder, target);
      }
    }, success: 'Moved to ${destination.name}');
  }

  static Future<void> setStarred(
    BuildContext context,
    WidgetRef ref,
    List<DriveFile> files, {
    required bool starred,
  }) async {
    await _guard(
      context,
      () => ref.read(driveRepositoryProvider).setStarred(files, starred: starred),
      success: starred ? 'Added to Starred' : 'Removed from Starred',
    );
  }

  static Future<bool> delete(
    BuildContext context,
    WidgetRef ref, {
    List<DriveFile> files = const [],
    List<DriveFolder> folders = const [],
  }) async {
    final count = files.length + folders.length;
    final what = count == 1
        ? '"${files.isNotEmpty ? files.first.name : folders.first.name}"'
        : '$count items';
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete $what?',
      message: folders.isEmpty
          ? 'It will be removed from your Telegram channel. This can\'t be undone.'
          : 'Folders are deleted with everything inside them. This can\'t be undone.',
      confirmLabel: 'Delete',
      destructive: true,
      icon: Icons.delete_outline_rounded,
    );
    if (!confirmed || !context.mounted) return false;
    return _guard(
      context,
      () => ref.read(driveRepositoryProvider).delete(files: files, folders: folders),
      success: count == 1 ? 'Deleted' : 'Deleted $count items',
    );
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
                  icon: Icons.ios_share_rounded,
                  label: 'Share or save to device',
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
                  label: 'Delete',
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
                label: 'Delete',
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
    final location = ['My Drive', ...path.map((f) => f.name)].join(' / ');
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
                  '${file.partCount} messages — Telegram caps a single file at 2 GB',
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

  /// Runs [action], turning failures into a snackbar. Returns success.
  static Future<bool> _guard(
    BuildContext context,
    Future<void> Function() action, {
    String? success,
  }) async {
    try {
      await action();
      if (success != null && context.mounted) showSnack(context, success);
      return true;
    } on DriveException catch (e) {
      if (context.mounted) showSnack(context, e.message);
    } on TelegramException catch (e) {
      if (context.mounted) showSnack(context, e.friendlyMessage);
    } catch (e) {
      if (context.mounted) showSnack(context, 'Something went wrong: $e');
    }
    return false;
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
        if (error is! DriveException || error.message != 'Signed out.') {
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

    return AlertDialog(
      icon: FileThumbnail(file: widget.file, size: 56),
      title: Text(
        widget.file.name,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress > 0 ? progress : null,
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            item == null
                ? 'Getting ready…'
                : '${Formatters.bytes(item.row.doneBytes)} of ${Formatters.bytes(item.row.totalBytes)}'
                      '${item.bytesPerSecond > 0 ? ' · ${Formatters.speed(item.bytesPerSecond)}' : ''}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            if (item != null) {
              ref.read(transferQueueProvider.notifier).cancel(item.id);
            }
          },
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
            showSnack(context, 'Still downloading — it\'s in Transfers.');
          },
          child: const Text('Hide'),
        ),
      ],
    );
  }
}

class _CreateOption extends StatelessWidget {
  const _CreateOption({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Ink(
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              color: scheme.surfaceContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: scheme.primaryContainer,
                  child: Icon(icon, color: scheme.onPrimaryContainer),
                ),
                const SizedBox(height: 10),
                Text(label, style: theme.textTheme.labelLarge, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
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
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
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
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = destructive ? scheme.error : scheme.onSurface;
    return ListTile(
      leading: Icon(icon, color: destructive ? scheme.error : scheme.onSurfaceVariant),
      title: Text(label, style: TextStyle(color: color)),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
