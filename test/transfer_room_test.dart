import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:path/path.dart' as p;
import 'package:telegrive/core/files/file_kind.dart';
import 'package:telegrive/features/drive/data/drive_repository.dart';
import 'package:telegrive/features/drive/data/drive_session.dart';
import 'package:telegrive/features/transfers/data/transfer_queue.dart';
import 'package:telegrive/features/transfers/domain/transfer_wait.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';
import 'package:telegrive/infrastructure/storage/device_profile.dart';
import 'package:telegrive/infrastructure/storage/device_storage.dart';
import 'package:telegrive/infrastructure/telegram/telegram_client.dart';

import 'support/fake_telegram.dart';

const _mb = 1 << 20;

/// A phone whose free space a test sets, and whose Download folder takes
/// any file where it is.
class _Storage extends DeviceStorage {
  int? free = 10 << 30;

  @override
  Future<int?> freeBytes() async => free;

  @override
  Future<String> saveFile(
    String source, {
    required List<String> folders,
    required String name,
    required String mimeType,
  }) async => source;
}

/// Downloads of TDLib file 7 that finish at once from [path], and sends
/// that are only counted.
class _Telegram extends FakeTelegram {
  _Telegram(this.path);

  final String path;
  int downloads = 0;
  int sends = 0;

  @override
  Future<td.TdObject?> answer(td.TdFunction function) async {
    switch (function) {
      case td.GetFile():
        return tdFile(7);
      case td.DownloadFile():
        downloads++;
        return tdFile(7, path: path, downloaded: true);
      case td.SendMessage(inputMessageContent: td.InputMessageDocument()):
        sends++;
        throw StateError('Nothing should be sent');
      default:
        return null;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late AppDatabase db;
  late _Storage storage;
  final now = DateTime(2026, 10, 4);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('telegrive_room');
    db = AppDatabase(NativeDatabase.memory());
    storage = _Storage();
    // The app's cache, support and documents folders all live here.
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

  /// The queue for [telegram], once it has read its saved rows.
  Future<(ProviderContainer, TransferQueue)> openQueue(FakeTelegram telegram) async {
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        telegramClientProvider.overrideWithValue(telegram),
        driveSessionProvider.overrideWith(TestSession.new),
        deviceStorageProvider.overrideWithValue(storage),
        saveMemoryProvider.overrideWithBuild((ref, notifier) => false),
      ],
    );
    addTearDown(container.dispose);
    var loaded = false;
    container.listen<TransfersState>(transferQueueProvider, (_, _) => loaded = true);
    container.read(transferQueueProvider);
    for (var i = 0; i < 200 && !loaded; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    return (container, container.read(transferQueueProvider.notifier));
  }

  Future<void> until(bool Function() condition) async {
    for (var i = 0; i < 200 && !condition(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(condition(), isTrue);
  }

  /// An upload of [name], [total] bytes long, from [source], kept in the
  /// database as it would be after the app stopped.
  TransferRow upload(
    String name,
    TransferStatus status, {
    required String source,
    required int total,
    bool ownsSource = true,
  }) => TransferRow(
    id: name,
    kind: TransferKind.upload,
    status: status,
    name: name,
    mimeType: 'video/mp4',
    fileId: 'file-$name',
    sourcePath: source,
    ownsSource: ownsSource,
    wifiOnly: false,
    origin: TransferOrigin.manual,
    totalBytes: total,
    doneBytes: 0,
    partCount: 1,
    completedParts: 0,
    createdAt: now,
    finishedAt: status.isFinished ? now : null,
    error: status == TransferStatus.failed ? 'Lost the connection to Telegram.' : null,
  );

  /// A download of the two parts of [fileId], kept in the database as it
  /// would be after the app stopped, with the first already joined.
  TransferRow download(String fileId, TransferStatus status) => TransferRow(
    id: fileId,
    kind: TransferKind.download,
    status: status,
    name: '$fileId.mkv',
    mimeType: 'video/x-matroska',
    fileId: fileId,
    ownsSource: false,
    wifiOnly: false,
    origin: TransferOrigin.manual,
    totalBytes: 40,
    doneBytes: 20,
    partCount: 2,
    completedParts: 1,
    createdAt: now,
    finishedAt: status.isFinished ? now : null,
  );

  test('a save the phone has no room for waits, sends nothing, and starts once '
      'there is room', () async {
    // Two parts of 600 MB, each fetched here as a few bytes.
    final fetched = File(p.join(dir.path, 'part.bin'))..writeAsStringSync('0123456789');
    final telegram = _Telegram(fetched.path);
    for (var index = 0; index < 2; index++) {
      telegram.holdsFile(1 + index, 7, size: 600 * _mb);
      await db.upsertFilePart(
        DriveFilesCompanion.insert(
          id: 'movie',
          name: 'movie.mp4',
          mimeType: 'video/mp4',
          kind: FileKind.video,
          size: 1200 * _mb,
          createdAt: now,
          modifiedAt: now,
          partCount: const Value(2),
        ),
        FilePartsCompanion.insert(
          fileId: 'movie',
          partIndex: index,
          messageId: 1 + index,
          tdFileId: 7,
          size: 600 * _mb,
        ),
      );
    }
    storage.free = 100 * _mb;
    final (container, queue) = await openQueue(telegram);
    TransfersState state() => container.read(transferQueueProvider);

    final file = (await container.read(driveRepositoryProvider).fileById('movie'))!;
    await queue.enqueueSaves([SaveRequest(file, target: SaveTarget.files)]);
    await until(() => state().items.single.wait is WaitingForRoom);

    final item = state().items.single;
    final wait = item.wait! as WaitingForRoom;
    // The file, its largest part beside the stitched copy, the copy into
    // Download, and the margin.
    expect(wait.needed, (1200 + 600 + 1200 + 64) * _mb);
    expect(wait.free, 100 * _mb);
    expect(wait.sentence, 'Needs 3.0 GB free · 100 MB free on this phone');
    expect(item.status, TransferStatus.queued);
    expect(state().active, isEmpty);
    expect(state().waitingForRoom, hasLength(1));
    expect(telegram.downloads, 0);

    // Still too little: it keeps waiting, and says what is free now.
    storage.free = 500 * _mb;
    await queue.recheckRoom();
    expect((state().items.single.wait! as WaitingForRoom).free, 500 * _mb);
    expect(telegram.downloads, 0);

    storage.free = 10 << 30;
    await queue.recheckRoom();
    final finished = await queue.whenFinished(item.id);

    expect(finished.status, TransferStatus.completed);
    expect(telegram.downloads, 2);
    expect(state().items.single.wait, isNull);
  });

  test('a copy shorter than its row says is never sent', () async {
    final copy = File(p.join(dir.path, 'telegrive-staging', 'cut', 'Wedding.mp4'))
      ..createSync(recursive: true)
      ..writeAsStringSync('0123456789');
    await db.saveTransfers([
      upload('Wedding.mp4', TransferStatus.queued, source: copy.path, total: 20),
    ]);
    final telegram = _Telegram('');
    final (_, queue) = await openQueue(telegram);

    final finished = await queue.whenFinished('Wedding.mp4');

    expect(finished.status, TransferStatus.failed);
    expect(finished.error, 'The copy of Wedding.mp4 was interrupted. Share or pick it again.');
    expect(telegram.sends, 0);
  });

  test('an original changed since it was added is never sent', () async {
    final original = File(p.join(dir.path, 'DCIM', 'Clip.mp4'))
      ..createSync(recursive: true)
      ..writeAsStringSync('0123456789');
    await db.saveTransfers([
      upload('Clip.mp4', TransferStatus.queued, source: original.path, total: 20, ownsSource: false),
    ]);
    final telegram = _Telegram('');
    final (_, queue) = await openQueue(telegram);

    final finished = await queue.whenFinished('Clip.mp4');

    expect(finished.error, 'Clip.mp4 has changed since it was added. Add it again.');
    expect(telegram.sends, 0);
    expect(original.existsSync(), isTrue);
  });

  test('a copy the app was stopped in the middle of fails, and its part is deleted', () async {
    final staged = p.join(dir.path, 'telegrive-staging', 'half', 'Wedding.mp4');
    final partial = File('$staged.part')
      ..createSync(recursive: true)
      ..writeAsStringSync('01234');
    await db.saveTransfers([
      upload('Wedding.mp4', TransferStatus.running, source: staged, total: 20),
    ]);
    final telegram = _Telegram('');
    final (container, _) = await openQueue(telegram);

    final item = container.read(transferQueueProvider).items.single;
    expect(item.status, TransferStatus.failed);
    expect(item.row.error, 'The copy of Wedding.mp4 was interrupted. Share or pick it again.');
    expect(partial.existsSync(), isFalse);
    expect(telegram.sends, 0);
  });

  test('removing a failed upload deletes the copy the app made, and its folder', () async {
    final copy = File(p.join(dir.path, 'file_picker', '1712345', 'notes.txt'))
      ..createSync(recursive: true)
      ..writeAsStringSync('0123456789');
    final original = File(p.join(dir.path, 'DCIM', 'clip.mp4'))
      ..createSync(recursive: true)
      ..writeAsStringSync('0123456789');
    await db.saveTransfers([
      upload('notes.txt', TransferStatus.failed, source: copy.path, total: 10),
      upload('clip.mp4', TransferStatus.failed, source: original.path, total: 10, ownsSource: false),
    ]);
    final (container, queue) = await openQueue(_Telegram(''));

    await queue.remove('notes.txt');
    await queue.remove('clip.mp4');

    expect(copy.existsSync(), isFalse);
    expect(copy.parent.existsSync(), isFalse);
    expect(Directory(p.join(dir.path, 'file_picker')).existsSync(), isTrue);
    expect(original.existsSync(), isTrue);
    expect(container.read(transferQueueProvider).items, isEmpty);
  });

  test('cancelling a paused upload deletes the copy the app made, its folder and its parts', () async {
    final copy = File(p.join(dir.path, 'file_picker', '1712345', 'notes.txt'))
      ..createSync(recursive: true)
      ..writeAsStringSync('0123456789');
    final original = File(p.join(dir.path, 'DCIM', 'clip.mp4'))
      ..createSync(recursive: true)
      ..writeAsStringSync('0123456789');
    final part = File(p.join(dir.path, 'telegrive-parts', 'movie.mkv', 'movie.mkv.001'))
      ..createSync(recursive: true)
      ..writeAsStringSync('0123456789');
    await db.saveTransfers([
      upload('notes.txt', TransferStatus.paused, source: copy.path, total: 10),
      upload('clip.mp4', TransferStatus.paused, source: original.path, total: 10, ownsSource: false),
      upload(
        'movie.mkv',
        TransferStatus.paused,
        source: original.path,
        total: 30,
        ownsSource: false,
      ).copyWith(partCount: 3),
    ]);
    final (container, queue) = await openQueue(_Telegram(''));

    await queue.cancel('notes.txt');
    await queue.cancel('clip.mp4');
    await queue.cancel('movie.mkv');

    expect(copy.existsSync(), isFalse);
    expect(copy.parent.existsSync(), isFalse);
    expect(Directory(p.join(dir.path, 'file_picker')).existsSync(), isTrue);
    expect(original.existsSync(), isTrue);
    expect(part.parent.existsSync(), isFalse);
    expect(
      container.read(transferQueueProvider).items.map((t) => t.status),
      everyElement(TransferStatus.cancelled),
    );
  });

  test('cancelling an upload while its copy is made leaves no copy behind', () async {
    final release = Completer<void>();
    final telegram = _Telegram('');
    final (container, queue) = await openQueue(telegram);
    TransfersState state() => container.read(transferQueueProvider);

    final [id] = await queue.enqueueUploads([
      UploadRequest(
        name: 'Wedding.mp4',
        size: 10,
        openRead: () async* {
          await release.future;
          yield [for (var i = 0; i < 10; i++) i];
        },
      ),
    ]);
    await until(() => state().items.single.preparing);
    await queue.cancel(id);
    release.complete();
    await until(() => !state().items.single.preparing);

    final staging = Directory(p.join(dir.path, 'telegrive-staging'));
    expect(staging.listSync(recursive: true).whereType<File>(), isEmpty);
    expect(state().items.single.status, TransferStatus.cancelled);
    expect(telegram.sends, 0);
  });

  test('joined split files go once they are old, unless a download is waiting for them', () async {
    File joined(String fileId, int bytes) =>
        File(p.join(dir.path, 'downloads', fileId, '$fileId.mkv'))
          ..createSync(recursive: true)
          ..writeAsBytesSync(List.filled(bytes, 1));
    final opened = joined('opened', 30);
    final failed = joined('failed', 20);
    final paused = joined('paused', 40);
    final recent = joined('recent', 50);
    await db.saveTransfers([
      download('opened', TransferStatus.completed),
      download('failed', TransferStatus.failed),
      download('paused', TransferStatus.paused),
    ]);
    final (_, queue) = await openQueue(_Telegram(''));

    // Three weeks on, with one joined only two days before.
    final later = DateTime.now().add(const Duration(days: 21));
    recent.setLastModifiedSync(later.subtract(const Duration(days: 2)));
    final freed = await queue.clearOldDownloads(
      olderThan: const Duration(days: 14),
      now: later,
    );

    expect(freed, 50);
    expect(opened.existsSync(), isFalse);
    expect(failed.existsSync(), isFalse);
    expect(paused.existsSync(), isTrue);
    expect(recent.existsSync(), isTrue);
  });
}
