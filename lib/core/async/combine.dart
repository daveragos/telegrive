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
