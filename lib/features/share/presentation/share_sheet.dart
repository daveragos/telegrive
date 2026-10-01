import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/files/file_kind.dart';
import '../../../core/format/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/file_visuals.dart';
import '../../../app/theme/file_style.dart';
import '../../../infrastructure/network/network_status.dart';
import '../../../infrastructure/storage/preferences.dart';
import '../../drive/data/drive_repository.dart';
import '../../drive/domain/drive_models.dart';
import '../../files/presentation/file_actions.dart';
import '../../files/presentation/folder_picker.dart';
import '../../transfers/data/transfer_policy.dart';
import '../../transfers/data/transfer_queue.dart';
import '../../transfers/presentation/mobile_data_prompt.dart';
import '../data/recent_destinations.dart';
import '../data/share_intake.dart';

/// Asks where files shared from another app should go, then uploads them.
/// Files shared to one of the drive's folders in Android's share sheet go
/// straight into it with no question, as long as the drive still shows
/// that folder; otherwise the sheet asks, so nothing is put into Trash.
Future<void> showShareSheet(BuildContext context, WidgetRef ref) async {
  final files = ref.read(shareIntakeProvider);
  if (files.isEmpty) return;
  final targets = files.map((f) => f.folderId).toSet();
  if (targets.length == 1 && targets.single != null) {
    final folder = await ref.read(driveRepositoryProvider).shownFolder(targets.single!);
    if (folder != null && context.mounted) {
      await _uploadStraight(context, ref, files, folder);
      return;
    }
  }
  if (!context.mounted) return;
  // A folder trashed on another device can reach the index through a live
  // update, which the recent folders do not follow, so they are looked up
  // again before the sheet starts on the first of them.
  await ref.read(recentDestinationsProvider.notifier).refresh();
  if (!context.mounted) return;
  final uploaded = await showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    isDismissible: false,
    builder: (_) => _ShareSheet(files: files),
  );
  if (uploaded != true) await ref.read(shareIntakeProvider.notifier).clear(discard: true);
}

/// Uploads [files] into [folder], which they were shared to, and says so
/// with Undo. A name the folder already has gets a number, so both files
/// are kept, and the sentence names the file as it will be called.
Future<void> _uploadStraight(
  BuildContext context,
  WidgetRef ref,
  List<SharedFile> files,
  DriveFolder folder,
) async {
  final names = await FileActions.namesKeepingBoth(
    ref.read(driveRepositoryProvider),
    ref.read(transferQueueProvider),
    [for (final file in files) file.name],
    folderId: folder.id,
  );
  final named = [
    for (final (index, file) in files.indexed)
      SharedFile(
        // A gallery original stays where it is, under its own name.
        path: names[index] == file.name || !file.owned
            ? file.path
            : await FileActions.renamedOnDisk(file.path, names[index]),
        name: names[index],
        size: file.size,
        owned: file.owned,
        folderId: file.folderId,
      ),
  ];
  final ids = await _enqueue(ref, named, folder.id);
  if (!context.mounted) return;
  showUndoSnack(
    context,
    named.length == 1
        ? 'Uploading ${named.single.name} to ${folder.name}'
        : 'Uploading ${Formatters.count(named.length, 'file')} to ${folder.name}',
    onUndo: () {
      if (context.mounted) FileActions.undoUploads(context, ref, ids);
    },
  );
}

/// Queues [files] for upload into [folderId], the root when null, and lets
/// the intake forget them: the queue owns them now. The folder becomes the
/// most recent place shared files went. [choice] is the answer to the
/// question about mobile data when it was asked; without one, a big file
/// waits for Wi-Fi when the setting says big transfers do.
Future<List<String>> _enqueue(
  WidgetRef ref,
  List<SharedFile> files,
  String? folderId, {
  DataChoice? choice,
}) async {
  final intake = ref.read(shareIntakeProvider.notifier);
  final recent = ref.read(recentDestinationsProvider.notifier);
  final bigWait = ref.read(preferencesProvider).bigTransfersWifiOnly;
  final ids = await ref.read(transferQueueProvider.notifier).enqueueUploads([
    for (final file in files)
      UploadRequest(
        name: file.name,
        path: file.path,
        size: file.size,
        ownsSource: file.owned,
        wifiOnly:
            wifiOnlyFrom(choice) ??
            TransferPolicy.wifiOnlyFor(file.size, bigWaitForWifi: bigWait),
      ),
  ], folderId: folderId);
  await intake.clear();
  unawaited(recent.note(folderId));
  return ids;
}

class _ShareSheet extends ConsumerStatefulWidget {
  const _ShareSheet({required this.files});

  final List<SharedFile> files;

  @override
  ConsumerState<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends ConsumerState<_ShareSheet> {
  /// Where the files go: the last folder used, until the person picks.
  late FolderChoice _folder = _lastUsed(ref.read(recentDestinationsProvider));

  /// Whether the person picked [_folder] here, which the recent folders
  /// arriving late never overrule.
  bool _chosen = false;

  static FolderChoice _lastUsed(List<FolderChoice> recent) =>
      recent.firstOrNull ?? const FolderChoice(null, 'Files');

  void _choose(FolderChoice folder) => setState(() {
    _folder = folder;
    _chosen = true;
  });

  /// Something big on mobile data asks first whether to wait for Wi-Fi;
  /// dismissing that question leaves the sheet as it was.
  Future<void> _upload() async {
    final files = widget.files;
    final bytes = files.fold<int>(0, (sum, f) => sum + f.size);
    final what = files.length == 1
        ? files.single.name
        : Formatters.count(files.length, 'file');
    DataChoice? choice;
    if (TransferPolicy.shouldAsk(network: ref.read(networkStatusProvider), bytes: bytes)) {
      choice = await askAboutMobileData(
        context,
        bytes: bytes,
        doing: 'Uploading $what',
        files: files.length,
        nowLabel: 'Upload now',
      );
      if (choice == null || !mounted) return;
    }
    await _enqueue(ref, files, _folder.folderId, choice: choice);
    if (!mounted) return;
    Navigator.pop(context, true);
    final router = GoRouter.of(context);
    showSnack(
      context,
      choice == DataChoice.later ? 'Waiting for Wi-Fi to upload $what' : 'Uploading $what',
      actionLabel: 'View',
      onAction: () => router.push('/transfers'),
    );
  }

  @override
  Widget build(BuildContext context) {
    // The folders are looked up as the drive opens, which can be after a
    // share that opened the app has already brought the sheet up.
    ref.listen<List<FolderChoice>>(recentDestinationsProvider, (_, recent) {
      if (!_chosen) setState(() => _folder = _lastUsed(recent));
    });
    final files = widget.files;
    final bytes = files.fold<int>(0, (sum, f) => sum + f.size);
    final colors = context.colors;
    // The other recent folders: all but the last one used, which the tile
    // starts on. They stay put as one is picked, so the pick shows.
    final others = ref.watch(recentDestinationsProvider).skip(1).take(3).toList();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              files.length == 1
                  ? 'Save to Telegrive'
                  : 'Save ${Formatters.count(files.length, 'file')} to Telegrive',
              style: context.text.titleMedium,
            ),
            const SizedBox(height: 2),
            Text(
              Formatters.bytes(bytes),
              style: context.text.bodyMedium?.copyWith(fontFeatures: tabularFigures),
            ),
            const SizedBox(height: Space.m),
            for (final file in files.take(4))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.xs),
                child: Row(
                  children: [
                    FileIconTile(
                      style: FileStyle.forFile(file.name, FileKind.detect(fileName: file.name)),
                      size: 32,
                    ),
                    const SizedBox(width: Space.m),
                    Expanded(
                      child: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ),
            if (files.length > 4)
              Padding(
                padding: const EdgeInsets.only(top: Space.xs),
                child: Text(
                  'and ${Formatters.count(files.length - 4, 'more file')}',
                  style: context.text.bodySmall,
                ),
              ),
            const SizedBox(height: Space.m),
            Material(
              color: colors.surface2,
              borderRadius: BorderRadius.circular(Radii.control),
              child: ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.control)),
                leading: Icon(Icons.folder_outlined, color: colors.text2),
                title: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 150),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeOut,
                  layoutBuilder: (current, previous) => Stack(
                    alignment: AlignmentDirectional.centerStart,
                    children: [...previous, ?current],
                  ),
                  child: Text(
                    _folder.name,
                    key: ValueKey(_folder.folderId),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                subtitle: const Text('Folder'),
                trailing: const Text('Change'),
                onTap: () async {
                  final choice = await showFolderPicker(
                    context,
                    title: 'Save to',
                    actionLabel: 'Save to',
                    startIn: _folder.folderId,
                  );
                  if (choice != null) _choose(choice);
                },
              ),
            ),
            if (others.isNotEmpty) ...[
              const SizedBox(height: Space.m),
              Text('Recent', style: context.text.labelMedium),
              const SizedBox(height: Space.s),
              Wrap(
                spacing: Space.s,
                runSpacing: Space.s,
                children: [
                  for (final folder in others)
                    ChoiceChip(
                      label: Text(folder.name),
                      selected: folder.folderId == _folder.folderId,
                      showCheckmark: false,
                      onSelected: (selected) => _choose(
                        selected ? folder : _lastUsed(ref.read(recentDestinationsProvider)),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: Space.xl),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: Space.m),
                Expanded(
                  child: FilledButton(onPressed: _upload, child: const Text('Upload')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
