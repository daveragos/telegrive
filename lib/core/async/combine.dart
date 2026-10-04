import 'dart:async';

/// Emits [combine] of the latest values once both streams have produced one.
Stream<R> combineLatest2<A, B, R>(
  Stream<A> first,
  Stream<B> second,
  R Function(A a, B b) combine,
) {
  late final StreamController<R> controller;
  StreamSubscription<A>? subA;
  StreamSubscription<B>? subB;
  late A lastA;
  late B lastB;
  var hasA = false;
  var hasB = false;

  controller = StreamController<R>(
    onListen: () {
      subA = first.listen((value) {
        lastA = value;
        hasA = true;
        if (hasB) controller.add(combine(lastA, lastB));
      }, onError: controller.addError);
      subB = second.listen((value) {
        lastB = value;
        hasB = true;
        if (hasA) controller.add(combine(lastA, lastB));
      }, onError: controller.addError);
    },
    onPause: () {
      subA?.pause();
      subB?.pause();
    },
    onResume: () {
      subA?.resume();
      subB?.resume();
    },
    onCancel: () async {
      await subA?.cancel();
      await subB?.cancel();
    },
  );
  return controller.stream;
}

/// [source] at most once per [interval]: the first event at once, then,
/// at the end of each interval that saw events, the latest of them. Events
/// in between are dropped, since each one replaces the last. One still
/// waiting when [source] closes is delivered before the close.
Stream<T> throttleLatest<T>(Stream<T> source, Duration interval) {
  late final StreamController<T> controller;
  StreamSubscription<T>? subscription;
  Timer? window;
  late T latest;
  var waiting = false;

  void open() {
    window = Timer(interval, () {
      window = null;
      if (!waiting) return;
      waiting = false;
      controller.add(latest);
      open();
    });
  }

  controller = StreamController<T>(
    onListen: () {
      subscription = source.listen(
        (value) {
          if (window == null) {
            controller.add(value);
            open();
          } else {
            latest = value;
            waiting = true;
          }
        },
        onError: controller.addError,
        onDone: () {
          subscription = null;
          window?.cancel();
          window = null;
          if (waiting) {
            waiting = false;
            controller.add(latest);
          }
          controller.close();
        },
      );
    },
    onPause: () => subscription?.pause(),
    onResume: () => subscription?.resume(),
    onCancel: () {
      window?.cancel();
      return subscription?.cancel();
    },
  );
  return controller.stream;
}
