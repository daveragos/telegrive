import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:telegrive/features/drive/data/drive_repository.dart';
import 'package:telegrive/features/drive/data/drive_session.dart';
import 'package:telegrive/features/drive/domain/drive_models.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';
import 'package:telegrive/infrastructure/telegram/telegram_client.dart';

import 'support/fake_telegram.dart';

/// An Undo applies the opposite change to the file as the index holds it
/// now. These check why: the repository passes over a file whose folder,
/// star or name already matches the one asked for, and the file the screen
/// held before the change still shows the old values.
void main() {
  late AppDatabase db;
  late FakeTelegram telegram;
  late ProviderContainer container;
  late DriveRepository repository;

  Future<void> receive(td.Message message) async {
    telegram.messages[message.id] = message;
    await repository.ingest(message);
  }

  Future<DriveFile> file() async => (await repository.fileById('a'))!;
  Future<DriveFolder> folder() async => (await repository.folderById('sub'))!;
  String caption() => (telegram.messages[10]!.content as td.MessageDocument).caption.text;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    telegram = FakeTelegram();
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        telegramClientProvider.overrideWithValue(telegram),
        driveSessionProvider.overrideWith(TestSession.new),
      ],
    );
    repository = container.read(driveRepositoryProvider);
    await receive(textMessage(1, '📁 Work\ntgrf1:{"id":"work","n":"Work","ct":1700000000000}'));
    await receive(textMessage(2, '📁 Home\ntgrf1:{"id":"home","n":"Home","ct":1700000000000}'));
    await receive(
      textMessage(3, '📁 Sub\ntgrf1:{"id":"sub","n":"Sub","p":"work","ct":1700000000000}'),
    );
    await receive(
      documentMessage(
        10,
        'Thesis final.docx\ntgr1:{"id":"a","n":"Thesis final.docx","f":"work",'
        '"m":"application/msword","s":9,"ct":1700000000000}',
        fileName: 'Thesis final.docx',
        mimeType: 'application/msword',
      ),
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('a move is undone from the file as it is now, not as it was', () async {
    final before = await file();
    await repository.moveFiles([before], 'home');
    expect((await file()).folderId, 'home');

    // The file in hand still says Work, so moving it to Work looks like no
    // change at all.
    await repository.moveFiles([before], before.folderId);
    expect((await file()).folderId, 'home');

    await repository.moveFiles([await file()], before.folderId);
    expect((await file()).folderId, 'work');
    expect(caption(), contains('"f":"work"'));
  });

  test('a star is undone the same way', () async {
    final before = await file();
    await repository.setStarred([before], starred: true);
    expect((await file()).starred, isTrue);

    await repository.setStarred([before], starred: before.starred);
    expect((await file()).starred, isTrue);

    await repository.setStarred([await file()], starred: before.starred);
    expect((await file()).starred, isFalse);
    expect(caption(), isNot(contains('"st"')));
  });

  test('a rename is undone the same way', () async {
    final before = await file();
    await repository.renameFile(before, 'Thesis finall.docx');
    expect((await file()).name, 'Thesis finall.docx');

    await repository.renameFile(before, before.name);
    expect((await file()).name, 'Thesis finall.docx');

    await repository.renameFile(await file(), before.name);
    expect((await file()).name, 'Thesis final.docx');
  });

  test('a folder move is undone from the folder as it is now', () async {
    final before = await folder();
    await repository.moveFolder(before, 'home');
    expect((await folder()).parentId, 'home');

    await repository.moveFolder(before, before.parentId);
    expect((await folder()).parentId, 'home');

    await repository.moveFolder(await folder(), before.parentId);
    expect((await folder()).parentId, 'work');
  });

  test('moving to Trash is undone by restoring', () async {
    await repository.trash(files: [await file()]);
    expect((await file()).trashedAt, isNotNull);

    await repository.restore(files: [await file()]);
    expect((await file()).trashedAt, isNull);
    expect((await file()).folderId, 'work');
  });
}
