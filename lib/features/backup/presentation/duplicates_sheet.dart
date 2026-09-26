import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/format/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../drive/data/drive_repository.dart';
import '../../drive/domain/drive_models.dart';
import '../data/backup_controller.dart';

/// Photos backed up more than once.
final duplicateBackupsProvider = FutureProvider.autoDispose<DuplicateBackups>(
  (ref) => ref
      .watch(driveRepositoryProvider)
      .findDuplicateBackups(BackupController.rootFolder),
);

/// Finds photos that were backed up twice and, once the person agrees,
/// moves the extra copies to the trash.
Future<void> removeDuplicateBackups(BuildContext context, WidgetRef ref) async {
  final found = await ref.read(duplicateBackupsProvider.future);
  if (!context.mounted) return;
  if (found.isEmpty) {
    showSnack(context, 'No photos were backed up twice');
    return;
  }

  final count = found.extras.length;
  final confirmed = await showConfirmDialog(
    context,
    title: count == 0
        ? 'Tidy up ${BackupController.rootFolder}?'
        : 'Remove ${Formatters.count(count, 'duplicate')}?',
    message: [
      if (count > 0)
        '${Formatters.count(count, 'photo or video', 'photos and videos')} '
            '(${Formatters.bytes(found.bytes)}) were backed up more than once. The '
            'first copy of each stays; the others go to the Trash, where they '
            'can be restored for 30 days.',
      if (found.extraRoots.isNotEmpty)
        'A second ${BackupController.rootFolder} folder is merged into the first.',
    ].join('\n\n'),
    confirmLabel: count == 0 ? 'Tidy up' : 'Remove',
  );
  if (!confirmed || !context.mounted) return;

  final progress = ValueNotifier<(int, int)>((0, count));
  final navigator = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: ValueListenableBuilder(
          valueListenable: progress,
          builder: (context, value, _) {
            final (done, total) = value;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Removing duplicates', style: context.text.titleMedium),
                const SizedBox(height: Space.l),
                LinearProgressIndicator(value: total == 0 ? null : done / total, minHeight: 4),
                const SizedBox(height: Space.s),
                Text(
                  total == 0 ? 'Merging folders' : '${Formatters.number(done)} of ${Formatters.number(total)}',
                  style: context.text.bodySmall?.copyWith(fontFeatures: tabularFigures),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );

  try {
    await ref.read(driveRepositoryProvider).removeDuplicateBackups(
      found,
      onProgress: (done, total) => progress.value = (done, total),
    );
    ref.read(backupControllerProvider.notifier).forgetFolders();
    ref.invalidate(duplicateBackupsProvider);
    navigator.pop();
    if (context.mounted) {
      showSnack(
        context,
        count == 0
            ? 'Backup folders merged'
            : 'Moved ${Formatters.count(count, 'duplicate')} to Trash',
      );
    }
  } catch (e) {
    navigator.pop();
    if (context.mounted) showSnack(context, 'Couldn\'t finish: $e');
  } finally {
    progress.dispose();
  }
}

/// A row that only shows while there are duplicates to remove.
class DuplicateBackupsTile extends ConsumerWidget {
  const DuplicateBackupsTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final found = ref.watch(duplicateBackupsProvider).value;
    if (found == null || found.isEmpty) return const SizedBox.shrink();
    return ListGroup(
      children: [
        ListTile(
          leading: Icon(Icons.auto_delete_outlined, color: context.colors.text2),
          title: const Text('Remove duplicate backups'),
          subtitle: Text(
            found.extras.isEmpty
                ? 'Merge the second ${BackupController.rootFolder} folder into the first'
                : '${Formatters.count(found.extras.length, 'photo or video', 'photos and videos')} '
                      'backed up twice · ${Formatters.bytes(found.bytes)}',
          ),
          onTap: () => removeDuplicateBackups(context, ref),
        ),
      ],
    );
  }
}
