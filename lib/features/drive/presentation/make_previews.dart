import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../../infrastructure/network/network_status.dart';
import '../../files/data/bulk_edits.dart';
import '../data/drive_repository.dart';

/// Asks before making previews for [without] files, then runs [make] and
/// says how it went. On mobile data it says how much of the person's data
/// that takes, and goes ahead on it if they agree.
Future<void> confirmMakePreviews(
  BuildContext context,
  WidgetRef ref,
  ({int count, int bytes}) without,
  Future<({BulkOutcome outcome, int noPicture})> Function({bool onMobileData}) make,
) async {
  final onMobileData = ref.read(networkStatusProvider).metered;
  final size = Formatters.bytes(without.bytes);
  final confirmed = await showConfirmDialog(
    context,
    title: 'Make ${Formatters.count(without.count, 'preview')}?',
    message: onMobileData
        ? 'You\'re on mobile data. Telegram takes a preview only with its file, so each of '
              'these is fetched and sent again with one, smallest first: $size down and the '
              'same up, from your data. You can stop at any point, or wait for Wi-Fi.'
        : 'Telegram takes a preview only with its file, so each of these is fetched and sent '
              'again with one, smallest first: $size down and the same up. '
              'Keep the phone on Wi-Fi. You can stop at any point.',
    confirmLabel: onMobileData ? 'Use mobile data' : 'Make previews',
  );
  if (!confirmed || !context.mounted) return;
  final BulkOutcome outcome;
  final int noPicture;
  try {
    (:outcome, :noPicture) = await make(onMobileData: onMobileData);
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
