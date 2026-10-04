import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/format/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../transfers/data/transfer_queue.dart';
import '../data/free_up_space.dart';

/// Offers to delete this phone's copies of photos and videos that are safely
/// in the drive. Transfers waiting for room look again once they are gone.
Future<void> showFreeUpSpace(BuildContext context, WidgetRef ref) async {
  final go = await showModalBottomSheet<Freeable>(
    context: context,
    useRootNavigator: true,
    builder: (_) => const _FreeUpSpaceSheet(),
  );
  if (go == null || !context.mounted) return;
  try {
    final deleted = await freeUpSpace(go);
    ref.invalidate(freeableProvider);
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
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.l),
        child: switch (freeable) {
          AsyncData(:final value) when value.isEmpty => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Nothing to free up', style: context.text.titleMedium),
              const SizedBox(height: Space.s),
              Text(
                'Photos and videos backed up from this phone show up here once '
                'they are safely in your drive.',
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
          AsyncData(:final value) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Free up ${Formatters.bytes(value.bytes)}',
                style: context.text.titleMedium,
              ),
              const SizedBox(height: Space.s),
              Text(
                '${Formatters.count(value.count, 'photo and video', 'photos and videos')} '
                'on this phone are backed up to your drive. They\'ll be deleted '
                'from this phone and stay in Telegrive, where you can download '
                'them again any time.',
                style: context.text.bodyMedium,
              ),
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
                      onPressed: () => Navigator.pop(context, value),
                      child: const Text('Free up'),
                    ),
                  ),
                ],
              ),
            ],
          ),
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
