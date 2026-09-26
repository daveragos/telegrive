import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;

import '../../../infrastructure/telegram/telegram_client.dart';
import '../../../infrastructure/telegram/telegram_exception.dart';
import '../data/auth_controller.dart';
import 'auth_layout.dart';

class CodeScreen extends ConsumerStatefulWidget {
  const CodeScreen({super.key});

  @override
  ConsumerState<CodeScreen> createState() => _CodeScreenState();
}

class _CodeScreenState extends ConsumerState<CodeScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;
  Timer? _ticker;
  int _resendIn = 0;

  @override
  void initState() {
    super.initState();
    final state = ref.read(authStateProvider).value;
    if (state is td.AuthorizationStateWaitCode) _startCountdown(state.codeInfo.timeout);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _code.dispose();
    super.dispose();
  }

  void _startCountdown(int seconds) {
    _ticker?.cancel();
    setState(() => _resendIn = seconds);
    if (seconds <= 0) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() => _resendIn--);
      if (_resendIn <= 0) timer.cancel();
    });
  }

  Future<void> _submit() async {
    final code = _code.text.trim();
    if (code.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).submitCode(code);
    } on TelegramException catch (e) {
      if (mounted) {
        setState(() => _error = e.friendlyMessage);
        _code.clear();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    try {
      await ref.read(authControllerProvider.notifier).resendCode();
    } on TelegramException catch (e) {
      if (mounted) setState(() => _error = e.friendlyMessage);
    }
  }

  static int _lengthOf(td.AuthenticationCodeType type) => switch (type) {
    td.AuthenticationCodeTypeTelegramMessage(:final length) => length,
    td.AuthenticationCodeTypeSms(:final length) => length,
    td.AuthenticationCodeTypeCall(:final length) => length,
    td.AuthenticationCodeTypeMissedCall(:final length) => length,
    td.AuthenticationCodeTypeFragment(:final length) => length,
    td.AuthenticationCodeTypeFirebaseAndroid(:final length) => length,
    td.AuthenticationCodeTypeFirebaseIos(:final length) => length,
    _ => 0,
  };

  static String _whereSent(td.AuthenticationCodeInfo info) => switch (info.type) {
    td.AuthenticationCodeTypeTelegramMessage() =>
      'We sent a code to your Telegram app. Check the chat from "Telegram" on '
          'any device you\'re signed in on.',
    td.AuthenticationCodeTypeSms() ||
    td.AuthenticationCodeTypeSmsWord() ||
    td.AuthenticationCodeTypeSmsPhrase() ||
    td.AuthenticationCodeTypeFirebaseAndroid() ||
    td.AuthenticationCodeTypeFirebaseIos() =>
      'We sent an SMS with a code to ${info.phoneNumber}.',
    td.AuthenticationCodeTypeCall() =>
      'You\'ll get a phone call at ${info.phoneNumber} that reads out the code.',
    td.AuthenticationCodeTypeMissedCall(:final phoneNumberPrefix) =>
      'You\'ll get a missed call. The code is the last digits of the number, '
          'after $phoneNumberPrefix.',
    td.AuthenticationCodeTypeFlashCall() =>
      'You\'ll get a call that ends immediately. The code is in the number.',
    td.AuthenticationCodeTypeFragment() =>
      'The code was sent to your anonymous number on Fragment.',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(authStateProvider).value;
    final info = state is td.AuthorizationStateWaitCode ? state.codeInfo : null;
    final length = info == null ? 0 : _lengthOf(info.type);

    return AuthLayout(
      title: 'Enter the code',
      subtitle: Text(info == null ? '' : _whereSent(info)),
      primary: BusyButton(label: 'Continue', busy: _busy, onPressed: _submit),
      secondary: TextButton(
        onPressed: () => ref.read(authControllerProvider.notifier).editPhone(),
        child: const Text('Wrong number? Change it'),
      ),
      children: [
        TextField(
          controller: _code,
          autofocus: true,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          autofillHints: const [AutofillHints.oneTimeCode],
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            if (length > 0) LengthLimitingTextInputFormatter(length),
          ],
          style: theme.textTheme.headlineMedium?.copyWith(
            letterSpacing: 10,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
          decoration: InputDecoration(
            hintText: length > 0 ? '•' * length : 'Code',
            hintStyle: theme.textTheme.headlineMedium?.copyWith(
              letterSpacing: 10,
              color: theme.colorScheme.outlineVariant,
            ),
          ),
          onChanged: (value) {
            if (length > 0 && value.length == length) _submit();
          },
          onSubmitted: (_) => _submit(),
        ),
        FormError(_error),
        const SizedBox(height: 12),
        if (info?.nextType != null)
          Center(
            child: TextButton(
              onPressed: _resendIn > 0 ? null : _resend,
              child: Text(
                _resendIn > 0
                    ? 'Send another way in 0:${_resendIn.toString().padLeft(2, '0')}'
                    : 'Didn\'t get it? Send another way',
              ),
            ),
          ),
      ],
    );
  }
}
