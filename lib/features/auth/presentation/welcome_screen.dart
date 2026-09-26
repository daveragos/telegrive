import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/tokens.dart';
import '../../../app/theme/file_style.dart';
import '../../../core/files/file_kind.dart';
import '../../../core/widgets/brand_mark.dart';
import '../../../core/widgets/file_visuals.dart';
import '../data/auth_controller.dart';

/// Says plainly what Telegrive is and where the files go, then gets out of
/// the way.
class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.xxl,
                Space.xxl,
                Space.xxl,
                Space.l,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const BrandLockup(markSize: 36),
                  const Spacer(),
                  const _Glimpse(),
                  const Spacer(),
                  Text(
                    'Your files, kept in your own Telegram.',
                    style: context.text.headlineMedium,
                  ),
                  const SizedBox(height: Space.l),
                  Text(
                    'Telegrive stores everything in a private channel on your '
                    'account and gives you a proper file manager and photo '
                    'backup on top. There are no Telegrive servers, and files '
                    'bigger than Telegram\'s limit are split for you.',
                    style: context.text.bodyLarge?.copyWith(
                      color: colors.text2,
                    ),
                  ),
                  const SizedBox(height: Space.x4),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => ref
                          .read(authControllerProvider.notifier)
                          .startSignIn(),
                      child: const Text('Sign in with Telegram'),
                    ),
                  ),
                  const SizedBox(height: Space.l),
                  Text(
                    'Independent app, not affiliated with Telegram.',
                    style: context.text.bodySmall?.copyWith(
                      color: colors.text3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What the drive looks like, drawn with the app's own rows rather than an
/// illustration: a few files, one of them bigger than Telegram allows.
class _Glimpse extends StatelessWidget {
  const _Glimpse();

  static const _files = [
    ('Passport scan.pdf', '1.8 MB', FileKind.document),
    ('Beach day.jpg', '4.2 MB', FileKind.image),
    ('Summer holiday 4K.mp4', '5.6 GB, stored as 12 parts', FileKind.video),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ExcludeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(Radii.card),
          border: Border.all(color: colors.line),
        ),
        child: Column(
          children: [
            for (final (index, (name, meta, kind)) in _files.indexed) ...[
              if (index > 0) Divider(indent: 72, color: colors.line),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.l,
                  vertical: Space.m,
                ),
                child: Row(
                  children: [
                    FileIconTile(
                      style: FileStyle.forFile(name, kind),
                      size: 40,
                    ),
                    const SizedBox(width: Space.l),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: context.text.titleSmall),
                          Text(
                            meta,
                            style: context.text.bodySmall?.copyWith(
                              fontFeatures: tabularFigures,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
