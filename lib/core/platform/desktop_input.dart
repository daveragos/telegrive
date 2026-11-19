import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'app_platform.dart';

/// The keyboard and mouse conventions of the computer the app runs on.
abstract final class DesktopInput {
  static bool get _mac => defaultTargetPlatform == TargetPlatform.macOS;

  /// Whether the click under way adds one item to the selection, or takes
  /// it out: with Cmd on a Mac, Ctrl on Windows and Linux. A phone has no
  /// such click.
  static bool get addingClick {
    if (!AppPlatform.isDesktop) return false;
    final keyboard = HardwareKeyboard.instance;
    return _mac ? keyboard.isMetaPressed : keyboard.isControlPressed;
  }

  /// Whether the click under way picks the run of items from the last one
  /// clicked, as Shift does.
  static bool get runClick => AppPlatform.isDesktop && HardwareKeyboard.instance.isShiftPressed;

  /// Whether a scroll under way zooms instead, with Cmd held on a Mac or
  /// Ctrl elsewhere.
  static bool get zoomScroll => addingClick;

  /// [key] with Cmd on a Mac, Ctrl elsewhere.
  static SingleActivator command(LogicalKeyboardKey key, {bool shift = false}) =>
      SingleActivator(key, meta: _mac, control: !_mac, shift: shift);

  /// The keys that move a page's item to the trash: Delete, and on a Mac
  /// Cmd-Backspace as in Finder.
  static List<SingleActivator> get trash => [
    const SingleActivator(LogicalKeyboardKey.delete),
    if (_mac) const SingleActivator(LogicalKeyboardKey.backspace, meta: true),
  ];

  /// The keys for the folder above: Cmd-Up on a Mac, Alt-Up elsewhere.
  static SingleActivator get up => SingleActivator(LogicalKeyboardKey.arrowUp, meta: _mac, alt: !_mac);
}

/// Find, from the Mac's menu bar: the page with the keys searches what it
/// shows, as Files searches the folder open in it. Nothing answering it,
/// the menu opens Search.
class FindIntent extends Intent {
  const FindIntent();
}

/// Tells a double-click from two clicks, by what the last plain click was
/// on and when, as a computer's file manager does: one click selects an
/// item there and then, and a second on it within [within] opens it. A
/// tap and double-tap recognizer would hold every click back by the wait.
class DoubleClick {
  DoubleClick({this.within = const Duration(milliseconds: 500), DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final Duration within;
  final DateTime Function() _clock;
  Object? _last;
  DateTime? _at;

  /// Whether this click on [item] is the second of a double-click. A third
  /// starts over.
  bool on(Object item) {
    final now = _clock();
    final second = _last == item && _at != null && now.difference(_at!) < within;
    _last = second ? null : item;
    _at = second ? null : now;
    return second;
  }
}

/// Keeps a page's keys with the page on a computer, as a window's file list
/// has them: it takes them when it shows, again whenever it comes back into
/// view, as a tab switched to or a folder gone back to does, and when it's
/// clicked. Its shortcuts and the Mac's menu bar reach it that way, which
/// they don't while the keys sit with the route around it. A text field
/// being typed in keeps them.
class PageKeys extends StatefulWidget {
  const PageKeys({super.key, required this.child});

  final Widget child;

  @override
  State<PageKeys> createState() => _PageKeysState();
}

class _PageKeysState extends State<PageKeys> {
  final _node = FocusNode(debugLabel: 'PageKeys');
  bool _shown = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shown = TickerMode.valuesOf(context).enabled;
    if (shown && !_shown) _take();
    _shown = shown;
  }

  /// Takes the keys once the frame is done: by then a click outside a text
  /// field has taken them from it, and one in it has left them there.
  void _take() {
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        if (!mounted || _node.hasFocus) return;
        final typing = primaryFocus?.context?.findAncestorStateOfType<EditableTextState>() != null;
        if (!typing) _node.requestFocus();
      })
      ..ensureVisualUpdate();
  }

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (_) => _take(),
    child: Focus(focusNode: _node, child: widget.child),
  );
}
