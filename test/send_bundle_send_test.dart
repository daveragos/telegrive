import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:telegrive/core/files/file_kind.dart';
import 'package:telegrive/features/drive/data/drive_repository.dart';
import 'package:telegrive/features/drive/data/drive_session.dart';
import 'package:telegrive/features/drive/data/telegram_wait.dart';
import 'package:telegrive/features/drive/domain/drive_models.dart';
import 'package:telegrive/features/send/data/send_bundle.dart';
import 'package:telegrive/features/send/data/telegram_chats.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';
import 'package:telegrive/infrastructure/telegram/telegram_client.dart';
import 'package:telegrive/infrastructure/telegram/telegram_exception.dart';

import 'support/fake_telegram.dart';

const _selam = TelegramChat(id: 42, title: 'Selam Tesfaye');
const _family = TelegramChat(id: 43, title: 'Family', isGroup: true);
const _slowGroup = TelegramChat(id: 44, title: 'Hiking club', isGroup: true, slowMode: true);

/// The channel, keeping every request it is asked, and turning the forwards
/// numbered in [floods], counting from 1, away with a flood wait of
/// [seconds].
class _LoggingTelegram extends FakeTelegram {
  _LoggingTelegram({this.floods = const {}, this.seconds = 2});

  final Set<int> floods;
  final int seconds;
  final List<td.TdFunction> requests = [];

  List<td.ForwardMessages> get forwards => requests.whereType<td.ForwardMessages>().toList();

  /// The text lines sent, in order.
  List<String> get lines => [
    for (final request in requests)
      if (request case td.SendMessage(
        inputMessageContent: td.InputMessageText(:final text),
      ))
        text.text,
  ];

  @override
  Future<td.TdObject?> answer(td.TdFunction function) async {
    requests.add(function);
    if (function is td.ForwardMessages && floods.contains(forwards.length)) {
      throw TelegramException(420, 'FLOOD_WAIT_$seconds');
    }
    return null;
  }

  /// What arrived in [chatId], in order: text as itself, a copied file as
  /// the id of the channel message it came from, which its document's file
  /// id still carries.
  List<Object> arrivedIn(int chatId) => [
    for (final message in messages.values)
      if (message.chatId == chatId)
        switch (message.content) {
          td.MessageText(:final text) => text.text,
          td.MessageDocument(:final document) => document.document.id,
          final content => content,
        },
  ];
}

void main() {
  late AppDatabase db;
  late _LoggingTelegram telegram;
  late ProviderContainer container;

  /// 228 one-part files, then a film in two parts: 230 messages in all.
  late List<DriveFile> files;

  /// The channel's message ids, in the order the files go.
  late List<int> channelIds;

  final now = DateTime(2026, 9, 26);

  setUp(() => TelegramWait.unit = const Duration(milliseconds: 1));
  tearDown(() => TelegramWait.unit = const Duration(seconds: 1));

  Future<TelegramChats> open({Set<int> floods = const {}, int seconds = 2}) async {
    db = AppDatabase(NativeDatabase.memory());
    telegram = _LoggingTelegram(floods: floods, seconds: seconds);
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

    files = [];
    channelIds = [];
    Future<void> add(String name, {int parts = 1}) async {
      files.add(
        DriveFile(
          id: name,
          folderId: null,
          name: name,
          mimeType: 'application/octet-stream',
          kind: FileKind.other,
          size: 10,
          createdAt: now,
          modifiedAt: now,
          partCount: parts,
          starred: false,
        ),
      );
      final ids = [for (var i = 0; i < parts; i++) 1 + channelIds.length + i];
      // Later parts reach the index first, so order comes from partIndex.
      for (var index = parts - 1; index >= 0; index--) {
        await db.upsertFilePart(
          DriveFilesCompanion.insert(
            id: name,
            name: name,
            mimeType: 'application/octet-stream',
            kind: FileKind.other,
            size: 10,
            createdAt: now,
            modifiedAt: now,
            partCount: Value(parts),
          ),
          FilePartsCompanion.insert(
            fileId: name,
            partIndex: index,
            messageId: ids[index],
            tdFileId: ids[index],
            size: 10,
          ),
        );
        telegram.messages[ids[index]] = documentMessage(ids[index], '$name\ntgr1:{}');
      }
      channelIds.addAll(ids);
    }

    for (var i = 0; i < 228; i++) {
      await add('IMG_${i.toString().padLeft(3, '0')}.jpg');
    }
    await add('trip.mkv', parts: 2);
    return container.read(telegramChatsProvider);
  }

  test('the message, then the header, then the files 100 to a request', () async {
    final chats = await open();
    final bundle = SendBundle([SendGroup(header: 'Day 1', files: files)]);

    await chats.sendBundle(bundle, const [_selam], message: 'Lalibela 2026');

    expect(telegram.lines, ['Lalibela 2026', 'Day 1']);
    final texts = telegram.requests.whereType<td.SendMessage>().toList();
    expect(texts.map((r) => r.chatId), everyElement(_selam.id));
    // Plain lines notify the way any message does.
    expect(texts.map((r) => r.options), everyElement(isNull));
    expect(telegram.forwards.map((f) => f.messageIds), [
      channelIds.sublist(0, 100),
      channelIds.sublist(100, 200),
      channelIds.sublist(200),
    ]);
    for (final request in telegram.forwards) {
      expect(request.chatId, _selam.id);
      expect(request.fromChatId, testChatId);
      expect(request.sendCopy, isTrue);
      expect(request.removeCaption, isTrue);
    }
    expect(telegram.arrivedIn(_selam.id), ['Lalibela 2026', 'Day 1', ...channelIds]);
    // The text went before any file.
    final firstForward = telegram.requests.indexWhere((r) => r is td.ForwardMessages);
    final lastText = telegram.requests.lastIndexWhere((r) => r is td.SendMessage);
    expect(lastText, lessThan(firstForward));
  });

  test('each group goes under its own header, and an empty message sends no line', () async {
    final chats = await open();
    final bundle = SendBundle([
      SendGroup(files: files.sublist(0, 3)),
      SendGroup(header: 'Day 2 › Gondar', files: files.sublist(3, 5)),
    ]);

    await chats.sendBundle(bundle, const [_selam, _family]);

    expect(telegram.lines, ['Day 2 › Gondar', 'Day 2 › Gondar']);
    expect(telegram.forwards.map((f) => f.chatId), [_selam.id, _selam.id, _family.id, _family.id]);
    expect(telegram.forwards.map((f) => f.messageIds), [
      channelIds.sublist(0, 3),
      channelIds.sublist(3, 5),
      channelIds.sublist(0, 3),
      channelIds.sublist(3, 5),
    ]);
    final arrived = [...channelIds.sublist(0, 3), 'Day 2 › Gondar', ...channelIds.sublist(3, 5)];
    expect(telegram.arrivedIn(_selam.id), arrived);
    expect(telegram.arrivedIn(_family.id), arrived);
  });

  test('a short flood wait between requests is waited out', () async {
    final chats = await open(floods: {2});
    final bundle = SendBundle([SendGroup(header: 'Day 1', files: files)]);

    await chats.sendBundle(bundle, const [_selam], message: 'Lalibela 2026');

    expect(telegram.forwards.map((f) => f.messageIds.length), [100, 100, 100, 30]);
    expect(telegram.forwards[2].messageIds, telegram.forwards[1].messageIds);
    expect(telegram.arrivedIn(_selam.id), ['Lalibela 2026', 'Day 1', ...channelIds]);
    expect(container.read(telegramWaitProvider), isNull);
  });

  test('a flood wait longer than two minutes fails the send', () async {
    final chats = await open(floods: {2}, seconds: 600);
    final bundle = SendBundle([SendGroup(header: 'Day 1', files: files)]);

    await expectLater(
      chats.sendBundle(bundle, const [_selam], message: 'Lalibela 2026'),
      throwsA(isA<TelegramException>().having((e) => e.retryAfterSeconds, 'wait', 600)),
    );
    expect(telegram.forwards, hasLength(2));
  });

  test('a group in slow mode gets the first file alone, and the send says so', () async {
    final chats = await open();
    final bundle = SendBundle([
      SendGroup(files: files.sublist(0, 2)),
      SendGroup(header: 'Day 1', files: files.sublist(2, 4)),
    ]);

    await expectLater(
      chats.sendBundle(bundle, const [_slowGroup, _selam], message: 'Lalibela 2026'),
      throwsA(
        isA<DriveException>().having(
          (e) => e.message,
          'message',
          'This group lets members send one message at a time, so only the first file went.',
        ),
      ),
    );

    expect(telegram.forwards.first.chatId, _slowGroup.id);
    expect(telegram.forwards.first.messageIds, [channelIds.first]);
    expect(
      telegram.requests.whereType<td.SendMessage>().map((r) => r.chatId),
      everyElement(_selam.id),
    );
    // The other chat still gets everything.
    expect(telegram.arrivedIn(_selam.id), [
      'Lalibela 2026',
      ...channelIds.sublist(0, 2),
      'Day 1',
      ...channelIds.sublist(2, 4),
    ]);
  });
}
