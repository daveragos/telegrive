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
import '../../backup/presentation/free_up_space_sheet.dart';
import '../../drive/data/drive_repository.dart';
import '../../drive/domain/drive_models.dart';
import '../../files/presentation/file_actions.dart';
import '../../files/presentation/folder_picker.dart';
import '../../transfers/data/transfer_policy.dart';
import '../../transfers/data/transfer_queue.dart';
import '../../transfers/presentation/mobile_data_prompt.dart';
import '../data/recent_destinations.dart';
import '../data/share_intake.dart';

/// How the share sheet was closed.
enum _Closed { uploaded, cancelled, freeUpSpace }

/// Asks where files shared from another app should go, then uploads them.
/// Files shared to one of the drive's folders in Android's share sheet go
/// straight into it with no question, as long as the drive still shows
/// that folder; otherwise the sheet asks, so nothing is put into Trash. A
/// file the phone had no room to take always brings the sheet up, which
/// says so, starting on the folder they were shared to.
Future<void> showShareSheet(BuildContext context, WidgetRef ref) async {
  final files = ref.read(shareIntakeProvider);
  if (files.isEmpty) return;
  final targets = files.map((f) => f.folderId).toSet();
  FolderChoice? target;
  if (targets.length == 1 && targets.single != null) {
    final folder = await ref
        .read(driveRepositoryProvider)
        .shownFolder(targets.single!);
    if (folder != null && context.mounted && !files.any((f) => f.tooBig)) {
      await _uploadStraight(context, ref, files, folder);
      return;
    }
    if (folder != null) target = FolderChoice(folder.id, folder.name);
  }
  if (!context.mounted) return;
  // A folder trashed on another device can reach the index through a live
  // update, which the recent folders do not follow, so they are looked up
  // again before the sheet starts on the first of them.
  await ref.read(recentDestinationsProvider.notifier).refresh();
  if (!context.mounted) return;
  final closed = await showModalBottomSheet<_Closed>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    isDismissible: false,
    builder: (_) => _ShareSheet(files: files, folder: target),
  );
  if (closed != _Closed.uploaded) {
    await ref.read(shareIntakeProvider.notifier).clear(discard: true);
  }
  if (closed == _Closed.freeUpSpace && context.mounted) {
    await showFreeUpSpace(context, ref);
  }
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
            : await FileActions.renamedOnDisk(file.path!, names[index]),
        name: names[index],
        size: file.size,
        owned: file.owned,
        folderId: file.folderId,
      ),
  ];
  final ids = await _enqueue(ref, _requests(ref, named), folder.id);
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

/// The uploads of [files], which all fit on the phone. [choice] is the
/// answer to the question about mobile data when it was asked; without one,
/// a big file waits for Wi-Fi when the setting says big transfers do.
List<UploadRequest> _requests(
  WidgetRef ref,
  List<SharedFile> files, {
  DataChoice? choice,
}) {
  final bigWait = ref.read(preferencesProvider).bigTransfersWifiOnly;
  return [
    for (final file in files)
      UploadRequest(
        name: file.name,
        path: file.path!,
        size: file.size,
        ownsSource: file.owned,
        wifiOnly:
            wifiOnlyFrom(choice) ??
            TransferPolicy.wifiOnlyFor(file.size, bigWaitForWifi: bigWait),
      ),
  ];
}

/// Queues [requests] for upload into [folderId], the root when null, and
/// lets the intake forget the shared files, those that didn't fit and
/// those skipped included: the queue owns the rest now. The folder becomes
/// the most recent place shared files went.
Future<List<String>> _enqueue(
  WidgetRef ref,
  List<UploadRequest> requests,
  String? folderId,
) async {
  final intake = ref.read(shareIntakeProvider.notifier);
  final recent = ref.read(recentDestinationsProvider.notifier);
  final ids = await ref
      .read(transferQueueProvider.notifier)
      .enqueueUploads(requests, folderId: folderId);
  await intake.clear();
  unawaited(recent.note(folderId));
  return ids;
}

class _ShareSheet extends ConsumerStatefulWidget {
  const _ShareSheet({required this.files, this.folder});

  final List<SharedFile> files;

  /// The folder they were shared to, when that is where the sheet starts.
  final FolderChoice? folder;

  @override
  ConsumerState<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends ConsumerState<_ShareSheet> {
  /// Where the files go: the folder they were shared to, or the last folder
  /// used, until the person picks.
  late FolderChoice _folder =
      widget.folder ?? _lastUsed(ref.read(recentDestinationsProvider));

  /// Whether [_folder] was picked here or shared to, which the recent
  /// folders arriving late never overrule.
  late bool _chosen = widget.folder != null;

  /// The files that can be saved, and those the phone had no room to take.
  late final List<SharedFile> _fits = [
    for (final file in widget.files)
      if (!file.tooBig) file,
  ];
  late final List<SharedFile> _tooBig = [
    for (final file in widget.files)
      if (file.tooBig) file,
  ];

  static FolderChoice _lastUsed(List<FolderChoice> recent) =>
      recent.firstOrNull ?? const FolderChoice(null, 'Files');

  void _choose(FolderChoice folder) => setState(() {
    _folder = folder;
    _chosen = true;
  });

  /// Something big on mobile data asks first whether to wait for Wi-Fi;
  /// dismissing that question leaves the sheet as it was. A file named like
  /// one already in the folder then asks Replace, Keep both or Skip; when
  /// every file is skipped nothing goes up and the sheet closes.
  Future<void> _upload() async {
    final files = _fits;
    final bytes = files.fold<int>(0, (sum, f) => sum + f.size);
    final what = files.length == 1
        ? files.single.name
        : Formatters.count(files.length, 'file');
    DataChoice? choice;
    if (TransferPolicy.shouldAsk(
      network: ref.read(networkStatusProvider),
      bytes: bytes,
    )) {
      choice = await askAboutMobileData(
        context,
        bytes: bytes,
        doing: 'Uploading $what',
        files: files.length,
        nowLabel: 'Upload now',
      );
      if (choice == null || !mounted) return;
    }
    final folderId = _folder.folderId;
    final resolved = await FileActions.resolveUploadClashes(
      context,
      ref,
      _requests(ref, files, choice: choice),
      folderId: folderId,
    );
    if (!mounted) return;
    if (resolved.isEmpty) {
      await ref.read(shareIntakeProvider.notifier).clear(discard: true);
      if (!mounted) return;
      Navigator.pop(context, _Closed.uploaded);
      showSnack(context, 'Nothing to upload');
      return;
    }
    await _enqueue(ref, resolved, folderId);
    if (!mounted) return;
    Navigator.pop(context, _Closed.uploaded);
    final going = resolved.length == 1
        ? resolved.single.name
        : Formatters.count(resolved.length, 'file');
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

  @override
  Widget build(BuildContext context) {
    // The folders are looked up as the drive opens, which can be after a
    // share that opened the app has already brought the sheet up.
    ref.listen<List<FolderChoice>>(recentDestinationsProvider, (_, recent) {
      if (!_chosen) setState(() => _folder = _lastUsed(recent));
    });
    final files = _fits;
    final bytes = files.fold<int>(0, (sum, f) => sum + f.size);
    final colors = context.colors;
    // The other recent folders: all but the last one used, which the tile
    // starts on. They stay put as one is picked, so the pick shows.
    final others = ref
        .watch(recentDestinationsProvider)
        .skip(1)
        .take(3)
        .toList();
    // Those that didn't fit first, so the sheet always shows why.
    final listed = [..._tooBig, ...files];
    final noneFit = files.isEmpty;

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
            if (noneFit)
              Text(
                _tooBig.length == 1
                    ? 'Not enough space on this phone to take this file.'
                    : 'Not enough space on this phone to take these files.',
                style: context.text.titleMedium,
              )
            else ...[
              Text(
                files.length == 1
                    ? 'Save to Telegrive'
                    : 'Save ${Formatters.count(files.length, 'file')} to Telegrive',
                style: context.text.titleMedium,
              ),
              const SizedBox(height: 2),
              Text(
                Formatters.bytes(bytes),
                style: context.text.bodyMedium?.copyWith(
                  fontFeatures: tabularFigures,
                ),
              ),
            ],
            const SizedBox(height: Space.m),
            for (final file in listed.take(4))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.xs),
                child: Row(
                  children: [
                    FileIconTile(
                      style: FileStyle.forFile(
                        file.name,
                        FileKind.detect(fileName: file.name),
                      ),
                      size: 32,
                    ),
                    const SizedBox(width: Space.m),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            file.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (file.tooBig)
                            Text(
                              'Not enough space to take this · needs '
                              '${Formatters.bytes(file.size)}, '
                              '${Formatters.bytes(file.free ?? 0)} free',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: context.text.bodySmall?.copyWith(
                                color: colors.danger,
                                fontFeatures: tabularFigures,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            if (listed.length > 4)
              Padding(
                padding: const EdgeInsets.only(top: Space.xs),
                child: Text(
                  'and ${Formatters.count(listed.length - 4, 'more file')}',
                  style: context.text.bodySmall,
                ),
              ),
            if (noneFit)
              const SizedBox(height: Space.xl)
            else ...[
              const SizedBox(height: Space.m),
              Material(
                color: colors.surface2,
                borderRadius: BorderRadius.circular(Radii.control),
                child: ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Radii.control),
                  ),
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
                          selected
                              ? folder
                              : _lastUsed(ref.read(recentDestinationsProvider)),
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: Space.xl),
            ],
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, _Closed.cancelled),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: Space.m),
                Expanded(
                  child: noneFit
                      ? FilledButton(
                          onPressed: () =>
                              Navigator.pop(context, _Closed.freeUpSpace),
                          child: const Text('Free up space'),
                        )
                      : FilledButton(
                          onPressed: _upload,
                          child: const Text('Upload'),
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
