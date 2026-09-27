import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/tokens.dart';

/// A sentence and, when there is one, the action. Nothing decorative.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    this.icon,
    this.message,
    this.action,
    this.compact = false,
  });

  final String title;

  /// A small muted hint of what belongs here; optional.
  final IconData? icon;
  final String? message;
  final Widget? action;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: Space.x4,
          vertical: compact ? Space.xxl : Space.x4,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 28, color: colors.text3),
                const SizedBox(height: Space.m),
              ],
              Text(title, textAlign: TextAlign.center, style: context.text.titleMedium),
              if (message != null) ...[
                const SizedBox(height: Space.s),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: context.text.bodyMedium,
                ),
              ],
              if (action != null) ...[const SizedBox(height: Space.xl), action!],
            ],
          ),
        ),
      ),
    );
  }
}

/// Renders an [AsyncValue], with sensible loading and error defaults.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({
    super.key,
    required this.value,
    required this.data,
    this.loading,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final Widget? loading;

  @override
  Widget build(BuildContext context) {
    return switch (value) {
      AsyncData(:final value) => data(value),
      AsyncError(:final error) when !value.hasValue => EmptyState(
        title: 'This didn\'t load',
        message: '$error',
        compact: true,
      ),
      _ when value.hasValue => data(value.requireValue),
      _ => loading ?? const Center(child: CircularProgressIndicator()),
    };
  }
}

/// The small label that opens a group of rows.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing, this.padding});

  final String title;
  final Widget? trailing;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          padding ??
          const EdgeInsets.fromLTRB(Space.gutter, Space.x3, Space.m, Space.s),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 28),
        child: Row(
          children: [
            Expanded(child: Text(title, style: context.text.labelMedium)),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

/// Rows on one surface, split by inset hairlines — the settings-list shape.
class ListGroup extends StatelessWidget {
  const ListGroup({super.key, required this.children, this.margin});

  final List<Widget> children;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final rows = <Widget>[];
    for (final (index, child) in children.indexed) {
      if (index > 0) {
        rows.add(Divider(indent: Space.gutter, endIndent: 0, color: colors.line));
      }
      rows.add(child);
    }
    return Padding(
      padding: margin ?? const EdgeInsets.symmetric(horizontal: Space.l),
      child: Material(
        color: colors.surface,
        borderRadius: BorderRadius.circular(Radii.card),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        ),
      ),
    );
  }
}

/// A sentence about something in progress, with a thin bar under it. Used
/// for backup and transfers where a banner card would shout.
class StatusLine extends StatelessWidget {
  const StatusLine({
    super.key,
    required this.icon,
    required this.text,
    this.detail,
    this.progress,
    this.color,
    this.progressColor,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String text;
  final String? detail;

  /// 0..1 for a bar, null for none. Use a negative value for an
  /// indeterminate bar.
  final double? progress;
  final Color? color;

  /// The bar's colour when it isn't the accent: grey for work that is
  /// waiting rather than moving.
  final Color? progressColor;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tint = color ?? colors.text2;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.gutter, Space.m, Space.m, Space.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: tint),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(text, style: context.text.titleSmall),
                      if (detail != null && detail!.isNotEmpty)
                        Text(
                          detail!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.bodySmall?.copyWith(
                            fontFeatures: tabularFigures,
                          ),
                        ),
                    ],
                  ),
                ),
                if (trailing != null)
                  trailing!
                else if (onTap != null)
                  Icon(Icons.chevron_right_rounded, color: colors.text3),
              ],
            ),
            if (progress != null) ...[
              const SizedBox(height: Space.s),
              Padding(
                padding: const EdgeInsets.only(left: 32, right: Space.s),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: progress! < 0 ? null : progress,
                    minHeight: 4,
                    color: progressColor,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Rebuilds [builder] once a second with the time left until [until], for
/// a wait that counts down. Only what it builds ticks; the rest stays still.
class Countdown extends StatefulWidget {
  const Countdown({super.key, required this.until, required this.builder});

  final DateTime until;
  final Widget Function(BuildContext context, Duration left) builder;

  @override
  State<Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<Countdown> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = widget.until.difference(DateTime.now());
    return widget.builder(context, left.isNegative ? Duration.zero : left);
  }
}

/// How long Undo is offered after a change that can be taken back.
const undoWindow = Duration(seconds: 6);

/// How long a snack takes to come in, and again to leave. Its duration
/// counts from the moment it is fully in.
const snackTransition = Duration(milliseconds: 250);

/// Shows [message] at the foot of the screen for [duration], in place of
/// any snack already there, or after it with [queue]. Its time starts once
/// it is fully in, which [onVisible] hears. Every snack leaves when its
/// time is up, one with an action too, so an Undo is never offered after
/// its window has closed. With TalkBack or another screen reader on, one
/// with an action stays until it is used or dismissed instead, since it
/// takes longer to reach; what the action stands for keeps its own time,
/// so a delete for good still runs and a late Undo says it was too late.
/// Returns the snack's controller, whose `closed` says how it went, or null
/// when there is nowhere to show it.
ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? showSnack(
  BuildContext context,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
  Duration duration = const Duration(seconds: 4),
  bool queue = false,
  VoidCallback? onVisible,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return null;
  final screenReader = MediaQuery.maybeAccessibleNavigationOf(context) ?? false;
  if (!queue) messenger.hideCurrentSnackBar();
  return messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      duration: duration,
      persist: screenReader ? null : false,
      onVisible: onVisible,
      action: actionLabel == null
          ? null
          : SnackBarAction(label: actionLabel, onPressed: onAction ?? () {}),
    ),
  );
}

/// A change that can be taken back: [message] says what happened, in the
/// past tense, and Undo calls [onUndo] for [duration].
ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? showUndoSnack(
  BuildContext context,
  String message, {
  required VoidCallback onUndo,
  Duration duration = undoWindow,
  VoidCallback? onVisible,
}) => showSnack(
  context,
  message,
  actionLabel: 'Undo',
  onAction: onUndo,
  duration: duration,
  onVisible: onVisible,
);

/// Asks for a single line of text (folder name, rename).
Future<String?> showTextInputDialog(
  BuildContext context, {
  required String title,
  String initialValue = '',
  String hint = '',
  String confirmLabel = 'Save',
  bool selectStem = false,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _TextInputDialog(
      title: title,
      initialValue: initialValue,
      hint: hint,
      confirmLabel: confirmLabel,
      selectStem: selectStem,
    ),
  );
}

class _TextInputDialog extends StatefulWidget {
  const _TextInputDialog({
    required this.title,
    required this.initialValue,
    required this.hint,
    required this.confirmLabel,
    required this.selectStem,
  });

  final String title;
  final String initialValue;
  final String hint;
  final String confirmLabel;
  final bool selectStem;

  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    // Renaming "report.pdf" selects "report", so typing replaces the name
    // and keeps the extension, the way desktop file managers do it.
    final dot = widget.initialValue.lastIndexOf('.');
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.selectStem && dot > 0 ? dot : widget.initialValue.length,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(hintText: widget.hint),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ValueListenableBuilder(
          valueListenable: _controller,
          builder: (context, value, _) => TextButton(
            onPressed: value.text.trim().isEmpty ? null : _submit,
            child: Text(widget.confirmLabel),
          ),
        ),
      ],
    );
  }
}

Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) {
      final colors = context.colors;
      return AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: destructive ? colors.danger : colors.accent,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return result ?? false;
}
