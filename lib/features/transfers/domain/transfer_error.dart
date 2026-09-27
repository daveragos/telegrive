import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart' show PlatformException;

import '../../../infrastructure/storage/device_storage.dart';
import '../../../infrastructure/telegram/telegram_exception.dart';
import '../../drive/data/channel_messenger.dart';
import '../../drive/data/drive_repository.dart';

/// Why a transfer stopped, in one sentence a person can act on. The raw
/// error still goes to the log; this is what the list and Home show, so
/// nobody has to read 'errno = 28'.
String describeTransferError(Object? error) => switch (error) {
  FileSystemException(osError: OSError(errorCode: 28)) => _noSpace,
  PlatformException(:final message?)
      when message.contains('No space left') || message.contains('ENOSPC') =>
    _noSpace,
  PathNotFoundException() || FileSystemException(osError: OSError(errorCode: 2)) =>
    'The original file is no longer available.',
  FileSystemException(osError: OSError(errorCode: 13)) =>
    'Telegrive can no longer read this file.',
  FileSystemException() => 'Couldn\'t read or write the file on this phone.',
  SocketException() || TimeoutException() || TelegramException(code: 408) =>
    'Lost the connection to Telegram. Retry when you\'re back online.',
  TelegramException e => e.friendlyMessage,
  DriveException(:final message) => message,
  SendCancelled() => 'Cancelled.',
  PlatformException(code: 'save_failed') =>
    'Couldn\'t save it to ${DeviceStorage.location}.',
  String message => message,
  _ => 'Something went wrong.',
};

const _noSpace = 'Not enough space on this phone.';

/// How long Telegram asked to be left alone, when [error] is a flood wait.
/// A wait with no time given counts as half a minute.
Duration? telegramWaitOf(Object error) => switch (error) {
  TelegramException(isFloodWait: true, :final retryAfterSeconds) =>
    Duration(seconds: retryAfterSeconds ?? 30),
  _ => null,
};
