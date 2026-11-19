import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';
import '../platform/app_platform.dart';

/// How a sheet shows on a computer, where a phone has a sheet from the
/// foot for everything.
enum SheetKind {
  /// A list of actions, opening where it was asked for: at the pointer
  /// for a right-click, at the ⋮ button for a click on it.
  menu,

  /// A choice to make or something to fill in, in the middle of the
  /// window.
  dialog,
}

/// Where a pointer last went down in the app, for a menu to open there.
abstract final class PointerPlace {
  static Offset? last;
}

/// Notes where each pointer goes down beneath it, for [PointerPlace].
class PointerPlaceRecorder extends StatelessWidget {
  const PointerPlaceRecorder({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (event) => PointerPlace.last = event.position,
    child: child,
  );
}

/// A sheet from the foot on a phone; on a computer a menu at the pointer or
/// a dialog, as [kind] says. [builder] draws the same content in each, and
/// closes it with `Navigator.pop` as a sheet's does.
Future<T?> showAdaptiveSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  SheetKind kind = SheetKind.menu,
  bool useRootNavigator = true,
  bool isScrollControlled = false,
  bool useSafeArea = false,
}) {
  if (!AppPlatform.isDesktop) {
    return showModalBottomSheet<T>(
      context: context,
      useRootNavigator: useRootNavigator,
      isScrollControlled: isScrollControlled,
      useSafeArea: useSafeArea,
      builder: builder,
    );
  }
  if (kind == SheetKind.dialog) {
    return showDialog<T>(
      context: context,
      useRootNavigator: useRootNavigator,
      builder: (dialogContext) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 520,
            maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.85,
          ),
          // The room a sheet's handle gives its first line on a phone.
          child: Padding(padding: const EdgeInsets.only(top: Space.m), child: builder(dialogContext)),
        ),
      ),
    );
  }
  final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
  return navigator.push(
    _MenuRoute<T>(
      anchor: PointerPlace.last,
      builder: builder,
      themes: InheritedTheme.capture(from: context, to: navigator.context),
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    ),
  );
}

/// A card of actions at [anchor], kept inside the window.
class _MenuRoute<T> extends PopupRoute<T> {
  _MenuRoute({
    required this.anchor,
    required this.builder,
    required this.themes,
    required this.barrierLabel,
  });

  final Offset? anchor;
  final WidgetBuilder builder;
  final CapturedThemes themes;

  static const double width = 300;

  @override
  final String barrierLabel;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 120);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) {
    final size = MediaQuery.sizeOf(context);
    return themes.wrap(
      CustomSingleChildLayout(
        delegate: _MenuLayout(anchor ?? size.center(Offset.zero)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: width,
            maxWidth: width,
            maxHeight: math.max(0, size.height - 2 * _MenuLayout.margin),
          ),
          child: Material(
            elevation: 8,
            color: context.colors.surface,
            clipBehavior: Clip.antiAlias,
            borderRadius: BorderRadius.circular(Radii.card),
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              removeBottom: true,
              // Rows as close as a computer's menus have them, under a
              // little room at the top where a phone's sheet has its handle.
              child: Padding(
                padding: const EdgeInsets.only(top: Space.xs),
                child: ListTileTheme.merge(
                  contentPadding: const EdgeInsets.symmetric(horizontal: Space.l),
                  minVerticalPadding: Space.xs,
                  minTileHeight: 36,
                  horizontalTitleGap: Space.m,
                  minLeadingWidth: 20,
                  child: IconTheme.merge(data: const IconThemeData(size: 20), child: Builder(builder: builder)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => FadeTransition(opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut), child: child);
}

/// Puts a menu's top-left corner at the anchor, moved left or up as far as
/// it needs to stay [margin] inside the window.
class _MenuLayout extends SingleChildLayoutDelegate {
  _MenuLayout(this.anchor);

  final Offset anchor;

  static const double margin = 8;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) => constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    var x = anchor.dx;
    var y = anchor.dy;
    if (x + childSize.width > size.width - margin) x = anchor.dx - childSize.width;
    if (y + childSize.height > size.height - margin) y = size.height - margin - childSize.height;
    return Offset(
      x.clamp(margin, math.max(margin, size.width - margin - childSize.width)),
      y.clamp(margin, math.max(margin, size.height - margin - childSize.height)),
    );
  }

  @override
  bool shouldRelayout(_MenuLayout old) => old.anchor != anchor;
}
