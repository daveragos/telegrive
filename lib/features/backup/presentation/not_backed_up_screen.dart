import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/file_style.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/files/file_kind.dart';
import '../../../core/format/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/file_visuals.dart';
import '../../files/presentation/file_actions.dart';
import '../data/backup_controller.dart';
import '../data/local_media.dart';

/// Every photo that hasn't reached the drive: the ones out of tries, each
/// with the reason and Retry or Skip, then the newest of those still
/// waiting, which Back up now sends up ahead of the rest.
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
                        _AssetRow(
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
                if (backup.remaining > 0) ..._waiting(context, backup, controller),
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

  List<Widget> _waiting(
    BuildContext context,
    BackupState backup,
    BackupController controller,
  ) {
    // While backup is off or held up (no Wi-Fi, the monthly data limit, no
    // photo access, the drive still opening), nothing goes up, so neither
    // can one photo first.
    final canStart = switch (backup.phase) {
      BackupPhase.waitingForWifi ||
      BackupPhase.waitingForBudget ||
      BackupPhase.needsPermission ||
      BackupPhase.off ||
      BackupPhase.waitingForDrive => false,
      _ => true,
    };
    final more = backup.remaining - backup.waiting.length;
    return [
      SectionHeader('Waiting · ${Formatters.number(backup.remaining)}'),
      ListGroup(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.gutter, vertical: Space.m),
            child: Text(
              '${Formatters.count(backup.remaining, 'item')} · ${_why(backup.phase)}',
              style: context.text.bodyMedium?.copyWith(fontFeatures: tabularFigures),
            ),
          ),
          for (final asset in backup.waiting)
            _AssetRow(
              key: ValueKey(asset.assetId),
              assetId: asset.assetId,
              subtitle: '${asset.folder} · ${Formatters.date(asset.takenAt)}',
              trailing: _BackUpNowButton(
                onPressed: canStart
                    ? () => FileActions.guarded(
                        context,
                        () async => controller.backUpNow(asset.assetId),
                      )
                    : null,
              ),
            ),
        ],
      ),
      if (backup.waiting.isNotEmpty && more > 0)
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, Space.s, Space.gutter, 0),
          child: Text(
            'and ${Formatters.number(more)} more, newest first.',
            style: context.text.bodySmall?.copyWith(fontFeatures: tabularFigures),
          ),
        ),
    ];
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

/// A phone photo as a row: its thumbnail, its file name, a second line and
/// the row's buttons. A photo the phone no longer has shows the kind glyph.
class _AssetRow extends ConsumerWidget {
  const _AssetRow({
    super.key,
    required this.assetId,
    required this.subtitle,
    required this.trailing,
    this.subtitleLines = 1,
  });

  final String assetId;
  final String subtitle;
  final int subtitleLines;
  final Widget trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thumbnail = ref.watch(assetThumbnailProvider(assetId)).value;
    final title = ref.watch(assetTitleProvider(assetId));
    final name = title.isLoading ? '' : (title.value ?? 'Photo');
    final kind = FileKind.detect(fileName: name) == FileKind.video
        ? FileKind.video
        : FileKind.image;

    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.s + 2, Space.s, Space.s + 2),
      child: Row(
        children: [
          if (thumbnail != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(Radii.thumb),
              child: Image.memory(
                thumbnail,
                width: 44,
                height: 44,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              ),
            )
          else
            FileIconTile(style: FileStyle.forKind(kind)),
          const SizedBox(width: Space.l),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: subtitleLines,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodySmall?.copyWith(fontFeatures: tabularFigures),
                ),
              ],
            ),
          ),
          const SizedBox(width: Space.s),
          trailing,
        ],
      ),
    );
  }
}

/// Back up now, which reads Queued once tapped, for as long as its row is
/// in the list.
class _BackUpNowButton extends StatefulWidget {
  const _BackUpNowButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  State<_BackUpNowButton> createState() => _BackUpNowButtonState();
}

class _BackUpNowButtonState extends State<_BackUpNowButton> {
  bool _queued = false;

  @override
  Widget build(BuildContext context) {
    final onPressed = widget.onPressed;
    return TextButton(
      style: _compact(context),
      onPressed: _queued || onPressed == null
          ? null
          : () {
              setState(() => _queued = true);
              onPressed();
            },
      child: Text(_queued ? 'Queued' : 'Back up now'),
    );
  }
}
