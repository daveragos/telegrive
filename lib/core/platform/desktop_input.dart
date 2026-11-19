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
