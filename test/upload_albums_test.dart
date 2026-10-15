import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:path/path.dart' as p;
import 'package:telegrive/features/drive/data/drive_session.dart';
import 'package:telegrive/features/drive/domain/manifest.dart';
import 'package:telegrive/features/transfers/data/transfer_queue.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';
import 'package:telegrive/infrastructure/storage/device_profile.dart';
import 'package:telegrive/infrastructure/telegram/telegram_client.dart';

import 'support/fake_telegram.dart';

/// Delivers every document sent to it, the way TDLib does: a pending
/// message at once and the delivered one as an update a moment later, and
/// keeps each caption under the file's name.
class _UploadTelegram extends FakeTelegram {
  final _updates = StreamController<td.TdObject>.broadcast();

  /// The caption each file went up with, by file name.
  final Map<String, String> captions = {};

  @override
  Stream<td.TdObject> get updates => _updates.stream;

  @override
  Future<td.TdObject?> answer(td.TdFunction function) async {
    switch (function) {
      case td.SendMessage(
        inputMessageContent: td.InputMessageDocument(
          document: td.InputFileLocal(:final path),
          :final caption?,
        ),
      ):
        final name = p.basename(path);
        captions[name] = caption.text;
        final pendingId = nextId++;
        final delivered = documentMessage(
          nextId++,
          caption.text,
          fileName: name,
        );
        messages[delivered.id] = delivered;
        Timer.run(
          () => _updates.add(
            td.UpdateMessageSendSucceeded(
              message: delivered,
              oldMessageId: pendingId,
            ),
          ),
        );
        return documentMessage(
          pendingId,
          caption.text,
          fileName: name,
        ).copyWith(
          sendingState: const td.MessageSendingStatePending(sendingId: 0),
        );
      default:
        return null;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late AppDatabase db;
  late _UploadTelegram telegram;
  late TransferQueue queue;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('telegrive_albums');
    db = AppDatabase(NativeDatabase.memory());
    telegram = _UploadTelegram();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => dir.path,
        );
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        telegramClientProvider.overrideWithValue(telegram),
        driveSessionProvider.overrideWith(TestSession.new),
        saveMemoryProvider.overrideWithBuild((ref, notifier) => false),
      ],
    );
    addTearDown(container.dispose);
    var loaded = false;
    container.listen<TransfersState>(
      transferQueueProvider,
      (_, _) => loaded = true,
    );
    container.read(transferQueueProvider);
    for (var i = 0; i < 200 && !loaded; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    queue = container.read(transferQueueProvider.notifier);
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await db.close();
    await dir.delete(recursive: true);
  });

  Future<String> write(String name) async =>
      (File(p.join(dir.path, name))..writeAsStringSync('0123456789')).path;

  test('albums, a star and the time taken go up in the first caption', () async {
    final taken = DateTime(2019, 6, 15, 14, 25);
    final [id] = await queue.enqueueUploads([
      UploadRequest(
        name: 'IMG_1.jpg',
        path: await write('IMG_1.jpg'),
        origin: TransferOrigin.takeout,
        takenAt: taken,
        albumIds: const ['a1b2c3d4e5f6', 'f6e5d4c3b2a1'],
        starred: true,
      ),
    ]);
    final finished = await queue.whenFinished(id);
    expect(finished.status, TransferStatus.completed);
    final manifest = ManifestCodec.decodeFile(telegram.captions['IMG_1.jpg']!)!;
    expect(manifest.albums, ['a1b2c3d4e5f6', 'f6e5d4c3b2a1']);
    expect(manifest.starred, isTrue);
    expect(manifest.takenAt, taken);
    expect(telegram.captions['IMG_1.jpg'], contains('#starred'));
  });

  test('a plain upload goes up in no album and unstarred', () async {
    final [id] = await queue.enqueueUploads([UploadRequest(name: 'notes.txt', path: await write('notes.txt'))]);
    await queue.whenFinished(id);
    final manifest = ManifestCodec.decodeFile(telegram.captions['notes.txt']!)!;
    expect(manifest.albums, isEmpty);
    expect(manifest.starred, isFalse);
  });

  test('asked after an import\'s upload landed and left, the queue still says how it ended', () async {
    final [id] = await queue.enqueueUploads([
      UploadRequest(name: 'IMG_3.jpg', path: await write('IMG_3.jpg'), origin: TransferOrigin.takeout),
    ]);
    for (var i = 0; i < 200 && (await db.allTransfers()).isNotEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(await db.allTransfers(), isEmpty);
    final ended = await queue.whenFinished(id).timeout(const Duration(seconds: 2));
    expect(ended.status, TransferStatus.completed);
  });

  test('an import\'s upload leaves Transfers once it lands, as backup\'s does', () async {
    final [imported] = await queue.enqueueUploads([
      UploadRequest(name: 'IMG_2.jpg', path: await write('IMG_2.jpg'), origin: TransferOrigin.takeout),
    ]);
    final [mine] = await queue.enqueueUploads([UploadRequest(name: 'mine.txt', path: await write('mine.txt'))]);
    await queue.whenFinished(imported);
    await queue.whenFinished(mine);
    expect((await db.allTransfers()).map((t) => t.id), [mine]);
  });
}
