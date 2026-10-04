import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;

import '../../../app/theme/tokens.dart';
import '../../../infrastructure/telegram/telegram_client.dart';
import '../../../infrastructure/telegram/telegram_exception.dart';
import '../../network/presentation/connection_notice.dart';
import '../data/auth_controller.dart';
import 'auth_layout.dart';

class PhoneScreen extends ConsumerStatefulWidget {
  const PhoneScreen({super.key});

  @override
  ConsumerState<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends ConsumerState<PhoneScreen> {
  final _phone = TextEditingController(text: '+');
  bool _busy = false;
  bool _qrBusy = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  bool get _valid => _phone.text.replaceAll(RegExp(r'\D'), '').length >= 7;

  Future<void> _submit() async {
    if (!_valid) {
      setState(() => _error = 'Enter your full number, starting with the country code.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).submitPhone(_phone.text);
    } on TelegramException catch (e) {
      if (mounted) setState(() => _error = e.friendlyMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _useQr() async {
    setState(() {
      _qrBusy = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).requestQrCode();
    } on TelegramException catch (e) {
      if (mounted) setState(() => _error = e.friendlyMessage);
    } finally {
      if (mounted) setState(() => _qrBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = ref.watch(authStateProvider).value;
    final editing = ref.watch(authControllerProvider).editingPhone;
    final canGoBack = editing && auth is! td.AuthorizationStateWaitPhoneNumber;

    return AuthLayout(
      title: 'Sign in to Telegram',
      subtitle: const Text(
        'Enter the number of the Telegram account your drive belongs to, '
        'starting with the country code.',
      ),
      onBack: canGoBack
          ? () => ref.read(authControllerProvider.notifier).cancelEditPhone()
          : () => ref.invalidate(authControllerProvider),
      primary: BusyButton(label: 'Send code', busy: _busy, onPressed: _submit),
      secondary: TextButton(
        onPressed: _qrBusy || _busy ? null : _useQr,
        child: _qrBusy
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Sign in with a QR code instead'),
      ),
      children: [
        TextField(
          controller: _phone,
          autofocus: true,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.telephoneNumber],
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[\d+ ]')),
            _LeadingPlusFormatter(),
          ],
          style: theme.textTheme.bodyLarge?.copyWith(
            fontSize: 18,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
          onSubmitted: (_) => _submit(),
          decoration: const InputDecoration(hintText: '+251 91 234 5678'),
        ),
        FormError(_error),
        const ConnectionNotice(margin: EdgeInsets.only(top: Space.l)),
      ],
    );
  }
}

/// Keeps exactly one `+` at the front, which is what Telegram expects.
class _LeadingPlusFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll('+', '');
    final text = '+$digits';
    final offset = (newValue.selection.end + (text.length - newValue.text.length))
        .clamp(1, text.length);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}
