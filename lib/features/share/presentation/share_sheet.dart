import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/files/file_kind.dart';
import '../../../core/format/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/file_visuals.dart';
import '../../../app/theme/file_style.dart';
import '../../files/presentation/folder_picker.dart';
import '../../transfers/data/transfer_queue.dart';
import '../data/share_intake.dart';

/// Asks where files shared from another app should go, then uploads them.
Future<void> showShareSheet(BuildContext context, WidgetRef ref) async {
  final files = ref.read(shareIntakeProvider);
  if (files.isEmpty) return;
  final uploaded = await showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    isDismissible: false,
    builder: (_) => _ShareSheet(files: files),
  );
  if (uploaded != true) await ref.read(shareIntakeProvider.notifier).clear(discard: true);
}

class _ShareSheet extends ConsumerStatefulWidget {
  const _ShareSheet({required this.files});

  final List<SharedFile> files;

  @override
  ConsumerState<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends ConsumerState<_ShareSheet> {
  FolderChoice _folder = const FolderChoice(null, 'My Drive');

  Future<void> _upload() async {
    final files = widget.files;
    await ref.read(transferQueueProvider.notifier).enqueueUploads([
      for (final file in files)
        UploadRequest(name: file.name, path: file.path, size: file.size, ownsSource: file.owned),
    ], folderId: _folder.folderId);
    await ref.read(shareIntakeProvider.notifier).clear();
    if (!mounted) return;
    Navigator.pop(context, true);
    final router = GoRouter.of(context);
    showSnack(
      context,
      files.length == 1
          ? 'Uploading ${files.single.name}'
          : 'Uploading ${Formatters.count(files.length, 'file')}',
      actionLabel: 'View',
      onAction: () => router.push('/transfers'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final files = widget.files;
    final bytes = files.fold<int>(0, (sum, f) => sum + f.size);
    final colors = context.colors;

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
                title: Text(_folder.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: const Text('Folder'),
                trailing: const Text('Change'),
                onTap: () async {
                  final choice = await showFolderPicker(context, title: 'Save to');
                  if (choice != null) setState(() => _folder = choice);
                },
              ),
            ),
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
