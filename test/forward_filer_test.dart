import 'dart:math' as math;

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegrive/features/drive/data/drive_repository.dart';
import 'package:telegrive/features/drive/data/drive_session.dart';
import 'package:telegrive/features/drive/data/forward_filer.dart';
import 'package:telegrive/features/drive/data/forward_origin.dart';
import 'package:telegrive/features/drive/data/message_indexer.dart';
import 'package:telegrive/features/drive/domain/manifest.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';
import 'package:telegrive/infrastructure/storage/preferences.dart';
import 'package:telegrive/infrastructure/telegram/telegram_client.dart';
import 'package:telegrive/infrastructure/telegram/telegram_exception.dart';

import 'support/fake_telegram.dart';

const _selam = td.MessageOriginHiddenUser(senderName: 'Selam Tesfaye');

ChannelPost _post(
  int id, {
  required int date,
  String? text,
  bool media = false,
  bool manifest = false,
  bool forwarded = false,
  String caption = '',
  int albumId = 0,
}) => (
  id: id,
  date: date,
  text: text,
  media: media,
  manifest: manifest,
  forwarded: forwarded,
  caption: caption,
  albumId: albumId,
);

/// A forwarded file with no manifest, [seconds] after the comment.
ChannelPost _forward(int id, int seconds) =>
    _post(id, date: 1000 + seconds, media: true, forwarded: true);

/// The channel, answering history requests from [messages] the way TDLib
/// does: the messages older than the one asked from, newest first, and
/// every request kept in [requests].
class _Channel extends FakeTelegram {
  final List<td.TdFunction> requests = [];

  /// Message ids whose copy is turned away with a flood wait too long to
  /// sit out.
  final Set<int> refuseCopies = {};

  /// Message ids whose deletion is turned away the same way.
  final Set<int> refuseDeletes = {};

  /// The most messages one history page holds, however many were asked
  /// for, the way TDLib cuts pages short.
  int pageLimit = 100;

  @override
  Future<td.TdObject?> answer(td.TdFunction function) async {
    requests.add(function);
    switch (function) {
      case td.GetChatHistory(:final fromMessageId, :final limit):
        final older = messages.values.where((m) => m.id < fromMessageId).toList()
          ..sort((a, b) => b.id.compareTo(a.id));
        final page = older.take(math.min(limit, pageLimit)).toList();
        return td.Messages(totalCount: older.length, messages: page);
      case td.SendMessage(inputMessageContent: td.InputMessageForwarded(:final messageId))
          when refuseCopies.contains(messageId):
        throw const TelegramException(420, 'FLOOD_WAIT_3600');
      case td.DeleteMessages(:final messageIds) when messageIds.any(refuseDeletes.contains):
        throw const TelegramException(420, 'FLOOD_WAIT_3600');
      default:
        return null;
    }
  }

  List<List<int>> get deleted => [
    for (final request in requests.whereType<td.DeleteMessages>()) request.messageIds,
  ];

  int get copies => requests
      .whereType<td.SendMessage>()
      .where((r) => r.inputMessageContent is td.InputMessageForwarded)
      .length;
}

void main() {
  group('addressFor', () {
    test('the comment right before a burst of forwards addresses all of them', () {
      final comment = _post(20, date: 1000, text: 'Wedding');
      final burst = [_forward(21, 1), _forward(22, 2), _forward(23, 3)];
      for (final target in burst) {
        final older = [...burst.where((p) => p.id < target.id).toList().reversed, comment];
        final address = ForwardFiler.addressFor(target, older)!;
        expect(address.text, 'Wedding');
        expect(address.commentId, 20);
        // The forwards between the comment and this one are covered too.
        expect(address.burst, [
          for (final p in older)
            if (p.media) p.id,
        ]);
      }
    });

    test('a comment older than ten seconds is not the forward\'s', () {
      final comment = _post(20, date: 1000, text: 'Wedding');
      expect(ForwardFiler.addressFor(_forward(21, 11), [comment]), isNull);
      expect(ForwardFiler.addressFor(_forward(21, 10), [comment]), isNotNull);
    });

    test('a burst that takes longer than ten seconds still reaches its comment', () {
      final comment = _post(20, date: 1000, text: 'Wedding');
      final older = [_forward(22, 8), _forward(21, 1), comment];
      expect(ForwardFiler.addressFor(_forward(23, 15), older)?.commentId, 20);
      // Unless two of its forwards are further apart than that.
      expect(ForwardFiler.addressFor(_forward(23, 19), older), isNull);
    });

    test('the nearer of two comments is the forward\'s', () {
      final wedding = _post(20, date: 1000, text: 'Wedding');
      final taxes = _post(22, date: 1002, text: 'Taxes');
      final older = [taxes, _forward(21, 1), wedding];
      expect(ForwardFiler.addressFor(_forward(23, 3), older)?.text, 'Taxes');
      expect(ForwardFiler.addressFor(_forward(21, 1), [wedding])?.text, 'Wedding');
    });

    test('a folder\'s own message before the burst is not a comment', () {
      final folder = _post(20, date: 1000, manifest: true);
      expect(ForwardFiler.addressFor(_forward(21, 1), [folder]), isNull);
    });

    test('anything else before the burst ends the search', () {
      final ownFile = _post(20, date: 1000, media: true, manifest: true);
      final comment = _post(19, date: 999, text: 'Wedding');
      expect(ForwardFiler.addressFor(_forward(21, 1), [ownFile, comment]), isNull);
    });

    test('a text forwarded with the files is part of the burst, not its comment', () {
      final comment = _post(19, date: 999, text: 'Wedding');
      final note = _post(20, date: 1000, text: 'Photos', forwarded: true);
      final address = ForwardFiler.addressFor(_forward(21, 1), [note, comment])!;
      expect(address.text, 'Wedding');
      expect(address.commentId, 19);
      expect(address.burst, isEmpty);
      // With no comment of the account's own behind it, it names nothing.
      expect(ForwardFiler.addressFor(_forward(21, 1), [note]), isNull);
    });

    test('newer messages are passed over', () {
      final comment = _post(20, date: 1000, text: 'Wedding');
      final later = _post(25, date: 1004, media: true, manifest: true);
      expect(ForwardFiler.addressFor(_forward(21, 1), [later, comment]), isNotNull);
    });

    test('own media is addressed by its own caption', () {
      final own = _post(30, date: 1000, media: true, caption: ' Wedding ');
      final address = ForwardFiler.addressFor(own, const [])!;
      expect(address.text, 'Wedding');
      expect(address.commentId, isNull);
      expect(address.burst, isEmpty);
    });

    test('an album captioned on its last item addresses every item', () {
      final items = [
        for (var i = 0; i < 3; i++)
          _post(30 + i, date: 1000, media: true, albumId: 7, caption: i == 2 ? 'Wedding' : ''),
      ];
      for (final target in items) {
        final rest = items.where((p) => p.id != target.id).toList();
        final address = ForwardFiler.addressFor(target, const [], sameAlbum: rest)!;
        expect(address.text, 'Wedding');
        expect(address.commentId, isNull);
      }
    });

    test('an album with two captions names no one folder', () {
      final items = [
        _post(30, date: 1000, media: true, albumId: 7, caption: 'Wedding'),
        _post(31, date: 1000, media: true, albumId: 7, caption: 'Taxes'),
      ];
      expect(ForwardFiler.addressFor(items[0], const [], sameAlbum: [items[1]]), isNotNull);
      final uncaptioned = _post(32, date: 1000, media: true, albumId: 7);
      expect(ForwardFiler.addressFor(uncaptioned, const [], sameAlbum: items), isNull);
    });

    test('own media with no caption never looks back', () {
      final comment = _post(20, date: 1000, text: 'Wedding');
      final copy = _post(21, date: 1000, media: true);
      expect(ForwardFiler.addressFor(copy, [comment]), isNull);
    });

    test('a forward\'s original caption is ignored', () {
      final forward = _post(21, date: 1001, media: true, forwarded: true, caption: 'Taxes');
      expect(ForwardFiler.addressFor(forward, const []), isNull);
      final comment = _post(20, date: 1000, text: 'Wedding');
      expect(ForwardFiler.addressFor(forward, [comment])?.text, 'Wedding');
    });
  });

  group('filer', () {
    late ProviderContainer container;
    late _Channel telegram;
    late AppDatabase db;
    late Preferences prefs;

    Future<void> start({
      Map<String, Object> stored = const {'forward_filing_from_$testChatId': 10},
    }) async {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues(stored);
      final shared = await SharedPreferences.getInstance();
      db = AppDatabase(NativeDatabase.memory());
      telegram = _Channel();
      container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(shared),
          appDatabaseProvider.overrideWithValue(db),
          telegramClientProvider.overrideWithValue(telegram),
          driveSessionProvider.overrideWith(TestSession.new),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await db.close();
      });
      prefs = container.read(preferencesProvider);
    }

    DriveRepository repository() => container.read(driveRepositoryProvider);
    ForwardFiler filer() => container.read(forwardFilerProvider.notifier);

    /// Puts [message] in the channel and the index.
    Future<void> post(td.Message message) async {
      telegram.messages[message.id] = message;
      await repository().ingest(message);
    }

    Future<void> folder(String id, String name, int messageId, {String? parentId}) async {
      final at = DateTime(2026, 9, 1);
      await post(
        textMessage(
          messageId,
          ManifestCodec.encodeFolder(
            FolderManifest(id: id, name: name, parentId: parentId, createdAt: at, modifiedAt: at),
          ).text,
        ),
      );
    }

    td.Message forward(int id, int seconds, {String name = 'contract.pdf'}) => documentMessage(
      id,
      '',
      fileName: name,
      mimeType: 'application/pdf',
      date: 1000 + seconds,
      forwardedFrom: _selam,
    );

    test('a comment files the burst into its folder and then goes', () async {
      await start();
      await folder('wedding', 'Wedding', 5);
      await post(textMessage(20, 'Wedding', date: 1000));
      final burst = [forward(21, 1), forward(22, 2), forward(23, 3)];
      for (final message in burst) {
        await post(message);
      }
      expect((await db.fileById('tg21'))!.adopted, isTrue);

      await filer().consider(burst);

      for (final id in ['tg21', 'tg22', 'tg23']) {
        final file = (await db.fileById(id))!;
        expect(file.folderId, 'wedding');
        expect(file.adopted, isFalse);
      }
      // Each forward was copied into the drive's own message and the
      // original deleted, then the comment went last.
      expect(telegram.deleted, [
        [21],
        [22],
        [23],
        [20],
      ]);
      expect(telegram.messages.keys, isNot(contains(20)));
      expect(telegram.copies, 3);
      // The comment was looked up once for the whole burst.
      expect(telegram.requests.whereType<td.GetChatHistory>(), hasLength(1));
      expect(prefs.forwardFilingFrom(testChatId), 23);
      expect(
        container.read(forwardFilerProvider),
        const FilingSummary(count: 3, folderNames: ['Wedding'], folderId: 'wedding'),
      );

      // The same messages again, and nothing moves twice.
      await filer().consider(burst);
      expect(telegram.copies, 3);
      expect(container.read(forwardFilerProvider)?.count, 3);
    });

    test('two comments sent close together each file their own burst', () async {
      await start();
      await folder('wedding', 'Wedding', 5);
      await folder('taxes', 'Taxes', 6);
      await post(textMessage(20, 'Wedding', date: 1000));
      final first = [forward(21, 1), forward(22, 2)];
      for (final message in first) {
        await post(message);
      }
      await post(textMessage(23, 'Taxes', date: 1003));
      final second = [forward(24, 4), forward(25, 5)];
      for (final message in second) {
        await post(message);
      }

      await filer().consider([...first, ...second]);

      expect((await db.fileById('tg21'))!.folderId, 'wedding');
      expect((await db.fileById('tg22'))!.folderId, 'wedding');
      expect((await db.fileById('tg24'))!.folderId, 'taxes');
      expect((await db.fileById('tg25'))!.folderId, 'taxes');
      expect(telegram.deleted, [
        [21],
        [22],
        [20],
        [24],
        [25],
        [23],
      ]);
      // One read of the channel served both bursts.
      expect(telegram.requests.whereType<td.GetChatHistory>(), hasLength(1));
      expect(container.read(forwardFilerProvider)?.folderNames, ['Wedding', 'Taxes']);
      expect(container.read(forwardFilerProvider)?.folderId, isNull);
    });

    test('messages at or below the watermark are left alone', () async {
      await start(stored: {'forward_filing_from_$testChatId': 22});
      await folder('wedding', 'Wedding', 5);
      await post(textMessage(20, 'Wedding', date: 1000));
      final burst = [forward(21, 1), forward(22, 2), forward(23, 3)];
      for (final message in burst) {
        await post(message);
      }

      await filer().consider(burst);

      expect((await db.fileById('tg21'))!.adopted, isTrue);
      expect((await db.fileById('tg22'))!.adopted, isTrue);
      expect((await db.fileById('tg23'))!.folderId, 'wedding');
      // The comment covered a file that stayed, so it stays too.
      expect(telegram.deleted, [
        [23],
      ]);
      expect(prefs.forwardFilingFrom(testChatId), 23);
    });

    test('a comment that names no folder moves nothing and stays', () async {
      await start();
      await folder('wedding', 'Wedding', 5);
      await post(textMessage(20, 'look at this', date: 1000));
      final message = forward(21, 1);
      await post(message);

      await filer().consider([message]);

      expect((await db.fileById('tg21'))!.adopted, isTrue);
      expect(telegram.deleted, isEmpty);
      expect(telegram.messages.keys, contains(20));
      expect(prefs.forwardFilingFrom(testChatId), 21);
      expect(container.read(forwardFilerProvider), isNull);
    });

    test('a folder in the trash is not where a comment points', () async {
      await start();
      final at = DateTime(2026, 9, 1);
      await post(
        textMessage(
          5,
          ManifestCodec.encodeFolder(
            FolderManifest(
              id: 'wedding',
              name: 'Wedding',
              parentId: null,
              createdAt: at,
              modifiedAt: at,
              trashedAt: at,
            ),
          ).text,
        ),
      );
      await post(textMessage(20, 'Wedding', date: 1000));
      final message = forward(21, 1);
      await post(message);

      await filer().consider([message]);

      expect(await repository().visibleFolders(), isEmpty);
      expect((await db.fileById('tg21'))!.adopted, isTrue);
      expect(telegram.messages.keys, contains(20));
    });

    test('a # comment makes the folders on the way', () async {
      await start();
      await post(textMessage(20, '#Taxes/2026', date: 1000));
      final message = forward(21, 1);
      await post(message);

      await filer().consider([message]);

      final folders = await repository().visibleFolders();
      final taxes = folders.singleWhere((f) => f.name == 'Taxes');
      final year = folders.singleWhere((f) => f.name == '2026');
      expect(taxes.parentId, isNull);
      expect(year.parentId, taxes.id);
      expect((await db.fileById('tg21'))!.folderId, year.id);
      expect(container.read(forwardFilerProvider)?.folderNames, ['2026']);
    });

    test('own media is filed by its caption, which the manifest replaces', () async {
      await start();
      await folder('wedding', 'Wedding', 5);
      final message = documentMessage(
        30,
        'Wedding',
        fileName: 'venue.pdf',
        mimeType: 'application/pdf',
        date: 1000,
      );
      await post(message);

      await filer().consider([message]);

      final file = (await db.fileById('tg30'))!;
      expect(file.folderId, 'wedding');
      expect(file.adopted, isFalse);
      // Edited in place: no copy and no delete.
      expect(telegram.copies, 0);
      expect(telegram.deleted, isEmpty);
      final caption = (telegram.messages[30]!.content as td.MessageDocument).caption.text;
      expect(ManifestCodec.decodeFile(caption)?.folderId, 'wedding');
    });

    test('a refused copy stops the pass with the watermark below it', () async {
      await start();
      await folder('wedding', 'Wedding', 5);
      await post(textMessage(20, 'Wedding', date: 1000));
      final burst = [forward(21, 1), forward(22, 2), forward(23, 3)];
      for (final message in burst) {
        await post(message);
      }
      telegram.refuseCopies.add(22);

      await filer().consider(burst);

      expect((await db.fileById('tg21'))!.folderId, 'wedding');
      expect((await db.fileById('tg22'))!.adopted, isTrue);
      expect((await db.fileById('tg23'))!.adopted, isTrue);
      expect(telegram.messages.keys, contains(20));
      expect(prefs.forwardFilingFrom(testChatId), 21);
      expect(container.read(forwardFilerProvider)?.count, 1);

      // Once Telegram takes the copy, the next pass carries on from there
      // and the comment goes with the last file.
      telegram.refuseCopies.clear();
      await filer().consider(burst);
      expect((await db.fileById('tg22'))!.folderId, 'wedding');
      expect((await db.fileById('tg23'))!.folderId, 'wedding');
      expect(telegram.messages.keys, isNot(contains(20)));
      expect(prefs.forwardFilingFrom(testChatId), 23);
      expect(
        container.read(forwardFilerProvider),
        const FilingSummary(count: 3, folderNames: ['Wedding'], folderId: 'wedding'),
      );
    });

    test('a history page cut short is read on until the comment', () async {
      await start();
      await folder('wedding', 'Wedding', 5);
      await post(textMessage(20, 'Wedding', date: 1000));
      final burst = [forward(21, 1), forward(22, 2), forward(23, 3)];
      for (final message in burst) {
        await post(message);
      }
      telegram.pageLimit = 1;

      await filer().consider(burst);

      for (final id in ['tg21', 'tg22', 'tg23']) {
        expect((await db.fileById(id))!.folderId, 'wedding');
      }
      expect(telegram.messages.keys, isNot(contains(20)));
      // One message a page: the two forwards above the first, then its comment.
      expect(telegram.requests.whereType<td.GetChatHistory>(), hasLength(3));
      expect(prefs.forwardFilingFrom(testChatId), 23);
    });

    test('a comment that can\'t be deleted goes with the next pass', () async {
      await start();
      await folder('wedding', 'Wedding', 5);
      await post(textMessage(20, 'Wedding', date: 1000));
      final burst = [forward(21, 1), forward(22, 2), forward(23, 3)];
      for (final message in burst) {
        await post(message);
      }
      telegram.refuseDeletes.add(20);

      await filer().consider(burst);

      for (final id in ['tg21', 'tg22', 'tg23']) {
        expect((await db.fileById(id))!.folderId, 'wedding');
      }
      expect(telegram.messages.keys, contains(20));
      // The watermark stays below the burst, so the comment is seen again.
      expect(prefs.forwardFilingFrom(testChatId), 10);
      expect(container.read(forwardFilerProvider)?.count, 3);

      telegram.refuseDeletes.clear();
      await filer().consider(burst);
      expect(telegram.messages.keys, isNot(contains(20)));
      expect(telegram.copies, 3);
      expect(prefs.forwardFilingFrom(testChatId), 23);
      expect(container.read(forwardFilerProvider)?.count, 3);
    });

    test('a forward delivered after its burst was filed goes with it', () async {
      await start();
      await folder('wedding', 'Wedding', 5);
      await post(textMessage(20, 'Wedding', date: 1000));
      final first = [forward(21, 1), forward(22, 2)];
      for (final message in first) {
        await post(message);
      }
      await filer().consider(first);
      expect(telegram.messages.keys, isNot(contains(20)));

      // The comment has gone, but the forward was sent with the others.
      final late = forward(23, 3);
      await post(late);
      await filer().consider([late]);

      expect((await db.fileById('tg23'))!.folderId, 'wedding');
      expect(telegram.deleted, [
        [21],
        [22],
        [20],
        [23],
      ]);
      expect(container.read(forwardFilerProvider)?.count, 3);

      // One sent well after the burst waits for a comment of its own.
      final apart = forward(24, 20);
      await post(apart);
      await filer().consider([apart]);
      expect((await db.fileById('tg24'))!.adopted, isTrue);
    });

    test('nothing is filed before the first sync has set the watermark', () async {
      await start(stored: const {});
      await folder('wedding', 'Wedding', 5);
      await post(textMessage(20, 'Wedding', date: 1000));
      final message = forward(21, 1);
      await post(message);

      await filer().consider([message]);

      expect((await db.fileById('tg21'))!.adopted, isTrue);
      expect(telegram.requests, isEmpty);
    });

    test('Keep here gives a forward a manifest at the root', () async {
      await start();
      final message = forward(21, 1);
      await post(message);
      final file = (await repository().fileById('tg21'))!;

      await repository().keepAtRoot([file]);

      final kept = (await db.fileById('tg21'))!;
      expect(kept.adopted, isFalse);
      expect(kept.folderId, isNull);
      expect(telegram.copies, 1);
      expect(telegram.deleted, [
        [21],
      ]);
    });

    test('the origin names who forwarded a file, and own media is its own', () async {
      await start();
      await post(forward(21, 1));
      await post(documentMessage(30, '', date: 1000));
      await post(
        documentMessage(
          31,
          '',
          date: 1000,
          forwardedFrom: const td.MessageOriginUser(senderUserId: 9),
        ),
      );

      expect(await container.read(forwardOriginProvider('tg21').future), (
        forwarded: true,
        name: 'Selam Tesfaye',
      ));
      expect(await container.read(forwardOriginProvider('tg30').future), (
        forwarded: false,
        name: null,
      ));
      // A sender TDLib can't describe leaves the row saying Forwarded.
      expect(await container.read(forwardOriginProvider('tg31').future), isNull);
      expect(await container.read(forwardOriginProvider('gone').future), isNull);
    });

    test('a summary adds up across passes and keeps one folder only while it is one', () {
      const first = FilingSummary(count: 3, folderNames: ['Wedding'], folderId: 'w');
      expect(first.plus(2, {'w': 'Wedding'}).folderId, 'w');
      final two = first.plus(1, {'t': 'Taxes'});
      expect(two.count, 4);
      expect(two.folderNames, ['Wedding', 'Taxes']);
      expect(two.folderId, isNull);
    });

    test('the indexer tells adopted media from the drive\'s own', () {
      expect(MessageIndexer.isAdopted(forward(21, 1)), isTrue);
      expect(MessageIndexer.isAdopted(documentMessage(30, 'Wedding')), isTrue);
      expect(MessageIndexer.isAdopted(textMessage(20, 'Wedding')), isFalse);
      final at = DateTime(2026, 9, 1);
      final own = ManifestCodec.encodeFile(
        FileManifest(
          id: 'a',
          name: 'a.pdf',
          folderId: null,
          mimeType: 'application/pdf',
          size: 9,
          createdAt: at,
          modifiedAt: at,
        ),
      ).text;
      expect(MessageIndexer.isAdopted(documentMessage(31, own)), isFalse);
      expect(
        MessageIndexer.isAdopted(
          forward(22, 1).copyWith(sendingState: const td.MessageSendingStatePending(sendingId: 0)),
        ),
        isFalse,
      );
    });
  });
}
