import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/widgets/common.dart';
import '../../files/presentation/file_actions.dart';
import '../../files/presentation/file_tiles.dart';
import '../data/edit_outbox.dart';
import '../domain/drive_models.dart';

/// The changes made on this phone that are still to reach Telegram, in the
/// order they go, each saying what changed or why it couldn't be sent. A
/// tap offers to throw one away, which puts its item back the way Telegram
/// has it.
class WaitingChangesScreen extends ConsumerWidget {
  const WaitingChangesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final failed = ref.watch(editOutboxProvider.select((s) => s.failed));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Waiting changes'),
        actions: [
          if (failed > 0)
            TextButton(
              onPressed: ref.read(editOutboxProvider.notifier).retryFailed,
              child: const Text('Try again'),
            ),
          const SizedBox(width: Space.s),
        ],
      ),
      body: AsyncView(
        value: ref.watch(pendingEditsProvider),
        data: (changes) => changes.isEmpty
            ? const EmptyState(
                icon: Icons.cloud_done_outlined,
                title: 'Nothing waiting',
                message: 'Changes made without a connection wait here until they reach Telegram.',
              )
            : ListView(
                padding: const EdgeInsets.only(bottom: Space.x4),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Space.gutter,
                      Space.s,
                      Space.gutter,
                      Space.l,
                    ),
                    child: Text(
                      'These changes are on this phone. They go to Telegram in the order you '
                      'made them when the connection is back.',
                      style: context.text.bodyMedium,
                    ),
                  ),
                  ListGroup(children: [for (final change in changes) _ChangeRow(change: change)]),
                ],
              ),
      ),
    );
  }
}

class _ChangeRow extends ConsumerWidget {
  const _ChangeRow({required this.change});

  final PendingEditView change;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final error = change.error;
    final subtitle = error == null ? change.description : 'Couldn\'t send: $error';
    final subtitleColor = error == null ? null : colors.danger;
    void discard() => _discard(context, ref);
    if (change.file case final file?) {
      return FileListTile(
        file: file,
        subtitle: subtitle,
        subtitleColor: subtitleColor,
        onTap: discard,
      );
    }
    if (change.folder case final folder?) {
      return FolderListTile(
        folder: folder,
        subtitle: subtitle,
        subtitleColor: subtitleColor,
        onTap: discard,
      );
    }
    return ListTile(
      leading: SizedBox.square(
        dimension: 44,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surface2,
            borderRadius: BorderRadius.circular(Radii.thumb),
          ),
          child: Icon(Icons.photo_album_outlined, color: colors.text2),
        ),
      ),
      title: Text(change.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: subtitleColor == null ? null : TextStyle(color: subtitleColor),
      ),
      onTap: discard,
    );
  }

  Future<void> _discard(BuildContext context, WidgetRef ref) async {
    final outbox = ref.read(editOutboxProvider.notifier);
    final confirmed = await showConfirmDialog(
      context,
      title: 'Discard this change?',
      message: '"${change.name}" goes back to how it is in Telegram.',
      confirmLabel: 'Discard',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    await FileActions.guarded(context, () => outbox.discard(change.target, change.id));
  }
}
