import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/brand_mark.dart';
import '../data/auth_controller.dart';

class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              scheme.primaryContainer.withValues(alpha: 0.55),
              scheme.surface,
              scheme.surface,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
                child: Column(
                  children: [
                    const Spacer(flex: 2),
                    const BrandLockup(markSize: 84),
                    const SizedBox(height: 28),
                    Text(
                      'Your Telegram,\nnow an unlimited drive.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(height: 1.25),
                    ),
                    const SizedBox(height: 36),
                    const _Feature(
                      icon: Icons.all_inclusive_rounded,
                      title: 'No storage limit',
                      body: 'Files live in a private channel on your own account.',
                    ),
                    const _Feature(
                      icon: Icons.upload_file_rounded,
                      title: 'Any file, any size',
                      body: 'Files past Telegram\'s 2 GB cap are split and rejoined for you.',
                    ),
                    const _Feature(
                      icon: Icons.lock_outline_rounded,
                      title: 'Just you and Telegram',
                      body: 'No Telegrive servers and no account to create.',
                    ),
                    const Spacer(flex: 3),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () =>
                            ref.read(authControllerProvider.notifier).startSignIn(),
                        child: const Text('Get started'),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Independent app · not affiliated with Telegram',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
            ),
            child: Icon(icon, size: 22, color: scheme.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
