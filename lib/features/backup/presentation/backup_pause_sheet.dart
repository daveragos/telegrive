import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/format/formatters.dart';
import '../data/backup_controller.dart';

/// When a pause "until tomorrow morning" ends: eight o'clock the day after
/// [now].
DateTime tomorrowMorning(DateTime now) => DateTime(now.year, now.month, now.day + 1, 8);

/// Asks how long to pause backup for, and pauses it: for an hour, until
/// tomorrow morning, or until the person resumes it.
Future<void> showBackupPauseSheet(BuildContext context, WidgetRef ref) async {
  final now = DateTime.now();
  final hour = now.add(const Duration(hours: 1));
  final morning = tomorrowMorning(now);
  final choice = await showModalBottomSheet<({DateTime? until})>(
    context: context,
    useRootNavigator: true,
    builder: (context) {
      Widget option(String title, String detail, DateTime? until) => ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(title),
        subtitle: Text(detail),
        onTap: () => Navigator.pop(context, (until: until)),
      );
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.l),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Pause backup', style: context.text.titleMedium),
              const SizedBox(height: Space.s),
              Text(
                'Uploads under way stop where they are and carry on when backup '
                'does. Photos already backed up stay in your drive.',
                style: context.text.bodyMedium,
              ),
              const SizedBox(height: Space.s),
              option('For 1 hour', 'Carries on ${Formatters.at(hour, now: now)}', hour),
              option(
                'Until tomorrow morning',
                'Carries on ${Formatters.at(morning, now: now)}',
                morning,
              ),
              option('Until I resume it', 'Stays paused until you tap Resume', null),
            ],
          ),
        ),
      );
    },
  );
  if (choice == null) return;
  await ref.read(backupControllerProvider.notifier).pause(choice.until);
}
