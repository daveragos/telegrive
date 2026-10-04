import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegrive/features/drive/data/drive_repository.dart';
import 'package:telegrive/features/drive/data/drive_session.dart';
import 'package:telegrive/features/drive/domain/manifest.dart';
import 'package:telegrive/features/offline/data/offline_sync.dart';
import 'package:telegrive/features/transfers/data/transfer_queue.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';
import 'package:telegrive/infrastructure/network/network_status.dart';
import 'package:telegrive/infrastructure/storage/device_profile.dart';
import 'package:telegrive/infrastructure/storage/device_storage.dart';
import 'package:telegrive/infrastructure/storage/preferences.dart';
import 'package:telegrive/infrastructure/telegram/telegram_client.dart';
import 'package:telegrive/infrastructure/telegram/telegram_exception.dart';

import 'support/fake_telegram.dart';

/// The original of IMG_1.HEIC on the phone, and its small copy's size.
const _original = 4000;
const _small = 300;

/// Telegram as a small copy's upload and replacement meet it. Documents
/// sent are delivered at once. The original uploads ahead as TDLib's file
/// 9; the edit that puts it in the small copy's place waits for [editGate]
/// and is refused when [refuseEdits]. Calling the upload off fails an edit
/// still waiting, as nothing is left to put in.
class _Telegram extends FakeTelegram {
  int cancels = 0;
  bool refuseEdits = false;
  String fetchedPath = '';
  Completer<void> editGate = Completer<void>()..complete();

  /// A message TDLib is still sending, the way a restart finds it.
  td.Message? pending;

  /// The messages asked to be deleted, in order.
  final List<int> deleted = [];

  /// Every caption a document went up or was edited with, in order.
  final List<String> captions = [];

  @override
  Future<td.TdObject?> answer(td.TdFunction function) async {
    switch (function) {
      case td.PreliminaryUploadFile():
        return uploading(0);
      // The small copy in message 7, on the phone already.
      case td.GetFile(fileId: 7):
        return tdFile(7, size: _small, path: fetchedPath, downloaded: true);
      // The original, once it is the message's file.
      case td.GetFile(fileId: 9):
        return tdFile(9, size: _original, path: fetchedPath, downloaded: true);
      // Fetching either lands the file at [fetchedPath] at once.
      case td.DownloadFile(fileId: 7):
        return tdFile(7, size: _small, path: fetchedPath, downloaded: true);
      case td.DownloadFile(fileId: 9):
        return tdFile(9, size: _original, path: fetchedPath, downloaded: true);
      case td.DeleteFile():
        return const td.Ok();
      case td.GetChatHistory(fromMessageId: 0, onlyLocal: true):
        final message = pending;
        return td.Messages(totalCount: message == null ? 0 : 1, messages: [?message]);
      case td.DeleteMessages(:final messageIds):
        deleted.addAll(messageIds);
        messageIds.forEach(messages.remove);
        return const td.Ok();
      case td.CancelPreliminaryUploadFile():
        cancels++;
        if (!editGate.isCompleted) {
          editGate.completeError(const TelegramException(400, 'Upload canceled'));
        }
        return const td.Ok();
      case td.EditMessageMedia(
        :final messageId,
        inputMessageContent: td.InputMessageDocument(
          document: td.InputFileId(:final id),
          :final caption?,
        ),
      ):
        if (refuseEdits) throw const TelegramException(400, "Message can't be edited");
        await editGate.future;
        captions.add(caption.text);
        final old = messages[messageId]!;
        return messages[messageId] = old.copyWith(
          content: td.MessageDocument(
            document: td.Document(
              fileName: 'IMG_1.HEIC',
              mimeType: 'image/heic',
              document: tdFile(id, size: _original),
            ),
            caption: caption,
          ),
        );
      case td.SendMessage(
        inputMessageContent: td.InputMessageDocument(
          document: td.InputFileLocal(:final path),
          :final caption?,
        ),
      ):
        captions.add(caption.text);
        final id = nextId++;
        return messages[id] = documentMessage(
          id,
          caption.text,
          fileName: p.basename(path),
          mimeType: 'image/jpeg',
          size: File(path).lengthSync(),
        );
      default:
        return null;
    }
  }

  /// TDLib's file 9 with [bytes] of the original uploaded.
  static td.File uploading(int bytes) {
    final file = tdFile(9, size: _original);
    return file.copyWith(
      remote: file.remote.copyWith(
        isUploadingActive: true,
        isUploadingCompleted: false,
        uploadedSize: bytes,
      ),
    );
  }
}

/// A phone with room for anything, whose Download folder keeps each file
/// under the name it is given.
class _Storage extends DeviceStorage {
  final List<String> saved = [];

  @override
  Future<int?> freeBytes() async => 10 << 30;

  @override
  Future<String> saveFile(
    String source, {
    required List<String> folders,
    required String name,
    required String mimeType,
  }) async {
    saved.add(name);
    return source;
  }
}

/// A phone whose connection the test sets.
class _Network extends NetworkStatus {
  _Network(this._initial);

  final NetworkState _initial;

  @override
  NetworkState build() => _initial;

  void set(NetworkState next) => state = next;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late AppDatabase db;
  late _Telegram telegram;
  late ProviderContainer container;
  late TransferQueue queue;
  late DriveRepository repository;
  late _Storage storage;

  /// The small copy's caption, in message 7: starred, in the Camera folder
  /// and an album.
  const smallCaption =
      'IMG_1.HEIC (small copy)\ntgr1:{"id":"p","n":"IMG_1.HEIC","f":"camera",'
      '"m":"image/jpeg","s":$_small,"ct":1700000000000,"mt":1700000000000,'
      '"st":1,"tk":1690000000000,"al":["a1"],"lt":$_original}';

  Future<void> open({NetworkState network = NetworkState.unknown}) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    final shared = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(shared),
        appDatabaseProvider.overrideWithValue(db),
        telegramClientProvider.overrideWithValue(telegram),
        driveSessionProvider.overrideWith(TestSession.new),
        saveMemoryProvider.overrideWithBuild((ref, notifier) => false),
        networkStatusProvider.overrideWith(() => _Network(network)),
        deviceStorageProvider.overrideWithValue(storage),
      ],
    );
    addTearDown(container.dispose);
    var loaded = false;
    container.listen<TransfersState>(transferQueueProvider, (_, _) => loaded = true);
    container.read(transferQueueProvider);
    for (var i = 0; i < 200 && !loaded; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    queue = container.read(transferQueueProvider.notifier);
    repository = container.read(driveRepositoryProvider);
    final small = documentMessage(
      7,
      smallCaption,
      fileName: 'IMG_1.HEIC',
      mimeType: 'image/jpeg',
      size: _small,
    );
    telegram.messages[7] = small;
    await repository.ingest(small);
  }

  /// Queues the phone's original of IMG_1.HEIC to replace its small copy.
  Future<String> replace({bool wifiOnly = false}) async {
    final original = File(p.join(dir.path, 'IMG_1.HEIC'))
      ..writeAsBytesSync(List.filled(_original, 1));
    final [id] = await queue.enqueueUploads([
      UploadRequest(
        name: 'IMG_1.HEIC',
        path: original.path,
        origin: TransferOrigin.backup,
        assetId: 'asset-1',
        fileId: 'p',
        replacesSmallCopy: true,
        wifiOnly: wifiOnly,
      ),
    ]);
    return id;
  }

  TransfersState transfers() => container.read(transferQueueProvider);

  /// IMG_2.HEIC's small copy as TDLib still sends it when the app stops: its
  /// row is running, its message pending, and the JPEG is on the phone.
  Future<File> leaveSmallCopySending() async {
    final jpeg = File(p.join(dir.path, 'telegrive-small', '2.jpg'))
      ..createSync(recursive: true)
      ..writeAsBytesSync(List.filled(_small, 2));
    final now = DateTime.fromMillisecondsSinceEpoch(1700000000000);
    final caption = ManifestCodec.encodeFile(
      FileManifest(
        id: 'q',
        name: 'IMG_2.HEIC',
        folderId: null,
        mimeType: 'image/jpeg',
        size: _small,
        createdAt: now,
        modifiedAt: now,
        originalSize: _original,
      ),
    );
    telegram.pending = documentMessage(
      500,
      caption.text,
      fileName: 'IMG_2.HEIC',
      mimeType: 'image/jpeg',
      size: _small,
    ).copyWith(sendingState: const td.MessageSendingStatePending(sendingId: 0));
    await db.saveTransfers([
      TransferRow(
        id: 'up',
        kind: TransferKind.upload,
        status: TransferStatus.running,
        name: 'IMG_2.HEIC',
        mimeType: 'image/jpeg',
        fileId: 'q',
        sourcePath: jpeg.path,
        ownsSource: true,
        wifiOnly: false,
        totalBytes: _small,
        doneBytes: 100,
        partCount: 1,
        completedParts: 0,
        createdAt: now,
        origin: TransferOrigin.backup,
        assetId: 'asset-2',
      ),
    ]);
    return jpeg;
  }

  Map<String, dynamic> machineLine(String caption) =>
      jsonDecode(caption.substring(caption.indexOf('{'))) as Map<String, dynamic>;

  Future<void> until(bool Function() condition) async {
    for (var i = 0; i < 200 && !condition(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(condition(), isTrue);
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('telegrive_small_copy');
    db = AppDatabase(NativeDatabase.memory());
    telegram = _Telegram();
    storage = _Storage();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => dir.path,
    );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    await db.close();
    await dir.delete(recursive: true);
  });

  test('a small copy goes up as a JPEG under the photo\'s name, marked as one', () async {
    await open();
    final jpeg = File(p.join(dir.path, 'telegrive-small', '2.jpg'))
      ..createSync(recursive: true)
      ..writeAsBytesSync(List.filled(_small, 2));
    final [id] = await queue.enqueueUploads([
      UploadRequest(
        name: 'IMG_2.HEIC',
        path: jpeg.path,
        ownsSource: true,
        origin: TransferOrigin.backup,
        assetId: 'asset-2',
        smallCopyOf: _original,
      ),
    ]);
    expect(queue.sendsSmallCopy(id), isTrue);
    final row = await queue.whenFinished(id);

    expect(row.status, TransferStatus.completed);
    expect(row.mimeType, 'image/jpeg');
    final caption = telegram.captions.single;
    expect(caption.split('\n').first, 'IMG_2.HEIC (small copy)');
    final sent = machineLine(caption);
    expect(sent['n'], 'IMG_2.HEIC');
    expect(sent['m'], 'image/jpeg');
    expect(sent['s'], _small);
    expect(sent['lt'], _original);
    final file = (await db.fileById(row.fileId))!;
    expect(file.originalSize, _original);
    expect(file.size, _small);
    expect(queue.sendsSmallCopy(id), isFalse);
    // The copy was the queue's own, and goes once it is in the drive.
    await until(() => !jpeg.existsSync());
  });

  test('the original takes the small copy\'s place in the same message', () async {
    await open();
    telegram.editGate = Completer<void>();
    final id = await replace();
    await until(() => transfers().byId(id)?.status == TransferStatus.running);

    // Progress is TDLib's file for the upload made ahead.
    telegram.receive(td.UpdateFile(file: _Telegram.uploading(3000)).toJson());
    await until(() => transfers().byId(id)?.row.doneBytes == 3000);

    telegram.editGate.complete();
    final row = await queue.whenFinished(id);
    expect(row.status, TransferStatus.completed);
    expect(row.fileId, 'p');

    final caption = telegram.captions.single;
    expect(caption.split('\n').first, 'IMG_1.HEIC');
    final sent = machineLine(caption);
    expect(sent.containsKey('lt'), isFalse);
    expect(sent['s'], _original);
    expect(sent['f'], 'camera');
    expect(sent['st'], 1);
    expect(sent['al'], ['a1']);
    expect(sent['tk'], 1690000000000);

    final file = (await db.fileById('p'))!;
    expect(file.originalSize, isNull);
    expect(file.size, _original);
    expect(file.starred, isTrue);
    expect(file.folderId, 'camera');
    expect(await db.albumIdsOf('p'), ['a1']);
    final part = (await db.partsOf('p')).single;
    expect(part.messageId, 7);
    expect(part.tdFileId, 9);
  });

  test('a rename made while the original goes up is kept once it is in', () async {
    await open();
    telegram.editGate = Completer<void>();
    final id = await replace();
    await until(() => transfers().byId(id)?.status == TransferStatus.running);
    // The edit was asked for with the caption as it stood.
    await Future<void>.delayed(const Duration(milliseconds: 20));

    await repository.renameFile((await repository.fileById('p'))!, 'Lalibela.HEIC');
    expect((await db.fileById('p'))!.originalSize, _original);

    telegram.editGate.complete();
    expect((await queue.whenFinished(id)).status, TransferStatus.completed);

    final caption = (telegram.messages[7]!.content as td.MessageDocument).caption.text;
    expect(caption.split('\n').first, 'Lalibela.HEIC');
    final sent = machineLine(caption);
    expect(sent['n'], 'Lalibela.HEIC');
    expect(sent.containsKey('lt'), isFalse);
    expect(sent['s'], _original);
    final file = (await db.fileById('p'))!;
    expect(file.name, 'Lalibela.HEIC');
    expect(file.originalSize, isNull);
    expect(file.size, _original);
  });

  test('a small copy of a HEIC photo saves to the phone as a .jpg', () async {
    await open();
    telegram.fetchedPath = (File(
      p.join(dir.path, 'fetched'),
    )..writeAsBytesSync(List.filled(_small, 2))).path;
    final file = (await repository.fileById('p'))!;
    expect(await queue.enqueueSaves([SaveRequest(file, target: SaveTarget.files)]), 1);
    final id = transfers().items.single.id;
    expect((await queue.whenFinished(id)).status, TransferStatus.completed);
    expect(storage.saved, ['IMG_1.jpg']);
  });

  test('cancelling calls the upload off and leaves the small copy in the drive', () async {
    await open();
    telegram.editGate = Completer<void>();
    final id = await replace();
    await until(() => transfers().byId(id)?.status == TransferStatus.running);
    // The edit is under way, waiting on the upload.
    await Future<void>.delayed(const Duration(milliseconds: 20));

    await queue.cancel(id);

    expect(telegram.cancels, 1);
    final file = (await db.fileById('p'))!;
    expect(file.originalSize, _original);
    expect(telegram.messages[7], isNotNull);
    expect(telegram.captions, isEmpty);
  });

  test('a message Telegram won\'t edit gets the original under a new id', () async {
    await open();
    telegram.refuseEdits = true;
    final id = await replace();
    final row = await queue.whenFinished(id);

    expect(row.status, TransferStatus.completed);
    expect(row.fileId, isNot('p'));
    expect(await db.fileById('p'), isNull);
    expect(telegram.messages.containsKey(7), isFalse);

    final file = (await db.fileById(row.fileId))!;
    expect(file.originalSize, isNull);
    expect(file.name, 'IMG_1.HEIC');
    expect(file.folderId, 'camera');
    expect(file.starred, isTrue);
    expect(file.takenAt, DateTime.fromMillisecondsSinceEpoch(1690000000000));
    expect(await db.albumIdsOf(row.fileId), ['a1']);
    final sent = machineLine(telegram.captions.single);
    expect(sent['id'], row.fileId);
    expect(sent.containsKey('lt'), isFalse);
  });

  test('a small copy still sending after a restart stays a small copy on mobile data', () async {
    await leaveSmallCopySending();
    await open(network: NetworkState.unknown);
    expect(queue.sendsSmallCopy('up'), isTrue);

    // Mobile data holds what waits for Wi-Fi, and this doesn't.
    (container.read(networkStatusProvider.notifier) as _Network).set(
      const NetworkState(online: true, metered: true),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(transfers().byId('up')?.status, TransferStatus.running);
    expect(telegram.deleted, isEmpty);

    final ended = queue.whenFinished('up');
    await queue.cancel('up');
    expect((await ended).status, TransferStatus.cancelled);
  });

  test('a small copy held after a restart is sent again with its mark', () async {
    final jpeg = await leaveSmallCopySending();
    await open(network: const NetworkState(online: true, metered: true));

    await queue.waitForWifi(['up']);
    await until(() => transfers().byId('up')?.status == TransferStatus.queued);
    expect(telegram.deleted, [500]);

    (container.read(networkStatusProvider.notifier) as _Network).set(
      const NetworkState(online: true, metered: false),
    );
    final row = await queue.whenFinished('up');

    expect(row.status, TransferStatus.completed);
    final caption = telegram.captions.single;
    expect(caption.split('\n').first, 'IMG_2.HEIC (small copy)');
    expect(machineLine(caption)['lt'], _original);
    expect((await db.fileById('q'))!.originalSize, _original);
    // The copy was the queue's own, and goes once it is in the drive.
    await until(() => !jpeg.existsSync());
  });

  test(
    'the copy kept offline goes with the small copy, and the original is fetched in its place',
    () async {
      await open();
      final kept = File(p.join(dir.path, 'offline', 'p', 'IMG_1.HEIC'))
        ..createSync(recursive: true)
        ..writeAsBytesSync(List.filled(_small, 2));
      await db.pinOffline('p', isFolder: false);
      await db.saveOfflineCopy('p', kept.path, _small);

      expect((await queue.whenFinished(await replace())).status, TransferStatus.completed);

      expect(await db.offlineCopyOf('p'), isNull);
      expect(kept.existsSync(), isFalse);
      telegram.fetchedPath = (File(
        p.join(dir.path, 'fetched'),
      )..writeAsBytesSync(List.filled(_original, 1))).path;
      await container.read(offlineSyncProvider.notifier).reconcile();
      final save = transfers().items
          .map((t) => t.row)
          .singleWhere((r) => r.saveTo == SaveTarget.offline);
      expect(save.fileId, 'p');
      expect((await queue.whenFinished(save.id)).status, TransferStatus.completed);
      expect((await db.offlineCopyOf('p'))!.size, _original);
    },
  );

  test('a file that grew in place doesn\'t resolve to what was kept of its small copy', () async {
    final opened = File(p.join(dir.path, 'opened.jpg'))..writeAsBytesSync(List.filled(_small, 2));
    await db.saveTransfers([
      TransferRow(
        id: 'dl',
        kind: TransferKind.download,
        status: TransferStatus.completed,
        name: 'IMG_1.HEIC',
        mimeType: 'image/jpeg',
        fileId: 'p',
        resultPath: opened.path,
        ownsSource: false,
        wifiOnly: false,
        totalBytes: _small,
        doneBytes: _small,
        partCount: 1,
        completedParts: 1,
        createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        origin: TransferOrigin.manual,
      ),
    ]);
    await open();
    expect(await queue.localPathIfAvailable((await repository.fileById('p'))!), opened.path);

    expect((await queue.whenFinished(await replace())).status, TransferStatus.completed);
    final grown = (await repository.fileById('p'))!;
    expect(grown.size, _original);
    expect(await queue.localPathIfAvailable(grown), isNull);

    // A copy kept offline from the small copy, on another phone or by a
    // save that was still going, is stale as well.
    final kept = File(p.join(dir.path, 'offline', 'p', 'IMG_1.HEIC'))
      ..createSync(recursive: true)
      ..writeAsBytesSync(List.filled(_small, 2));
    await db.saveOfflineCopy('p', kept.path, _small);
    expect(await queue.localPathIfAvailable(grown), isNull);
  });

  test('the small copy indexed again doesn\'t pass for its original', () async {
    // On mobile data, so the original waits for Wi-Fi in the queue.
    await open(network: const NetworkState(online: true, metered: true));
    final id = await replace(wifiOnly: true);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(transfers().byId(id)?.status, TransferStatus.queued);

    // Starred again from another phone: the small copy is indexed again.
    await repository.ingest(telegram.messages[7]!);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(transfers().byId(id)?.status, TransferStatus.queued);

    // TDLib finished an edit an earlier run asked for: the original is in.
    final original = ManifestCodec.encodeFile(
      ManifestCodec.decodeFile(smallCaption)!.copyWith(clearOriginalSize: true),
    );
    final ended = queue.whenFinished(id);
    await repository.ingest(
      channelMessage(
        7,
        td.MessageDocument(
          document: td.Document(
            fileName: 'IMG_1.HEIC',
            mimeType: 'image/heic',
            document: tdFile(9, size: _original),
          ),
          caption: td.FormattedText(
            text: original.text.replaceFirst('"s":$_small', '"s":$_original'),
            entities: const [],
          ),
        ),
      ),
    );
    expect((await ended).status, TransferStatus.completed);
  });
}
