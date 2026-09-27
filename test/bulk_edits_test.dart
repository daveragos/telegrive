import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:telegrive/features/drive/data/drive_repository.dart';
import 'package:telegrive/features/drive/data/drive_session.dart';
import 'package:telegrive/features/drive/data/telegram_wait.dart';
import 'package:telegrive/features/drive/domain/drive_models.dart';
import 'package:telegrive/features/files/data/bulk_edits.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';
import 'package:telegrive/infrastructure/telegram/telegram_client.dart';
import 'package:telegrive/infrastructure/telegram/telegram_exception.dart';

import 'support/fake_telegram.dart';

/// A channel that turns the first [floods] caption edits away with a flood
/// wait of [seconds], or only those of message [floodOn] when it is set.
class _FakeTelegram extends FakeTelegram {
  _FakeTelegram({required this.floods, required this.seconds, this.floodOn});

  int floods;
  final int seconds;
  final int? floodOn;
  int captionEdits = 0;

  @override
  Future<td.TdObject?> answer(td.TdFunction function) async {
    if (function is td.EditMessageCaption) {
      captionEdits++;
      if (floods > 0 && (floodOn == null || function.messageId == floodOn)) {
        floods--;
        throw TelegramException(420, 'FLOOD_WAIT_$seconds');
      }
    }
    return null;
  }
}

/// A channel where message 10 was forwarded in, so its caption can't be
/// edited. Telegram turns the first copy of it away with a flood wait once
/// the copy is being sent, and TDLib keeps that failed copy under
/// [failedId]; the next copy is delivered as [copyId], carrying the caption
/// it was asked for.
class _CopyTelegram extends _FakeTelegram {
  _CopyTelegram() : super(floods: 0, seconds: 2);

  static const pendingId = 600;
  static const failedId = 601;
  static const copyId = 602;

  final _updates = StreamController<td.TdObject>.broadcast();
  int copies = 0;

  @override
  Stream<td.TdObject> get updates => _updates.stream;

  @override
  Future<td.TdObject?> answer(td.TdFunction function) async {
    switch (function) {
      case td.EditMessageCaption(messageId: 10):
        throw const TelegramException(400, "Message can't be edited");
      case td.SendMessage(
        inputMessageContent: td.InputMessageForwarded(
          copyOptions: td.MessageCopyOptions(:final newCaption?),
        ),
      ):
        copies++;
        td.Message copy(int id) =>
            documentMessage(id, newCaption.text, fileName: 'a.jpg', mimeType: 'image/jpeg');
        final td.TdObject outcome;
        if (copies == 1) {
          messages[failedId] = copy(failedId);
          outcome = td.UpdateMessageSendFailed(
            message: copy(failedId),
            oldMessageId: pendingId,
            error: const td.TdError(code: 429, message: 'Too Many Requests: retry after 2'),
          );
        } else {
          messages[copyId] = copy(copyId);
          outcome = td.UpdateMessageSendSucceeded(message: copy(copyId), oldMessageId: pendingId);
        }
        Timer.run(() => _updates.add(outcome));
        return copy(pendingId).copyWith(
          sendingState: const td.MessageSendingStatePending(sendingId: 0),
        );
      default:
        return super.answer(function);
    }
  }
}

void main() {
  late AppDatabase db;
  late _FakeTelegram telegram;
  late ProviderContainer container;
  late DriveRepository repository;

  Future<void> receive(td.Message message) async {
    telegram.messages[message.id] = message;
    await repository.ingest(message);
  }

  Future<void> open({
    int floods = 0,
    int seconds = 2,
    int? floodOn,
    _FakeTelegram? channel,
  }) async {
    db = AppDatabase(NativeDatabase.memory());
    telegram = channel ?? _FakeTelegram(floods: floods, seconds: seconds, floodOn: floodOn);
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        telegramClientProvider.overrideWithValue(telegram),
        driveSessionProvider.overrideWith(TestSession.new),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    repository = container.read(driveRepositoryProvider);
    await receive(textMessage(1, '📁 Trips\ntgrf1:{"id":"trips","n":"Trips","ct":1700000000000}'));
    for (final (index, name) in ['a', 'b', 'c'].indexed) {
      await receive(
        documentMessage(
          10 + index,
          '$name.jpg\ntgr1:{"id":"$name","n":"$name.jpg","m":"image/jpeg","s":9,'
          '"ct":1700000000000}',
          fileName: '$name.jpg',
          mimeType: 'image/jpeg',
        ),
      );
    }
  }

  Future<List<DriveFile>> files() async => [
    for (final id in ['a', 'b', 'c']) (await repository.fileById(id))!,
  ];

  Future<List<String?>> folders() async => [
    for (final file in await files()) file.folderId,
  ];

  setUp(() => TelegramWait.unit = const Duration(milliseconds: 1));
  tearDown(() => TelegramWait.unit = const Duration(seconds: 1));

  test('a flood wait on an edit is waited out and announced', () async {
    await open(floods: 1);
    final waits = <DateTime?>[];
    container.listen<DateTime?>(telegramWaitProvider, (_, next) => waits.add(next));

    await repository.moveFiles(await files(), 'trips');

    expect(await folders(), ['trips', 'trips', 'trips']);
    expect(telegram.captionEdits, 4);
    expect(waits.whereType<DateTime>(), isNotEmpty);
    expect(container.read(telegramWaitProvider), isNull);
  });

  test('a copy turned away while sending is waited out, without leftovers', () async {
    final channel = _CopyTelegram();
    await open(channel: channel);
    final waits = <DateTime?>[];
    container.listen<DateTime?>(telegramWaitProvider, (_, next) => waits.add(next));

    await repository.moveFiles([(await repository.fileById('a'))!], 'trips');

    expect((await repository.fileById('a'))!.folderId, 'trips');
    expect(channel.copies, 2);
    expect(channel.captionEdits, 0);
    expect(channel.messages.keys, contains(_CopyTelegram.copyId));
    expect(channel.messages.keys, isNot(contains(_CopyTelegram.failedId)));
    expect(channel.messages.keys, isNot(contains(10)));
    expect(waits.whereType<DateTime>(), isNotEmpty);
  });

  test('a wait longer than 15 minutes fails instead', () async {
    await open(floods: 1, seconds: 7200);

    await expectLater(
      repository.moveFiles(await files(), 'trips'),
      throwsA(isA<TelegramException>().having((e) => e.retryAfterSeconds, 'wait', 7200)),
    );
    expect(await folders(), [null, null, null]);
    expect(container.read(telegramWaitProvider), isNull);
  });

  test('stop ends a bulk change after the item in hand', () async {
    await open();
    final edits = container.read(bulkEditsProvider.notifier);
    final all = await files();

    final outcome = await edits.run(
      label: 'Moving 3 items',
      icon: Icons.drive_file_move_outline,
      items: all,
      apply: (file) async {
        await repository.moveFiles([file], 'trips');
        edits.stop();
      },
    );

    expect(outcome.stopped, isTrue);
    expect(outcome.done, 1);
    expect(outcome.total, 3);
    expect(outcome.error, isNull);
    expect(await folders(), ['trips', null, null]);
    expect(container.read(bulkEditsProvider), isNull);
  });

  test('stop during a Telegram wait cuts it short and counts as stopped', () async {
    TelegramWait.unit = const Duration(seconds: 1);
    await open(floods: 1);
    final edits = container.read(bulkEditsProvider.notifier);
    final progress = <BulkEdit?>[];
    container.listen<BulkEdit?>(bulkEditsProvider, (_, next) => progress.add(next));

    final run = edits.run(
      label: 'Moving 3 items',
      icon: Icons.drive_file_move_outline,
      items: await files(),
      apply: (file) => repository.moveFiles([file], 'trips'),
    );
    for (var i = 0; i < 100 && container.read(telegramWaitProvider) == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(container.read(telegramWaitProvider), isNotNull);
    edits.stop();
    final outcome = await run;

    expect(outcome.stopped, isTrue);
    expect(outcome.error, isNull);
    expect(outcome.done, 0);
    expect(await folders(), [null, null, null]);
    expect(container.read(telegramWaitProvider), isNull);
    expect(progress.whereType<BulkEdit>().any((p) => p.stopping), isTrue);
  });

  test('a wait that comes up after Stop ends as it starts', () async {
    TelegramWait.unit = const Duration(seconds: 1);
    await open(floods: 1, seconds: 600);
    final edits = container.read(bulkEditsProvider.notifier);
    final all = await files();

    final outcome = await edits.run(
      label: 'Moving 3 items',
      icon: Icons.drive_file_move_outline,
      items: all,
      apply: (file) {
        edits.stop();
        return repository.moveFiles([file], 'trips');
      },
    );

    expect(outcome.stopped, isTrue);
    expect(outcome.done, 0);
    expect(await folders(), [null, null, null]);
    expect(container.read(telegramWaitProvider), isNull);

    // The next change, and a Stop with nothing running, leave later waits
    // to be sat out as usual.
    edits.stop();
    TelegramWait.unit = const Duration(milliseconds: 1);
    telegram.floods = 1;
    final next = await edits.run(
      label: 'Moving 3 items',
      icon: Icons.drive_file_move_outline,
      items: all,
      apply: (file) => repository.moveFiles([file], 'trips'),
    );

    expect(next.complete, isTrue);
    expect(await folders(), ['trips', 'trips', 'trips']);
  });

  test('stop lets a split file finish its parts before it ends', () async {
    TelegramWait.unit = const Duration(milliseconds: 100);
    // The second part's edit has to wait, after the first part has moved.
    await open(floods: 1, floodOn: 21);
    for (final index in [0, 1]) {
      await receive(
        documentMessage(
          20 + index,
          'big.bin.00${index + 1}\ntgr1:{"id":"big","n":"big.bin","s":18,'
          '"ct":1700000000000,"pc":2${index == 0 ? '' : ',"pi":$index'}}',
          fileName: 'big.bin.00${index + 1}',
        ),
      );
    }
    final edits = container.read(bulkEditsProvider.notifier);

    final run = edits.run(
      label: 'Moving 4 items',
      icon: Icons.drive_file_move_outline,
      items: [(await repository.fileById('big'))!, ...await files()],
      apply: (file) => repository.moveFiles([file], 'trips'),
    );
    for (var i = 0; i < 100 && container.read(telegramWaitProvider) == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(container.read(telegramWaitProvider), isNotNull);
    edits.stop();
    final outcome = await run;

    expect(outcome.stopped, isTrue);
    expect(outcome.done, 1);
    expect((await repository.fileById('big'))!.folderId, 'trips');
    for (final id in [20, 21]) {
      final caption = (telegram.messages[id]!.content as td.MessageDocument).caption.text;
      expect(caption, contains('"f":"trips"'));
    }
    expect(await folders(), [null, null, null]);
  });

  test('a second change waits for the first', () async {
    await open();
    final edits = container.read(bulkEditsProvider.notifier);
    final release = Completer<void>();
    final first = edits.run(
      label: 'Starring 1 item',
      icon: Icons.star_outline_rounded,
      items: [0],
      apply: (_) => release.future,
    );

    await expectLater(
      edits.run(
        label: 'Moving 1 item',
        icon: Icons.drive_file_move_outline,
        items: [0],
        apply: (_) async {},
      ),
      throwsA(
        isA<DriveException>().having(
          (e) => e.message,
          'message',
          'Wait for the current change to finish.',
        ),
      ),
    );
    release.complete();
    expect((await first).done, 1);
  });
}
