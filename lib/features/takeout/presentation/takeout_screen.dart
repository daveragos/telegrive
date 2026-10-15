import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme/file_style.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/files/file_kind.dart';
import '../../../core/format/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/file_visuals.dart';
import '../../../infrastructure/database/app_database.dart';
import '../../drive/data/drive_repository.dart';
import '../../files/data/bulk_edits.dart';
import '../../transfers/data/transfer_queue.dart';
import '../../transfers/domain/transfer_wait.dart';
import '../data/takeout_import.dart';
import '../domain/takeout_catalog.dart';
import 'takeout_status.dart';

/// Takeout, opened at Google Photos alone.
final Uri takeoutAddress = Uri.parse('https://takeout.google.com/settings/takeout/custom/photos');

final _partsProvider = StreamProvider.autoDispose<List<TakeoutPartRow>>(
  (ref) => ref.watch(appDatabaseProvider).watchTakeoutParts(),
);

/// Importing a Google Photos library: how to get it out of Google with
/// Takeout, the parts picked so far, and the one button that starts,
/// pauses or carries on.
class TakeoutScreen extends ConsumerWidget {
  const TakeoutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final parts = ref.watch(_partsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Google Photos'),
        actions: [
          if (parts.value?.isNotEmpty ?? false)
            PopupMenuButton<String>(
              onSelected: (_) => _startOver(context, ref),
              itemBuilder: (_) => const [PopupMenuItem(value: 'over', child: Text('Start over'))],
            ),
        ],
      ),
      body: AsyncView<List<TakeoutPartRow>>(
        value: parts,
        data: (parts) => parts.isEmpty ? const _Steps() : _Import(parts: parts),
      ),
    );
  }

  static Future<void> _startOver(BuildContext context, WidgetRef ref) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Start over?',
      message:
          'Telegrive forgets the parts and what it imported from them, and stops '
          'the uploads under way. Everything already in your drive stays, and the '
          'parts stay on this phone.',
      confirmLabel: 'Start over',
      destructive: true,
    );
    if (confirmed) await ref.read(takeoutImportProvider.notifier).startOver();
  }
}

/// Opens the picker and says what came of it.
Future<void> addTakeoutParts(BuildContext context, WidgetRef ref) async {
  try {
    final added = await ref.read(takeoutImportProvider.notifier).addParts();
    if (added > 0 && context.mounted) {
      showSnack(context, added == 1 ? 'Added 1 part' : 'Added $added parts');
    }
  } on PlatformException {
    if (context.mounted) showSnack(context, 'Couldn\'t open the file picker.');
  }
}

/// The way to get a library out of Google, before any part is added.
class _Steps extends ConsumerWidget {
  const _Steps();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    Widget step(int number, String title, String detail, {Widget? trailing}) => ListTile(
      leading: CircleAvatar(
        radius: 14,
        backgroundColor: colors.surface2,
        child: Text('$number', style: context.text.labelLarge?.copyWith(color: colors.text2)),
      ),
      title: Text(title),
      subtitle: Text(detail),
      trailing: trailing,
    );

    return ListView(
      padding: const EdgeInsets.only(bottom: Space.x4),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, Space.s, Space.gutter, 0),
          child: Text(
            'Bring your Google Photos library into your drive. Google lets you download it as zip '
            'files with Google Takeout. Telegrive reads them on this phone and sends each photo up '
            'once, with its date, albums and favorites.',
            style: context.text.bodyMedium,
          ),
        ),
        const SectionHeader('Get your photos from Google'),
        ListGroup(
          children: [
            step(
              1,
              'Open Google Takeout',
              'Google Photos is already picked. Choose Next step.',
              trailing: TextButton(
                onPressed: () => launchUrl(takeoutAddress, mode: LaunchMode.externalApplication),
                child: const Text('Open'),
              ),
            ),
            step(2, 'Choose how to get it', 'Send download link via email, Export once, .zip and 2 GB.'),
            step(3, 'Wait for Google\'s email', 'It can take hours or a few days. Its links work for a week.'),
            step(
              4,
              'Download the parts to this phone',
              'All of them, or a few at a time if the phone is short of room.',
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, Space.xl, Space.gutter, 0),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => addTakeoutParts(context, ref),
              child: const Text('Choose the downloaded parts'),
            ),
          ),
        ),
        const _Footnote(),
      ],
    );
  }
}

/// Where the import stands, the button for it, and the parts.
class _Import extends ConsumerWidget {
  const _Import({required this.parts});

  final List<TakeoutPartRow> parts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final state = ref.watch(takeoutImportProvider);
    final controller = ref.read(takeoutImportProvider.notifier);
    final progress = state.progress;
    final status = describeTakeout(state);
    final missing = missingTakeoutParts([for (final part in parts) part.name]);
    final exports = {for (final part in parts) ?takeoutPartNumber(part.name)?.export};
    final ordered = [...parts]..sort((a, b) => compareTakeoutParts(a.name, b.name));
    final reading = state.phase == TakeoutPhase.reading || progress == null;

    final Widget? action = switch (progress) {
      _ when reading => null,
      null => null,
      final p when p.finished => null,
      final p when p.left == p.blocked => null,
      _ when state.running => OutlinedButton(onPressed: controller.pause, child: const Text('Pause')),
      final p => FilledButton(
        onPressed: controller.start,
        child: Text(p.total - p.left > 0 ? 'Import ${Formatters.number(p.left)} more' : 'Import'),
      ),
    };
    final bulk = ref.watch(bulkEditsProvider);
    final figures = progress == null || reading ? const <String>[] : _figures(progress, state);
    final deletable = [
      for (final part in ordered)
        if (part.deletedAt == null &&
            part.readAt != null &&
            part.problem == null &&
            (progress?.partsLeft[part.id] ?? 0) == 0 &&
            !reading)
          part,
    ];

    return ListView(
      padding: const EdgeInsets.only(bottom: Space.x4),
      children: [
        _Panel(status: status, figures: figures),
        if (action != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.s),
            child: SizedBox(width: double.infinity, child: action),
          ),
        if (progress != null && progress.finished && deletable.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.s),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => _deleteParts(context, ref, deletable),
                child: Text(
                  'Delete the parts from this phone · '
                  '${Formatters.bytes(deletable.fold(0, (sum, p) => sum + p.size))}',
                ),
              ),
            ),
          ),
        if (missing.isNotEmpty ||
            (progress?.failed ?? 0) > 0 ||
            (progress?.missing ?? 0) > 0 ||
            (progress?.extraMotion ?? 0) > 0 ||
            state.withoutPreview.count > 0 ||
            bulk != null ||
            state.phase == TakeoutPhase.waitingForRoom) ...[
          const SizedBox(height: Space.s),
          ListGroup(
            children: [
              if ((progress?.missing ?? 0) > 0)
                StatusLine(
                  icon: Icons.error_outline_rounded,
                  color: colors.danger,
                  text:
                      '${Formatters.count(progress!.missing, 'photo or video', 'photos and videos')} '
                      '${progress.missing == 1 ? 'is' : 'are'} no longer in your drive',
                  detail: 'Imported, then deleted for good or removed in Telegram.',
                  trailing: TextButton(onPressed: controller.importMissingAgain, child: const Text('Import again')),
                ),
              if (bulk != null)
                StatusLine(
                  icon: bulk.icon,
                  color: colors.accent,
                  text: bulk.stopping ? 'Stopping' : bulk.label,
                  detail: '${Formatters.number(bulk.done)} of ${Formatters.number(bulk.total)}',
                  progress: bulk.total == 0 ? -1 : bulk.done / bulk.total,
                  trailing: bulk.stopping
                      ? null
                      : TextButton(
                          onPressed: ref.read(bulkEditsProvider.notifier).stop,
                          child: const Text('Stop'),
                        ),
                )
              else if (state.withoutPreview.count > 0)
                StatusLine(
                  icon: Icons.image_not_supported_outlined,
                  text:
                      '${Formatters.count(state.withoutPreview.count, 'photo or video', 'photos and videos')} '
                      '${state.withoutPreview.count == 1 ? 'has' : 'have'} no preview',
                  detail:
                      'Making previews fetches each and sends it again · '
                      '${Formatters.bytes(state.withoutPreview.bytes)}, on Wi-Fi.',
                  trailing: TextButton(
                    onPressed: () => _makePreviews(context, ref, state.withoutPreview),
                    child: const Text('Make previews'),
                  ),
                ),
              if (bulk == null && (progress?.extraMotion ?? 0) > 0)
                StatusLine(
                  icon: Icons.motion_photos_on_outlined,
                  text:
                      '${Formatters.count(progress!.extraMotion, 'Live Photo video')} went up beside '
                      '${progress.extraMotion == 1 ? 'its photo' : 'their photos'}',
                  detail: 'The photos your phone backed up already hold the movement.',
                  trailing: TextButton(
                    onPressed: () => _trashExtraMotion(context, ref, progress.extraMotion),
                    child: const Text('Move to trash'),
                  ),
                ),
              if (missing.isNotEmpty)
                StatusLine(
                  icon: Icons.error_outline_rounded,
                  color: colors.danger,
                  text: missing.length == 1
                      ? 'Part ${missing.single} isn\'t here'
                      : 'Parts ${_list(missing)} aren\'t here',
                  detail: 'Download ${missing.length == 1 ? 'it' : 'them'} from Google\'s email and add '
                      '${missing.length == 1 ? 'it' : 'them'}.',
                  trailing: TextButton(onPressed: () => addTakeoutParts(context, ref), child: const Text('Add')),
                ),
              if ((progress?.failed ?? 0) > 0)
                StatusLine(
                  icon: Icons.error_outline_rounded,
                  color: colors.danger,
                  text: '${Formatters.count(progress!.failed, 'photo or video', 'photos and videos')} didn\'t import',
                  detail: 'Each was tried three times.',
                  trailing: TextButton(onPressed: controller.retryFailed, child: const Text('Try again')),
                ),
              if (state.phase == TakeoutPhase.waitingForRoom)
                StatusLine(
                  icon: Icons.refresh_rounded,
                  text: 'Made room?',
                  trailing: TextButton(
                    onPressed: () => controller.schedule(immediate: true),
                    child: const Text('Try again'),
                  ),
                ),
            ],
          ),
        ],
        if (state.flights.isNotEmpty) ...[
          const SectionHeader('Now'),
          ListGroup(children: [for (final flight in state.flights) _FlightRow(flight, key: ValueKey(flight.key))]),
        ],
        SectionHeader(
          'Parts · ${Formatters.number(parts.length)}',
          trailing: TextButton(onPressed: () => addTakeoutParts(context, ref), child: const Text('Add')),
        ),
        ListGroup(
          children: [
            // Parts deleted from the phone are done with: one line says so,
            // and only the parts still here are listed one by one.
            if (ordered.where((part) => part.deletedAt != null).toList() case final gone when gone.isNotEmpty)
              _DeletedParts(gone),
            for (final part in ordered)
              if (part.deletedAt == null)
                _PartRow(
                part: part,
                withExport: exports.length > 1,
                left: progress?.partsLeft[part.id] ?? 0,
                total: progress?.partsTotal[part.id] ?? 0,
                reading: state.phase == TakeoutPhase.reading && state.reading == part.name,
                known: progress != null,
              ),
          ],
        ),
        const _Footnote(),
      ],
    );
  }

  /// The counts under the status: what became of the photos so far, and
  /// how much of the whole import's bytes went up.
  static List<String> _figures(TakeoutProgress progress, TakeoutState state) {
    final counts = [
      if (progress.sent > 0) '${Formatters.number(progress.sent)} imported',
      if (progress.inDrive > 0) '${Formatters.number(progress.inDrive)} already in your drive',
      if (progress.failed > 0) '${Formatters.number(progress.failed)} didn\'t import',
      if (progress.left > 0 && progress.total - progress.left > 0) '${Formatters.number(progress.left)} left',
    ];
    final sent = math.max(state.uploadedBytes, progress.sentBytes);
    final whole = progress.sentBytes + progress.leftBytes;
    // Done, the line under the title already gives the counts.
    if (progress.finished) return [if (sent > 0) '${Formatters.bytes(sent)} sent'];
    return [
      if (counts.isNotEmpty) counts.join(' · '),
      if (whole > 0 && sent > 0) '${Formatters.bytes(sent)} of ${Formatters.bytes(whole)} sent',
    ];
  }

  static String _list(List<int> numbers) {
    if (numbers.length == 2) return '${numbers.first} and ${numbers.last}';
    final shown = numbers.take(5).toList();
    final rest = numbers.length - shown.length;
    return rest > 0 ? '${shown.join(', ')} and $rest more' : '${shown.take(shown.length - 1).join(', ')} and ${shown.last}';
  }

  static Future<void> _makePreviews(BuildContext context, WidgetRef ref, ({int count, int bytes}) without) async {
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
      (:outcome, :noPicture) = await ref.read(takeoutImportProvider.notifier).makePreviews();
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

  static Future<void> _trashExtraMotion(BuildContext context, WidgetRef ref, int count) async {
    final confirmed = await showConfirmDialog(
      context,
      title: count == 1 ? 'Move the video to the trash?' : 'Move $count videos to the trash?',
      message:
          'Each is the moving part of a Live Photo your phone already backed up, with the '
          'movement inside it. The trash keeps them for 30 days.',
      confirmLabel: 'Move to trash',
    );
    if (!confirmed || !context.mounted) return;
    final BulkOutcome outcome;
    try {
      outcome = await ref.read(takeoutImportProvider.notifier).trashExtraMotion();
    } on DriveException catch (e) {
      if (context.mounted) showSnack(context, e.message);
      return;
    }
    if (!context.mounted) return;
    final moved = Formatters.count(outcome.done, 'video');
    showSnack(
      context,
      outcome.complete
          ? 'Moved $moved to the trash'
          : outcome.stopped
          ? 'Stopped after moving $moved to the trash'
          : 'Moved $moved to the trash, then something went wrong',
    );
  }

  static Future<void> _deleteParts(BuildContext context, WidgetRef ref, List<TakeoutPartRow> parts) async {
    final bytes = parts.fold(0, (sum, p) => sum + p.size);
    final confirmed = await showConfirmDialog(
      context,
      title: parts.length == 1 ? 'Delete the part?' : 'Delete ${parts.length} parts?',
      message:
          'Everything in ${parts.length == 1 ? 'it' : 'them'} is in your drive. '
          'This frees ${Formatters.bytes(bytes)} on this phone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed) return;
    final controller = ref.read(takeoutImportProvider.notifier);
    var kept = 0;
    for (final part in parts) {
      if (!await controller.deletePart(part.id)) kept++;
    }
    if (kept > 0 && context.mounted) {
      showSnack(context, 'Telegrive couldn\'t delete ${kept == 1 ? 'a part' : '$kept parts'}. Delete them in your files app.');
    }
  }
}

/// The import's status, larger than a row, at the top of its screen.
class _Panel extends StatelessWidget {
  const _Panel({required this.status, this.figures = const []});

  final TakeoutStatus status;

  /// Lines of counts under the bar.
  final List<String> figures;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final progress = status.progress;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.s, Space.gutter, Space.l),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        alignment: Alignment.topCenter,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  status.icon,
                  size: 22,
                  color: switch (status.tone) {
                    TakeoutTone.busy => colors.accent,
                    TakeoutTone.good => colors.success,
                    TakeoutTone.bad => colors.danger,
                    TakeoutTone.neutral => colors.text2,
                  },
                ),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Text(
                    status.title,
                    style: context.text.titleMedium?.copyWith(fontFeatures: tabularFigures),
                  ),
                ),
              ],
            ),
            if (status.detail case final detail? when detail.isNotEmpty) ...[
              const SizedBox(height: Space.xs),
              Padding(
                padding: const EdgeInsets.only(left: 34),
                child: Text(
                  detail,
                  style: context.text.bodyMedium?.copyWith(fontFeatures: tabularFigures),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            if (progress != null) ...[
              const SizedBox(height: Space.m),
              Padding(
                padding: const EdgeInsets.only(left: 34),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: progress < 0 ? 0 : progress),
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    builder: (context, value, _) => LinearProgressIndicator(
                      value: progress < 0 ? null : value,
                      minHeight: 4,
                      color: status.waiting ? colors.text3 : null,
                    ),
                  ),
                ),
              ),
            ],
            for (final line in figures) ...[
              const SizedBox(height: Space.s),
              Padding(
                padding: const EdgeInsets.only(left: 34),
                child: Text(line, style: context.text.bodySmall?.copyWith(fontFeatures: tabularFigures)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A photo or video in hand: what is being done with it, and how far its
/// upload has got.
class _FlightRow extends ConsumerWidget {
  const _FlightRow(this.flight, {super.key});

  final TakeoutFlight flight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final transfer = flight.transferId == null
        ? null
        : ref.watch(transferQueueProvider.select((s) => s.byId(flight.transferId!)));
    final kind = FileKind.detect(fileName: flight.name);
    final row = transfer?.row;
    final fraction = row == null || row.totalBytes == 0 ? null : (row.doneBytes / row.totalBytes).clamp(0.0, 1.0);
    final String detail = switch (flight.step) {
      TakeoutStep.checking => 'Looking for it in your drive',
      TakeoutStep.extracting => 'Taking it out of ${flight.part ?? 'its part'} · ${Formatters.bytes(flight.size)}',
      TakeoutStep.updating => 'Already in your drive · adding its albums and star',
      TakeoutStep.uploading => switch (transfer?.wait) {
        WaitingForTelegram(:final until) =>
          'Telegram asked to wait · ${Formatters.countdown(until.difference(DateTime.now()))}',
        WaitingForNetwork() => 'Waiting for network',
        WaitingForWifi() => 'Waiting for Wi-Fi',
        WaitingForRoom(:final sentence) => sentence,
        null => switch (row) {
          final row? when row.doneBytes > 0 => [
            '${((fraction ?? 0) * 100).floor()}%',
            '${Formatters.bytes(row.doneBytes)} of ${Formatters.bytes(row.totalBytes)}',
            if (transfer!.bytesPerSecond > 0) Formatters.speed(transfer.bytesPerSecond),
          ].join(' · '),
          // Telegram takes one upload at a time; the next waits its turn
          // with nothing sent yet.
          _ => 'Waiting to upload · ${Formatters.bytes(flight.size)}',
        },
      },
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.m, Space.gutter, Space.m),
      child: Row(
        children: [
          FileIconTile(style: FileStyle.forFile(flight.name, kind), size: 40),
          const SizedBox(width: Space.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(flight.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall),
                const SizedBox(height: 2),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodySmall?.copyWith(fontFeatures: tabularFigures),
                ),
                if (flight.step != TakeoutStep.checking) ...[
                  const SizedBox(height: Space.s),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(end: fraction ?? 0),
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                      builder: (context, value, _) => LinearProgressIndicator(
                        // Taking out and updating have no measure of their own.
                        value: flight.step == TakeoutStep.uploading && fraction != null ? value : null,
                        minHeight: 3,
                        color: transfer?.wait == null ? null : colors.text3,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The parts deleted from the phone, as one line: everything in them is in
/// the drive. They stay on the import's list so a part added later still
/// knows its place among them, until the person clears them.
class _DeletedParts extends ConsumerWidget {
  const _DeletedParts(this.parts);

  final List<TakeoutPartRow> parts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final freed = parts.fold(0, (sum, part) => sum + part.size);
    return ListTile(
      leading: Icon(Icons.check_circle_outline_rounded, color: colors.success),
      title: Text(
        parts.length == 1 ? '1 part deleted from this phone' : '${parts.length} parts deleted from this phone',
      ),
      subtitle: Text(
        // A size keeps its number and unit on one line.
        'Everything in them is in your drive · ${Formatters.bytes(freed).replaceAll(' ', '\u00a0')} freed',
        style: context.text.bodySmall?.copyWith(fontFeatures: tabularFigures),
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (_) async {
          final controller = ref.read(takeoutImportProvider.notifier);
          for (final part in parts) {
            await controller.removePart(part.id);
          }
        },
        itemBuilder: (_) => const [PopupMenuItem(value: 'clear', child: Text('Clear from the list'))],
      ),
    );
  }
}

class _PartRow extends ConsumerWidget {
  const _PartRow({
    required this.part,
    required this.withExport,
    required this.left,
    required this.total,
    required this.reading,
    required this.known,
  });

  final TakeoutPartRow part;

  /// Parts of more than one export are listed, so each says which it is of.
  final bool withExport;

  /// Items still to go that it holds, of [total].
  final int left;
  final int total;
  final bool reading;

  /// The import has been looked through, so [left] means something.
  final bool known;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final controller = ref.read(takeoutImportProvider.notifier);
    final problem = part.problem;
    final done = part.readAt != null && problem == null && known && left == 0;
    final String status = switch (problem) {
      TakeoutPartProblem.incomplete => 'Didn\'t finish downloading. Download it again and add it.',
      TakeoutPartProblem.notZip => 'Not a zip file.',
      TakeoutPartProblem.damaged => 'Damaged. Download it again and add it.',
      TakeoutPartProblem.noAccess => 'Telegrive can\'t read it any more.',
      null when part.deletedAt != null => 'Done. Deleted from this phone.',
      null when reading => 'Reading',
      null when part.readAt == null => 'Waiting to be read',
      null when !known => 'Read',
      null when left == 0 => 'Done. It can be deleted.',
      null => '${Formatters.number(left)} of ${Formatters.count(total, 'item')} left',
    };
    final going = problem == null && part.deletedAt == null && known && left > 0 && left < total;

    return ListTile(
      leading: Icon(
        problem != null
            ? Icons.error_outline_rounded
            : done
            ? Icons.check_circle_outline_rounded
            : Icons.folder_zip_outlined,
        color: problem != null
            ? colors.danger
            : done
            ? colors.success
            : colors.text2,
      ),
      // Takeout's names differ only in their last digits, which a cut-off
      // name hides, so a part it named goes by its number, and by when its
      // export was made when there are several.
      title: Text(
        switch (takeoutPartNumber(part.name)) {
          (:final number, :final export) when withExport && takeoutExportTime(export) != null =>
            'Part $number · ${Formatters.date(takeoutExportTime(export)!.toLocal())}',
          (:final number, export: _) => 'Part $number',
          null => part.name,
        },
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${Formatters.bytes(part.size)} · $status',
            style: context.text.bodySmall?.copyWith(fontFeatures: tabularFigures),
          ),
          if (going) ...[
            const SizedBox(height: Space.s),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(value: (total - left) / total, minHeight: 3),
            ),
          ],
        ],
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (choice) async {
          switch (choice) {
            case 'again':
              await addTakeoutParts(context, ref);
            case 'delete':
              final confirmed = await showConfirmDialog(
                context,
                title: 'Delete ${part.name}?',
                message: left == 0
                    ? 'Everything in it is in your drive. This frees ${Formatters.bytes(part.size)} on this phone.'
                    : '${Formatters.count(left, 'item')} in it ${left == 1 ? 'hasn\'t' : 'haven\'t'} gone up yet.',
                confirmLabel: 'Delete',
                destructive: true,
              );
              if (!confirmed) return;
              if (!await controller.deletePart(part.id) && context.mounted) {
                showSnack(context, 'Telegrive couldn\'t delete it. Delete it in your files app.');
              }
            case 'remove':
              await controller.removePart(part.id);
          }
        },
        itemBuilder: (_) => [
          if (problem != null) const PopupMenuItem(value: 'again', child: Text('Choose again')),
          if (problem != TakeoutPartProblem.noAccess)
            const PopupMenuItem(value: 'delete', child: Text('Delete from this phone')),
          const PopupMenuItem(value: 'remove', child: Text('Remove from the import')),
        ],
      ),
    );
  }
}

class _Footnote extends StatelessWidget {
  const _Footnote();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.gutter, Space.xxl, Space.gutter, 0),
    child: Text(
      'Photos go to Files › $takeoutRootFolder, in a folder for each year, and show in Photos. '
      'Albums come across as albums, and favorites are starred. Photos already in your drive '
      'aren\'t sent again. Imports follow Photo backup\'s Mobile data choice, and nothing is '
      'deleted from Google.',
      style: context.text.bodySmall,
    ),
  );
}
