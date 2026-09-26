import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/widgets/common.dart';
import '../../../infrastructure/telegram/telegram_client.dart';
import '../data/auth_controller.dart';
import 'auth_layout.dart';

/// Sign in by approving from a device that is already signed in. TDLib
/// rotates the link every ~30 s; the screen follows along.
class QrScreen extends ConsumerWidget {
  const QrScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final state = ref.watch(authStateProvider).value;
    final link = state is td.AuthorizationStateWaitOtherDeviceConfirmation
        ? state.link
        : null;

    return AuthLayout(
      icon: Icons.qr_code_scanner_rounded,
      title: 'Scan to sign in',
      subtitle: const Text(
        'On a phone signed in to Telegram, open Settings → Devices → '
        'Link Desktop Device, and point it at this code.',
      ),
      onBack: () => ref.read(authControllerProvider.notifier).editPhone(),
      primary: FilledButton.tonalIcon(
        onPressed: link == null
            ? null
            : () async {
                final opened = await launchUrl(
                  Uri.parse(link),
                  mode: LaunchMode.externalApplication,
                );
                if (!opened && context.mounted) {
                  showSnack(context, 'Telegram isn\'t installed on this device.');
                }
              },
        icon: const Icon(Icons.send_rounded),
        label: const Text('Confirm in Telegram on this device'),
      ),
      secondary: TextButton(
        onPressed: () => ref.read(authControllerProvider.notifier).editPhone(),
        child: const Text('Use phone number instead'),
      ),
      children: [
        Center(
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: link == null
                  ? const SizedBox.square(
                      dimension: 220,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : QrImageView(
                      key: ValueKey(link),
                      data: link,
                      size: 220,
                      padding: EdgeInsets.zero,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.circle,
                        color: Color(0xFF12151B),
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.circle,
                        color: Color(0xFF12151B),
                      ),
                      embeddedImage: null,
                    ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            'The code refreshes on its own.',
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}
