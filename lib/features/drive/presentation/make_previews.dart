import 'package:flutter/material.dart';

import '../../../core/format/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../files/data/bulk_edits.dart';
import '../data/drive_repository.dart';

/// Asks before making previews for [without] files, then runs [make] and
/// says how it went.
Future<void> confirmMakePreviews(
  BuildContext context,
  ({int count, int bytes}) without,
  Future<({BulkOutcome outcome, int noPicture})> Function() make,
) async {
  final confirmed = await showConfirmDialog(
    context,
    title: 'Make ${Formatters.count(without.count, 'preview')}?',
    message:
        'Telegram takes a preview only with its file, so each of these is fetched and sent '
        'again with one, smallest first: ${Formatters.bytes(without.bytes)} down and the same up. '
        'Keep the phone on Wi-Fi. You can stop at any point.',
    confirmLabel: 'Make previews',
  );
  if (!confirmed || !context.mounted) return;
  final BulkOutcome outcome;
  final int noPicture;
  try {
    (:outcome, :noPicture) = await make();
  } on DriveException catch (e) {
    if (context.mounted) showSnack(context, e.message);
    return;
  }
  if (!context.mounted) return;
  final made = Formatters.count(outcome.done - noPicture, 'preview');
  final missed = noPicture == 0 ? '' : '. ${Formatters.count(noPicture, 'file')} made no picture';
  showSnack(
    context,
    outcome.complete
        ? 'Made $made$missed'
        : outcome.stopped
        ? 'Stopped after making $made$missed'
        : 'Made $made$missed, then: ${outcome.error is DriveException ? (outcome.error! as DriveException).message : 'something went wrong'}',
  );
}
