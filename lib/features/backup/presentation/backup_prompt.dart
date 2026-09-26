import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/widgets/common.dart';
import '../../../infrastructure/storage/preferences.dart';
import '../data/backup_controller.dart';

/// Asks once, right after the drive first opens: "Back up your photos?"
Future<void> maybeAskToBackUp(BuildContext context, WidgetRef ref) async {
  final prefs = ref.read(preferencesProvider);
  if (prefs.backupPromptShown || prefs.backupEnabled) return;
  await prefs.setBackupPromptShown();
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (sheetContext) => _BackupPromptSheet(parentContext: context),
  );
}

class _BackupPromptSheet extends ConsumerWidget {
  const _BackupPromptSheet({required this.parentContext});

  final BuildContext parentContext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.gutter, Space.xs, Space.gutter, Space.l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Back up this phone\'s photos?', style: context.text.headlineSmall),
            const SizedBox(height: Space.m),
            Text(
              'Telegrive copies your photos and videos to your drive in full '
              'quality, then keeps new ones backed up as you take them. It '
              'uses Wi-Fi only unless you allow mobile data.',
              style: context.text.bodyLarge?.copyWith(color: context.colors.text2),
            ),
            const SizedBox(height: Space.xxl),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () async {
                  Navigator.of(context).pop();
                  final ok = await ref.read(backupControllerProvider.notifier).enable();
                  if (!ok && parentContext.mounted) {
                    showSnack(
                      parentContext,
                      'Backup needs photo access. You can turn it on later in Photos.',
                    );
                  }
                },
                child: const Text('Turn on backup'),
              ),
            ),
            const SizedBox(height: Space.s),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Not now'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
