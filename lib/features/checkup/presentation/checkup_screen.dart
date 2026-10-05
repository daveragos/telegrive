import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/format/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../backup/data/backup_controller.dart';
import '../../drive/data/drive_repository.dart';
import '../../drive/data/drive_session.dart';
import '../../drive/data/drive_sync.dart';
import '../../files/data/bulk_edits.dart';
import '../../files/presentation/file_actions.dart';
import '../data/drive_checkup.dart';

/// Looks the drive over and says, one sentence per check, whether the
/// channel, the index, split files, photo backup, the trash and the account
/// are as they should be, with a fix beside each that has one.
class CheckupScreen extends ConsumerWidget {
  const CheckupScreen({super.key});

  /// How many incomplete split files get a row of their own.
  static const int _splitRowsShown = 5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(driveCheckupProvider);
    final sync = ref.watch(driveSyncProvider);
    final running = report.isLoading;
    final value = report.value;
    final figures = context.text.bodySmall?.copyWith(fontFeatures: tabularFigures);

    return Scaffold(
      appBar: AppBar(title: const Text('Check my drive')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: Space.x4),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.gutter, Space.s, Space.gutter, Space.l),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  running
                      ? 'Checking…'
                      : value == null
                      ? 'Not checked yet'
                      : 'Checked ${_when(value.at)}',
                  style: figures,
                ),
                if (running) ...[
                  const SizedBox(height: Space.s),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: const LinearProgressIndicator(minHeight: 4),
                  ),
                ],
              ],
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 150),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeOut,
            child: switch (report) {
              AsyncError() when value == null => Padding(
                key: const ValueKey('failed'),
                padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
                child: Text(
                  'The check-up didn\'t finish. Check again in a moment.',
                  style: context.text.bodyMedium,
                ),
              ),
              _ when value != null => KeyedSubtree(
                key: ValueKey(value.at),
                child: ListGroup(
                  children: [
                    for (final finding in value.findings) ..._rows(context, ref, finding, sync),
                  ],
                ),
              ),
              _ => const SizedBox.shrink(key: ValueKey('empty')),
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.gutter, Space.xxl, Space.gutter, 0),
            child: OutlinedButton(
              onPressed: running ? null : () => ref.invalidate(driveCheckupProvider),
              child: const Text('Check again'),
            ),
          ),
        ],
      ),
    );
  }

  /// `today at 7:32 PM`, or the date.
  static String _when(DateTime at) {
    final now = DateTime.now();
    final sameDay = at.year == now.year && at.month == now.month && at.day == now.day;
    return sameDay ? 'today at ${Formatters.date(at)}' : 'on ${Formatters.date(at)}';
  }

  List<Widget> _rows(BuildContext context, WidgetRef ref, CheckFinding finding, SyncState sync) {
    final colors = context.colors;
    final checkup = ref.read(driveCheckupProvider.notifier);
    Color tint(CheckSeverity severity) => switch (severity) {
      CheckSeverity.fine => colors.success,
      CheckSeverity.action => colors.danger,
      CheckSeverity.neutral => colors.text2,
    };
    IconData glyph(CheckSeverity severity) => switch (severity) {
      CheckSeverity.fine => Icons.check_circle_outline_rounded,
      CheckSeverity.action => Icons.error_outline_rounded,
      CheckSeverity.neutral => Icons.info_outline_rounded,
    };
    Widget row(
      CheckSeverity severity,
      String title, {
      String? detail,
      List<Widget> fixes = const [],
      VoidCallback? onTap,
      double? progress,
    }) => _CheckRow(
      icon: glyph(severity),
      color: tint(severity),
      title: title,
      detail: detail,
      fixes: fixes,
      onTap: onTap,
      progress: progress,
    );
    Widget fix(String label, Future<void> Function() action, {String? success}) => TextButton(
      onPressed: () => FileActions.guarded(context, action, success: success),
      child: Text(label),
    );

    switch (finding) {
      case ChannelFinding():
        final title = ref.read(driveSessionProvider)?.channelTitle ?? 'Telegrive';
        if (finding.error != null) {
          return [
            row(
              finding.severity,
              'Telegrive can\'t open your drive channel',
              detail: finding.error,
            ),
          ];
        }
        if (finding.autoDeleteSeconds > 0) {
          return [
            row(
              finding.severity,
              'Messages in your drive delete themselves after '
              '${Formatters.period(Duration(seconds: finding.autoDeleteSeconds))}',
              detail: 'Telegram\'s auto-delete timer is on for this channel.',
              fixes: [fix('Turn off', checkup.turnOffAutoDelete)],
            ),
          ];
        }
        if (finding.username case final name?) {
          return [
            row(
              finding.severity,
              'Your drive channel is public',
              detail: 'Anyone with t.me/$name can see your files.',
              fixes: [
                if (finding.supergroupId case final id?)
                  fix('Make private', () => checkup.makePrivate(id)),
              ],
            ),
          ];
        }
        return [
          row(
            finding.severity,
            'Your drive channel is private and yours',
            detail: '$title · created by you',
          ),
        ];

      case IndexFinding():
        Widget readAgain() => fix('Read everything again', () async {
          await ref.read(driveSyncProvider.notifier).rebuildIndex();
          ref.invalidate(driveCheckupProvider);
        });
        if (sync.running) {
          return [
            row(
              CheckSeverity.neutral,
              'Reading the channel · ${Formatters.count(sync.scanned, 'item')}',
              progress: -1,
            ),
          ];
        }
        if (finding.error case final error?) {
          return [
            row(
              finding.severity,
              'Reading the channel stopped',
              detail: error,
              fixes: [readAgain()],
            ),
          ];
        }
        final lastFull = finding.lastFull;
        if (lastFull == null || finding.isStale) {
          return [
            row(
              finding.severity,
              lastFull == null
                  ? 'Not read in full yet'
                  : 'Not read in full since ${Formatters.date(lastFull)}',
              fixes: [readAgain()],
            ),
          ];
        }
        return [
          row(
            finding.severity,
            'Your index was checked against the channel',
            detail: 'Read in full ${_when(lastFull)}',
          ),
        ];

      case SplitFinding():
        if (finding.incomplete.isEmpty) {
          return [
            row(
              finding.severity,
              finding.total == 1
                  ? 'Your split file has every part'
                  : 'All ${Formatters.count(finding.total, 'split file')} have every part',
            ),
          ];
        }
        final shown = finding.incomplete.take(_splitRowsShown).toList();
        final rest = finding.incomplete.length - shown.length;
        return [
          for (final (:file, :missingParts) in shown)
            row(
              finding.severity,
              '${file.name} is missing ${_parts(missingParts)} of ${file.partCount}',
              detail: _otherParts(file.partCount - missingParts.length),
              onTap: () => FileActions.showInTelegram(context, ref, file),
              fixes: [
                TextButton(
                  onPressed: () async {
                    final confirmed = await showConfirmDialog(
                      context,
                      title: 'Delete the parts of "${file.name}"?',
                      message:
                          'The ${Formatters.count(file.partCount - missingParts.length, 'part')} '
                          'in your channel are removed. Without ${_parts(missingParts)} the '
                          'file can\'t be opened anyway.',
                      confirmLabel: 'Delete',
                      destructive: true,
                    );
                    if (confirmed && context.mounted) {
                      await FileActions.guarded(context, () => checkup.deleteParts(file.id));
                    }
                  },
                  child: const Text('Delete parts'),
                ),
              ],
            ),
          if (rest > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.gutter + _CheckRow.iconColumn,
                Space.s,
                Space.gutter,
                Space.m,
              ),
              child: Text('and ${Formatters.number(rest)} more', style: context.text.bodySmall),
            ),
        ];

      case CaptionFinding():
        return [
          row(
            finding.severity,
            '${Formatters.count(finding.older, 'message')} in your channel '
            '${finding.older == 1 ? 'is' : 'are'} in the older layout',
            detail:
                'Updating writes each again with the name in bold and the folder as a '
                'tag to tap in Telegram, in about ${Formatters.inWords(finding.takes)}. '
                'Telegram marks each one edited. Nothing in your drive changes.',
            fixes: [
              TextButton(
                onPressed: () => _updateCaptions(context, ref),
                child: const Text('Update'),
              ),
            ],
          ),
        ];

      case BackupFinding():
        final backup = ref.read(backupControllerProvider.notifier);
        if (!finding.enabled) {
          return [
            row(
              finding.severity,
              'Photo backup is off',
              fixes: [
                TextButton(onPressed: () => context.push('/backup'), child: const Text('Turn on')),
              ],
            ),
          ];
        }
        if (finding.missingCount > 0) {
          final one = finding.missingCount == 1;
          return [
            row(
              finding.severity,
              '${Formatters.count(finding.missingCount, 'photo')} from this phone '
              '${one ? 'is' : 'are'} no longer in your drive',
              detail:
                  '${one ? 'It was' : 'They were'} removed from the channel outside this phone.',
              fixes: [
                fix('Back up again', () async {
                  await backup.retryMissing();
                  ref.invalidate(driveCheckupProvider);
                }),
                fix('Leave ${one ? 'it' : 'them'} out', () async {
                  await backup.leaveOutMissing();
                  ref.invalidate(driveCheckupProvider);
                }),
              ],
            ),
          ];
        }
        if (finding.cannotCheck) {
          return [
            row(
              finding.severity,
              'Backup can\'t be checked yet',
              detail: 'The index on this phone looks incomplete. Read everything again first.',
            ),
          ];
        }
        if (finding.verifiedCount == 0) {
          return [row(finding.severity, 'No photos from this phone are backed up yet')];
        }
        if (finding.notCheckedYet) {
          return [
            row(
              finding.severity,
              'Backup hasn\'t been checked yet',
              detail: 'It is checked after the next full read of the channel.',
            ),
          ];
        }
        final checkedAt = finding.verifiedAt;
        return [
          row(
            finding.severity,
            'All ${Formatters.count(finding.verifiedCount, 'backed-up photo')} are in your drive',
            detail: 'From this phone${checkedAt == null ? '' : ' · checked ${_when(checkedAt)}'}',
          ),
        ];

      case TrashFinding():
        if (finding.dueSoon > 0) {
          return [
            row(
              finding.severity,
              '${Formatters.count(finding.dueSoon, 'item')} in Trash '
              '${finding.dueSoon == 1 ? 'goes' : 'go'} for good in the next '
              '${Formatters.count(TrashFinding.dueWithin.inDays, 'day')}',
              detail: 'Restore anything you still need.',
              fixes: [
                TextButton(
                  onPressed: () => context.push('/trash'),
                  child: const Text('Open Trash'),
                ),
              ],
            ),
          ];
        }
        return [
          row(
            finding.severity,
            '${Formatters.count(finding.count, 'item')} in Trash',
            detail: 'Each goes for good 30 days after it was deleted.',
          ),
        ];

      case TwoStepFinding():
        return [
          switch (finding.hasPassword) {
            true => row(
              finding.severity,
              'Two-step verification is on',
              detail: 'Signing in on a new phone needs your password.',
            ),
            false => row(
              finding.severity,
              'Two-step verification is off',
              detail: 'Anyone who gets your SIM could sign in and see your drive.',
              fixes: [
                TextButton(
                  onPressed: () => _openTelegramSettings(context),
                  child: const Text('Open Telegram'),
                ),
              ],
            ),
            null => row(
              finding.severity,
              'Two-step verification couldn\'t be checked',
              detail: 'Telegram didn\'t answer.',
            ),
          },
        ];

      case AccountTtlFinding():
        if (finding.days case final days?) {
          return [
            row(
              finding.severity,
              'If you stop using Telegram for ${Formatters.period(Duration(days: days))}, '
              'your account and drive are deleted',
              detail: 'Opening Telegram or Telegrive counts as activity.',
              fixes: [
                TextButton(
                  onPressed: () => showAccountTtlSheet(context, ref, days),
                  child: const Text('Change'),
                ),
              ],
            ),
          ];
        }
        return [
          row(
            finding.severity,
            'The inactive-account timer couldn\'t be checked',
            detail: 'Telegram didn\'t answer.',
          ),
        ];
    }
  }

  /// Writes every message still in the older layout again, one every
  /// [DriveCheckup.captionPace], in the status line above the bar, where
  /// Stop ends it. It goes on after this screen is left; what is done stays
  /// done, and the check-up then counts what is left.
  static Future<void> _updateCaptions(BuildContext context, WidgetRef ref) async {
    final edits = ref.read(bulkEditsProvider.notifier);
    final repository = ref.read(driveRepositoryProvider);
    final older = await repository.olderCaptions();
    if (!context.mounted || older.isEmpty) return;
    await FileActions.runBulk(
      context,
      edits,
      label: 'Updating ${Formatters.count(older.length, 'message')}',
      icon: Icons.text_fields_rounded,
      items: older,
      apply: (caption) async {
        await repository.rewriteInCurrentLayout(caption);
        await Future<void>.delayed(DriveCheckup.captionPace);
      },
      success: 'Every message in your channel is in the current layout',
    );
    if (context.mounted) ref.invalidate(driveCheckupProvider);
  }

  /// `part 7`, `parts 7 and 9`, `parts 3, 7 and 9`.
  static String _parts(List<int> parts) {
    if (parts.length == 1) return 'part ${parts.single}';
    final head = parts.take(parts.length - 1).join(', ');
    return 'parts $head and ${parts.last}';
  }

  static String _otherParts(int count) => count == 1
      ? 'The other part is in your channel.'
      : 'The other ${Formatters.count(count, 'part')} are in your channel.';

  /// Telegram's settings, where two-step verification is set up; the exact
  /// page has no link, so the way there is spelt out when the app can't be
  /// opened.
  static Future<void> _openTelegramSettings(BuildContext context) async {
    var opened = false;
    try {
      opened = await launchUrl(Uri.parse('tg://settings'), mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!opened && context.mounted) {
      showSnack(
        context,
        'In Telegram, open Settings › Privacy and Security › Two-Step Verification.',
      );
    }
  }
}

/// Picks after how long without activity Telegram deletes the account, and
/// applies the choice at once.
Future<void> showAccountTtlSheet(BuildContext context, WidgetRef ref, int currentDays) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    builder: (sheet) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Delete account if away for', style: sheet.text.titleMedium),
            const SizedBox(height: Space.s),
            Text(
              'Telegram deletes an account that hasn\'t been used for this long, '
              'and your drive goes with it.',
              style: sheet.text.bodyMedium,
            ),
            const SizedBox(height: Space.m),
            RadioGroup<int>(
              groupValue: currentDays,
              onChanged: (days) {
                Navigator.pop(sheet);
                if (days == null || days == currentDays) return;
                // The timer's provider is held until Telegram has answered,
                // so the new value lands in it wherever the sheet was opened
                // from, not only where a screen already watches it.
                final keep = ref.listenManual(accountTtlProvider, (_, _) {});
                FileActions.guarded(
                  context,
                  () => ref.read(accountTtlProvider.notifier).set(days),
                  success: 'Set to ${Formatters.period(Duration(days: days))}',
                ).whenComplete(keep.close);
              },
              child: Column(
                children: [
                  for (final days in accountTtlChoices)
                    RadioListTile<int>(
                      value: days,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        Formatters.period(Duration(days: days)),
                        style: sheet.text.bodyLarge?.copyWith(fontFeatures: tabularFigures),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// One check: a glyph that says how it went, a sentence, the detail under
/// it, and the fixes. One fix sits at the end of the row; more go under
/// the text, so neither is squeezed.
class _CheckRow extends StatelessWidget {
  const _CheckRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.detail,
    required this.fixes,
    required this.onTap,
    required this.progress,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String? detail;
  final List<Widget> fixes;
  final VoidCallback? onTap;
  final double? progress;

  /// The glyph's size.
  static const double iconSize = 20;

  /// What the glyph and the gap after it take, so what sits under the text
  /// starts where the text does.
  static const double iconColumn = iconSize + Space.m;

  @override
  Widget build(BuildContext context) {
    final single = fixes.length == 1;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.gutter, Space.m, Space.m, Space.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(icon, size: iconSize, color: color),
                ),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: context.text.titleSmall),
                      if (detail case final detail? when detail.isNotEmpty)
                        Text(
                          detail,
                          style: context.text.bodySmall?.copyWith(fontFeatures: tabularFigures),
                        ),
                    ],
                  ),
                ),
                if (single) ...[const SizedBox(width: Space.s), fixes.single],
              ],
            ),
            if (progress != null) ...[
              const SizedBox(height: Space.s),
              Padding(
                padding: const EdgeInsets.only(left: iconColumn, right: Space.s),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: progress! < 0 ? null : progress,
                    minHeight: 4,
                  ),
                ),
              ),
            ],
            if (fixes.length > 1)
              // A text button's own inset makes up the rest of the column.
              Padding(
                padding: const EdgeInsets.only(left: iconColumn - Space.s, top: Space.xs),
                child: Wrap(spacing: Space.s, children: fixes),
              ),
          ],
        ),
      ),
    );
  }
}
