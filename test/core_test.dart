import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegrive/core/files/file_kind.dart';
import 'package:telegrive/core/format/formatters.dart';
import 'package:telegrive/features/drive/domain/drive_models.dart';
import 'package:telegrive/features/files/presentation/file_location.dart';
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
      expect(kind('backup.tar.gz', 'application/octet-stream'), FileKind.archive);
      expect(kind('app-release.apk', 'application/octet-stream'), FileKind.app);
      expect(kind('notes.md'), FileKind.document);
      expect(kind('mystery.bin'), FileKind.other);
    });

    test('call recordings and audiobooks are audio', () {
      for (final name in ['call.amr', 'wide.awb', 'rec.3ga', 'book.m4b']) {
        expect(kind(name, 'application/octet-stream'), FileKind.audio, reason: name);
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
      expect(Formatters.countdown(const Duration(minutes: 58, seconds: 12)), '58:12');
      expect(Formatters.countdown(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
      // Part of a second still to go reads as a whole one, never 0:00.
      expect(Formatters.countdown(const Duration(milliseconds: 71200)), '1:12');
      expect(Formatters.countdown(const Duration(milliseconds: 300)), '0:01');
      expect(Formatters.countdown(Duration.zero), '0:00');
    });

    test('inWords', () {
      expect(Formatters.inWords(const Duration(seconds: 1)), '1 second');
      expect(Formatters.inWords(const Duration(seconds: 37)), '37 seconds');
      expect(Formatters.inWords(const Duration(minutes: 5)), '5 minutes');
      expect(Formatters.inWords(const Duration(hours: 2)), '2 hours');
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

    final files = [file('b.txt', 10, 3), file('A.txt', 30, 1), file('c.txt', 20, 2)];

    test('by name ignores case', () {
      final sorted = [...files]..sort(const SortOrder(SortField.name).compareFiles);
      expect(sorted.map((f) => f.name), ['A.txt', 'b.txt', 'c.txt']);
    });

    test('by size, largest first', () {
      final sorted = [...files]
        ..sort(const SortOrder(SortField.size, descending: true).compareFiles);
      expect(sorted.map((f) => f.size), [30, 20, 10]);
    });

    test('by date', () {
      final sorted = [...files]..sort(const SortOrder(SortField.modified).compareFiles);
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
          for (final name in ['c.pdf', 'a.pdf', 'b.pdf']) (file(name, yesterday), today),
        ],
        added: [for (var i = 1; i <= 5; i++) file('added $i.pdf', DateTime(2026, 9, i))],
        limit: 4,
      );
      expect(entries.map((e) => e.file.name), ['a.pdf', 'b.pdf', 'c.pdf', 'added 5.pdf']);
    });
  });

  group('TelegramException', () {
    test('reads flood waits in both spellings', () {
      expect(const TelegramException(420, 'FLOOD_WAIT_37').retryAfterSeconds, 37);
      expect(
        const TelegramException(429, 'Too Many Requests: retry after 12').retryAfterSeconds,
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
      for (final f in [folder('Work', null), folder('Invoices', 'Work')]) f.id: f,
    };

    test('names the folders from the top down', () {
      expect(locationOf(byId, 'Invoices'), 'Work › Invoices');
      expect(locationOf(byId, 'Invoices', fromRoot: true), 'Files › Work › Invoices');
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

  group('Preferences', () {
    test('rememberSentTo keeps the newest first, once each, and five at most', () async {
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
    });
  });
}
