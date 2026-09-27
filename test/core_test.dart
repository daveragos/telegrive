import 'package:flutter_test/flutter_test.dart';
import 'package:telegrive/core/files/file_kind.dart';
import 'package:telegrive/core/format/formatters.dart';
import 'package:telegrive/features/drive/domain/drive_models.dart';
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
}
