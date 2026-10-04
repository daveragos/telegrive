import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/format/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../transfers/data/transfer_queue.dart';
import '../data/free_up_space.dart';

/// Offers to delete this phone's copies of photos and videos that are safely
/// in the drive, keeping the newest for as long as the person chooses.
/// Transfers waiting for room look again once they are gone.
Future<void> showFreeUpSpace(BuildContext context, WidgetRef ref) async {
  final go = await showModalBottomSheet<Freeable>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (_) => const _FreeUpSpaceSheet(),
  );
  if (go == null || !context.mounted) return;
  try {
    final deleted = await freeUpSpace(go);
    ref
      ..invalidate(freeableProvider)
      ..invalidate(lowSpaceProvider);
    await ref.read(transferQueueProvider.notifier).recheckRoom();
    if (!context.mounted) return;
    showSnack(
      context,
      deleted == 0
          ? 'Nothing was deleted'
          : 'Freed up space: ${Formatters.count(deleted, 'item')} deleted from this phone',
    );
  } catch (e) {
    if (context.mounted) showSnack(context, 'Couldn\'t delete them: $e');
  }
}

class _FreeUpSpaceSheet extends ConsumerWidget {
  const _FreeUpSpaceSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final freeable = ref.watch(freeableProvider);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.l),
        child: switch (freeable) {
          AsyncValue(:final value?) when value.isEmpty => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Nothing to free up', style: context.text.titleMedium),
              const SizedBox(height: Space.s),
              Text(
                describeFreeable(value, value, KeepWindow.nothing, DateTime.now()),
                style: context.text.bodyMedium,
              ),
              const SizedBox(height: Space.xl),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
          AsyncValue(:final value?) => _Choice(all: value),
          AsyncError(:final error) => Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.xl),
            child: Text('Couldn\'t check: $error'),
          ),
          _ => const Padding(
            padding: EdgeInsets.symmetric(vertical: Space.x3),
            child: Center(child: CircularProgressIndicator()),
          ),
        },
      ),
    );
  }
}

/// How much to keep, what that leaves to delete, and the button that
/// deletes it. A new window changes the sentence and the button at once,
/// and is remembered for next time. A window that leaves nothing turns the
/// button off but keeps the choice open, so a wider one can be picked.
class _Choice extends ConsumerWidget {
  const _Choice({required this.all});

  /// Everything that could go, whatever the window.
  final Freeable all;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final keep = ref.watch(freeUpKeepProvider);
    final now = DateTime.now();
    final candidates = all.before(keep.cutoff(now));
    final label = candidates.isEmpty
        ? 'Free up'
        : 'Free up ${Formatters.bytes(candidates.bytes)}';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          candidates.isEmpty ? 'Free up space' : label,
          style: context.text.titleMedium?.copyWith(fontFeatures: tabularFigures),
        ),
        const SizedBox(height: Space.s),
        Text('Keep on this phone', style: context.text.labelMedium),
        const SizedBox(height: Space.s),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<KeepWindow>(
            segments: [
              for (final window in KeepWindow.values)
                ButtonSegment(value: window, label: Text(window.label)),
            ],
            selected: {keep},
            showSelectedIcon: false,
            onSelectionChanged: (value) => ref.read(freeUpKeepProvider.notifier).set(value.first),
          ),
        ),
        const SizedBox(height: Space.l),
        Text(
          describeFreeable(all, candidates, keep, now),
          style: context.text.bodyMedium?.copyWith(fontFeatures: tabularFigures),
        ),
        if (!candidates.isEmpty) ...[
          const SizedBox(height: Space.s),
          TextButton(
            style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 44)),
            onPressed: () => context.push('/free-up'),
            child: const Text('Show them'),
          ),
        ],
        const SizedBox(height: Space.xl),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: Space.m),
            Expanded(
              child: FilledButton(
                onPressed: candidates.isEmpty ? null : () => Navigator.pop(context, candidates),
                child: Text(label, style: const TextStyle(fontFeatures: tabularFigures)),
              ),
            ),
          ],
        ),
        // Android 11 and later confirm a delete once for each batch of 500,
        // which freeUpSpace sends one after another.
        if (candidates.count > 500) ...[
          const SizedBox(height: Space.s),
          Text(
            'Android asks you to confirm, once per 500 items.',
            style: context.text.bodySmall,
          ),
        ],
      ],
    );
  }
}

/// The Backup screen's way in: a row saying how much can leave the phone
/// with the remembered window, shown only while there is something to free.
class FreeUpSpaceTile extends ConsumerWidget {
  const FreeUpSpaceTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final candidates = ref.watch(freeUpCandidatesProvider).value;
    if (candidates == null || candidates.isEmpty) return const SizedBox.shrink();
    final keep = ref.watch(freeUpKeepProvider);
    // The gap below comes with the row, so a hidden row leaves none.
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s),
      child: ListGroup(
        children: [
          ListTile(
            leading: Icon(Icons.phonelink_erase_outlined, color: context.colors.text2),
            title: const Text('Free up space on this phone'),
            subtitle: Text(
              summarizeFreeable(candidates, keep, DateTime.now()),
              style: const TextStyle(fontFeatures: tabularFigures),
            ),
            onTap: () => showFreeUpSpace(context, ref),
          ),
        ],
      ),
    );
  }
}
