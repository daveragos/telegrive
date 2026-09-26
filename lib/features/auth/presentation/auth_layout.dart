import 'package:flutter/material.dart';

import '../../../app/theme/tokens.dart';

/// Shared frame for every sign-in step: what is being asked, a line on why,
/// the field, and one obvious next action pinned above the keyboard.
class AuthLayout extends StatelessWidget {
  const AuthLayout({
    super.key,
    required this.title,
    required this.subtitle,
    required this.children,
    this.primary,
    this.secondary,
    this.onBack,
  });

  final String title;
  final Widget subtitle;
  final List<Widget> children;
  final Widget? primary;
  final Widget? secondary;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: onBack == null
            ? null
            : IconButton(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: 'Back',
              ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(Space.xxl, Space.s, Space.xxl, Space.xxl),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: context.text.headlineSmall),
                        const SizedBox(height: Space.s),
                        DefaultTextStyle.merge(
                          style: context.text.bodyLarge?.copyWith(color: context.colors.text2),
                          child: subtitle,
                        ),
                        const SizedBox(height: Space.xxl),
                        ...children,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (primary != null || secondary != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.xxl, 0, Space.xxl, Space.l),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ?primary,
                      if (secondary != null) ...[
                        const SizedBox(height: Space.xs),
                        secondary!,
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Primary button that shows a spinner while [busy].
class BusyButton extends StatelessWidget {
  const BusyButton({
    super.key,
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: busy ? null : onPressed,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 150),
        child: busy
            ? const SizedBox.square(
                key: ValueKey('busy'),
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(label, key: const ValueKey('label')),
      ),
    );
  }
}

/// Inline error under a form.
class FormError extends StatelessWidget {
  const FormError(this.message, {super.key});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      child: message == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(top: Space.m),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline_rounded, size: 18, color: colors.danger),
                  const SizedBox(width: Space.s),
                  Expanded(
                    child: Text(
                      message!,
                      style: context.text.bodyMedium?.copyWith(color: colors.danger),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
