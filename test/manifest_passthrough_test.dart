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
    return jsonDecode(text.substring(text.indexOf('{')))
        as Map<String, dynamic>;
  }

  test(
    'a key a newer version wrote survives a rename, star and trash here',
    () async {
      // The length is a key this version knows and keeps in its own column;
      // xv is one no version knows yet, and rides along as an extra.
      await receive(
        documentMessage(
          10,
          'clip.mp4\ntgr1:{"id":"v","n":"clip.mp4","f":"docs","m":"video/mp4",'
          '"s":9,"ct":1700000000000,"mt":1700000000000,"du":84,"xv":123456}',
        ),
      );
      final row = (await db.fileById('v'))!;
      expect(row.durationSeconds, 84);
      expect(jsonDecode(row.manifestExtra!), {'xv': 123456});

      await repository.renameFile(DriveFile.fromRow(row), 'trip.mp4');
      var sent = machineLine(telegram.messages[10]!);
      expect(sent['n'], 'trip.mp4');
      expect(sent['du'], 84);
      expect(sent['xv'], 123456);

      var file = (await repository.fileById('v'))!;
      await repository.setStarred([file], starred: true);
      file = (await repository.fileById('v'))!;
      await repository.trash(files: [file]);
      sent = machineLine(telegram.messages[10]!);
      expect(sent['st'], 1);
      expect(sent['tr'], isA<int>());
      expect(sent['du'], 84);
      expect(sent['xv'], 123456);
      final after = (await db.fileById('v'))!;
      expect(after.durationSeconds, 84);
      expect(jsonDecode(after.manifestExtra!), {'xv': 123456});
    },
  );

  test('a small copy stays one through a rename, star and move here', () async {
    await receive(
      documentMessage(
        10,
        'IMG_1.HEIC (small copy)\ntgr1:{"id":"p","n":"IMG_1.HEIC","m":"image/jpeg",'
        '"s":300,"ct":1700000000000,"lt":6100000}',
        fileName: 'IMG_1.HEIC',
        mimeType: 'image/jpeg',
        size: 300,
      ),
    );
    var file = (await repository.fileById('p'))!;
    expect(file.isSmallCopy, isTrue);

    await repository.renameFile(file, 'Lalibela.HEIC');
    file = (await repository.fileById('p'))!;
    await repository.setStarred([file], starred: true);
    file = (await repository.fileById('p'))!;
    await repository.moveFiles([file], 'trip');

    final caption = (telegram.messages[10]!.content as td.MessageDocument).caption.text;
    expect(caption.split('\n').first, 'Lalibela.HEIC (small copy)');
    final sent = machineLine(telegram.messages[10]!);
    expect(sent['lt'], 6100000);
    expect(sent['s'], 300);
    expect(sent['m'], 'image/jpeg');
    expect(sent['st'], 1);
    expect(sent['f'], 'trip');
    file = (await repository.fileById('p'))!;
    expect(file.originalSize, 6100000);
    expect((await db.fileById('p'))!.manifestExtra, isNull);
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
        manifestExtra: Value('{"n":"stale.mp4","du":10,"xv":123456}'),
      ),
    );

    await repository.setStarred([
      (await repository.fileById('v'))!,
    ], starred: true);
    final sent = machineLine(telegram.messages[10]!);
    expect(sent['n'], 'clip.mp4');
    expect(sent['st'], 1);
    expect(sent['du'], 84);
    expect(sent['xv'], 123456);
    expect(jsonDecode((await db.fileById('v'))!.manifestExtra!), {
      'xv': 123456,
    });
  });

  test(
    'a replacement is dropped by restore and never comes back from the extras',
    () async {
      await receive(
        documentMessage(
          10,
          'old.pdf\ntgr1:{"id":"a","n":"old.pdf","s":9,"ct":1700000000000,'
          '"tr":1700000000000,"rb":"b"}',
        ),
      );
      final row = (await db.fileById('a'))!;
      expect(row.replacedBy, 'b');
      expect(row.manifestExtra, isNull);

      await repository.restore(files: [DriveFile.fromRow(row)]);
      final sent = machineLine(telegram.messages[10]!);
      expect(sent.containsKey('tr'), isFalse);
      expect(sent.containsKey('rb'), isFalse);
      expect((await db.fileById('a'))!.replacedBy, isNull);
    },
  );

  test(
    'a folder key a newer version wrote survives a rename and move here',
    () async {
      // The star has its own column; the colour rides along as an extra.
      await receive(
        textMessage(
          1,
          '📁 Invoices\ntgrf1:{"id":"inv","n":"Invoices","ct":1700000000000,'
          '"mt":1700000000000,"st":1,"c":"blue"}',
        ),
      );
      await receive(
        textMessage(
          2,
          '📁 Work\ntgrf1:{"id":"work","n":"Work","ct":1700000000000}',
        ),
      );
      expect((await db.folderById('inv'))!.starred, isTrue);
      expect(jsonDecode((await db.folderById('inv'))!.manifestExtra!), {
        'c': 'blue',
      });
      expect((await db.folderById('work'))!.starred, isFalse);
      expect((await db.folderById('work'))!.manifestExtra, isNull);

      Future<DriveFolder> invoices() async =>
          DriveFolder.fromRow((await db.folderById('inv'))!);
      await repository.renameFolder(await invoices(), 'Bills');
      await repository.moveFolder(await invoices(), 'work');

      final sent = machineLine(telegram.messages[1]!);
      expect(sent['n'], 'Bills');
      expect(sent['p'], 'work');
      expect(sent['st'], 1);
      expect(sent['c'], 'blue');
      final after = (await db.folderById('inv'))!;
      expect(after.starred, isTrue);
      expect(jsonDecode(after.manifestExtra!), {'c': 'blue'});
    },
  );

  test('starring a folder is one text edit that the index then reflects', () async {
    await receive(
      textMessage(
        2,
        '📁 Work\ntgrf1:{"id":"work","n":"Work","ct":1700000000000,"c":"blue"}',
      ),
    );
    Future<DriveFolder> work() async =>
        DriveFolder.fromRow((await db.folderById('work'))!);
    expect((await work()).starred, isFalse);

    await repository.setFolderStarred([await work()], starred: true);
    var sent = machineLine(telegram.messages[2]!);
    expect(sent['st'], 1);
    expect(sent['n'], 'Work');
    expect(sent['c'], 'blue', reason: 'the extras ride along');
    expect((await work()).starred, isTrue);

    // Already starred, so nothing is sent: the text keeps its mt.
    final before = (telegram.messages[2]!.content as td.MessageText).text.text;
    await repository.setFolderStarred([await work()], starred: true);
    expect((telegram.messages[2]!.content as td.MessageText).text.text, before);

    await repository.setFolderStarred([await work()], starred: false);
    sent = machineLine(telegram.messages[2]!);
    expect(sent.containsKey('st'), isFalse);
    expect(sent['c'], 'blue');
    expect((await work()).starred, isFalse);
  });

  test('an edit without extras clears them from the index', () async {
    await receive(
      documentMessage(10, 'a.pdf\ntgr1:{"id":"a","n":"a.pdf","s":9,"xv":5}'),
    );
    expect((await db.fileById('a'))!.manifestExtra, isNotNull);
    await receive(
      documentMessage(10, 'a.pdf\ntgr1:{"id":"a","n":"a.pdf","s":9}'),
    );
    expect((await db.fileById('a'))!.manifestExtra, isNull);
  });
}
