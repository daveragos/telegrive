import 'package:drift/drift.dart' show TableUpdateQuery;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegrive/features/drive/data/drive_session.dart';
import 'package:telegrive/features/drive/data/drive_sync.dart';
import 'package:telegrive/features/drive/data/forward_filer.dart';
import 'package:telegrive/features/drive/data/message_indexer.dart';
import 'package:telegrive/features/drive/domain/manifest.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';
import 'package:telegrive/infrastructure/storage/preferences.dart';
import 'package:telegrive/infrastructure/telegram/secure_store.dart';
import 'package:telegrive/infrastructure/telegram/telegram_client.dart';
import 'package:telegrive/infrastructure/telegram/telegram_exception.dart';

import 'support/fake_telegram.dart';

const _chatId = -1001234567890;

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

/// Answers history requests with [failures] first, then a channel holding
/// [history], newest first, in a single page.
class _FakeTelegram extends TelegramClient {
  _FakeTelegram(this.failures, {this.history = const []}) : super(SecureStore());

  final List<TelegramException> failures;
  final List<td.Message> history;
  int historyCalls = 0;

  @override
  Future<T> send<T extends td.TdObject>(
    td.TdFunction function, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (function is td.GetChatHistory) {
      historyCalls++;
      if (failures.isNotEmpty) throw failures.removeAt(0);
      final page = function.fromMessageId == 0 ? history : const <td.Message>[];
      return td.Messages(totalCount: history.length, messages: page) as T;
    }
    if (function is td.OpenChat || function is td.CloseChat) return const td.Ok() as T;
    throw UnsupportedError('$function');
  }
}

/// A channel holding [history], read 100 messages a page, newest first, as
/// Telegram pages it. The [failOnCall]th request is turned away. Pages
/// pass over the messages in [holes], as TDLib does over holes in its copy
/// of the history, while they are still there when asked for by number
/// and in Telegram's count of files.
class _Paged extends TelegramClient {
  _Paged(List<td.Message> history, {this.failOnCall, this.holes = const {}})
    : _history = [...history]..sort((a, b) => b.id.compareTo(a.id)),
      super(SecureStore());

  final List<td.Message> _history;
  final int? failOnCall;
  final Set<int> holes;
  final List<List<int>> askedFor = [];
  int _calls = 0;

  @override
  Future<T> send<T extends td.TdObject>(
    td.TdFunction function, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (function is td.GetChatHistory) {
      if (++_calls == failOnCall) throw const TelegramException(400, 'CHANNEL_INVALID');
      final from = function.fromMessageId;
      final page = _history
          .where((m) => (from == 0 || m.id < from) && !holes.contains(m.id))
          .take(function.limit);
      return td.Messages(totalCount: _history.length, messages: page.toList()) as T;
    }
    if (function is td.GetChat) {
      return channelChat().copyWith(lastMessage: _history.firstOrNull) as T;
    }
    if (function is td.GetChatMessageCount) {
      return td.Count(count: _history.where((m) => m.content is td.MessageDocument).length) as T;
    }
    if (function is td.GetMessages) {
      askedFor.add(function.messageIds);
      final ids = function.messageIds.toSet();
      final found = _history.where((m) => ids.contains(m.id)).toList();
      return td.Messages(totalCount: found.length, messages: found) as T;
    }
    if (function is td.OpenChat || function is td.CloseChat) return const td.Ok() as T;
    throw UnsupportedError('$function');
  }
}

void main() {
  Future<(ProviderContainer, _FakeTelegram, Preferences)> start(
    List<TelegramException> failures, {
    Map<String, Object> stored = const {},
    List<td.Message> history = const [],
  }) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues(stored);
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase(NativeDatabase.memory());
    final telegram = _FakeTelegram(failures, history: history);
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        appDatabaseProvider.overrideWithValue(db),
        telegramClientProvider.overrideWithValue(telegram),
        driveSessionProvider.overrideWith(_Session.new),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    return (container, telegram, container.read(preferencesProvider));
  }

  test('a rate limit halfway through reading is waited out, not fatal', () async {
    final (container, telegram, prefs) = await start([
      const TelegramException(420, 'FLOOD_WAIT_1'),
    ]);
    await container.read(driveSyncProvider.notifier).fullSync();

    expect(telegram.historyCalls, 2);
    expect(container.read(driveSyncProvider).error, isNull);
    expect(prefs.lastFullSync(_chatId), isNotNull);
  });

  test('a bad request fails the sync and leaves the index marked unfinished', () async {
    final (container, _, prefs) = await start([
      const TelegramException(400, 'CHANNEL_INVALID'),
    ]);
    await container.read(driveSyncProvider.notifier).fullSync();

    expect(container.read(driveSyncProvider).error, isNotNull);
    // Backup reads this to know the index can't be trusted yet.
    expect(prefs.lastFullSync(_chatId), isNull);
  });

  test('a failure stays while the next try runs, and clears when it succeeds', () async {
    final (container, _, _) = await start([
      const TelegramException(400, 'CHANNEL_INVALID'),
    ]);
    final sync = container.read(driveSyncProvider.notifier);
    await sync.refresh();
    expect(container.read(driveSyncProvider).error, isNotNull);

    final whileRunning = <String?>[];
    container.listen<SyncState>(driveSyncProvider, (_, next) {
      if (next.running) whileRunning.add(next.error);
    });
    await sync.refresh();

    // Home keeps saying Telegram can't be reached until a try gets through.
    expect(whileRunning, isNotEmpty);
    expect(whileRunning, everyElement(isNotNull));
    expect(container.read(driveSyncProvider).error, isNull);
  });

  test('a full read that succeeds is noted in the state; a catch-up is not', () async {
    final (container, _, _) = await start([]);
    final sync = container.read(driveSyncProvider.notifier);
    expect(container.read(driveSyncProvider).lastFull, isNull);

    await sync.refresh();
    expect(container.read(driveSyncProvider).lastSynced, isNotNull);
    expect(container.read(driveSyncProvider).lastFull, isNull);

    await sync.fullSync();
    final full = container.read(driveSyncProvider).lastFull;
    expect(full, isNotNull);

    // A later catch-up keeps the moment of the full read.
    await sync.refresh();
    expect(container.read(driveSyncProvider).lastFull, full);
  });

  test('a full read that fails leaves no note of one', () async {
    final (container, _, _) = await start([
      const TelegramException(400, 'CHANNEL_INVALID'),
    ]);
    await container.read(driveSyncProvider.notifier).fullSync();
    expect(container.read(driveSyncProvider).lastFull, isNull);
  });

  test('an index another indexer built is read again in full', () async {
    final readToday = DateTime.now().subtract(const Duration(minutes: 5));
    // Read in full today, by a build whose indexer counted differently.
    final (container, _, prefs) = await start(
      [],
      stored: {
        'full_sync_$_chatId': readToday.millisecondsSinceEpoch,
        'indexed_with_$_chatId': MessageIndexer.version + 3,
      },
    );

    await container.read(driveSyncProvider.notifier).syncOnOpen();

    expect(prefs.indexedWith(_chatId), MessageIndexer.version);
    expect(prefs.lastFullSync(_chatId)!.isAfter(readToday), isTrue);
  });

  test('an index built by this indexer and read today only catches up', () async {
    final readToday = DateTime.now().subtract(const Duration(minutes: 5));
    // The index holds the channel up to message 10; 11 came after.
    final (container, _, prefs) = await start(
      [],
      stored: {
        'full_sync_$_chatId': readToday.millisecondsSinceEpoch,
        'indexed_with_$_chatId': MessageIndexer.version,
        'synced_upto_$_chatId': 10,
      },
      history: [documentMessage(11, ''), documentMessage(10, '')],
    );
    await container.read(driveSyncProvider.notifier).syncOnOpen();

    expect(
      prefs.lastFullSync(_chatId)!.millisecondsSinceEpoch,
      readToday.millisecondsSinceEpoch,
    );
    // The catch-up read what came after the index and stopped there.
    final db = container.read(appDatabaseProvider);
    expect(await db.fileById(MessageIndexer.adoptedId(11)), isNotNull);
    expect(await db.fileById(MessageIndexer.adoptedId(10)), isNull);
    expect(prefs.lastSyncedMessageId(_chatId), 11);
  });

  group('a big drive', () {
    final at = DateTime(2025, 3, 1);

    td.Message folder(int id, String folderId, {bool private = false, bool trashed = false}) =>
        textMessage(
          id,
          ManifestCodec.encodeFolder(
            FolderManifest(
              id: folderId,
              name: folderId,
              parentId: null,
              createdAt: at,
              modifiedAt: at,
              trashedAt: trashed ? at : null,
              private: private,
            ),
          ).text,
        );
    td.Message photo(int id, {String? folderId}) => documentMessage(
      id,
      ManifestCodec.encodeFile(
        FileManifest(
          id: 'p$id',
          name: 'IMG_$id.jpg',
          folderId: folderId,
          mimeType: 'image/jpeg',
          size: 9,
          createdAt: at,
          modifiedAt: at,
        ),
      ).text,
      fileName: 'IMG_$id.jpg',
      mimeType: 'image/jpeg',
    );

    Future<(ProviderContainer, AppDatabase, _Paged)> open(
      List<td.Message> history, {
      int? failOnCall,
      Set<int> holes = const {},
    }) async {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = AppDatabase(NativeDatabase.memory());
      final telegram = _Paged(history, failOnCall: failOnCall, holes: holes);
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          appDatabaseProvider.overrideWithValue(db),
          telegramClientProvider.overrideWithValue(telegram),
          driveSessionProvider.overrideWith(_Session.new),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await db.close();
      });
      return (container, db, telegram);
    }

    test('is written a lot at a time, so the screens watching it look again rarely', () async {
      final (container, db, _) = await open([for (var id = 1; id <= 1200; id++) photo(id)]);
      var writes = 0;
      final watching = db
          .tableUpdates(TableUpdateQuery.onTable(db.driveFiles))
          .listen((_) => writes++);
      addTearDown(watching.cancel);

      await container.read(driveSyncProvider.notifier).fullSync();
      await pumpEventQueue();

      expect(await db.knownMessageIds(), hasLength(1200));
      // 500, 500 and the last 200, rather than once for each of 1,200.
      expect(writes, lessThanOrEqualTo(4));
    });

    test('what was read before a failure is kept', () async {
      final (container, db, _) = await open(
        [for (var id = 1; id <= 300; id++) photo(id)],
        failOnCall: 3,
      );
      await container.read(driveSyncProvider.notifier).fullSync();

      expect(container.read(driveSyncProvider).error, isNotNull);
      expect(await db.knownMessageIds(), hasLength(200));
    });

    test('messages the history passes over are asked for by number', () async {
      // TDLib's ids for a channel's messages are their numbers times 2^20.
      int id(int number) => number << 20;
      td.Message part(int number, int index) => documentMessage(
        id(number),
        index == 0
            ? ManifestCodec.encodeFile(
                FileManifest(
                  id: 'film',
                  name: 'Film.mp4',
                  folderId: null,
                  mimeType: 'video/mp4',
                  size: 30,
                  createdAt: at,
                  modifiedAt: at,
                  partCount: 3,
                ),
              ).text
            : ManifestCodec.encodePart(
                PartRecord(fileId: 'film', index: index, count: 3, size: 30),
              ).text,
        fileName: 'Film.mp4.00${index + 1}',
      );
      // Photos 1 to 300, a deleted message at 301, then a film in three
      // parts; the history passes over 150 to 250 and the film's last two
      // parts.
      final history = [
        for (var number = 1; number <= 300; number++) photo(id(number)),
        part(302, 0),
        part(303, 1),
        part(304, 2),
      ];
      final holes = {
        for (var number = 150; number <= 250; number++) id(number),
        id(303),
        id(304),
      };
      final (container, db, telegram) = await open(history, holes: holes);

      await container.read(driveSyncProvider.notifier).fullSync();

      expect(await db.knownMessageIds(), hasLength(303));
      final film = (await db.fileById('film'))!;
      expect((film.partsPresent, film.partCount), (3, 3));
      // Only the numbers the history passed over, the deleted one with them.
      expect(
        telegram.askedFor.expand((ids) => ids).toSet(),
        {...holes, id(301)},
      );
    });

    test('a read that found every file asks for nothing by number', () async {
      final (container, db, telegram) = await open([
        for (var number = 1; number <= 120; number++) photo(number << 20),
      ]);

      await container.read(driveSyncProvider.notifier).fullSync();

      expect(await db.knownMessageIds(), hasLength(120));
      expect(telegram.askedFor, isEmpty);
    });

    test('a file read before its folder still lands hidden or in Private', () async {
      // Newest first: the files come before the folders they are in.
      final (container, db, _) = await open([
        folder(1, 'secret', private: true),
        folder(2, 'old', trashed: true),
        photo(3, folderId: 'secret'),
        photo(4, folderId: 'old'),
        photo(5),
      ]);
      await container.read(driveSyncProvider.notifier).fullSync();

      expect((await db.fileById('p3'))!.inPrivate, isTrue);
      expect((await db.fileById('p4'))!.hidden, isTrue);
      final loose = (await db.fileById('p5'))!;
      expect((loose.hidden, loose.inPrivate), (false, false));
    });
  });

  group('forward filing', () {
    final at = DateTime(2026, 9, 1);

    Future<void> until(bool Function() condition) async {
      for (var i = 0; i < 500 && !condition(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(condition(), isTrue);
    }

    final wedding = textMessage(
      5,
      ManifestCodec.encodeFolder(
        FolderManifest(id: 'wedding', name: 'Wedding', parentId: null, createdAt: at, modifiedAt: at),
      ).text,
    );
    td.Message forward(int id, int seconds) => documentMessage(
      id,
      '',
      fileName: 'contract.pdf',
      mimeType: 'application/pdf',
      date: 1000 + seconds,
      forwardedFrom: const td.MessageOriginHiddenUser(senderName: 'Selam Tesfaye'),
    );

    Future<(ProviderContainer, _Channel, Preferences)> open(
      List<td.Message> history, {
      Map<String, Object> stored = const {},
    }) async {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues(stored);
      final prefs = await SharedPreferences.getInstance();
      final db = AppDatabase(NativeDatabase.memory());
      final telegram = _Channel();
      for (final message in history) {
        telegram.messages[message.id] = message;
      }
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          appDatabaseProvider.overrideWithValue(db),
          telegramClientProvider.overrideWithValue(telegram),
          driveSessionProvider.overrideWith(TestSession.new),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await db.close();
      });
      return (container, telegram, container.read(preferencesProvider));
    }

    test('the first read sets the watermark at the end and files nothing', () async {
      final (container, telegram, prefs) = await open([
        wedding,
        textMessage(20, 'Wedding', date: 1000),
        forward(21, 1),
      ]);
      await container.read(driveSyncProvider.notifier).fullSync();
      await container.read(forwardFilerProvider.notifier).whenIdle();

      expect(prefs.forwardFilingFrom(testChatId), 21);
      final db = container.read(appDatabaseProvider);
      expect((await db.fileById(MessageIndexer.adoptedId(21)))!.adopted, isTrue);
      expect(telegram.copies, 0);
      expect(telegram.messages.keys, contains(20));
    });

    test('a catch-up read hands what is newer than the watermark to the filer', () async {
      final (container, telegram, prefs) = await open(
        [wedding, textMessage(20, 'Wedding', date: 1000), forward(21, 1), forward(22, 2)],
        stored: {
          'full_sync_$testChatId': DateTime.now().millisecondsSinceEpoch,
          'indexed_with_$testChatId': MessageIndexer.version,
          'synced_upto_$testChatId': 4,
          'forward_filing_from_$testChatId': 4,
        },
      );
      await container.read(driveSyncProvider.notifier).syncOnOpen();
      await container.read(forwardFilerProvider.notifier).whenIdle();

      final db = container.read(appDatabaseProvider);
      for (final id in [21, 22]) {
        final file = (await db.fileById(MessageIndexer.adoptedId(id)))!;
        expect(file.folderId, 'wedding');
        expect(file.adopted, isFalse);
      }
      expect(telegram.copies, 2);
      expect(telegram.messages.keys, isNot(contains(20)));
      expect(prefs.forwardFilingFrom(testChatId), 22);
      expect(container.read(forwardFilerProvider)?.count, 2);
    });

    test('forwards that arrive live are filed once the burst has settled', () async {
      DriveSync.burstSettle = const Duration(milliseconds: 20);
      addTearDown(() => DriveSync.burstSettle = const Duration(seconds: 3));
      final (container, telegram, prefs) = await open(
        [wedding],
        stored: {
          'full_sync_$testChatId': DateTime.now().millisecondsSinceEpoch,
          'indexed_with_$testChatId': MessageIndexer.version,
          'synced_upto_$testChatId': 4,
          'forward_filing_from_$testChatId': 4,
        },
      );
      final sync = container.read(driveSyncProvider.notifier);
      await sync.syncOnOpen();

      final comment = textMessage(20, 'Wedding', date: 1000);
      telegram.messages[20] = comment;
      telegram.receive(td.UpdateNewMessage(message: comment).toJson());
      for (final message in [forward(21, 1), forward(22, 2)]) {
        telegram.messages[message.id] = message;
        telegram.receive(td.UpdateNewMessage(message: message).toJson());
      }
      // The burst settles, then the filer's pass runs; it has run once the
      // watermark has passed the burst.
      await until(() => prefs.forwardFilingFrom(testChatId) == 22);
      await container.read(forwardFilerProvider.notifier).whenIdle();

      final db = container.read(appDatabaseProvider);
      expect((await db.fileById(MessageIndexer.adoptedId(21)))!.folderId, 'wedding');
      expect((await db.fileById(MessageIndexer.adoptedId(22)))!.folderId, 'wedding');
      expect(telegram.copies, 2);
      expect(prefs.forwardFilingFrom(testChatId), 22);
    });
  });
}

/// The channel for the filing tests: history comes from [messages], newest
/// first and older than the message asked from, the way TDLib pages.
class _Channel extends FakeTelegram {
  final List<td.TdFunction> requests = [];

  @override
  Future<td.TdObject?> answer(td.TdFunction function) async {
    requests.add(function);
    if (function is td.GetChatHistory) {
      final older = messages.values.where((m) => m.id < function.fromMessageId).toList()
        ..sort((a, b) => b.id.compareTo(a.id));
      final page = function.fromMessageId == 0
          ? (messages.values.toList()..sort((a, b) => b.id.compareTo(a.id)))
          : older;
      return td.Messages(totalCount: page.length, messages: page.take(function.limit).toList());
    }
    if (function is td.OpenChat || function is td.CloseChat) return const td.Ok();
    return null;
  }

  int get copies => requests
      .whereType<td.SendMessage>()
      .where((r) => r.inputMessageContent is td.InputMessageForwarded)
      .length;
}
