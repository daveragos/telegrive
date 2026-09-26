import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/widgets/brand_mark.dart';
import '../data/app_lock.dart';

/// Covers the app while it is locked. The app underneath keeps its place,
/// and the back gesture can't reach it.
class LockGate extends ConsumerWidget {
  const LockGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locked = ref.watch(appLockProvider.select((s) => s.locked));
    return Stack(
      children: [
        ExcludeSemantics(
          excluding: locked,
          child: TickerMode(enabled: !locked, child: child),
        ),
        if (locked) const Positioned.fill(child: _LockScreen()),
      ],
    );
  }
}

class _LockScreen extends ConsumerStatefulWidget {
  const _LockScreen();

  @override
  ConsumerState<_LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<_LockScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Registered after the router, so it hears the back button first.
  @override
  Future<bool> didPopRoute() async => true;

  void _unlock() {
    if (mounted) ref.read(appLockProvider.notifier).unlock();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: colors.bg,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Space.x3),
          child: Column(
            children: [
              const Spacer(),
              const BrandMark(size: 72),
              const SizedBox(height: Space.xxl),
              Text('Telegrive is locked', style: context.text.titleLarge),
              const SizedBox(height: Space.s),
              Text(
                'Use your fingerprint, face or screen lock to open it.',
                textAlign: TextAlign.center,
                style: context.text.bodyMedium,
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _unlock,
                  icon: const Icon(Icons.lock_open_rounded),
                  label: const Text('Unlock'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
