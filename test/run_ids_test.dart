import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:telegrive/core/files/file_kind.dart';
import 'package:telegrive/features/drive/data/drive_repository.dart';
import 'package:telegrive/features/drive/data/drive_session.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';
import 'package:telegrive/infrastructure/telegram/telegram_client.dart';
import 'package:telegrive/infrastructure/telegram/telegram_exception.dart';

import 'support/fake_telegram.dart';

/// TDLib's file ids last one run, so the id the index stored for a part may
/// name nothing, or another file, in this one. Telegram here keeps what it
/// is asked, answers a file lookup for any id except those in [forgotten],
/// and hands messages back from the channel.
class _Telegram extends FakeTelegram {
  final requests = <td.TdFunction>[];
  final Set<int> forgotten = {};

  Iterable<T> asked<T extends td.TdFunction>() => requests.whereType<T>();

  @override
  Future<td.TdObject?> answer(td.TdFunction function) async {
    requests.add(function);
    switch (function) {
      case td.GetFile(:final fileId):
        if (forgotten.contains(fileId)) {
          throw const TelegramException(400, 'Invalid file identifier');
        }
        return tdFile(fileId);
      default:
        return null;
    }
  }
}

void main() {
  late AppDatabase db;
  late _Telegram telegram;
  late DriveRepository repository;

  /// The index's record of file `report`, whose one part is in message 5
  /// and which an earlier run of TDLib knew as file 7.
  const stored = PartRow(fileId: 'report', partIndex: 0, messageId: 5, tdFileId: 7, size: 10);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    telegram = _Telegram();
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        telegramClientProvider.overrideWithValue(telegram),
        driveSessionProvider.overrideWith(TestSession.new),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    final now = DateTime(2026, 10, 5);
    await db.upsertFilePart(
      DriveFilesCompanion.insert(
        id: 'report',
        name: 'report.jpg',
        mimeType: 'image/jpeg',
        kind: FileKind.image,
        size: 10,
        createdAt: now,
        modifiedAt: now,
        thumbnailFileId: const Value(11),
        partCount: const Value(1),
      ),
      FilePartsCompanion.insert(
        fileId: 'report',
        partIndex: 0,
        messageId: stored.messageId,
        tdFileId: stored.tdFileId,
        size: stored.size,
      ),
    );
    repository = container.read(driveRepositoryProvider);
  });

  group('a part\'s TDLib file', () {
    test('is the one its message holds, and TDLib is asked nothing of the stored id', () async {
      telegram.holdsFile(5, 42);

      final file = await repository.resolveTdFile(stored);

      expect(file.id, 42);
      expect(telegram.asked<td.GetMessage>().map((m) => m.messageId), [5]);
      expect(telegram.asked<td.GetFile>(), isEmpty);
      expect(telegram.requests.whereType<td.DownloadFile>(), isEmpty);
    });

    test('is read from the message once, then asked of TDLib by the id it gave', () async {
      telegram.holdsFile(5, 42);

      await repository.resolveTdFile(stored);
      final again = await repository.resolveTdFile(stored);

      expect(again.id, 42);
      expect(telegram.asked<td.GetMessage>(), hasLength(1));
      expect(telegram.asked<td.GetFile>().map((f) => f.fileId), [42]);
    });

    test('is read from the message again once TDLib has dropped the id it gave', () async {
      telegram.holdsFile(5, 42);
      await repository.resolveTdFile(stored);

      telegram.forgotten.add(42);
      telegram.holdsFile(5, 43);
      final again = await repository.resolveTdFile(stored);

      expect(again.id, 43);
      expect(telegram.asked<td.GetMessage>(), hasLength(2));
    });

    test('is refused as gone when its message holds no file', () async {
      telegram.messages[5] = textMessage(5, 'moved');

      await expectLater(
        repository.resolveTdFile(stored),
        throwsA(
          isA<DriveException>().having(
            (e) => e.message,
            'message',
            'This file is no longer in your drive.',
          ),
        ),
      );
    });
  });

  group('a file\'s thumbnail', () {
    test('is the one the first part\'s message holds, read once', () async {
      telegram.holdsFile(5, 42, thumbnailId: 211);

      expect(await repository.thumbnailTdId('report', stored: 11), 211);
      expect(await repository.thumbnailTdId('report', stored: 11), 211);

      expect(telegram.asked<td.GetMessage>().map((m) => m.messageId), [5]);
    });

    test('is nothing when the message is gone', () async {
      expect(await repository.thumbnailTdId('report', stored: 11), isNull);
      expect(await repository.thumbnailTdId('report', stored: 11), isNull);

      expect(telegram.asked<td.GetMessage>(), hasLength(1));
    });

    test('is its own id for a file the index doesn\'t hold', () async {
      expect(await repository.thumbnailTdId('offered', stored: 77), 77);

      expect(telegram.asked<td.GetMessage>(), isEmpty);
    });
  });
}
