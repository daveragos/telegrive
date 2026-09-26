import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format/formatters.dart';
import '../../../core/widgets/brand_mark.dart';
import '../../auth/data/auth_controller.dart';
import '../../drive/data/drive_sync.dart';
import '../data/drive_setup.dart';

/// Shown between sign-in and the drive. For a returning user it is a blink;
/// the first time on a device it narrates finding (or creating) the channel
/// and building the index.
class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(driveSetupProvider.notifier).run();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final setup = ref.watch(driveSetupProvider);
    final scanned = ref.watch(driveSyncProvider.select((s) => s.scanned));

    final steps = [
      (SetupStep.account, 'Connecting to your account'),
      (SetupStep.channel, 'Finding your drive'),
      (SetupStep.indexing, 'Indexing your files'),
    ];

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const BrandMark(size: 72),
                  const SizedBox(height: 32),
                  Text(
                    setup.error != null
                        ? 'We hit a snag'
                        : setup.createdChannel
                        ? 'Creating your drive'
                        : 'Opening your drive',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 28),
                  for (final (step, label) in steps)
                    _StepRow(
                      label: step == SetupStep.indexing && scanned > 0
                          ? '$label · ${Formatters.count(scanned, 'item')}'
                          : label,
                      state: setup.error != null && setup.step == step
                          ? _RowState.failed
                          : setup.step.index > step.index
                          ? _RowState.done
                          : setup.step == step
                          ? _RowState.active
                          : _RowState.waiting,
                    ),
                  if (setup.error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      setup.error!,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(color: scheme.error),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () =>
                                ref.read(authControllerProvider.notifier).signOut(),
                            child: const Text('Sign out'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () =>
                                ref.read(driveSetupProvider.notifier).run(),
                            child: const Text('Retry'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _RowState { waiting, active, done, failed }

class _StepRow extends StatelessWidget {
  const _StepRow({required this.label, required this.state});

  final String label;
  final _RowState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final Widget leading = switch (state) {
      _RowState.active => const SizedBox.square(
        dimension: 20,
        child: CircularProgressIndicator(strokeWidth: 2.4),
      ),
      _RowState.done => Icon(Icons.check_circle_rounded, color: scheme.primary, size: 22),
      _RowState.failed => Icon(Icons.error_rounded, color: scheme.error, size: 22),
      _RowState.waiting => Icon(
        Icons.circle_outlined,
        color: scheme.outlineVariant,
        size: 22,
      ),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox.square(dimension: 24, child: Center(child: leading)),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: state == _RowState.waiting
                    ? scheme.onSurfaceVariant
                    : scheme.onSurface,
                fontWeight: state == _RowState.active ? FontWeight.w600 : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
