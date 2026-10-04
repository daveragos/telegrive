import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/tokens.dart';
import '../format/formatters.dart';

/// One labelled action in a [SelectionActionBar]. Without [onTap] it is
/// greyed out and does nothing, as before anything is picked.
class SelectionAction {
  const SelectionAction({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
}

/// What can be done with a selection, at the foot of the screen within
/// thumb reach: up to four actions, each an icon over its name, then More
/// for the rest. Screens show it as their Scaffold's bottomNavigationBar
/// while selecting. On a wide window, where the rail stands in for a
/// bottom bar, each name sits beside its icon instead.
///
/// Inside the shell, a status line the shell hands down through
/// [SelectionBarStatus] rides on top of the actions, since the shell's own
/// place for it, above its bar, has made way for this one.
class SelectionActionBar extends StatelessWidget {
  const SelectionActionBar({
    super.key,
    required this.actions,
    this.more = const <PopupMenuEntry<Object>>[],
    this.onMore,
  });

  /// The window width from which the actions sit in a row, as the shell
  /// switches to its rail there.
  static const double wideFrom = 840;

  /// Marks the wide layout's row of actions.
  static const wideKey = ValueKey('selection-actions-wide');

  static const double _height = 64;

  final List<SelectionAction> actions;

  /// The entries under More, which shows only when there are some.
  final List<PopupMenuEntry<Object>> more;

  /// Called with the value of the More entry picked.
  final ValueChanged<Object>? onMore;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final wide = MediaQuery.sizeOf(context).width >= wideFrom;
    final status = SelectionBarStatus.lineOf(context);
    final items = [
      for (final action in actions) _ActionButton(action: action, wide: wide),
      if (more.isNotEmpty) _MoreButton(entries: more, onSelected: onMore, wide: wide),
    ];

    return Material(
      color: colors.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            child: status ?? const SizedBox(width: double.infinity),
          ),
          DecoratedBox(
            decoration: BoxDecoration(border: Border(top: BorderSide(color: colors.line))),
            child: SafeArea(
              top: false,
              child: SizedBox(
                height: _height,
                child: wide
                    // Each action pads its own content, so the first icon
                    // lands on the screen's gutter.
                    ? Padding(
                        padding: const EdgeInsets.symmetric(horizontal: Space.gutter - Space.l),
                        child: Row(
                          key: wideKey,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: items,
                        ),
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [for (final item in items) Expanded(child: item)],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A status line for the selection bars below it to carry on top of their
/// actions. The shell puts it over its tabs while one of them is selecting,
/// so a change to many items still shows how far it got, above the bar
/// rather than under it.
class SelectionBarStatus extends InheritedWidget {
  const SelectionBarStatus({super.key, required this.line, required super.child});

  /// The line to show, or null for none.
  final Widget? line;

  static Widget? lineOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SelectionBarStatus>()?.line;

  @override
  bool updateShouldNotify(SelectionBarStatus oldWidget) => line != oldWidget.line;
}

/// An action's icon and name: one over the other, or side by side when
/// [wide], starting at the left so the row reads from the edge.
class _ActionContent extends StatelessWidget {
  const _ActionContent({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.wide,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = enabled ? colors.text2 : colors.text3;
    final glyph = Icon(icon, size: 24, color: color);
    final name = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: context.text.labelMedium?.copyWith(color: color),
    );
    if (wide) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.l),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [glyph, const SizedBox(width: Space.s), name],
        ),
      );
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [glyph, const SizedBox(height: Space.xs), name],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.action, required this.wide});

  final SelectionAction action;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final enabled = action.onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      child: InkWell(
        onTap: action.onTap,
        child: _ActionContent(
          icon: action.icon,
          label: action.label,
          enabled: enabled,
          wide: wide,
        ),
      ),
    );
  }
}

/// More, opening its menu just above the bar, so the menu never covers
/// the actions it adds to.
class _MoreButton extends StatelessWidget {
  const _MoreButton({required this.entries, required this.onSelected, required this.wide});

  final List<PopupMenuEntry<Object>> entries;
  final ValueChanged<Object>? onSelected;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    // The menu is laid out from its top, so it starts its own height above
    // the bar: its entries plus the menu's padding above and below them.
    final menuHeight = entries.fold<double>(2 * Space.s, (sum, entry) => sum + entry.height);
    return PopupMenuButton<Object>(
      tooltip: 'More',
      offset: Offset(0, -(menuHeight + Space.xs)),
      itemBuilder: (_) => entries,
      onSelected: onSelected,
      child: _ActionContent(
        icon: Icons.more_horiz_rounded,
        label: 'More',
        enabled: true,
        wide: wide,
      ),
    );
  }
}

/// The app bar while selecting: X to let go of the selection, and how many
/// are selected with what their files weigh, '6 selected · 48 MB'. Folders
/// add nothing to the size, so two folders read '2 selected'. After Select,
/// before anything is picked, it asks for some: 'Select items', or 'Select
/// photos' with [noun].
PreferredSizeWidget selectionAppBar(
  BuildContext context, {
  required int count,
  required int bytes,
  required VoidCallback onClear,
  String noun = 'items',
}) {
  return AppBar(
    backgroundColor: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5),
    leading: IconButton(
      onPressed: onClear,
      icon: const Icon(Icons.close_rounded),
      tooltip: 'Clear selection',
    ),
    title: Text(
      count == 0
          ? 'Select $noun'
          : [
              '${Formatters.number(count)} selected',
              if (bytes > 0) Formatters.bytes(bytes),
            ].join(' · '),
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontFeatures: tabularFigures),
    ),
  );
}

/// Whether the screen showing in the shell is selecting, so the shell can
/// give up its bottom bar to the selection's. Only screens inside the shell
/// set it; screens opened over the shell have no bar to give up.
class SelectionActive extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool active) {
    // A screen that goes while selecting says so once the frame is done,
    // which can be after the app itself has closed.
    if (!ref.mounted) return;
    if (state != active) state = active;
  }
}

final selectionActiveProvider = NotifierProvider<SelectionActive, bool>(SelectionActive.new);
