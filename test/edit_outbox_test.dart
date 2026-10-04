import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegrive/features/drive/data/drive_repository.dart';
import 'package:telegrive/features/drive/data/drive_session.dart';
import 'package:telegrive/features/drive/data/edit_outbox.dart';
import 'package:telegrive/features/drive/domain/drive_models.dart';
import 'package:telegrive/features/drive/domain/manifest.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';
import 'package:telegrive/infrastructure/storage/preferences.dart';
import 'package:telegrive/infrastructure/telegram/telegram_client.dart';
import 'package:telegrive/infrastructure/telegram/telegram_exception.dart';

import 'support/fake_telegram.dart';

/// The channel of [FakeTelegram], which keeps every request it is sent and
/// refuses any of them while TDLib says it has no connection, as a request
/// that would wait for one; [refusals] turns a kind of request down.
class _Telegram extends FakeTelegram {
  final requests = <td.TdFunction>[];
  final refusals = <Type, TelegramException>{};

  @override
  Future<td.TdObject?> answer(td.TdFunction function) async {
    if (function is td.OpenChat || function is td.CloseChat) return const td.Ok();
    requests.add(function);
    if (!isOnline) throw StateError('Sent without a connection: $function');
    if (refusals[function.runtimeType] case final refusal?) throw refusal;
    return null;
  }

  void goOffline() => setConnectionState(const td.ConnectionStateWaitingForNetwork());

  void goOnline() => setConnectionState(const td.ConnectionStateReady());

  /// The file manifest of the caption the last edit of [messageId] wrote.
  FileManifest lastCaption(int messageId) => ManifestCodec.decodeFile(
    requests
        .whereType<td.EditMessageCaption>()
        .lastWhere((edit) => edit.messageId == messageId)
        .caption!
        .text,
  )!;
}

void main() {
  final created = DateTime(2026, 9, 1);
  late ProviderContainer container;
  late _Telegram telegram;
  late AppDatabase db;
  late DriveRepository repository;

  FileManifest manifest(
    String id,
    String name, {
    bool starred = false,
    DateTime? trashedAt,
    List<String> albums = const [],
  }) => FileManifest(
    id: id,
    name: name,
    folderId: null,
    mimeType: 'application/pdf',
    size: 9,
    createdAt: created,
    modifiedAt: created,
    starred: starred,
    trashedAt: trashedAt,
    albums: albums,
  );

  /// Puts [m] in the channel as message [id] and reads it into the index.
  Future<void> post(int id, FileManifest m) async {
    telegram.messages[id] = documentMessage(
      id,
      ManifestCodec.encodeFile(m).text,
      fileName: m.name,
      mimeType: m.mimeType,
    );
    await repository.ingest(telegram.messages[id]!);
  }

  Future<void> postText(int id, String text) async {
    telegram.messages[id] = textMessage(id, text);
    await repository.ingest(telegram.messages[id]!);
  }

  Future<DriveFile> fileOf(String id) async => (await repository.fileById(id))!;

  EditOutbox outbox() => container.read(editOutboxProvider.notifier);

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    db = AppDatabase(NativeDatabase.memory());
    telegram = _Telegram();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        appDatabaseProvider.overrideWithValue(db),
        telegramClientProvider.overrideWithValue(telegram),
        driveSessionProvider.overrideWith(TestSession.new),
      ],
    );
    // Passes run when a test asks for them, not on a timer of their own.
    EditOutbox.settle = const Duration(hours: 1);
    container.listen(editOutboxProvider, (_, _) {});
    repository = container.read(driveRepositoryProvider);
    await post(10, manifest('f1', 'Scan 12.pdf'));
  });

  tearDown(() async {
    EditOutbox.settle = const Duration(seconds: 2);
    container.dispose();
    await db.close();
  });

  test('a rename without a connection shows at once and waits on the phone', () async {
    telegram.goOffline();
    await repository.renameFile(await fileOf('f1'), 'Lease.pdf');

    expect((await db.fileById('f1'))!.name, 'Lease.pdf');
    expect(telegram.requests, isEmpty);
    final rows = await db.pendingEditList();
    expect(rows.single.target, EditTarget.file);
    expect(rows.single.itemId, 'f1');
    await pumpEventQueue();
    expect(container.read(editOutboxProvider).waiting, 1);

    // A sync reading the message as Telegram still has it keeps the name.
    await repository.ingest(telegram.messages[10]!);
    expect((await db.fileById('f1'))!.name, 'Lease.pdf');
  });

  test('once the connection is back the change goes, read again first', () async {
    telegram.goOffline();
    await repository.renameFile(await fileOf('f1'), 'Lease.pdf');

    telegram.goOnline();
    await outbox().drain();

    expect(telegram.requests.map((r) => r.runtimeType), [td.GetMessage, td.EditMessageCaption]);
    expect(telegram.lastCaption(10).name, 'Lease.pdf');
    expect((await db.fileById('f1'))!.name, 'Lease.pdf');
    expect(await db.pendingEditList(), isEmpty);
    await pumpEventQueue();
    expect(container.read(editOutboxProvider).waiting, 0);
    expect(container.read(editOutboxProvider).sending, isFalse);
  });

  test('another device\'s rename wins, and a star made here still goes', () async {
    telegram.goOffline();
    await repository.renameFile(await fileOf('f1'), 'Lease.pdf');
    await repository.setStarred([await fileOf('f1')], starred: true);
    expect(await db.pendingEditList(), hasLength(1));
    // Meanwhile another phone renamed it.
    telegram.messages[10] = documentMessage(
      10,
      ManifestCodec.encodeFile(manifest('f1', 'Budget.xlsx')).text,
    );

    telegram.goOnline();
    await outbox().drain();

    final written = telegram.lastCaption(10);
    expect(written.name, 'Budget.xlsx');
    expect(written.starred, isTrue);
    final row = (await db.fileById('f1'))!;
    expect(row.name, 'Budget.xlsx');
    expect(row.starred, isTrue);
    expect(await db.pendingEditList(), isEmpty);
    final notice = container.read(editOutboxProvider).notice!;
    expect(notice.name, 'Scan 12.pdf');
    expect(notice.verb, 'rename');
  });

  test('a trash and its Undo without a connection leave nothing waiting', () async {
    telegram.goOffline();
    await repository.trash(files: [await fileOf('f1')]);
    expect((await db.fileById('f1'))!.trashedAt, isNotNull);
    expect(await db.watchFilesIn(null).first, isEmpty);
    expect(await db.pendingEditList(), hasLength(1));

    await repository.restore(files: [await fileOf('f1')]);

    expect((await db.fileById('f1'))!.trashedAt, isNull);
    expect(await db.watchFilesIn(null).first, hasLength(1));
    expect(await db.pendingEditList(), isEmpty);
    expect(telegram.requests, isEmpty);
  });

  test(
    'a restore without a connection goes out whatever milliseconds the trash time has',
    () async {
      // The caption keeps the millisecond the index cuts off.
      await post(
        11,
        manifest('f2', 'Old.pdf', trashedAt: DateTime.fromMillisecondsSinceEpoch(1727430000123)),
      );
      telegram.goOffline();
      await repository.restore(files: [await fileOf('f2')]);
      expect((await db.fileById('f2'))!.trashedAt, isNull);

      telegram.goOnline();
      await outbox().drain();

      expect(telegram.lastCaption(11).trashedAt, isNull);
      expect((await db.fileById('f2'))!.trashedAt, isNull);
      expect(container.read(editOutboxProvider).notice, isNull);
      expect(await db.pendingEditList(), isEmpty);
    },
  );

  test('a request that times out leaves the change waiting instead of failing', () async {
    telegram.refusals[td.EditMessageCaption] = const TelegramException(408, 'Request timeout');

    await repository.renameFile(await fileOf('f1'), 'Lease.pdf');

    expect((await db.fileById('f1'))!.name, 'Lease.pdf');
    expect(await db.pendingEditList(), hasLength(1));
  });

  test('a change with one already waiting joins it rather than going first', () async {
    telegram.goOffline();
    await repository.renameFile(await fileOf('f1'), 'Lease.pdf');
    telegram.goOnline();

    await repository.setStarred([await fileOf('f1')], starred: true);

    expect(telegram.requests, isEmpty);
    final waiting = await db.pendingEditList();
    expect(waiting.single.patch, allOf(contains('"n"'), contains('"st"')));
  });

  test('a pause Telegram asks for holds the changes until it is over', () async {
    telegram.goOffline();
    await repository.renameFile(await fileOf('f1'), 'Lease.pdf');
    telegram.goOnline();
    telegram.refusals[td.EditMessageCaption] = const TelegramException(420, 'FLOOD_WAIT_120');

    final before = DateTime.now();
    await outbox().drain();

    final pausedUntil = container.read(editOutboxProvider).pausedUntil!;
    expect(pausedUntil.isAfter(before.add(const Duration(seconds: 120))), isTrue);
    final row = (await db.pendingEditList()).single;
    expect(row.attempts, 0);
    // The name stays as it was changed, though Telegram hasn't taken it.
    expect((await db.fileById('f1'))!.name, 'Lease.pdf');

    // Nothing more goes out while the pause lasts.
    telegram.requests.clear();
    await outbox().drain();
    expect(telegram.requests, isEmpty);
  });

  test('a change Telegram keeps turning down waits for Try again', () async {
    telegram.goOffline();
    await repository.renameFile(await fileOf('f1'), 'Lease.pdf');
    telegram.goOnline();
    telegram.refusals[td.EditMessageCaption] = const TelegramException(403, 'CHAT_WRITE_FORBIDDEN');

    for (var pass = 0; pass < EditOutbox.maxAttempts + 1; pass++) {
      await outbox().drain();
    }

    expect(telegram.requests.whereType<td.EditMessageCaption>(), hasLength(EditOutbox.maxAttempts));
    final row = (await db.pendingEditList()).single;
    expect(row.lastError, 'Chat write forbidden');
    await pumpEventQueue();
    expect(container.read(editOutboxProvider).failed, 1);
    final views = await repository.watchPendingEdits().first;
    expect(views.single.error, 'Chat write forbidden');

    telegram.refusals.clear();
    await outbox().retryFailed();
    expect(await db.pendingEditList(), isEmpty);
    expect(telegram.lastCaption(10).name, 'Lease.pdf');
  });

  test('discarding without a connection puts back how Telegram had it', () async {
    telegram.goOffline();
    await repository.renameFile(await fileOf('f1'), 'Lease.pdf');
    await repository.setStarred([await fileOf('f1')], starred: true);

    await outbox().discard(EditTarget.file, 'f1');

    final row = (await db.fileById('f1'))!;
    expect(row.name, 'Scan 12.pdf');
    expect(row.starred, isFalse);
    expect(await db.pendingEditList(), isEmpty);
    expect(telegram.requests, isEmpty);
  });

  test('discarding online reads the message again', () async {
    telegram.goOffline();
    await repository.renameFile(await fileOf('f1'), 'Lease.pdf');
    telegram.goOnline();

    await outbox().discard(EditTarget.file, 'f1');

    expect(telegram.requests.map((r) => r.runtimeType), [td.GetMessage]);
    expect((await db.fileById('f1'))!.name, 'Scan 12.pdf');
  });

  test('folders and albums wait, merge and go the same way', () async {
    await postText(
      20,
      ManifestCodec.encodeFolder(
        FolderManifest(
          id: 'work',
          name: 'Work',
          parentId: null,
          createdAt: created,
          modifiedAt: created,
        ),
      ).text,
    );
    await postText(
      30,
      ManifestCodec.encodeAlbum(
        AlbumManifest(id: 'a1', name: 'Trip', createdAt: created, modifiedAt: created),
      ).text,
    );
    await post(11, manifest('f2', 'IMG_2.jpg', albums: ['a0']));
    telegram.goOffline();

    final work = (await repository.folderById('work'))!;
    await repository.renameFolder(work, 'Work 2026');
    await repository.moveFiles([await fileOf('f1')], 'work');
    await repository.renameFile(await fileOf('f1'), 'Lease.pdf');
    await repository.addToAlbum([await fileOf('f1'), await fileOf('f2')], 'a1');
    await repository.renameAlbum('a1', 'Lalibela 2026');

    expect((await db.folderById('work'))!.name, 'Work 2026');
    expect((await db.albumById('a1'))!.name, 'Lalibela 2026');
    expect(await db.albumIdsOf('f2'), unorderedEquals(['a0', 'a1']));
    final views = {for (final view in await repository.watchPendingEdits().first) view.id: view};
    expect(
      views['f1']!.description,
      'Renamed from "Scan 12.pdf" · Moved to Work 2026 · Added to "Lalibela 2026"',
    );
    expect(views['work']!.description, 'Renamed from "Work"');
    expect(views['a1']!.description, 'Renamed from "Trip"');
    // Another phone put the second photo in an album of its own meanwhile.
    telegram.messages[11] = documentMessage(
      11,
      ManifestCodec.encodeFile(manifest('f2', 'IMG_2.jpg', albums: ['a0', 'b9'])).text,
    );

    telegram.goOnline();
    await outbox().drain();

    expect(telegram.lastCaption(10).folderId, 'work');
    expect(telegram.lastCaption(10).albums, ['a1']);
    expect(telegram.lastCaption(11).albums, ['a0', 'a1', 'b9']);
    final texts = {
      for (final edit in telegram.requests.whereType<td.EditMessageText>())
        edit.messageId: (edit.inputMessageContent as td.InputMessageText).text.text,
    };
    expect(ManifestCodec.decodeFolder(texts[20]!)!.name, 'Work 2026');
    expect(ManifestCodec.decodeAlbum(texts[30]!)!.name, 'Lalibela 2026');
    expect(await db.pendingEditList(), isEmpty);
    expect(await db.albumIdsOf('f2'), unorderedEquals(['a0', 'a1', 'b9']));
  });

  test('a chat Telegram hasn\'t loaded yet is not an item that went', () async {
    telegram.goOffline();
    await repository.renameFile(await fileOf('f1'), 'Lease.pdf');
    telegram.goOnline();
    telegram.refusals[td.GetMessage] = const TelegramException(400, 'Chat not found');

    await outbox().drain();

    final row = (await db.pendingEditList()).single;
    expect(row.lastError, isNotNull);
    expect((await db.fileById('f1'))!.name, 'Lease.pdf');
  });

  test('deleting an album without a connection is refused before anything changes', () async {
    await postText(
      30,
      ManifestCodec.encodeAlbum(
        AlbumManifest(id: 'a1', name: 'Trip', createdAt: created, modifiedAt: created),
      ).text,
    );
    await post(11, manifest('f2', 'IMG_2.jpg', albums: ['a1']));
    telegram.goOffline();

    await expectLater(repository.deleteAlbum('a1'), throwsA(isA<DriveException>()));

    expect(await db.albumIdsOf('f2'), ['a1']);
    expect((await db.albumById('a1'))!.name, 'Trip');
    expect(await db.pendingEditList(), isEmpty);
    expect(telegram.requests, isEmpty);
  });

  test('deleting an album takes a waiting rename of it along', () async {
    await postText(
      30,
      ManifestCodec.encodeAlbum(
        AlbumManifest(id: 'a1', name: 'Trip', createdAt: created, modifiedAt: created),
      ).text,
    );
    telegram.goOffline();
    await repository.renameAlbum('a1', 'Lalibela 2026');
    expect(await db.pendingEditList(), hasLength(1));
    telegram.goOnline();

    await repository.deleteAlbum('a1');

    expect(await db.albumById('a1'), isNull);
    expect(await db.pendingEditList(), isEmpty);
  });

  test('a change to an item deleted elsewhere meanwhile is dropped', () async {
    telegram.goOffline();
    await repository.renameFile(await fileOf('f1'), 'Lease.pdf');
    telegram.messages.remove(10);

    telegram.goOnline();
    await outbox().drain();

    expect(await db.pendingEditList(), isEmpty);
    expect(telegram.requests.whereType<td.EditMessageCaption>(), isEmpty);
  });
}
