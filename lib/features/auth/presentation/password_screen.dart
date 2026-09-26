import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;

import '../../../infrastructure/telegram/telegram_client.dart';
import '../../../infrastructure/telegram/telegram_exception.dart';
import '../data/auth_controller.dart';
import 'auth_layout.dart';

class PasswordScreen extends ConsumerStatefulWidget {
  const PasswordScreen({super.key});

  @override
  ConsumerState<PasswordScreen> createState() => _PasswordScreenState();
}

class _PasswordScreenState extends ConsumerState<PasswordScreen> {
  final _password = TextEditingController();
  bool _obscured = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_password.text.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).submitPassword(_password.text);
    } on TelegramException catch (e) {
      if (mounted) setState(() => _error = e.friendlyMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authStateProvider).value;
    final hint = state is td.AuthorizationStateWaitPassword ? state.passwordHint : '';

    return AuthLayout(
      title: 'Two-step verification',
      subtitle: const Text(
        'Your account has an extra password. Enter it to finish signing in.',
      ),
      primary: BusyButton(label: 'Unlock', busy: _busy, onPressed: _submit),
      children: [
        TextField(
          controller: _password,
          autofocus: true,
          obscureText: _obscured,
          autofillHints: const [AutofillHints.password],
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            labelText: 'Password',
            helperText: hint.isEmpty ? null : 'Hint: $hint',
            prefixIcon: const Icon(Icons.password_rounded),
            suffixIcon: IconButton(
              onPressed: () => setState(() => _obscured = !_obscured),
              icon: Icon(
                _obscured ? Icons.visibility_rounded : Icons.visibility_off_rounded,
              ),
              tooltip: _obscured ? 'Show password' : 'Hide password',
            ),
          ),
        ),
        FormError(_error),
      ],
    );
  }
}
