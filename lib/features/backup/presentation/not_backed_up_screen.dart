import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/format/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../files/presentation/file_actions.dart';
import '../data/backup_controller.dart';
import 'phone_asset_row.dart';

/// Every photo that hasn't reached the drive: the ones out of tries, each
/// with the reason and Retry or Skip, then how many still wait and for
/// what, which the Backup queue lists.
class NotBackedUpScreen extends ConsumerWidget {
  const NotBackedUpScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backup = ref.watch(backupControllerProvider);
    final controller = ref.read(backupControllerProvider.notifier);
    final failed = ref.watch(failedBackupAssetsProvider).value;
    final skipped = ref.watch(skippedBackupCountProvider).value ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Not backed up'),
        actions: [
          TextButton(
            onPressed: failed == null || failed.isEmpty
                ? null
                : () => FileActions.guarded(context, controller.retryFailed),
            child: const Text('Retry all'),
          ),
          const SizedBox(width: Space.s),
        ],
      ),
      body: failed == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: Space.x4),
              children: [
                if (failed.isEmpty && backup.remaining == 0)
                  const EmptyState(
                    title: 'Everything is backed up',
                    message: 'Photos that couldn\'t be backed up would be listed here, '
                        'with the reason.',
                    compact: true,
                  ),
                if (failed.isNotEmpty) ...[
                  SectionHeader('Didn\'t back up · ${Formatters.number(failed.length)}'),
                  ListGroup(
                    children: [
                      for (final record in failed)
                        PhoneAssetRow(
                          key: ValueKey(record.assetId),
                          assetId: record.assetId,
                          subtitle: record.reason ?? 'Something went wrong.',
                          subtitleLines: 2,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextButton(
                                style: _compact(context),
                                onPressed: () => FileActions.guarded(
                                  context,
                                  () => controller.retryOne(record.assetId),
                                ),
                                child: const Text('Retry'),
                              ),
                              TextButton(
                                style: _compact(context),
                                onPressed: () => _skip(context, controller, record.assetId),
                                child: const Text('Skip'),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
                if (backup.remaining > 0) ...[
                  SectionHeader('Waiting · ${Formatters.number(backup.remaining)}'),
                  ListGroup(
                    children: [
                      StatusLine(
                        icon: Icons.schedule_rounded,
                        text: '${Formatters.count(backup.remaining, 'item')} · ${_why(backup.phase)}',
                        detail: 'See what\'s left, and leave out what you don\'t want.',
                        onTap: () => context.push('/backup/queue'),
                      ),
                    ],
                  ),
                ],
                if (skipped > 0) ...[
                  const SizedBox(height: Space.xxl),
                  ListGroup(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          Space.gutter,
                          Space.s,
                          Space.s,
                          Space.s,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${Formatters.count(skipped, 'item')} skipped',
                                style: context.text.bodyMedium?.copyWith(
                                  fontFeatures: tabularFigures,
                                ),
                              ),
                            ),
                            TextButton(
                              style: _compact(context),
                              onPressed: () => FileActions.guarded(context, controller.unskipAll),
                              child: const Text('Bring back'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
    );
  }

  /// Sets [assetId] aside, offering Undo only when this tap did: a second
  /// tap, or one on a photo Retry took back, changes nothing.
  static Future<void> _skip(
    BuildContext context,
    BackupController controller,
    String assetId,
  ) async {
    var setAside = false;
    await FileActions.guarded(context, () async => setAside = await controller.skip(assetId));
    if (!setAside || !context.mounted) return;
    // Undo can be tapped after this screen has closed, so it reports
    // through the root navigator, which lasts as long as the app.
    final lasting = Navigator.of(context, rootNavigator: true).context;
    showUndoSnack(
      context,
      'Skipped 1 item',
      onUndo: () => FileActions.guarded(
        lasting,
        () => controller.unskip(assetId),
        success: 'Undone',
      ),
    );
  }

  /// What the waiting photos are waiting on, after their count.
  static String _why(BackupPhase phase) => switch (phase) {
    BackupPhase.waitingForWifi => 'waiting for Wi-Fi',
    BackupPhase.waitingForBudget => 'monthly data limit reached',
    BackupPhase.scanning || BackupPhase.uploading => 'backing up now',
    BackupPhase.needsPermission => 'allow photo access to continue',
    BackupPhase.off => 'backup is off',
    BackupPhase.waitingForDrive => 'backup is starting',
    BackupPhase.stopped => 'backup stopped',
    BackupPhase.upToDate => 'backing up soon',
  };
}

/// The small text buttons at the end of a row.
ButtonStyle _compact(BuildContext context) => TextButton.styleFrom(
  minimumSize: const Size(0, 32),
  padding: const EdgeInsets.symmetric(horizontal: Space.s),
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  disabledForegroundColor: context.colors.text3,
);
