import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/format/formatters.dart';
import '../../../core/widgets/common.dart';
import '../data/takeout_import.dart';

/// How a status reads at a glance: what colour its icon takes.
enum TakeoutTone { neutral, busy, good, bad }

/// Where the import stands, in the words the screen, Home and Transfers use.
@immutable
class TakeoutStatus {
  const TakeoutStatus({
    required this.icon,
    required this.title,
    this.detail,
    this.progress,
    this.tone = TakeoutTone.neutral,
    this.waiting = false,
  });

  final IconData icon;
  final String title;
  final String? detail;

  /// 0..1 for a bar, negative for one that moves without a value, null for
  /// none.
  final double? progress;
  final TakeoutTone tone;

  /// The bar is for work that waits rather than moves.
  final bool waiting;
}

String _items(int count) => Formatters.count(count, 'photo or video', 'photos and videos');

/// [photos] and [videos], naming only the kinds there are.
String _kinds(int photos, int videos) => [
  if (photos > 0 || videos == 0) Formatters.count(photos, 'photo'),
  if (videos > 0) Formatters.count(videos, 'video'),
].join(' and ');

/// How long the rest of the import takes and how fast it goes, for the whole
/// import rather than the files in hand: `38 min left · 2.4 MB/s`. Null
/// until the import has gone long enough to tell.
String? takeoutPace(TakeoutState state) {
  if (state.speed <= 0) return null;
  return [
    if (state.timeLeft case final left?) Formatters.left(left),
    Formatters.speed(state.speed),
  ].join(' · ');
}

/// [state] as a title and a line under it. Pure, so every wording is tested
/// on its own.
TakeoutStatus describeTakeout(TakeoutState state) {
  final progress = state.progress;
  if (state.phase == TakeoutPhase.reading || progress == null) {
    return TakeoutStatus(
      icon: Icons.folder_zip_outlined,
      title: 'Reading the parts',
      detail: state.reading,
      progress: -1,
      tone: TakeoutTone.busy,
    );
  }
  if (progress.total == 0) {
    return const TakeoutStatus(
      icon: Icons.photo_library_outlined,
      title: 'No photos or videos found',
      detail: 'The parts added so far hold none.',
    );
  }
  final settled = progress.total - progress.left;
  final fraction = settled / progress.total;
  final ofTotal = '${Formatters.number(settled)} of ${Formatters.number(progress.total)}';
  final already = progress.inDrive > 0
      ? '${Formatters.number(progress.inDrive)} ${progress.inDrive == 1 ? 'was' : 'were'} already in your drive.'
      : null;

  if (progress.finished) {
    final imported = '${Formatters.number(progress.sent)} imported.';
    if (progress.failed > 0) {
      return TakeoutStatus(
        icon: Icons.error_outline_rounded,
        title: '${_items(progress.failed)} didn\'t import',
        detail: [imported, ?already].join(' '),
        tone: TakeoutTone.bad,
      );
    }
    return TakeoutStatus(
      icon: Icons.check_circle_outline_rounded,
      title: 'Imported from Google Photos',
      detail: [imported, ?already].join(' '),
      tone: TakeoutTone.good,
    );
  }

  final left = '${_items(progress.left)} left';
  switch (state.phase) {
    case TakeoutPhase.waitingForWifi:
      return TakeoutStatus(
        icon: Icons.wifi_off_rounded,
        title: 'Waiting for Wi-Fi',
        detail: '$left. Imports follow Photo backup\'s Mobile data choice.',
        progress: fraction,
        waiting: true,
      );
    case TakeoutPhase.waitingForRoom:
      return TakeoutStatus(
        icon: Icons.sd_storage_outlined,
        title: 'Not enough room on this phone',
        detail: 'Free up ${Formatters.bytes(state.roomNeeded)} to carry on.',
        progress: fraction,
        tone: TakeoutTone.bad,
        waiting: true,
      );
    case TakeoutPhase.importing:
      return TakeoutStatus(
        icon: Icons.cloud_upload_outlined,
        title: 'Importing $ofTotal',
        detail: takeoutPace(state) ?? 'Working out how long the rest takes',
        progress: fraction,
        tone: TakeoutTone.busy,
      );
    case TakeoutPhase.idle || TakeoutPhase.reading:
  }
  if (state.running && progress.blocked > 0 && progress.blocked == progress.left) {
    return TakeoutStatus(
      icon: Icons.error_outline_rounded,
      title: 'Waiting for parts',
      detail: 'The ${_items(progress.left)} left are in parts Telegrive can\'t read.',
      progress: fraction,
      tone: TakeoutTone.bad,
      waiting: true,
    );
  }
  if (state.running) {
    return TakeoutStatus(
      icon: Icons.cloud_upload_outlined,
      title: 'Importing $ofTotal',
      progress: fraction,
      tone: TakeoutTone.busy,
    );
  }
  if (settled > 0) {
    return TakeoutStatus(
      icon: Icons.pause_circle_outline_rounded,
      title: 'Paused · $ofTotal',
      detail: '$left, ${Formatters.bytes(progress.leftBytes)}.',
      progress: fraction,
      waiting: true,
    );
  }
  return TakeoutStatus(
    icon: Icons.photo_library_outlined,
    title: _kinds(progress.photos, progress.videos),
    detail: [
      [Formatters.bytes(progress.bytes), if (progress.albums > 0) Formatters.count(progress.albums, 'album')].join(' · '),
      if (progress.alreadyThere > 0)
        '${Formatters.number(progress.alreadyThere)} ${progress.alreadyThere == 1 ? 'is' : 'are'} already in your drive.',
    ].join('. '),
  );
}

/// The import as one line, for Home, Transfers and the Backup screen. It
/// opens the import's screen.
class TakeoutStatusLine extends ConsumerWidget {
  const TakeoutStatusLine({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final status = describeTakeout(ref.watch(takeoutImportProvider));
    return StatusLine(
      icon: status.icon,
      color: switch (status.tone) {
        TakeoutTone.busy => colors.accent,
        TakeoutTone.good => colors.success,
        TakeoutTone.bad => colors.danger,
        TakeoutTone.neutral => null,
      },
      text: status.title,
      detail: status.detail,
      progress: status.progress,
      progressColor: status.waiting ? colors.text3 : null,
      onTap: () => context.push('/takeout'),
    );
  }
}

/// Whether the import has something to say away from its own screen: it
/// is running, or paused partway.
bool takeoutWorthShowing(TakeoutState state) {
  final progress = state.progress;
  if (progress == null) return state.phase == TakeoutPhase.reading;
  if (progress.finished) return false;
  return state.running || progress.total - progress.left > 0;
}
