import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegrive/core/async/combine.dart';
import 'package:telegrive/core/files/file_kind.dart';
import 'package:telegrive/core/format/formatters.dart';
import 'package:telegrive/features/backup/data/backup_controller.dart';
import 'package:telegrive/features/backup/data/local_media.dart';
import 'package:telegrive/features/drive/domain/drive_models.dart';
import 'package:telegrive/features/files/presentation/file_location.dart';
import 'package:telegrive/features/search/data/content_indexer.dart';
import 'package:telegrive/features/transfers/data/transfer_keep_alive.dart';
import 'package:telegrive/features/transfers/data/transfer_queue.dart';
import 'package:telegrive/features/transfers/domain/transfer_wait.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';
import 'package:telegrive/infrastructure/storage/device_profile.dart';
import 'package:telegrive/infrastructure/storage/preferences.dart';
import 'package:telegrive/infrastructure/telegram/telegram_exception.dart';

void main() {
  group('FileKind.detect', () {
    FileKind kind(String name, [String? mime]) =>
        FileKind.detect(fileName: name, mimeType: mime);

    test('uses the MIME type when Telegram knows it', () {
      expect(kind('x', 'image/png'), FileKind.image);
      expect(kind('x', 'video/mp4'), FileKind.video);
      expect(kind('x', 'audio/ogg'), FileKind.audio);
      expect(kind('x', 'application/pdf'), FileKind.document);
    });

    test('falls back to the extension for octet-stream', () {
      expect(kind('holiday.JPG', 'application/octet-stream'), FileKind.image);
      expect(
        kind('backup.tar.gz', 'application/octet-stream'),
        FileKind.archive,
      );
      expect(kind('app-release.apk', 'application/octet-stream'), FileKind.app);
      expect(kind('notes.md'), FileKind.document);
      expect(kind('mystery.bin'), FileKind.other);
    });

    test('call recordings and audiobooks are audio', () {
      for (final name in ['call.amr', 'wide.awb', 'rec.3ga', 'book.m4b']) {
        expect(
          kind(name, 'application/octet-stream'),
          FileKind.audio,
          reason: name,
        );
        expect(kind(name), FileKind.audio, reason: name);
      }
      expect(kind('x', 'application/ogg'), FileKind.audio);
    });

    test('uploads carry an audio type the player understands', () {
      expect(mimeTypeFor('call.amr'), 'audio/amr');
      expect(mimeTypeFor('book.m4b'), 'audio/mp4');
      expect(mimeTypeFor('note.opus'), 'audio/ogg');
    });

    test('a call recording opens in the player', () {
      expect(
        Preview.of(
          name: 'rec.3ga',
          mimeType: 'application/octet-stream',
          kind: FileKind.audio,
          size: 1,
        ),
        Preview.media,
      );
    });

    test('a PDF in parts opens in the reader; other split files do not', () {
      Preview split(String name, String mimeType) => Preview.of(
        name: name,
        mimeType: mimeType,
        kind: FileKind.detect(fileName: name, mimeType: mimeType),
        size: 3 * 1024 * 1024 * 1024,
        isSplit: true,
      );
      expect(split('scan.pdf', 'application/pdf'), Preview.pdf);
      expect(split('photos.zip', 'application/zip'), Preview.none);
      expect(split('notes.txt', 'text/plain'), Preview.none);
    });
  });

  group('withExtension', () {
    test('puts back an extension that was typed away', () {
      expect(withExtension('Receipt', 'pdf'), 'Receipt.pdf');
    });

    test('leaves a name that already ends in it, in any case', () {
      expect(withExtension('Receipt.PDF', 'pdf'), 'Receipt.PDF');
      expect(withExtension('Photo.jpg', 'JPG'), 'Photo.jpg');
    });

    test('adds it after a different one', () {
      expect(withExtension('a.b', 'jpg'), 'a.b.jpg');
    });
  });

  group('Formatters', () {
    test('bytes', () {
      expect(Formatters.bytes(0), '0 B');
      expect(Formatters.bytes(512), '512 B');
      expect(Formatters.bytes(1536), '1.5 KB');
      expect(Formatters.bytes(5 * 1024 * 1024 * 1024), '5.0 GB');
      expect(Formatters.bytes(150 * 1024 * 1024), '150 MB');
    });

    test('eta', () {
      expect(Formatters.eta(const Duration(seconds: 42)), '42s left');
      expect(Formatters.eta(const Duration(seconds: 75)), '1m 15s left');
      expect(Formatters.eta(const Duration(minutes: 125)), '2h 5m left');
    });

    test('countdown', () {
      expect(Formatters.countdown(const Duration(seconds: 7)), '0:07');
      expect(Formatters.countdown(const Duration(seconds: 72)), '1:12');
      expect(
        Formatters.countdown(const Duration(minutes: 58, seconds: 12)),
        '58:12',
      );
      expect(
        Formatters.countdown(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '1:02:03',
      );
      // Part of a second still to go reads as a whole one, never 0:00.
      expect(Formatters.countdown(const Duration(milliseconds: 71200)), '1:12');
      expect(Formatters.countdown(const Duration(milliseconds: 300)), '0:01');
      expect(Formatters.countdown(Duration.zero), '0:00');
    });

    test('length', () {
      expect(Formatters.length(const Duration(seconds: 42)), '0:42');
      expect(
        Formatters.length(const Duration(minutes: 12, seconds: 40)),
        '12:40',
      );
      expect(
        Formatters.length(const Duration(hours: 1, minutes: 12, seconds: 40)),
        '1:12:40',
      );
      expect(
        Formatters.length(const Duration(hours: 10, minutes: 5)),
        '10:05:00',
      );
      // Unlike a countdown, a part-second is dropped rather than counted.
      expect(Formatters.length(const Duration(milliseconds: 71900)), '1:11');
    });

    test('latency', () {
      expect(
        Formatters.latency(const Duration(microseconds: 240400)),
        '240 ms',
      );
      expect(
        Formatters.latency(const Duration(milliseconds: 1240)),
        '1,240 ms',
      );
    });

    test('inWords', () {
      expect(Formatters.inWords(const Duration(seconds: 1)), '1 second');
      expect(Formatters.inWords(const Duration(seconds: 37)), '37 seconds');
      expect(Formatters.inWords(const Duration(minutes: 5)), '5 minutes');
      expect(Formatters.inWords(const Duration(hours: 2)), '2 hours');
    });

    test('daysLeft', () {
      final now = DateTime(2026, 10, 4, 12);
      expect(
        Formatters.daysLeft(DateTime(2026, 10, 31, 12), now: now),
        'goes for good in 27 days',
      );
      expect(
        Formatters.daysLeft(DateTime(2026, 10, 5, 13), now: now),
        'goes for good in 1 day',
      );
      // Less than a day left, and already past, both read as today.
      expect(
        Formatters.daysLeft(DateTime(2026, 10, 5, 11), now: now),
        'goes for good today',
      );
      expect(
        Formatters.daysLeft(DateTime(2026, 10, 1), now: now),
        'goes for good today',
      );
      expect(
        Formatters.capitalised('goes for good today'),
        'Goes for good today',
      );
      expect(Formatters.capitalised(''), '');
    });

    test('dayOfMonth', () {
      expect(Formatters.dayOfMonth(1), '1st');
      expect(Formatters.dayOfMonth(2), '2nd');
      expect(Formatters.dayOfMonth(3), '3rd');
      expect(Formatters.dayOfMonth(4), '4th');
      expect(Formatters.dayOfMonth(11), '11th');
      expect(Formatters.dayOfMonth(12), '12th');
      expect(Formatters.dayOfMonth(13), '13th');
      expect(Formatters.dayOfMonth(21), '21st');
      expect(Formatters.dayOfMonth(22), '22nd');
      expect(Formatters.dayOfMonth(23), '23rd');
      expect(Formatters.dayOfMonth(28), '28th');
    });

    test('clock says the time today, tomorrow and its time, then the date', () {
      final now = DateTime(2026, 10, 4, 22, 15);
      // The locale's own space before AM and PM.
      String time(String text) => text.replaceAll(' ', '\u202f');
      expect(
        Formatters.clock(DateTime(2026, 10, 4, 23, 40), now: now),
        time('11:40 PM'),
      );
      expect(
        Formatters.clock(DateTime(2026, 10, 5, 0, 40), now: now),
        'tomorrow ${time('12:40 AM')}',
      );
      expect(Formatters.clock(DateTime(2026, 10, 6, 9, 5), now: now), 'Oct 6');
      // The last day of a month runs into the first of the next.
      expect(
        Formatters.clock(
          DateTime(2026, 11, 1, 1, 0),
          now: DateTime(2026, 10, 31, 23, 0),
        ),
        'tomorrow ${time('1:00 AM')}',
      );
    });
  });

  group('SortOrder', () {
    DriveFile file(String name, int size, int day) => DriveFile(
      id: name,
      folderId: null,
      name: name,
      mimeType: 'text/plain',
      kind: FileKind.document,
      size: size,
      createdAt: DateTime(2026, 1, day),
      modifiedAt: DateTime(2026, 1, day),
      partCount: 1,
      starred: false,
    );

    final files = [
      file('b.txt', 10, 3),
      file('A.txt', 30, 1),
      file('c.txt', 20, 2),
    ];

    test('by name ignores case', () {
      final sorted = [...files]
        ..sort(const SortOrder(SortField.name).compareFiles);
      expect(sorted.map((f) => f.name), ['A.txt', 'b.txt', 'c.txt']);
    });

    test('by size, largest first', () {
      final sorted = [...files]
        ..sort(const SortOrder(SortField.size, descending: true).compareFiles);
      expect(sorted.map((f) => f.size), [30, 20, 10]);
    });

    test('by date', () {
      final sorted = [...files]
        ..sort(const SortOrder(SortField.modified).compareFiles);
      expect(sorted.map((f) => f.name), ['A.txt', 'c.txt', 'b.txt']);
    });
  });

  group('RecentEntry.merge', () {
    DriveFile file(String name, DateTime added) => DriveFile(
      id: name,
      folderId: null,
      name: name,
      mimeType: 'application/pdf',
      kind: FileKind.document,
      size: 100,
      createdAt: added,
      modifiedAt: added,
      partCount: 1,
      starred: false,
    );

    final yesterday = DateTime(2026, 9, 26, 18);
    final today = DateTime(2026, 9, 27, 9);

    test('an open from yesterday and an add from today, newest first', () {
      final lease = file('lease.pdf', DateTime(2026, 8, 1));
      final invoice = file('invoice.pdf', today);
      final entries = RecentEntry.merge(
        opened: [(lease, yesterday)],
        added: [invoice],
        limit: 12,
      );
      expect(entries, [
        RecentEntry(invoice, at: today, opened: false),
        RecentEntry(lease, at: yesterday, opened: true),
      ]);
      expect(entries.map((e) => e.verb), ['Added', 'Opened']);
    });

    test('a file opened after it was added appears once, as opened', () {
      final lease = file('lease.pdf', yesterday);
      final entries = RecentEntry.merge(
        opened: [(lease, today)],
        added: [lease],
        limit: 12,
      );
      expect(entries, [RecentEntry(lease, at: today, opened: true)]);
    });

    test('a file added after its recorded open appears once, as added', () {
      final lease = file('lease.pdf', today);
      final entries = RecentEntry.merge(
        opened: [(lease, yesterday)],
        added: [lease],
        limit: 12,
      );
      expect(entries, [RecentEntry(lease, at: today, opened: false)]);
    });

    test('keeps to the limit, and orders ties by name', () {
      final entries = RecentEntry.merge(
        opened: [
          for (final name in ['c.pdf', 'a.pdf', 'b.pdf'])
            (file(name, yesterday), today),
        ],
        added: [
          for (var i = 1; i <= 5; i++)
            file('added $i.pdf', DateTime(2026, 9, i)),
        ],
        limit: 4,
      );
      expect(entries.map((e) => e.file.name), [
        'a.pdf',
        'b.pdf',
        'c.pdf',
        'added 5.pdf',
      ]);
    });
  });

  group('TelegramException', () {
    test('reads flood waits in both spellings', () {
      expect(
        const TelegramException(420, 'FLOOD_WAIT_37').retryAfterSeconds,
        37,
      );
      expect(
        const TelegramException(
          429,
          'Too Many Requests: retry after 12',
        ).retryAfterSeconds,
        12,
      );
      expect(const TelegramException(420, 'FLOOD_WAIT_37').isFloodWait, isTrue);
    });

    test('speaks human', () {
      expect(
        const TelegramException(400, 'PHONE_CODE_INVALID').friendlyMessage,
        contains('code'),
      );
      expect(
        const TelegramException(400, 'SOMETHING_ODD').friendlyMessage,
        'Something odd',
      );
      expect(
        const TelegramException(400, 'FILE_REFERENCE_EXPIRED').friendlyMessage,
        'Telegram needs this file fetched again. Retry.',
      );
      expect(
        const TelegramException(420, 'FLOOD_WAIT_7200').friendlyMessage,
        'Too many attempts. Try again in 2 hours.',
      );
    });
  });

  group('locationOf', () {
    DriveFolder folder(String id, String? parentId) => DriveFolder(
      id: id,
      parentId: parentId,
      name: id,
      createdAt: DateTime(2026),
      modifiedAt: DateTime(2026),
    );
    final byId = {
      for (final f in [folder('Work', null), folder('Invoices', 'Work')])
        f.id: f,
    };

    test('names the folders from the top down', () {
      expect(locationOf(byId, 'Invoices'), 'Work › Invoices');
      expect(
        locationOf(byId, 'Invoices', fromRoot: true),
        'Files › Work › Invoices',
      );
    });

    test('a file at the root, or in a folder that is gone, is in Files', () {
      expect(locationOf(byId, null), 'Files');
      expect(locationOf(byId, 'missing'), 'Files');
    });

    test('a loop in the folder tree still ends', () {
      final loop = {'a': folder('a', 'b'), 'b': folder('b', 'a')};
      expect(locationOf(loop, 'a'), 'b › a');
    });
  });

  group('Copies from chats', () {
    TransferItem item(
      String id,
      TransferKind kind,
      TransferOrigin origin,
      TransferStatus status, {
      int total = 10,
      int done = 0,
    }) => TransferItem(
      TransferRow(
        id: id,
        kind: kind,
        status: status,
        name: '$id.pdf',
        mimeType: 'application/pdf',
        fileId: id,
        ownsSource: false,
        wifiOnly: false,
        totalBytes: total,
        doneBytes: done,
        partCount: 1,
        completedParts: 0,
        createdAt: DateTime(2026, 10, 1),
        origin: origin,
      ),
    );
    TransferItem copy(String id, TransferStatus status) =>
        item(id, TransferKind.upload, TransferOrigin.fromChat, status);

    final state = TransfersState([
      item(
        'upload',
        TransferKind.upload,
        TransferOrigin.manual,
        TransferStatus.running,
      ),
      copy('copy 1', TransferStatus.running),
      copy('copy 2', TransferStatus.queued),
      copy('copy 3', TransferStatus.completed),
      item(
        'download',
        TransferKind.download,
        TransferOrigin.manual,
        TransferStatus.running,
      ),
    ]);
    const idle = BackupState(phase: BackupPhase.off);

    test('are their own group', () {
      expect(state.copies.map((t) => t.id), ['copy 1', 'copy 2', 'copy 3']);
    });

    test('are counted by file, leaving out cancelled ones', () {
      final count = TransfersState([
        ...state.copies,
        copy('copy 4', TransferStatus.failed),
        copy('copy 5', TransferStatus.cancelled),
      ]).copyCount;
      expect(count, (saved: 1, total: 4, left: 2));
    });

    test('the notification counts them apart from uploads', () {
      final (title, _) = TransferKeepAlive.describe(state, idle);
      expect(
        title,
        'Uploading 1 file · Downloading 1 file · Saving 2 files from Telegram',
      );
      final (onlyCopies, _) = TransferKeepAlive.describe(
        TransfersState(state.copies),
        idle,
      );
      expect(onlyCopies, 'Saving 2 files from Telegram');
    });

    test('on their own, the notification says how many files are left', () {
      final (title, text) = TransferKeepAlive.describe(
        TransfersState([
          ...state.copies,
          copy('copy 4', TransferStatus.failed),
          copy('copy 5', TransferStatus.cancelled),
        ]),
        idle,
      );
      expect(title, 'Saving 2 files from Telegram');
      expect(text, '2 files left');
    });

    test('next to an upload, the notification gives the upload\'s share', () {
      final (title, text) = TransferKeepAlive.describe(
        TransfersState([
          item(
            'upload',
            TransferKind.upload,
            TransferOrigin.manual,
            TransferStatus.running,
            total: 10 << 20,
            done: 5 << 20,
          ),
          for (var i = 0; i < 80; i++)
            item(
              'copy $i',
              TransferKind.upload,
              TransferOrigin.fromChat,
              TransferStatus.queued,
              total: 2 << 20,
            ),
        ]),
        idle,
      );
      expect(title, 'Uploading 1 file · Saving 80 files from Telegram');
      expect(text, '50%');
    });
  });

  test(
    'a backup pass with a video waiting for Wi-Fi still says it is backing up',
    () {
      TransferItem backupUpload(
        String name,
        TransferStatus status, {
        TransferWait? wait,
      }) => TransferItem(
        TransferRow(
          id: name,
          kind: TransferKind.upload,
          status: status,
          name: name,
          mimeType: mimeTypeFor(name),
          fileId: name,
          ownsSource: false,
          wifiOnly: wait is WaitingForWifi,
          totalBytes: 10,
          doneBytes: 0,
          partCount: 1,
          completedParts: 0,
          createdAt: DateTime(2026, 10, 1),
          origin: TransferOrigin.backup,
        ),
        wait: wait,
      );
      const uploading = BackupState(
        phase: BackupPhase.uploading,
        total: 10,
        done: 4,
      );

      final (title, text) = TransferKeepAlive.describe(
        TransfersState([
          backupUpload(
            'VID_1.mp4',
            TransferStatus.queued,
            wait: const WaitingForWifi(),
          ),
          backupUpload('IMG_2.jpg', TransferStatus.running),
        ]),
        uploading,
      );
      expect(title, 'Backing up photos');
      expect(text, '6 items left');

      final (paused, _) = TransferKeepAlive.describe(
        TransfersState([
          backupUpload(
            'IMG_3.jpg',
            TransferStatus.queued,
            wait: WaitingForTelegram(
              DateTime.now().add(const Duration(hours: 1)),
            ),
          ),
        ]),
        uploading,
      );
      expect(paused, 'Telegrive');
    },
  );

  group('Preferences', () {
    test(
      'rememberSentTo keeps the newest first, once each, and five at most',
      () async {
        // ignore: invalid_use_of_visible_for_testing_member
        SharedPreferences.setMockInitialValues({
          'recent_send_chats': ['3', 'not a chat', '2', '1'],
        });
        final prefs = Preferences(await SharedPreferences.getInstance());
        expect(prefs.recentSendChats, [3, 2, 1]);

        await prefs.rememberSentTo([2]);
        expect(prefs.recentSendChats, [2, 3, 1]);

        await prefs.rememberSentTo([7, 6, 5]);
        expect(prefs.recentSendChats, [7, 6, 5, 2, 3]);

        await prefs.rememberSentTo([9, 9]);
        expect(prefs.recentSendChats, [9, 7, 6, 5, 2]);

        await prefs.forgetRecentSendChats();
        expect(prefs.recentSendChats, isEmpty);
      },
    );
  });

  group('throttleLatest', () {
    const interval = Duration(milliseconds: 750);

    test('the first value comes through at once', () {
      fakeAsync((async) {
        final source = StreamController<int>();
        final seen = <int>[];
        throttleLatest(source.stream, interval).listen(seen.add);
        source.add(1);
        async.flushMicrotasks();
        expect(seen, [1]);
        source.close();
        async.flushTimers();
      });
    });

    test(
      'a burst collapses to its latest value, delivered as the interval ends',
      () {
        fakeAsync((async) {
          final source = StreamController<int>();
          final seen = <int>[];
          throttleLatest(source.stream, interval).listen(seen.add);
          source.add(1);
          async.flushMicrotasks();
          for (var i = 2; i <= 5; i++) {
            async.elapse(const Duration(milliseconds: 100));
            source.add(i);
          }
          async.flushMicrotasks();
          expect(seen, [1], reason: 'still inside the first interval');
          async.elapse(const Duration(milliseconds: 350));
          expect(seen, [1, 5]);

          // Quiet for a whole interval, so the next value comes at once.
          async.elapse(interval);
          source.add(6);
          async.flushMicrotasks();
          expect(seen, [1, 5, 6]);
          source.close();
          async.flushTimers();
        });
      },
    );

    test('a value still waiting when the source closes is delivered', () {
      fakeAsync((async) {
        final source = StreamController<int>();
        final seen = <int>[];
        var closed = false;
        throttleLatest(
          source.stream,
          interval,
        ).listen(seen.add, onDone: () => closed = true);
        source
          ..add(1)
          ..add(2)
          ..add(3)
          ..close();
        async.flushMicrotasks();
        expect(seen, [1, 3]);
        expect(closed, isTrue);
      });
    });
  });

  test('thumbBucket picks the smallest size that is big enough to within 5%, up to 512', () {
    expect(thumbBucket(115), 128);
    expect(thumbBucket(128), 128);
    expect(thumbBucket(250), 256);
    // A tile of a four-column grid on a 1080 px phone.
    expect(thumbBucket(266), 256);
    expect(thumbBucket(267), 256);
    expect(thumbBucket(300), 384);
    expect(thumbBucket(700), 512);
  });

  test('a phone with little memory is offered Save memory', () {
    const gb = 1 << 30;
    DeviceProfile profile({bool lowRam = false, int totalRam = 0}) =>
        DeviceProfile(
          lowRam: lowRam,
          memoryClassMb: 128,
          totalRamBytes: totalRam,
        );

    expect(profile(lowRam: true, totalRam: 4 * gb).suggestSaveMemory, isTrue);
    expect(profile(totalRam: (1.9 * gb).round()).suggestSaveMemory, isTrue);
    expect(profile(totalRam: (3.6 * gb).round()).suggestSaveMemory, isFalse);
    expect(DeviceProfile.unknown.suggestSaveMemory, isFalse);
  });

  group('Save memory', () {
    const gb = 1 << 30;
    final small = DeviceProfile(
      lowRam: false,
      memoryClassMb: 128,
      totalRamBytes: (1.9 * gb).round(),
    );
    const roomy = DeviceProfile(
      lowRam: false,
      memoryClassMb: 256,
      totalRamBytes: 6 * gb,
    );

    Future<ProviderContainer> phone(
      DeviceProfile profile, [
      Map<String, Object> stored = const {},
    ]) async {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues(stored);
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
          deviceProfileProvider.overrideWithValue(profile),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('follows the phone until the person chooses', () async {
      expect((await phone(small)).read(saveMemoryProvider), isTrue);
      expect((await phone(roomy)).read(saveMemoryProvider), isFalse);
    });

    test('a stored choice wins over what the phone suggests', () async {
      expect(
        (await phone(small, {'save_memory': false})).read(saveMemoryProvider),
        isFalse,
      );
      expect(
        (await phone(roomy, {'save_memory': true})).read(saveMemoryProvider),
        isTrue,
      );
    });

    test('turning it on or off applies at once and is stored', () async {
      final container = await phone(small);
      final prefs = container.read(preferencesProvider);
      expect(prefs.saveMemory, isNull);

      container.read(saveMemoryProvider.notifier).set(false);
      expect(container.read(saveMemoryProvider), isFalse);
      expect(prefs.saveMemory, isFalse);

      container.read(saveMemoryProvider.notifier).set(true);
      expect(container.read(saveMemoryProvider), isTrue);
      expect(prefs.saveMemory, isTrue);
    });

    test('Search inside documents starts off while saving memory, and can be turned on', () async {
      final saving = await phone(small);
      expect(saving.read(contentIndexerProvider).enabled, isFalse);
      await saving.read(contentIndexerProvider.notifier).setEnabled(true);
      expect(saving.read(contentIndexerProvider).enabled, isTrue);
      expect(saving.read(preferencesProvider).contentSearchOr(false), isTrue);

      expect((await phone(roomy)).read(contentIndexerProvider).enabled, isTrue);
    });

    test(
      'a stored Search inside documents choice outlasts the phone\'s default',
      () async {
        expect(
          (await phone(small, {
            'content_search': true,
          })).read(contentIndexerProvider).enabled,
          isTrue,
        );
        expect(
          (await phone(roomy, {
            'content_search': false,
          })).read(contentIndexerProvider).enabled,
          isFalse,
        );
      },
    );

    test(
      'contentSearchOr gives the fallback until a choice is stored',
      () async {
        final fresh = (await phone(roomy)).read(preferencesProvider);
        expect(fresh.contentSearchOr(false), isFalse);
        expect(fresh.contentSearchOr(true), isTrue);

        final off = (await phone(roomy, {
          'content_search': false,
        })).read(preferencesProvider);
        expect(off.contentSearchOr(true), isFalse);
        final on = (await phone(roomy, {
          'content_search': true,
        })).read(preferencesProvider);
        expect(on.contentSearchOr(false), isTrue);
      },
    );
  });
}
