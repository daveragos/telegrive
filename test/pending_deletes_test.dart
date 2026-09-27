import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegrive/features/trash/data/pending_deletes.dart';
import 'package:telegrive/infrastructure/telegram/telegram_exception.dart';

void main() {
  late ProviderContainer container;

  PendingDeletes pending() => container.read(pendingDeletesProvider.notifier);
  PendingDeletesState state() => container.read(pendingDeletesProvider);

  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  test('hides at once and deletes once ten seconds are up', () {
    fakeAsync((async) {
      var runs = 0;
      pending().schedule(
        fileIds: {'a'},
        folderIds: {'docs'},
        label: '2 items',
        run: () async => runs++,
      );

      expect(state().hiddenIds, {'a', 'docs'});
      async.elapse(const Duration(seconds: 9));
      expect(runs, 0);
      expect(state().hiddenIds, {'a', 'docs'});

      async.elapse(const Duration(seconds: 1));
      expect(runs, 1);
      expect(state().hiddenIds, isEmpty);
      expect(state().lastFailure, isNull);

      async.elapse(const Duration(minutes: 1));
      expect(runs, 1);
    });
  });

  test('undo within the window keeps everything', () {
    fakeAsync((async) {
      var runs = 0;
      final token = pending().schedule(
        albumIds: {'trip'},
        label: '"Trip"',
        run: () async => runs++,
      );
      async.elapse(const Duration(seconds: 5));

      expect(pending().undo(token), isTrue);
      expect(state().hiddenIds, isEmpty);
      async.elapse(const Duration(minutes: 1));
      expect(runs, 0);
      expect(pending().undo(token), isFalse);
    });
  });

  test('flush deletes what is waiting straight away', () {
    fakeAsync((async) {
      var runs = 0;
      final token = pending().schedule(
        fileIds: {'a'},
        label: '"a.pdf"',
        run: () async => runs++,
      );

      pending().flush();
      async.flushMicrotasks();
      expect(runs, 1);
      expect(state().hiddenIds, isEmpty);
      expect(pending().undo(token), isFalse);
      async.elapse(const Duration(seconds: 10));
      expect(runs, 1);
    });
  });

  test('a second delete sends the first on its way, since its Undo is gone', () {
    fakeAsync((async) {
      final runs = <String>[];
      final first = pending().schedule(
        fileIds: {'a'},
        label: '"a.pdf"',
        run: () async => runs.add('a'),
      );
      pending().schedule(
        fileIds: {'b'},
        label: '"b.pdf"',
        run: () async => runs.add('b'),
      );
      async.flushMicrotasks();

      expect(runs, ['a']);
      expect(state().hiddenIds, {'b'});
      expect(pending().undo(first), isFalse);
      async.elapse(const Duration(seconds: 10));
      expect(runs, ['a', 'b']);
    });
  });

  test('what is being deleted stays hidden until Telegram answers', () {
    fakeAsync((async) {
      final answer = Completer<void>();
      final token = pending().schedule(
        fileIds: {'a'},
        label: '"a.pdf"',
        run: () => answer.future,
      );
      async.elapse(const Duration(seconds: 10));

      expect(state().hiddenIds, {'a'});
      expect(pending().undo(token), isFalse);
      answer.complete();
      async.flushMicrotasks();
      expect(state().hiddenIds, isEmpty);
    });
  });

  test('a delete that fails brings the items back and says why', () {
    fakeAsync((async) {
      pending().schedule(
        fileIds: {'a', 'b', 'c'},
        label: '3 items',
        run: () async => throw const TelegramException(420, 'FLOOD_WAIT_30'),
      );
      async.elapse(const Duration(seconds: 10));

      expect(state().hiddenIds, isEmpty);
      expect(state().lastFailure?.message, startsWith('Couldn\'t delete 3 items for good: '));
      expect(state().lastFailure?.message, contains('Too many attempts'));
    });
  });

  test('the same failure twice is a new failure each time', () {
    fakeAsync((async) {
      final failures = <DeleteFailure?>[];
      container.listen(
        pendingDeletesProvider.select((s) => s.lastFailure),
        (_, next) => failures.add(next),
      );
      for (var i = 0; i < 2; i++) {
        pending().commit(
          pending().schedule(
            label: '3 items from this phone',
            failure: 'Couldn\'t delete 3 items from this phone',
            needsForeground: true,
            run: () async => throw Exception('deleteWithIds failed'),
          ),
        );
        async.flushMicrotasks();
      }

      expect(failures.nonNulls.map((f) => f.message), [
        'Couldn\'t delete 3 items from this phone',
        'Couldn\'t delete 3 items from this phone',
      ]);
    });
  });

  test('going to the background deletes for good at once', () {
    fakeAsync((async) {
      var runs = 0;
      pending().schedule(fileIds: {'a'}, label: '"a.pdf"', run: () async => runs++);

      pending().appPaused();
      async.flushMicrotasks();
      expect(runs, 1);
    });
  });

  test('commit runs a delete as soon as its Undo closes unused', () {
    fakeAsync((async) {
      var runs = 0;
      final token = pending().schedule(
        label: '3 items from this phone',
        needsForeground: true,
        run: () async => runs++,
      );
      async.elapse(const Duration(seconds: 6));
      expect(runs, 0);

      pending().commit(token);
      async.flushMicrotasks();
      expect(runs, 1);
      expect(pending().undo(token), isFalse);
      async.elapse(const Duration(seconds: 10));
      expect(runs, 1);
    });
  });

  test('a phone delete waits out the background and runs on return', () {
    fakeAsync((async) {
      var runs = 0;
      final token = pending().schedule(
        label: '3 items from this phone',
        needsForeground: true,
        run: () async => runs++,
      );

      pending().appPaused();
      async.flushMicrotasks();
      expect(runs, 0);

      // Its window closes while the app is away.
      pending().commit(token);
      async.elapse(const Duration(minutes: 1));
      expect(runs, 0);

      pending().appResumed();
      async.flushMicrotasks();
      expect(runs, 1);
    });
  });

  test('a phone delete back in front before its window closes still waits for it', () {
    fakeAsync((async) {
      var runs = 0;
      final token = pending().schedule(
        label: '3 items from this phone',
        needsForeground: true,
        run: () async => runs++,
      );

      pending().appPaused();
      async.elapse(const Duration(seconds: 2));
      pending().appResumed();
      async.flushMicrotasks();
      expect(runs, 0);

      expect(pending().undo(token), isTrue);
      async.elapse(const Duration(minutes: 1));
      expect(runs, 0);
    });
  });

  test('a phone delete whose backstop passes in the background waits a full window on return', () {
    fakeAsync((async) {
      var runs = 0;
      pending().schedule(
        label: '3 items from this phone',
        needsForeground: true,
        run: () async => runs++,
      );

      pending().appPaused();
      async.elapse(const Duration(seconds: 30));
      expect(runs, 0);

      // Its snack may not have been on screen yet, so Undo gets its time.
      pending().appResumed();
      async.flushMicrotasks();
      expect(runs, 0);
      async.elapse(const Duration(seconds: 9));
      expect(runs, 0);
      async.elapse(const Duration(seconds: 1));
      expect(runs, 1);
    });
  });

  test('a phone delete back in front before its backstop passes waits a full window from then', () {
    fakeAsync((async) {
      var runs = 0;
      pending().schedule(
        label: '3 items from this phone',
        needsForeground: true,
        run: () async => runs++,
      );

      pending().appPaused();
      async.elapse(const Duration(seconds: 8));
      pending().appResumed();
      async.elapse(const Duration(seconds: 9));
      expect(runs, 0);
      async.elapse(const Duration(seconds: 1));
      expect(runs, 1);
    });
  });

  test('a phone delete back from the background runs when its Undo closes', () {
    fakeAsync((async) {
      var runs = 0;
      final token = pending().schedule(
        label: '3 items from this phone',
        needsForeground: true,
        run: () async => runs++,
      );

      pending().appPaused();
      async.elapse(const Duration(seconds: 30));
      pending().appResumed();
      async.elapse(const Duration(seconds: 6));
      expect(runs, 0);

      pending().commit(token);
      async.flushMicrotasks();
      expect(runs, 1);
      async.elapse(const Duration(minutes: 1));
      expect(runs, 1);
    });
  });

  test('a phone delete back from the background can still be undone', () {
    fakeAsync((async) {
      var runs = 0;
      final token = pending().schedule(
        label: '3 items from this phone',
        needsForeground: true,
        run: () async => runs++,
      );

      pending().appPaused();
      async.elapse(const Duration(seconds: 30));
      pending().appResumed();
      async.elapse(const Duration(seconds: 2));

      expect(pending().undo(token), isTrue);
      async.elapse(const Duration(minutes: 1));
      expect(runs, 0);
    });
  });

  test('phone deletes run one at a time, whatever the one before did', () {
    fakeAsync((async) {
      final first = Completer<void>();
      final second = Completer<void>();
      final started = <String>[];
      final a = pending().schedule(
        label: '"a.jpg" from this phone',
        needsForeground: true,
        run: () {
          started.add('a');
          return first.future;
        },
      );
      pending().schedule(
        label: '"b.jpg" from this phone',
        needsForeground: true,
        run: () {
          started.add('b');
          return second.future;
        },
      );
      final c = pending().schedule(
        label: '"c.jpg" from this phone',
        needsForeground: true,
        run: () async => started.add('c'),
      );

      // Scheduling b and c sent a and b on their way, and c's Undo closes
      // while the phone still asks about a.
      pending().commit(c);
      async.flushMicrotasks();
      expect(started, ['a']);
      expect(pending().undo(a), isFalse);

      first.completeError(Exception('deleteWithIds failed'));
      async.flushMicrotasks();
      expect(started, ['a', 'b']);

      second.complete();
      async.flushMicrotasks();
      expect(started, ['a', 'b', 'c']);
    });
  });

  test('a failed phone delete says its own sentence and hides nothing', () {
    fakeAsync((async) {
      final token = pending().schedule(
        label: '3 items from this phone',
        failure: 'Couldn\'t delete 3 items from this phone',
        needsForeground: true,
        run: () async => throw Exception('deleteWithIds failed'),
      );
      expect(state().hiddenIds, isEmpty);

      pending().commit(token);
      async.flushMicrotasks();
      expect(state().lastFailure?.message, 'Couldn\'t delete 3 items from this phone');
    });
  });

  test('a phone delete waiting its turn can still be undone', () {
    fakeAsync((async) {
      final first = Completer<void>();
      final started = <String>[];
      final a = pending().schedule(
        label: '"a.jpg" from this phone',
        needsForeground: true,
        run: () {
          started.add('a');
          return first.future;
        },
      );
      final b = pending().schedule(
        label: '"b.jpg" from this phone',
        needsForeground: true,
        run: () async => started.add('b'),
      );
      pending().commit(a);
      pending().commit(b);
      async.flushMicrotasks();
      expect(started, ['a']);

      expect(pending().undo(b), isTrue);
      first.complete();
      async.elapse(const Duration(minutes: 1));
      expect(started, ['a']);
    });
  });

  test('a phone delete whose turn comes in the background waits for the app', () {
    fakeAsync((async) {
      final first = Completer<void>();
      final started = <String>[];
      final a = pending().schedule(
        label: '"a.jpg" from this phone',
        needsForeground: true,
        run: () {
          started.add('a');
          return first.future;
        },
      );
      final b = pending().schedule(
        label: '"b.jpg" from this phone',
        needsForeground: true,
        run: () async => started.add('b'),
      );
      pending().commit(a);
      pending().commit(b);
      async.flushMicrotasks();

      // The person answers about a and leaves the app before b's turn.
      pending().appPaused();
      first.complete();
      async.elapse(const Duration(minutes: 1));
      expect(started, ['a']);

      pending().appResumed();
      async.flushMicrotasks();
      expect(started, ['a', 'b']);
    });
  });

  test('restoring a file keeps its phone copy out of the delete', () {
    fakeAsync((async) {
      final asked = <List<String>>[];
      final token = pending().schedulePhoneDelete(
        copies: {
          'a': ['asset-a'],
          'b': ['asset-b', 'asset-b2'],
        },
        label: '2 items from this phone',
        failure: 'Couldn\'t delete 2 items from this phone',
        run: (assetIds) async => asked.add(assetIds),
      );

      pending().keepPhoneCopies(['b', 'c']);
      pending().commit(token);
      async.flushMicrotasks();
      expect(asked, [
        ['asset-a'],
      ]);
    });
  });

  test('restoring every file drops the phone delete', () {
    fakeAsync((async) {
      final asked = <List<String>>[];
      final token = pending().schedulePhoneDelete(
        copies: {
          'a': ['asset-a'],
        },
        label: '"a.jpg" from this phone',
        failure: 'Couldn\'t delete "a.jpg" from this phone',
        run: (assetIds) async => asked.add(assetIds),
      );
      pending().appPaused();
      pending().commit(token);

      // Due, and waiting for the app to come back.
      pending().keepPhoneCopies(['a']);
      pending().appResumed();
      async.elapse(const Duration(minutes: 1));
      expect(asked, isEmpty);
      expect(pending().undo(token), isFalse);
    });
  });

  test('the wait starts again once the snack is on screen', () {
    fakeAsync((async) {
      var runs = 0;
      final token = pending().schedule(
        fileIds: {'a'},
        label: '"a.pdf"',
        run: () async => runs++,
      );
      async.elapse(const Duration(milliseconds: 500));
      pending().shown(token);

      async.elapse(const Duration(milliseconds: 9900));
      expect(runs, 0);
      async.elapse(const Duration(milliseconds: 100));
      expect(runs, 1);
    });
  });

  test('signing out drops what is waiting and forgets what failed', () {
    fakeAsync((async) {
      final answer = Completer<void>();
      var runs = 0;
      pending().schedule(
        fileIds: {'a'},
        label: '"a.pdf"',
        run: () => answer.future,
      );
      async.elapse(const Duration(seconds: 10));
      final phone = pending().schedule(
        label: '"c.jpg" from this phone',
        needsForeground: true,
        run: () async => runs++,
      );
      pending().appPaused();
      pending().commit(phone);
      final forGood = pending().schedule(
        fileIds: {'b'},
        label: '"b.pdf"',
        run: () async => runs++,
      );
      async.flushMicrotasks();
      expect(state().hiddenIds, {'a', 'b'});
      pending().reportFailure('Couldn\'t delete "d.pdf" for good: Telegram took too long.');

      pending().discardAll();
      expect(state().hiddenIds, isEmpty);
      expect(state().lastFailure, isNull);

      // The delete already under way ends, but says nothing any more.
      answer.completeError(const TelegramException(408, 'Request timeout'));
      pending().appResumed();
      pending().flush();
      async.elapse(const Duration(minutes: 1));
      expect(runs, 0);
      expect(state().lastFailure, isNull);
      expect(pending().undo(forGood), isFalse);
      expect(pending().undo(phone), isFalse);
    });
  });

  test('closing the app within the window deletes nothing', () {
    fakeAsync((async) {
      final own = ProviderContainer();
      var runs = 0;
      own.read(pendingDeletesProvider.notifier).schedule(
        fileIds: {'a'},
        label: '"a.pdf"',
        run: () async => runs++,
      );
      own.dispose();
      async.elapse(const Duration(minutes: 1));
      expect(runs, 0);
    });
  });
}
