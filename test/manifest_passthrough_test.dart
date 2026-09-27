import 'dart:convert';

import 'package:drift/drift.dart' show Value;
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

void main() {
  late AppDatabase db;
  late FakeTelegram telegram;
  late DriveRepository repository;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    telegram = FakeTelegram();
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        telegramClientProvider.overrideWithValue(telegram),
        driveSessionProvider.overrideWith(TestSession.new),
      ],
    );
    repository = container.read(driveRepositoryProvider);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
  });

  Future<void> receive(td.Message message) async {
    telegram.messages[message.id] = message;
    await repository.ingest(message);
  }

  Map<String, dynamic> machineLine(td.Message message) {
    final text = switch (message.content) {
      td.MessageDocument(:final caption) => caption.text,
      td.MessageText(:final text) => text.text,
      _ => '',
    };
    return jsonDecode(text.substring(text.indexOf('{'))) as Map<String, dynamic>;
  }

  test('a key a newer version wrote survives a rename, star and trash here', () async {
    await receive(
      documentMessage(
        10,
        'clip.mp4\ntgr1:{"id":"v","n":"clip.mp4","f":"docs","m":"video/mp4",'
        '"s":9,"ct":1700000000000,"mt":1700000000000,"du":84,"lt":123456}',
      ),
    );
    final row = (await db.fileById('v'))!;
    expect(jsonDecode(row.manifestExtra!), {'du': 84, 'lt': 123456});

    await repository.renameFile(DriveFile.fromRow(row), 'trip.mp4');
    var sent = machineLine(telegram.messages[10]!);
    expect(sent['n'], 'trip.mp4');
    expect(sent['du'], 84);
    expect(sent['lt'], 123456);

    var file = (await repository.fileById('v'))!;
    await repository.setStarred([file], starred: true);
    file = (await repository.fileById('v'))!;
    await repository.trash(files: [file]);
    sent = machineLine(telegram.messages[10]!);
    expect(sent['st'], 1);
    expect(sent['tr'], isA<int>());
    expect(sent['du'], 84);
    expect(sent['lt'], 123456);
    expect(jsonDecode((await db.fileById('v'))!.manifestExtra!), {'du': 84, 'lt': 123456});
  });

  test('a known key wins over a stale extra of the same name', () async {
    await receive(
      documentMessage(
        10,
        'clip.mp4\ntgr1:{"id":"v","n":"clip.mp4","s":9,"ct":1700000000000,"du":84}',
      ),
    );
    await db.updateFile(
      'v',
      const DriveFilesCompanion(
        manifestExtra: Value('{"n":"stale.mp4","du":84}'),
      ),
    );

    await repository.setStarred([(await repository.fileById('v'))!], starred: true);
    final sent = machineLine(telegram.messages[10]!);
    expect(sent['n'], 'clip.mp4');
    expect(sent['st'], 1);
    expect(sent['du'], 84);
    expect(jsonDecode((await db.fileById('v'))!.manifestExtra!), {'du': 84});
  });

  test('a folder key a newer version wrote survives a rename and move here', () async {
    await receive(
      textMessage(
        1,
        '📁 Invoices\ntgrf1:{"id":"inv","n":"Invoices","ct":1700000000000,'
        '"mt":1700000000000,"st":1}',
      ),
    );
    await receive(
      textMessage(2, '📁 Work\ntgrf1:{"id":"work","n":"Work","ct":1700000000000}'),
    );
    expect(jsonDecode((await db.folderById('inv'))!.manifestExtra!), {'st': 1});
    expect((await db.folderById('work'))!.manifestExtra, isNull);

    Future<DriveFolder> invoices() async =>
        DriveFolder.fromRow((await db.folderById('inv'))!);
    await repository.renameFolder(await invoices(), 'Bills');
    await repository.moveFolder(await invoices(), 'work');

    final sent = machineLine(telegram.messages[1]!);
    expect(sent['n'], 'Bills');
    expect(sent['p'], 'work');
    expect(sent['st'], 1);
    expect(jsonDecode((await db.folderById('inv'))!.manifestExtra!), {'st': 1});
  });

  test('an edit without extras clears them from the index', () async {
    await receive(
      documentMessage(10, 'a.pdf\ntgr1:{"id":"a","n":"a.pdf","s":9,"rb":"b"}'),
    );
    expect((await db.fileById('a'))!.manifestExtra, isNotNull);
    await receive(documentMessage(10, 'a.pdf\ntgr1:{"id":"a","n":"a.pdf","s":9}'));
    expect((await db.fileById('a'))!.manifestExtra, isNull);
  });
}
