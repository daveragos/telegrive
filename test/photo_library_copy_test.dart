import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:path/path.dart' as p;
import 'package:telegrive/features/drive/data/drive_session.dart';
import 'package:telegrive/features/transfers/data/leftovers.dart';
import 'package:telegrive/features/transfers/data/transfer_queue.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';
import 'package:telegrive/infrastructure/storage/app_dirs.dart';
import 'package:telegrive/infrastructure/storage/device_profile.dart';
import 'package:telegrive/infrastructure/telegram/telegram_client.dart';

import 'support/fake_telegram.dart';

/// Delivers every document sent to it, the way TDLib does, and keeps the
/// path each was sent from, in order.
class _UploadTelegram extends FakeTelegram {
  final _updates = StreamController<td.TdObject>.broadcast();
  final List<String> paths = [];

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
        paths.add(path);
        final pendingId = nextId++;
        final delivered = documentMessage(nextId++, caption.text, fileName: p.basename(path));
        messages[delivered.id] = delivered;
        Timer.run(
          () => _updates.add(td.UpdateMessageSendSucceeded(message: delivered, oldMessageId: pendingId)),
        );
        return documentMessage(pendingId, caption.text, fileName: p.basename(path))
            .copyWith(sendingState: const td.MessageSendingStatePending(sendingId: 0));
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

  /// The app's temporary folder, as on an iPhone.
  late String tmp;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('telegrive_library_copy');
    tmp = p.join(dir.path, 'tmp');
    db = AppDatabase(NativeDatabase.memory());
    telegram = _UploadTelegram();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => dir.path,
    );
    CopyFolders.debugFolders = CopyFolders(cache: (await scratchDirectory()).path, iosTemp: tmp);
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        telegramClientProvider.overrideWithValue(telegram),
        driveSessionProvider.overrideWith(TestSession.new),
        saveMemoryProvider.overrideWithBuild((ref, notifier) => false),
      ],
    );
    addTearDown(container.dispose);
    container.read(transferQueueProvider);
    queue = container.read(transferQueueProvider.notifier);
    await queue.loaded;
  });

  tearDown(() async {
    CopyFolders.debugFolders = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    await db.close();
    await dir.delete(recursive: true);
  });

  /// A copy of [name] the app owns at [path] under [tmp], sent up, with the
  /// path TDLib was given.
  Future<String> send(String path, String name) async {
    final copy = File(p.join(tmp, path))
      ..createSync(recursive: true)
      ..writeAsStringSync('0123456789');
    final [id] = await queue.enqueueUploads([
      UploadRequest(name: name, path: copy.path, ownsSource: true),
    ]);
    final finished = await queue.whenFinished(id).timeout(const Duration(seconds: 5));
    expect(finished.status, TransferStatus.completed);
    return telegram.paths.last;
  }

  test('a copy the photo library made goes from a path of its own, a new one each time', () async {
    const library = '.video/2DAA_L0_001_1795376576.291953_o_IMG_0404.MOV';
    final staging = p.join((await scratchDirectory()).path, 'telegrive-staging');

    final first = await send(library, 'IMG_0404.MOV');
    // The library makes the copy again at the same path, as for a retry.
    final second = await send(library, 'IMG_0404.MOV');

    expect(p.isWithin(staging, first), isTrue);
    expect(p.isWithin(staging, second), isTrue);
    expect(first, isNot(second));
    expect(p.basename(first), 'IMG_0404.MOV');
    // Moved, not copied: nothing is left at the library's path.
    expect(File(p.join(tmp, library)).existsSync(), isFalse);
  });

  test('a copy the file picker made goes from where it is', () async {
    final sent = await send('9F2C/report.pdf', 'report.pdf');

    expect(sent, p.join(tmp, '9F2C', 'report.pdf'));
  });

  test('the photo library\'s copies are told from the rest, written with /private or not', () {
    const container = '/var/mobile/Containers/Data/Application/AB12';
    const folders = CopyFolders(cache: '$container/Library/Caches', iosTemp: '$container/tmp');

    expect(folders.isPhotoLibraryCopy('$container/tmp/.image/A_o_IMG_0001.HEIC'), isTrue);
    expect(folders.isPhotoLibraryCopy('/private$container/tmp/.video/C_o_IMG_0003.MOV'), isTrue);
    expect(folders.isPhotoLibraryCopy('$container/tmp/9F2C/report.pdf'), isFalse);
    expect(folders.isPhotoLibraryCopy('$container/Library/Caches/file_picker/a.txt'), isFalse);
    const android = CopyFolders(cache: '/data/user/0/app/cache');
    expect(android.isPhotoLibraryCopy('/data/user/0/app/cache/.image/a.jpg'), isFalse);
  });
}
