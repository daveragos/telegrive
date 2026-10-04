import 'package:flutter/material.dart';

/// Lets a full-screen page be flicked down to close it or up for its
/// details. The child follows the finger and fades as it goes; a drag too
/// short to count slides it back.
///
/// Only vertical drags are claimed, so taps, double-taps and the page
/// swipes around it keep working. Nested inside an InteractiveViewer, its
/// drag wins at touch slop, before the viewer's pan does; turn it off with
/// [enabled] while the content is zoomed so panning has the drag.
class VerticalSwipe extends StatefulWidget {
  const VerticalSwipe({
    super.key,
    this.enabled = true,
    required this.onDismiss,
    required this.onSwipeUp,
    this.onDragging,
    required this.child,
  });

  /// How far down a drag must go to close the page.
  static const dismissDistance = 120.0;

  /// How far up a drag must go to open the details.
  static const detailsDistance = 60.0;

  /// A release faster than this, in logical pixels a second, counts in its
  /// direction however short the drag.
  static const flingVelocity = 700.0;

  /// The child follows an upward drag only this far.
  static const upLimit = 80.0;

  /// The child is at its faintest, 40 %, this far from where it started.
  static const fadeDistance = 300.0;

  /// The slide back after a drag that didn't count.
  static const snapBack = Duration(milliseconds: 150);

  final bool enabled;

  /// Called on a release far or fast enough downwards. It is meant to close
  /// the page, so the child stays where the finger left it.
  final VoidCallback onDismiss;

  /// Called on a release far or fast enough upwards, as the child slides
  /// back. Drags are ignored until its future completes, so one that starts
  /// while a details sheet is on its way can't close the page under it.
  final Future<void> Function() onSwipeUp;

  /// Told true when a drag starts and false when it ends without closing
  /// the page, so the screen can hide its bars meanwhile.
  final ValueChanged<bool>? onDragging;

  final Widget child;

  @override
  State<VerticalSwipe> createState() => _VerticalSwipeState();
}

class _VerticalSwipeState extends State<VerticalSwipe> with SingleTickerProviderStateMixin {
  late final AnimationController _back = AnimationController(
    vsync: this,
    duration: VerticalSwipe.snapBack,
  )..addListener(() => setState(() => _dy = _from * (1 - Curves.easeOut.transform(_back.value))));

  /// How far the child has moved, down positive.
  double _dy = 0;

  /// Where the slide back started.
  double _from = 0;

  /// Set while [VerticalSwipe.onSwipeUp]'s future runs.
  bool _busy = false;

  /// Set once a release has closed the page.
  bool _gone = false;

  @override
  void dispose() {
    _back.dispose();
    super.dispose();
  }

  bool get _armed => widget.enabled && !_busy && !_gone;

  void _start(DragStartDetails details) {
    _back.stop();
    widget.onDragging?.call(true);
  }

  void _update(DragUpdateDetails details) {
    setState(() {
      _dy = (_dy + details.delta.dy).clamp(-VerticalSwipe.upLimit, double.infinity);
    });
  }

  void _end(DragEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond.dy;
    if (_dy > VerticalSwipe.dismissDistance || velocity > VerticalSwipe.flingVelocity) {
      setState(() => _gone = true);
      widget.onDismiss();
      return;
    }
    final up = _dy < -VerticalSwipe.detailsDistance || velocity < -VerticalSwipe.flingVelocity;
    widget.onDragging?.call(false);
    if (_dy != 0) {
      _from = _dy;
      _back.forward(from: 0);
    }
    if (up) {
      setState(() => _busy = true);
      widget.onSwipeUp().whenComplete(() {
        if (mounted) setState(() => _busy = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final armed = _armed;
    final fade = (_dy.abs() / VerticalSwipe.fadeDistance * 0.6).clamp(0.0, 0.6);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragStart: armed ? _start : null,
      onVerticalDragUpdate: armed ? _update : null,
      onVerticalDragEnd: armed ? _end : null,
      child: Transform.translate(
        offset: Offset(0, _dy),
        child: Opacity(opacity: 1 - fade, child: widget.child),
      ),
    );
  }
}
