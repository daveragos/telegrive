import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:telegrive/features/drive/data/drive_repository.dart';
import 'package:telegrive/features/drive/data/drive_session.dart';
import 'package:telegrive/features/drive/domain/drive_models.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';
import 'package:telegrive/infrastructure/telegram/secure_store.dart';
import 'package:telegrive/infrastructure/telegram/telegram_client.dart';

const _chatId = -100;

class _Session extends DriveSessionNotifier {
  @override
  DriveSession? build() => const DriveSession(
    userId: 1,
    chatId: _chatId,
    channelTitle: 'Telegrive',
    firstName: 'A',
    lastName: '',
    phoneNumber: '',
    username: null,
    isPremium: false,
  );
}

td.Message _message(int id, td.MessageContent content) => td.Message(
  id: id,
  senderId: const td.MessageSenderChat(chatId: _chatId),
  chatId: _chatId,
  isOutgoing: true,
  isPinned: false,
  isFromOffline: false,
  canBeSaved: true,
  hasTimestampedMedia: false,
  isChannelPost: true,
  isTopicMessage: false,
  containsUnreadMention: false,
  date: 1_700_000_000,
  editDate: 0,
  unreadReactions: const [],
  messageThreadId: 0,
  savedMessagesTopicId: 0,
  selfDestructIn: 0,
  autoDeleteIn: 0,
  viaBotUserId: 0,
  senderBusinessBotUserId: 0,
  senderBoostCount: 0,
  authorSignature: '',
  mediaAlbumId: 0,
  effectId: 0,
  hasSensitiveContent: false,
  restrictionReason: '',
  content: content,
);

td.Message _document(int id, String caption) => _message(
  id,
  td.MessageDocument(
    document: const td.Document(
      fileName: 'clip.mp4',
      mimeType: 'video/mp4',
      document: td.File(
        id: 7,
        size: 9,
        expectedSize: 9,
        local: td.LocalFile(
          path: '',
          canBeDownloaded: true,
          canBeDeleted: true,
          isDownloadingActive: false,
          isDownloadingCompleted: false,
          downloadOffset: 0,
          downloadedPrefixSize: 0,
          downloadedSize: 0,
        ),
        remote: td.RemoteFile(
          id: 'r',
          uniqueId: 'u',
          isUploadingActive: false,
          isUploadingCompleted: true,
          uploadedSize: 9,
        ),
      ),
    ),
    caption: td.FormattedText(text: caption, entities: const []),
  ),
);

td.Message _text(int id, String text) => _message(
  id,
  td.MessageText(text: td.FormattedText(text: text, entities: const [])),
);

/// A channel that holds messages and applies caption and text edits to
/// them, the way Telegram hands the edited message back.
class _FakeTelegram extends TelegramClient {
  _FakeTelegram() : super(SecureStore());

  final Map<int, td.Message> messages = {};

  @override
  Future<T> send<T extends td.TdObject>(
    td.TdFunction function, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    switch (function) {
      case td.EditMessageCaption(:final messageId, :final caption?):
        final old = messages[messageId]!;
        final content = old.content as td.MessageDocument;
        return (messages[messageId] = old.copyWith(
              content: content.copyWith(caption: caption),
            ))
            as T;
      case td.EditMessageText(
        :final messageId,
        inputMessageContent: td.InputMessageText(:final text),
      ):
        return (messages[messageId] = messages[messageId]!.copyWith(
              content: td.MessageText(text: text),
            ))
            as T;
      default:
        throw UnsupportedError('$function');
    }
  }
}

void main() {
  late AppDatabase db;
  late _FakeTelegram telegram;
  late DriveRepository repository;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    telegram = _FakeTelegram();
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        telegramClientProvider.overrideWithValue(telegram),
        driveSessionProvider.overrideWith(_Session.new),
      ],
    );
    repository = container.read(driveRepositoryProvider);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
  });

  Future<void> receive(td.Message message) async {
    telegram.messages[message.id] = message;
    await repository.ingest(message);
  }

  Map<String, dynamic> machineLine(td.Message message) {
    final text = switch (message.content) {
      td.MessageDocument(:final caption) => caption.text,
      td.MessageText(:final text) => text.text,
      _ => '',
    };
    return jsonDecode(text.substring(text.indexOf('{'))) as Map<String, dynamic>;
  }

  test('a key a newer version wrote survives a rename, star and trash here', () async {
    await receive(
      _document(
        10,
        'clip.mp4\ntgr1:{"id":"v","n":"clip.mp4","f":"docs","m":"video/mp4",'
        '"s":9,"ct":1700000000000,"mt":1700000000000,"du":84,"lt":123456}',
      ),
    );
    final row = (await db.fileById('v'))!;
    expect(jsonDecode(row.manifestExtra!), {'du': 84, 'lt': 123456});

    await repository.renameFile(DriveFile.fromRow(row), 'trip.mp4');
    var sent = machineLine(telegram.messages[10]!);
    expect(sent['n'], 'trip.mp4');
    expect(sent['du'], 84);
    expect(sent['lt'], 123456);

    var file = (await repository.fileById('v'))!;
    await repository.setStarred([file], starred: true);
    file = (await repository.fileById('v'))!;
    await repository.trash(files: [file]);
    sent = machineLine(telegram.messages[10]!);
    expect(sent['st'], 1);
    expect(sent['tr'], isA<int>());
    expect(sent['du'], 84);
    expect(sent['lt'], 123456);
    expect(jsonDecode((await db.fileById('v'))!.manifestExtra!), {'du': 84, 'lt': 123456});
  });

  test('a known key wins over a stale extra of the same name', () async {
    await receive(
      _document(
        10,
        'clip.mp4\ntgr1:{"id":"v","n":"clip.mp4","s":9,"ct":1700000000000,"du":84}',
      ),
    );
    await db.updateFile(
      'v',
      const DriveFilesCompanion(
        manifestExtra: Value('{"n":"stale.mp4","du":84}'),
      ),
    );

    await repository.setStarred([(await repository.fileById('v'))!], starred: true);
    final sent = machineLine(telegram.messages[10]!);
    expect(sent['n'], 'clip.mp4');
    expect(sent['st'], 1);
    expect(sent['du'], 84);
    expect(jsonDecode((await db.fileById('v'))!.manifestExtra!), {'du': 84});
  });

  test('a folder key a newer version wrote survives a rename and move here', () async {
    await receive(
      _text(
        1,
        '📁 Invoices\ntgrf1:{"id":"inv","n":"Invoices","ct":1700000000000,'
        '"mt":1700000000000,"st":1}',
      ),
    );
    await receive(
      _text(2, '📁 Work\ntgrf1:{"id":"work","n":"Work","ct":1700000000000}'),
    );
    expect(jsonDecode((await db.folderById('inv'))!.manifestExtra!), {'st': 1});
    expect((await db.folderById('work'))!.manifestExtra, isNull);

    Future<DriveFolder> invoices() async =>
        DriveFolder.fromRow((await db.folderById('inv'))!);
    await repository.renameFolder(await invoices(), 'Bills');
    await repository.moveFolder(await invoices(), 'work');

    final sent = machineLine(telegram.messages[1]!);
    expect(sent['n'], 'Bills');
    expect(sent['p'], 'work');
    expect(sent['st'], 1);
    expect(jsonDecode((await db.folderById('inv'))!.manifestExtra!), {'st': 1});
  });

  test('an edit without extras clears them from the index', () async {
    await receive(
      _document(10, 'a.pdf\ntgr1:{"id":"a","n":"a.pdf","s":9,"rb":"b"}'),
    );
    expect((await db.fileById('a'))!.manifestExtra, isNotNull);
    await receive(_document(10, 'a.pdf\ntgr1:{"id":"a","n":"a.pdf","s":9}'));
    expect((await db.fileById('a'))!.manifestExtra, isNull);
  });
}
