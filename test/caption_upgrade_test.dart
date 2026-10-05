import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:telegrive/features/drive/data/drive_repository.dart';
import 'package:telegrive/features/drive/data/drive_session.dart';
import 'package:telegrive/features/drive/data/telegram_wait.dart';
import 'package:telegrive/features/drive/domain/manifest.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';
import 'package:telegrive/infrastructure/telegram/telegram_client.dart';

import 'support/fake_telegram.dart';

/// Telegram that counts the edits it is asked for.
class _Telegram extends FakeTelegram {
  int edits = 0;

  @override
  Future<td.TdObject?> answer(td.TdFunction function) async {
    if (function is td.EditMessageCaption || function is td.EditMessageText) edits++;
    return null;
  }
}

void main() {
  late AppDatabase db;
  late _Telegram telegram;
  late DriveRepository repository;

  setUp(() async {
    TelegramWait.unit = const Duration(milliseconds: 1);
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
    repository = container.read(driveRepositoryProvider);
  });
  tearDown(() => TelegramWait.unit = const Duration(seconds: 1));

  Future<void> receive(td.Message message) async {
    telegram.messages[message.id] = message;
    await repository.ingest(message);
  }

  String textOf(int id) => switch (telegram.messages[id]!.content) {
    td.MessageDocument(:final caption) => caption.text,
    td.MessageText(:final text) => text.text,
    _ => '',
  };

  /// A drive written by an older version: a folder, an album, a photo in
  /// both, a file split in two with the manifest on both parts, and a
  /// forward nobody has filed.
  Future<void> seedOlderDrive() async {
    await receive(textMessage(1, '📁 Trips\ntgrf1:{"id":"trips","n":"Trips","ct":1700000000000}'));
    await receive(textMessage(2, '🖼 Lalibela\ntgra1:{"id":"lal","n":"Lalibela","ct":1700000000000}'));
    await receive(
      documentMessage(
        10,
        'IMG_1.jpg\ntgr1:{"id":"p","n":"IMG_1.jpg","f":"trips","m":"image/jpeg","s":9,'
        '"ct":1700000000000,"st":1,"al":["lal"]}',
        fileName: 'IMG_1.jpg',
        mimeType: 'image/jpeg',
      ),
    );
    for (final index in [0, 1]) {
      await receive(
        documentMessage(
          20 + index,
          'big.bin.00${index + 1}\ntgr1:{"id":"big","n":"big.bin","f":"trips","s":18,'
          '"ct":1700000000000,"pc":2${index == 0 ? '' : ',"pi":$index'}}',
          fileName: 'big.bin.00${index + 1}',
        ),
      );
    }
    await receive(
      documentMessage(
        30,
        '',
        fileName: 'forwarded.pdf',
        forwardedFrom: const td.MessageOriginHiddenUser(senderName: 'Selam'),
      ),
    );
  }

  test('the older messages are listed, a forward without a caption of the drive\'s is not', () async {
    await seedOlderDrive();

    final older = await repository.olderCaptions();
    expect(
      {for (final c in older) (c.kind, c.id, c.messageId)},
      {
        (OlderCaptionKind.folder, 'trips', 1),
        (OlderCaptionKind.album, 'lal', 2),
        (OlderCaptionKind.file, 'p', 10),
        (OlderCaptionKind.file, 'big', 20),
        (OlderCaptionKind.laterPart, 'big', 21),
      },
    );
  });

  test('each is written again in the current layout, and nothing about the drive changes', () async {
    await seedOlderDrive();
    final before = (await repository.fileById('p'))!;

    for (final caption in await repository.olderCaptions()) {
      await repository.rewriteInCurrentLayout(caption);
    }

    expect(await repository.olderCaptions(), isEmpty);
    expect(textOf(1), contains('\ntgfolder2;'));
    expect(textOf(2), contains('\ntgalbum2;'));
    expect(textOf(10), startsWith('IMG_1.jpg\n#Trips #starred\n'));
    expect(textOf(20), contains('\ntgfile2;'));
    expect(ManifestCodec.decodePart(textOf(21))!.fileId, 'big');
    expect(textOf(30), '', reason: 'the forward is left alone');

    final after = (await repository.fileById('p'))!;
    expect(after.name, before.name);
    expect(after.folderId, 'trips');
    expect(after.starred, isTrue);
    expect(after.modifiedAt, before.modifiedAt);
    expect(await db.albumIdsOf('p'), ['lal']);
    final big = (await repository.fileById('big'))!;
    expect((big.name, big.folderId), ('big.bin', 'trips'));
    expect((await db.fileById('big'))!.partsPresent, 2);
  });

  test('an item with a change waiting is left for that change to write', () async {
    final now = DateTime.now();
    await db.savePendingEdit(
      PendingEditsCompanion.insert(
        target: EditTarget.folder,
        itemId: 'trips',
        patch: '{"n":{"b":"Trips","w":"Travel"}}',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await seedOlderDrive();
    final folder = (await repository.olderCaptions()).firstWhere(
      (c) => c.kind == OlderCaptionKind.folder,
    );

    await repository.rewriteInCurrentLayout(folder);

    expect(telegram.edits, 0);
    expect(textOf(1), contains('tgrf1:'));
  });

  test('a later part of a file whose first part is gone keeps the manifest it carries', () async {
    await receive(
      documentMessage(
        21,
        'big.bin.002\ntgr1:{"id":"big","n":"big.bin","s":18,"ct":1700000000000,"pc":2,"pi":1}',
        fileName: 'big.bin.002',
      ),
    );

    expect(await repository.olderCaptions(), isEmpty);
  });

  test('a message already in the current layout is only noted as such', () async {
    await seedOlderDrive();
    final file = (await repository.olderCaptions()).firstWhere((c) => c.id == 'p');
    await repository.rewriteInCurrentLayout(file);
    final edits = telegram.edits;

    // The index holds the message as older, as an index without layouts does.
    await (db.update(db.fileParts)..where((p) => p.messageId.equals(10)))
        .write(const FilePartsCompanion(captionLayout: Value(CaptionLayouts.older)));
    await repository.rewriteInCurrentLayout(file);

    expect(telegram.edits, edits + 1);
    expect((await repository.olderCaptions()).where((c) => c.id == 'p'), isEmpty);
  });
}
