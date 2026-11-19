import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/platform/app_platform.dart';
import '../../../core/widgets/brand_mark.dart';
import '../../../core/widgets/common.dart';
import '../../../infrastructure/storage/preferences.dart';
import '../../../infrastructure/telegram/telegram_client.dart';
import '../../network/presentation/connection_notice.dart';
import '../data/auth_controller.dart';
import 'auth_layout.dart';

/// Sign in by approving from a device that is already signed in. TDLib
/// rotates the link every ~30 s; the screen follows along.
///
/// A computer opens on this screen, so on one it asks for the code itself
/// while TDLib waits for a phone number, and says what Welcome says on a
/// phone: whose app this is, and when Telegram ended the last session.
class QrScreen extends ConsumerStatefulWidget {
  const QrScreen({super.key});

  @override
  ConsumerState<QrScreen> createState() => _QrScreenState();
}

class _QrScreenState extends ConsumerState<QrScreen> {
  bool _asking = false;

  @override
  void initState() {
    super.initState();
    _askIfWaiting(ref.read(authStateProvider).value);
  }

  void _askIfWaiting(td.AuthorizationState? state) {
    if (state is! td.AuthorizationStateWaitPhoneNumber || _asking) return;
    _asking = true;
    ref.read(authControllerProvider.notifier).openWithQrCode().whenComplete(() => _asking = false);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authStateProvider, (_, next) => _askIfWaiting(next.value));
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final desktop = AppPlatform.isDesktop;
    final state = ref.watch(authStateProvider).value;
    final endedAt = desktop ? ref.watch(preferencesProvider).sessionEndedAt : null;
    final link = state is td.AuthorizationStateWaitOtherDeviceConfirmation
        ? state.link
        : null;

    return AuthLayout(
      header: desktop ? const BrandLockup(markSize: 32) : null,
      title: 'Scan to sign in',
      subtitle: const Text(
        'On a phone that is signed in to Telegram, open Settings, then '
        'Devices, then Link Desktop Device, and scan this code.',
      ),
      onBack: desktop ? null : () => ref.read(authControllerProvider.notifier).editPhone(),
      primary: FilledButton(
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
        child: Text('Confirm in Telegram on ${AppPlatform.thisDevice}'),
      ),
      secondary: TextButton(
        onPressed: () => ref.read(authControllerProvider.notifier).usePhoneNumber(),
        child: const Text('Use phone number instead'),
      ),
      children: [
        if (endedAt != null) ...[
          Text(
            'Telegram ended your session on '
            '${DateFormat.E().add_jm().format(endedAt)}. Your files are safe '
            'in your channel. Sign in to continue.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: context.colors.text2,
              fontFeatures: tabularFigures,
            ),
          ),
          const SizedBox(height: Space.xl),
        ],
        Center(
          child: Container(
            padding: const EdgeInsets.all(Space.l),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(Radii.card),
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
                        eyeShape: QrEyeShape.square,
                        color: Color(0xFF15171B),
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: Color(0xFF15171B),
                      ),
                      embeddedImage: null,
                    ),
            ),
          ),
        ),
        const SizedBox(height: Space.m),
        Center(
          child: Text(
            'The code refreshes by itself.',
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
        const ConnectionNotice(margin: EdgeInsets.only(top: Space.l)),
        if (desktop) ...[
          const SizedBox(height: Space.xl),
          Center(
            child: Text(
              'Independent app, not affiliated with Telegram.',
              style: theme.textTheme.bodySmall?.copyWith(color: context.colors.text3),
            ),
          ),
        ],
      ],
    );
  }
}
