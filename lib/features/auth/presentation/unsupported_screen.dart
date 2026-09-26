import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;

import '../../../infrastructure/telegram/telegram_client.dart';
import '../data/auth_controller.dart';
import 'auth_layout.dart';

/// Sign-in states Telegrive leaves to the official app: creating a brand new
/// Telegram account, or setting up a login email.
class UnsupportedAuthScreen extends ConsumerWidget {
  const UnsupportedAuthScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(authStateProvider).value;
    final isRegistration = state is td.AuthorizationStateWaitRegistration;

    return AuthLayout(
      title: isRegistration ? 'No Telegram account yet' : 'Finish in Telegram',
      subtitle: Text(
        isRegistration
            ? 'This number isn\'t on Telegram. Create an account in the official '
                  'Telegram app first, then come back and sign in.'
            : 'Telegram wants to set up a login email for this account. Do it '
                  'once in the official Telegram app, then sign in here again.',
      ),
      primary: FilledButton(
        onPressed: () => ref.read(authControllerProvider.notifier).editPhone(),
        child: const Text('Use a different number'),
      ),
      children: const [],
    );
  }
}
