import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// A photo that pinches to zoom and pans once zoomed, inside a viewer whose
/// pages swipe sideways and flick down to close.
///
/// Those swipes start at the phone's touch slop, a few pixels, while a
/// pinch only counts once the fingers have spread further; a pinch with one
/// finger held still and the other moving would always lose to them. So
/// while the photo is at its own size, two fingers down make a pinch at
/// once, and it zooms here. Once zoomed, the swipes step aside and
/// [InteractiveViewer] takes every pinch and pan, with its fling.
class PinchZoom extends StatefulWidget {
  const PinchZoom({
    super.key,
    required this.controller,
    this.maxScale = 6,
    required this.child,
  });

  final TransformationController controller;
  final double maxScale;

  /// Fills the viewer, as the photo's page does.
  final Widget child;

  @override
  State<PinchZoom> createState() => _PinchZoomState();
}

class _PinchZoomState extends State<PinchZoom> {
  Size _viewport = Size.zero;
  Matrix4 _start = Matrix4.identity();
  Offset _startFocal = Offset.zero;

  bool get _atOwnSize => widget.controller.value.getMaxScaleOnAxis() <= 1.01;

  void _begin(ScaleStartDetails details) {
    _start = widget.controller.value.clone();
    _startFocal = details.localFocalPoint;
  }

  void _update(ScaleUpdateDetails details) {
    final startScale = _start.getMaxScaleOnAxis();
    final scale = (startScale * details.scale).clamp(1.0, widget.maxScale);
    final by = scale / startScale;
    final focal = details.localFocalPoint;
    // The point under the fingers when they landed stays under them.
    final next = (Matrix4.identity()
          ..translateByDouble(focal.dx, focal.dy, 0, 1)
          ..scaleByDouble(by, by, 1, 1)
          ..translateByDouble(-_startFocal.dx, -_startFocal.dy, 0, 1))
        .multiplied(_start);
    // The photo always covers the viewer, as InteractiveViewer keeps it.
    final x = next.storage[12].clamp(_viewport.width * (1 - scale), 0.0);
    final y = next.storage[13].clamp(_viewport.height * (1 - scale), 0.0);
    widget.controller.value = next..setTranslationRaw(x, y, 0);
  }

  /// A pinch let go this close to the photo's own size goes back to it, so
  /// the swipes don't stay off for a zoom too small to see.
  static const _snapBelow = 1.1;

  void _settle() {
    if (widget.controller.value.getMaxScaleOnAxis() < _snapBelow) {
      widget.controller.value = Matrix4.identity();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _viewport = constraints.biggest;
        return RawGestureDetector(
          gestures: {
            _FirstPinch: GestureRecognizerFactoryWithHandlers<_FirstPinch>(
              () => _FirstPinch(atOwnSize: () => _atOwnSize),
              (pinch) => pinch
                ..onStart = _begin
                ..onUpdate = _update
                ..onEnd = (_) => _settle(),
            ),
          },
          child: InteractiveViewer(
            transformationController: widget.controller,
            minScale: 1,
            maxScale: widget.maxScale,
            onInteractionEnd: (_) => _settle(),
            child: widget.child,
          ),
        );
      },
    );
  }
}

/// A pinch that wins as soon as a second finger lands on a photo at its own
/// size, and never takes a gesture of one finger.
class _FirstPinch extends ScaleGestureRecognizer {
  _FirstPinch({required this.atOwnSize});

  final bool Function() atOwnSize;
  final _down = <int>{};

  @override
  bool isPointerAllowed(PointerDownEvent event) =>
      atOwnSize() && super.isPointerAllowed(event);

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    _down.add(event.pointer);
    if (_down.length >= 2) resolve(GestureDisposition.accepted);
  }

  @override
  void resolve(GestureDisposition disposition) {
    if (disposition == GestureDisposition.accepted && _down.length < 2) return;
    super.resolve(disposition);
  }

  @override
  void stopTrackingPointer(int pointer) {
    _down.remove(pointer);
    super.stopTrackingPointer(pointer);
  }

  @override
  String get debugDescription => 'first pinch';
}
