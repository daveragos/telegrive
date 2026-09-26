import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget point(IconData icon, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 22, color: scheme.primary),
          const SizedBox(width: 14),
          Expanded(child: Text(text, style: theme.textTheme.bodyLarge)),
        ],
      ),
    );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.photo_library_rounded, size: 42, color: scheme.primary),
              ),
            ),
            const SizedBox(height: 20),
            Center(
              child: Text(
                'Back up your photos?',
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                'Keep your photos and videos safe in your Telegram drive.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 24),
            point(Icons.high_quality_rounded, 'Full-quality originals, no storage limit'),
            point(Icons.autorenew_rounded, 'New photos back up automatically'),
            point(Icons.wifi_rounded, 'Over Wi-Fi only, unless you allow mobile data'),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () async {
                  Navigator.of(context).pop();
                  final ok = await ref.read(backupControllerProvider.notifier).enable();
                  if (!ok && parentContext.mounted) {
                    showSnack(
                      parentContext,
                      'Photo access is needed to back up. You can turn it on '
                      'later from the Photos tab.',
                    );
                  }
                },
                child: const Text('Turn on backup'),
              ),
            ),
            const SizedBox(height: 8),
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
