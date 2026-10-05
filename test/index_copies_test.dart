import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegrive/features/drive/data/drive_repository.dart';
import 'package:telegrive/features/drive/data/drive_session.dart';
import 'package:telegrive/features/drive/data/index_copies.dart';
import 'package:telegrive/features/drive/data/message_indexer.dart';
import 'package:telegrive/features/drive/domain/manifest.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';
import 'package:telegrive/infrastructure/network/network_status.dart';
import 'package:telegrive/infrastructure/storage/preferences.dart';
import 'package:telegrive/infrastructure/telegram/telegram_client.dart';

import 'support/fake_telegram.dart';

/// TDLib's id for channel message [number], as it hands them out.
int _m(int number) => number << 20;

/// The pinned drive message, message 5.
final _cardId = _m(5);

/// A connection the test picks.
class _Network extends NetworkStatus {
  _Network(this._state);

  final NetworkState _state;

  @override
  NetworkState build() => _state;
}

/// Telegram that keeps what documents are sent with or replaced by in
/// [stored], under the TDLib file id it hands out, and downloads them back
/// from there.
class _Telegram extends FakeTelegram {
  _Telegram(this.stored);

  final Directory stored;
  final requests = <td.TdFunction>[];
  int nextFileId = 500;

  /// The number the next message sent here gets.
  int nextNumber = 100;

  td.MessageDocument _document(String path, td.FormattedText caption) {
    final id = nextFileId++;
    File(path).copySync('${stored.path}/$id');
    return td.MessageDocument(
      document: td.Document(
        fileName: IndexCopies.fileName,
        mimeType: 'application/gzip',
        document: tdFile(id, size: File(path).lengthSync()),
      ),
      caption: caption,
    );
  }

  @override
  Future<td.TdObject?> answer(td.TdFunction function) async {
    requests.add(function);
    switch (function) {
      case td.SendMessage(
        inputMessageContent: td.InputMessageDocument(
          document: td.InputFileLocal(:final path),
          :final caption?,
        ),
      ):
        final id = _m(nextNumber++);
        return messages[id] = channelMessage(id, _document(path, caption));
      case td.EditMessageMedia(
        :final messageId,
        inputMessageContent: td.InputMessageDocument(
          document: td.InputFileLocal(:final path),
          :final caption?,
        ),
      ):
        return messages[messageId] = channelMessage(messageId, _document(path, caption));
      case td.DownloadFile(:final fileId):
        final path = '${stored.path}/$fileId';
        return tdFile(fileId, path: path, downloaded: true, size: File(path).lengthSync());
      default:
        return null;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  late Directory temp;
  late Directory stored;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('index_copies_test');
    stored = Directory('${temp.path}/stored')..createSync();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      pathProvider,
      (call) async => temp.path,
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      pathProvider,
      null,
    );
    temp.deleteSync(recursive: true);
  });

  /// A phone with the drive open on [telegram], its drive message known,
  /// on [network].
  Future<(ProviderContainer, AppDatabase, Preferences)> open(
    _Telegram telegram, {
    NetworkState network = NetworkState.unknown,
    bool cardKnown = true,
  }) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({
      if (cardKnown) 'drive_card_$testChatId': _cardId,
      'synced_upto_$testChatId': _m(900),
    });
    final shared = await SharedPreferences.getInstance();
    final db = AppDatabase(NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(shared),
        appDatabaseProvider.overrideWithValue(db),
        telegramClientProvider.overrideWithValue(telegram),
        driveSessionProvider.overrideWith(TestSession.new),
        networkStatusProvider.overrideWith(() => _Network(network)),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    telegram.messages.putIfAbsent(
      _cardId,
      () => textMessage(
        _cardId,
        ManifestCodec.encodeDrive(DriveManifest(id: 'drive-1', createdAt: DateTime(2026, 10, 5))).text,
      ),
    );
    return (container, db, container.read(preferencesProvider));
  }

  /// A drive with a folder, an album, a starred photo in both, a file split
  /// in two, and a trashed file with a key only a newer version knows.
  Future<void> seed(DriveRepository repository) async {
    final created = DateTime.fromMillisecondsSinceEpoch(1_700_000_000_000);
    FileManifest file(String id, String name, {int partCount = 1, int partIndex = 0}) =>
        FileManifest(
          id: id,
          name: name,
          folderId: 'trips',
          mimeType: 'image/jpeg',
          size: 18,
          createdAt: created,
          modifiedAt: created,
          partCount: partCount,
          partIndex: partIndex,
        );
    await repository.ingest(textMessage(
      _m(1),
      ManifestCodec.encodeFolder(
        FolderManifest(id: 'trips', name: 'Trips', parentId: null, createdAt: created, modifiedAt: created),
      ).text,
    ));
    await repository.ingest(textMessage(
      _m(2),
      ManifestCodec.encodeAlbum(AlbumManifest(id: 'lal', name: 'Lalibela', createdAt: created, modifiedAt: created)).text,
    ));
    await repository.ingest(documentMessage(
      _m(10),
      ManifestCodec.encodeFile(
        file('p', 'IMG_1.jpg').copyWith(starred: true, albums: ['lal']),
      ).text,
    ));
    await repository.ingest(documentMessage(_m(20), ManifestCodec.encodeFile(file('big', 'big.bin', partCount: 2)).text));
    await repository.ingest(documentMessage(
      _m(21),
      ManifestCodec.encodePart(const PartRecord(fileId: 'big', index: 1, count: 2, size: 18)).text,
    ));
    await repository.ingest(documentMessage(
      _m(30),
      'tgfile2;xq=later;id=old;name=old.pdf;size=9;trashed=1700000500000;added=1700000000000',
    ));
  }

  test('a copy written and read back gives the same index', () async {
    final telegram = _Telegram(stored);
    final (container, db, _) = await open(telegram);
    await seed(container.read(driveRepositoryProvider));
    final before = await IndexCopies.snapshot(db);

    expect(await container.read(indexCopiesProvider).writeIfDue(testChatId), isTrue);

    final restoredDb = AppDatabase(NativeDatabase.memory());
    addTearDown(restoredDb.close);
    final copyNumber = ManifestCodec.decodeDrive(
      (telegram.messages[_cardId]!.content as td.MessageText).text.text,
    )!.indexMessageId!;
    final document =
        (telegram.messages[_m(copyNumber)]!.content as td.MessageDocument).document.document;
    final contents = IndexCopies.read(File('${stored.path}/${document.id}').readAsBytesSync())!;
    await restoredDb.replaceIndex(
      folderRows: contents.folders,
      albumRows: contents.albums,
      fileRows: contents.files,
      partRows: contents.parts,
      albumFileRows: contents.albumFiles,
    );

    expect(await IndexCopies.snapshot(restoredDb), before);
    final old = (await restoredDb.fileById('old'))!;
    expect(old.manifestExtra, '{"xq":"later"}');
    expect(old.hidden, isTrue, reason: 'in the trash');
    expect((await restoredDb.fileById('big'))!.partsPresent, 2);
    expect(await restoredDb.albumIdsOf('p'), ['lal']);
  });

  test('the first copy is sent and the drive message points to it; the next replaces it', () async {
    final telegram = _Telegram(stored);
    final (container, db, prefs) = await open(telegram);
    final repository = container.read(driveRepositoryProvider);
    await seed(repository);
    final copies = container.read(indexCopiesProvider);

    expect(await copies.writeIfDue(testChatId), isTrue);
    final card = ManifestCodec.decodeDrive(
      (telegram.messages[_cardId]!.content as td.MessageText).text.text,
    )!;
    // The drive message names the copy by its number, as its t.me link does.
    expect(card.indexMessageId, 100);
    final copyId = _m(card.indexMessageId!);
    final caption = (telegram.messages[copyId]!.content as td.MessageDocument).caption.text;
    expect(caption.split('\n').first, 'Telegrive index');
    final record = ManifestCodec.decodeIndex(caption)!;
    expect((record.driveId, record.throughMessageId, record.files), ('drive-1', 900, 3));
    expect(prefs.indexCopyAt(testChatId), isNotNull);

    // Not due again yet.
    expect(await copies.writeIfDue(testChatId), isFalse);

    // Due, but nothing changed.
    final unchanged = prefs.indexCopyPrint(testChatId)!;
    await prefs.setIndexCopy(testChatId, DateTime(2026), unchanged);
    expect(await copies.writeIfDue(testChatId), isFalse);

    // Due and changed: the same message takes the new copy.
    await repository.ingest(textMessage(
      _m(3),
      ManifestCodec.encodeFolder(
        FolderManifest(id: 'work', name: 'Work', parentId: null, createdAt: DateTime(2026), modifiedAt: DateTime(2026)),
      ).text,
    ));
    expect(await copies.writeIfDue(testChatId), isTrue);
    expect(telegram.requests.whereType<td.EditMessageMedia>().single.messageId, copyId);
    expect(telegram.requests.whereType<td.SendMessage>(), hasLength(1));
    expect(await db.folderById('work'), isNotNull);
  });

  test('on mobile data only a small copy goes', () async {
    addTearDown(() => IndexCopies.meteredLimit = 1024 * 1024);
    final telegram = _Telegram(stored);
    final (container, _, _) = await open(
      telegram,
      network: const NetworkState(online: true, metered: true),
    );
    await seed(container.read(driveRepositoryProvider));
    final copies = container.read(indexCopiesProvider);

    IndexCopies.meteredLimit = 100;
    expect(await copies.writeIfDue(testChatId), isFalse);
    expect(telegram.requests.whereType<td.SendMessage>(), isEmpty);

    IndexCopies.meteredLimit = 1024 * 1024;
    expect(await copies.writeIfDue(testChatId), isTrue);
    expect(telegram.requests.whereType<td.SendMessage>(), hasLength(1));
  });

  test('offline, nothing is written', () async {
    final telegram = _Telegram(stored);
    final (container, _, _) = await open(
      telegram,
      network: const NetworkState(online: false, metered: false),
    );
    expect(await container.read(indexCopiesProvider).writeIfDue(testChatId), isFalse);
    expect(telegram.requests, isEmpty);
  });

  test('without the drive message known, nothing is written', () async {
    final telegram = _Telegram(stored);
    final (container, _, _) = await open(telegram, cardKnown: false);
    expect(await container.read(indexCopiesProvider).writeIfDue(testChatId), isFalse);
    expect(telegram.requests, isEmpty);
  });

  test('a new phone fills its index from the copy', () async {
    final telegram = _Telegram(stored);
    final (writer, _, _) = await open(telegram);
    await seed(writer.read(driveRepositoryProvider));
    expect(await writer.read(indexCopiesProvider).writeIfDue(testChatId), isTrue);

    final (reader, db, _) = await open(telegram);
    expect(await reader.read(indexCopiesProvider).restore(testChatId), isTrue);

    final photo = (await db.fileById('p'))!;
    expect((photo.name, photo.folderId, photo.starred), ('IMG_1.jpg', 'trips', true));
    expect((await db.folderById('trips'))!.name, 'Trips');
    expect((await db.albumById('lal'))!.name, 'Lalibela');
    expect((await db.partsOf('big')).map((p) => p.messageId), [_m(20), _m(21)]);
  });

  test('a copy that belongs to another drive, or none at all, leaves the index alone', () async {
    final telegram = _Telegram(stored);
    final (writer, _, _) = await open(telegram);
    await seed(writer.read(driveRepositoryProvider));
    expect(await writer.read(indexCopiesProvider).writeIfDue(testChatId), isTrue);
    final card = ManifestCodec.decodeDrive(
      (telegram.messages[_cardId]!.content as td.MessageText).text.text,
    )!;

    // The drive message names a different drive.
    final (reader, db, _) = await open(telegram);
    telegram.messages[_cardId] = textMessage(
      _cardId,
      ManifestCodec.encodeDrive(
        DriveManifest(id: 'drive-2', createdAt: DateTime(2026), indexMessageId: card.indexMessageId),
      ).text,
    );
    expect(await reader.read(indexCopiesProvider).restore(testChatId), isFalse);
    expect(await db.fileById('p'), isNull);

    telegram.messages[_cardId] = textMessage(
      _cardId,
      ManifestCodec.encodeDrive(DriveManifest(id: 'drive-1', createdAt: DateTime(2026))).text,
    );
    expect(await reader.read(indexCopiesProvider).restore(testChatId), isFalse);
  });

  test('a copy that can\'t be read is no copy', () {
    expect(IndexCopies.read([1, 2, 3]), isNull);
    expect(IndexCopies.read(gzip.encode('{"format":99}'.codeUnits)), isNull);
    // A copy of another format, such as the first, is passed over.
    expect(
      IndexCopies.read(gzip.encode('{"format":1,"folders":[],"albums":[],"files":[]}'.codeUnits)),
      isNull,
    );
  });

  test('the copy in the channel is never taken for a file', () {
    final message = channelMessage(
      40,
      td.MessageDocument(
        document: td.Document(
          fileName: IndexCopies.fileName,
          mimeType: 'application/gzip',
          document: tdFile(40),
        ),
        caption: td.FormattedText(
          text: ManifestCodec.encodeIndex(
            IndexRecord(driveId: 'drive-1', throughMessageId: 900, files: 3, createdAt: DateTime(2026)),
          ).text,
          entities: const [],
        ),
      ),
    );
    expect(MessageIndexer.entryFor(message), isNull);
    expect(MessageIndexer.isAdopted(message), isFalse);
    expect(MessageIndexer.postOf(message).manifest, isTrue);
    expect(MessageIndexer.manifestOf(message), isA<IndexRecord>());
  });

  test('the fingerprint is the same in every run and tells contents apart', () {
    expect(IndexCopies.fingerprint('abc'.codeUnits), 0x1a47e90b);
    expect(IndexCopies.fingerprint('abd'.codeUnits), isNot(0x1a47e90b));
    expect(IndexCopies.fingerprint(const []), 0x811c9dc5);
  });
}
