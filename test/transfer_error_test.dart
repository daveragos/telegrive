import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:telegrive/features/drive/data/channel_messenger.dart';
import 'package:telegrive/features/drive/data/drive_repository.dart';
import 'package:telegrive/features/transfers/domain/transfer_error.dart';
import 'package:telegrive/infrastructure/storage/device_storage.dart';
import 'package:telegrive/infrastructure/telegram/telegram_exception.dart';

void main() {
  group('describeTransferError', () {
    const connection = 'Lost the connection to Telegram. Retry when you\'re back online.';

    test('a full phone says so, however it is reported', () {
      expect(
        describeTransferError(
          const FileSystemException('x', 'p', OSError('No space left on device', 28)),
        ),
        'Not enough space on this phone.',
      );
      expect(
        describeTransferError(
          PlatformException(code: 'save_failed', message: 'ENOSPC (No space left on device)'),
        ),
        'Not enough space on this phone.',
      );
    });

    test('a file that is gone or can no longer be read', () {
      expect(
        describeTransferError(const PathNotFoundException('p', OSError('No such file', 2))),
        'The original file is no longer available.',
      );
      expect(
        describeTransferError(const FileSystemException('x', 'p', OSError('No such file', 2))),
        'The original file is no longer available.',
      );
      expect(
        describeTransferError(const FileSystemException('x', 'p', OSError('Permission denied', 13))),
        'Telegrive can no longer read this file.',
      );
      expect(
        describeTransferError(const FileSystemException('x', 'p', OSError('I/O error', 5))),
        'Couldn\'t read or write the file on this phone.',
      );
    });

    test('a lost connection, in any of its forms', () {
      expect(describeTransferError(const SocketException('Network is unreachable')), connection);
      expect(describeTransferError(TimeoutException('slow')), connection);
      expect(describeTransferError(const TelegramException(408, 'Request timeout')), connection);
    });

    test('Telegram and drive errors keep their own sentences', () {
      expect(
        describeTransferError(const TelegramException(400, 'FILE_PARTS_INVALID')),
        'Telegram refused the file size.',
      );
      expect(
        describeTransferError(const DriveException('This file is no longer in your drive.')),
        'This file is no longer in your drive.',
      );
    });

    test('saving to the phone that failed says where', () {
      expect(
        describeTransferError(PlatformException(code: 'save_failed', message: 'denied')),
        'Couldn\'t save it to ${DeviceStorage.location}.',
      );
    });

    test('cancelled, stored sentences, and anything else', () {
      expect(describeTransferError(const SendCancelled()), 'Cancelled.');
      expect(
        describeTransferError('Not enough space on this phone.'),
        'Not enough space on this phone.',
      );
      expect(describeTransferError(null), 'Something went wrong.');
      expect(describeTransferError(Object()), 'Something went wrong.');
      expect(describeTransferError(StateError('errno = 28')), 'Something went wrong.');
    });
  });

  group('telegramWaitOf', () {
    test('reads both spellings of a flood wait', () {
      expect(
        telegramWaitOf(const TelegramException(420, 'FLOOD_WAIT_37')),
        const Duration(seconds: 37),
      );
      expect(
        telegramWaitOf(const TelegramException(429, 'Too Many Requests: retry after 12')),
        const Duration(seconds: 12),
      );
    });

    test('waits half a minute when Telegram gives no time', () {
      expect(
        telegramWaitOf(const TelegramException(429, 'Too Many Requests')),
        const Duration(seconds: 30),
      );
    });

    test('is null for anything that is not a flood wait', () {
      expect(telegramWaitOf(const TelegramException(400, 'MESSAGE_ID_INVALID')), isNull);
      expect(telegramWaitOf(const DriveException('Stopped.')), isNull);
    });
  });
}
