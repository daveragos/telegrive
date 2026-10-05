import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegrive/features/drive/data/drive_session.dart';
import 'package:telegrive/features/drive/data/drive_sync.dart';
import 'package:telegrive/features/drive/data/message_indexer.dart';
import 'package:telegrive/features/drive/domain/manifest.dart';
import 'package:telegrive/features/setup/data/drive_setup.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';
import 'package:telegrive/infrastructure/storage/preferences.dart';
import 'package:telegrive/infrastructure/telegram/telegram_client.dart';
import 'package:telegrive/infrastructure/telegram/telegram_exception.dart';

import 'support/fake_telegram.dart';

/// A channel this account owns that isn't a drive.
const _otherChatId = -300;

/// The drive message as it sits in the channel, pinned or not, pointing
/// at the copy of the index in [indexMessageId] when there is one.
td.Message _card(int id, {bool pinned = true, int? indexMessageId}) {
  final text = ManifestCodec.encodeDrive(
    DriveManifest(id: 'drive-1', createdAt: DateTime(2026, 10, 5), indexMessageId: indexMessageId),
  );
  return channelMessage(
    id,
    td.MessageText(text: td.FormattedText(text: text.text, entities: const [])),
  ).copyWith(isPinned: pinned);
}

/// TDLib for an account whose search finds [found], each an owned channel
/// whose description is [description] and whose pinned message is
/// [pinned]. [searchFinds] is what a search of the channel's messages
/// turns up. With [pinnedFails] Telegram can't be asked for pinned
/// messages at all.
class _Telegram extends FakeTelegram {
  _Telegram({
    this.found = const [],
    this.description = '',
    this.pinned,
    this.searchFinds = const [],
    this.pinnedFails = false,
    this.downloads = const {},
  });

  final List<int> found;
  final String description;
  final td.Message? pinned;
  final List<td.Message> searchFinds;
  final bool pinnedFails;

  /// Where each TDLib file id downloads to.
  final Map<int, String> downloads;
  final asked = <td.TdFunction>[];

  Iterable<T> askedFor<T>() => asked.whereType<T>();

  @override
  Future<td.TdObject?> answer(td.TdFunction function) async {
    asked.add(function);
    switch (function) {
      case td.GetMe():
        return testUser();
      case td.GetChat(:final chatId):
        return channelChat().copyWith(id: chatId);
      case td.GetSupergroup():
        return ownedSupergroup();
      case td.GetSupergroupFullInfo():
        return channelInfo().copyWith(description: description);
      case td.SearchChatsOnServer() || td.SearchChats():
        return td.Chats(totalCount: found.length, chatIds: found);
      case td.LoadChats():
        throw const TelegramException(404, 'Not Found');
      case td.GetChats():
        return td.Chats(totalCount: found.length, chatIds: found);
      case td.CreateNewSupergroupChat():
        return channelChat();
      case td.GetChatPinnedMessage():
        if (pinnedFails) throw const TelegramException(500, 'Request timed out');
        return pinned ?? (throw const TelegramException(404, 'Not Found'));
      case td.SearchChatMessages(:final filter):
        final messages = filter is td.SearchMessagesFilterPinned
            ? [?pinned]
            : searchFinds;
        return td.FoundChatMessages(
          totalCount: messages.length,
          messages: messages,
          nextFromMessageId: 0,
        );
      case td.DownloadFile(:final fileId) when downloads.containsKey(fileId):
        return tdFile(fileId, path: downloads[fileId]!, downloaded: true);
      case td.AddChatToList() ||
          td.SetChatPhoto() ||
          td.SetChatDescription() ||
          td.SetChatTitle() ||
          td.PinChatMessage() ||
          td.OpenChat():
        return const td.Ok();
      default:
        return null;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  late Directory support;

  setUp(() {
    support = Directory.systemTemp.createTempSync('drive_card_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      pathProvider,
      (call) async => support.path,
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      pathProvider,
      null,
    );
    support.deleteSync(recursive: true);
  });

  /// Opens the drive with [telegram] on a phone holding [stored].
  Future<(ProviderContainer, Preferences)> open(
    _Telegram telegram, {
    Map<String, Object> stored = const {},
  }) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({'last_user_id': 1, ...stored});
    final shared = await SharedPreferences.getInstance();
    final db = AppDatabase(NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(shared),
        appDatabaseProvider.overrideWithValue(db),
        telegramClientProvider.overrideWithValue(telegram),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    await container.read(driveSetupProvider.notifier).run();
    expect(container.read(driveSetupProvider).error, isNull);
    return (container, container.read(preferencesProvider));
  }

  /// The drive messages in the channel.
  List<td.Message> cards(FakeTelegram telegram) => [
    for (final message in telegram.messages.values)
      if (message.content case td.MessageText(:final text)
          when ManifestCodec.decodeDrive(text.text) != null)
        message,
  ];

  test('a new drive gets the drive message pinned, and a description without tags', () async {
    final telegram = _Telegram();
    final (container, prefs) = await open(telegram);

    final created = telegram.askedFor<td.CreateNewSupergroupChat>().single;
    expect(created.description, isNot(contains('#')));
    final card = cards(telegram).single;
    final pin = telegram.askedFor<td.PinChatMessage>().single;
    expect(pin.messageId, card.id);
    expect(pin.disableNotification, isTrue);
    expect(pin.onlyForSelf, isFalse);
    expect(prefs.driveCardId(testChatId), card.id);
    expect(container.read(driveSessionProvider)?.chatId, testChatId);

    final text = (card.content as td.MessageText).text.text;
    expect(text.split('\n').first, 'Telegrive drive');
    expect(ManifestCodec.decodeDrive(text)!.id, isNotEmpty);
  });

  test('a channel with the drive message pinned is found again, as it is', () async {
    final telegram = _Telegram(
      found: [testChatId],
      description: 'My own words',
      pinned: _card(50),
    );
    final (container, prefs) = await open(telegram);

    expect(container.read(driveSessionProvider)?.chatId, testChatId);
    expect(telegram.askedFor<td.CreateNewSupergroupChat>(), isEmpty);
    expect(telegram.askedFor<td.SetChatDescription>(), isEmpty);
    expect(telegram.askedFor<td.PinChatMessage>(), isEmpty);
    expect(cards(telegram), isEmpty, reason: 'no second drive message');
    expect(prefs.driveCardId(testChatId), 50);
  });

  test('a drive made before the drive message is found by its tag and gets one', () async {
    final telegram = _Telegram(
      found: [testChatId],
      description: 'Storage for the Telegrive app. #telegrive',
    );
    final (container, prefs) = await open(telegram);

    expect(container.read(driveSessionProvider)?.chatId, testChatId);
    expect(telegram.askedFor<td.CreateNewSupergroupChat>(), isEmpty);
    expect(telegram.askedFor<td.SetChatDescription>().single.description, isNot(contains('#')));
    final card = cards(telegram).single;
    expect(telegram.askedFor<td.PinChatMessage>().single.messageId, card.id);
    expect(prefs.driveCardId(testChatId), card.id);
  });

  test('a channel of the account\'s with neither the message nor the tag is not taken', () async {
    final telegram = _Telegram(found: [_otherChatId], description: 'Holiday plans');
    final (container, _) = await open(telegram);

    expect(telegram.askedFor<td.CreateNewSupergroupChat>(), hasLength(1));
    expect(container.read(driveSessionProvider)?.chatId, testChatId);
  });

  test('a drive message that came unpinned is pinned again rather than sent again', () async {
    final telegram = _Telegram(
      found: [testChatId],
      description: 'My own words',
      searchFinds: [_card(60, pinned: false)],
    );
    final (_, prefs) = await open(telegram);

    expect(telegram.askedFor<td.CreateNewSupergroupChat>(), isEmpty);
    expect(cards(telegram), isEmpty);
    expect(telegram.askedFor<td.PinChatMessage>().single.messageId, 60);
    expect(prefs.driveCardId(testChatId), 60);
  });

  test('when Telegram can\'t be asked, no second drive message is sent', () async {
    final telegram = _Telegram(pinnedFails: true);
    final (_, prefs) = await open(
      telegram,
      stored: {'drive_chat_1': testChatId},
    );

    expect(telegram.askedFor<td.CreateNewSupergroupChat>(), isEmpty);
    expect(cards(telegram), isEmpty);
    expect(telegram.askedFor<td.PinChatMessage>(), isEmpty);
    expect(prefs.driveCardId(testChatId), isNull);
  });

  test('the drive message this phone saw is checked by itself, without a search', () async {
    final telegram = _Telegram()..messages[70] = _card(70);
    await open(
      telegram,
      stored: {'drive_chat_1': testChatId, 'drive_card_$testChatId': 70},
    );

    expect(telegram.askedFor<td.GetChatPinnedMessage>(), isEmpty);
    expect(telegram.askedFor<td.SearchChatMessages>(), isEmpty);
    expect(telegram.askedFor<td.PinChatMessage>(), isEmpty);
    expect(cards(telegram).single.id, 70);
  });

  test('a drive with a copy of its index opens from it, before the channel is read', () async {
    final copy = File('${support.path}/copy.json.gz')
      ..writeAsBytesSync(
        gzip.encode(
          utf8.encode(
            jsonEncode({
              'format': 1,
              'folders': [
                {'id': 'docs', 'p': null, 'n': 'Docs', 'msg': 3, 'ct': 0, 'mt': 0, 'tr': null, 'st': false, 'x': null, 'ly': 2},
              ],
              'albums': <Object>[],
              'files': <Object>[],
            }),
          ),
        ),
      );
    final telegram = _Telegram(
      found: [testChatId],
      description: 'My own words',
      pinned: _card(50, indexMessageId: 60),
      downloads: {77: copy.path},
    );
    telegram.messages[50] = _card(50, indexMessageId: 60);
    telegram.messages[60] = channelMessage(
      60,
      td.MessageDocument(
        document: td.Document(fileName: 'telegrive-index.json.gz', mimeType: 'application/gzip', document: tdFile(77)),
        caption: td.FormattedText(
          text: ManifestCodec.encodeIndex(
            IndexRecord(driveId: 'drive-1', throughMessageId: 900, files: 0, createdAt: DateTime(2026, 10, 5)),
          ).text,
          entities: const [],
        ),
      ),
    );
    final (container, _) = await open(telegram);

    expect(telegram.askedFor<td.DownloadFile>().single.fileId, 77);
    expect((await container.read(appDatabaseProvider).folderById('docs'))?.name, 'Docs');
    // The full read went on behind; it ends before the phone does.
    await container.read(driveSyncProvider.notifier).whenIdle();
  });

  test('the drive message is never read as a comment for forwards', () {
    final post = MessageIndexer.postOf(_card(80));
    expect(post.manifest, isTrue);
    expect(post.text, isNull);
    expect(MessageIndexer.entryFor(_card(80)), isNull);
  });
}
