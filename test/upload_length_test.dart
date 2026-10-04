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
    dir = await Directory.systemTemp.createTemp('telegrive_length');
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

  /// Uploads a file called [name] with [request]'s other fields and returns
  /// the manifest its caption carried.
  Future<FileManifest> upload(String name, {int? durationSeconds}) async {
    final source = File(p.join(dir.path, name))
      ..writeAsStringSync('0123456789');
    final [id] = await queue.enqueueUploads([
      UploadRequest(
        name: name,
        path: source.path,
        durationSeconds: durationSeconds,
      ),
    ]);
    final finished = await queue.whenFinished(id);
    expect(finished.status, TransferStatus.completed);
    expect(finished.durationSeconds, durationSeconds);
    return ManifestCodec.decodeFile(telegram.captions[name]!)!;
  }

  test('a length the caller knows goes up in the caption', () async {
    final manifest = await upload('clip.mp4', durationSeconds: 84);
    expect(manifest.durationSeconds, 84);
    expect(telegram.captions['clip.mp4'], contains('"du":84'));
  });

  test('a file whose length nobody knows carries none', () async {
    // Off Android the file isn't asked, so the caption says nothing.
    expect((await upload('clip.mp4')).durationSeconds, isNull);
    expect(telegram.captions['clip.mp4'], isNot(contains('"du"')));
    expect((await upload('notes.txt')).durationSeconds, isNull);
  });
}
