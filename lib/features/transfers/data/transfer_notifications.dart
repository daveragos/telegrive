import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../../core/files/file_kind.dart';
import '../../../core/format/formatters.dart';
import '../../../infrastructure/database/app_database.dart';
import '../../../infrastructure/notifications/app_notifications.dart';
import '../../../infrastructure/storage/device_storage.dart';
import '../domain/transfer_error.dart';
import 'transfer_queue.dart';

/// What one notification says about a batch of transfers that finished
/// while Telegrive was in the background: what went where, or why some
/// didn't, with Open for a single file the phone can open and Retry when
/// anything failed. Copies made from chats are worded apart from uploads,
/// since Telegram makes them and nothing goes up.
@immutable
class TransferSummary {
  const TransferSummary({
    required this.title,
    required this.body,
    required this.payload,
    this.actionId,
    this.actionLabel,
  });

  final String title;
  final String body;

  /// What a tap on the notification opens: the file, for a single one the
  /// phone can open, otherwise Transfers.
  final String payload;
  final String? actionId;
  final String? actionLabel;

  /// What follows the count of copies made from chats, and what the body
  /// says about them, in the words Transfers uses.
  static const String _fromTelegram = ' from Telegram';
  static const String _copiedInside = 'Copied inside Telegram.';

  /// The summary of [items] that finished at [since] or later, or null when
  /// none did. Photo backup has its own place and its own reminder, and a
  /// cancelled transfer was the person's own doing, so neither is told.
  static TransferSummary? of(List<TransferItem> items, DateTime since) {
    final batch = [
      for (final item in items)
        if (item.origin != TransferOrigin.backup &&
            (item.status == TransferStatus.completed ||
                item.status == TransferStatus.failed) &&
            !(item.row.finishedAt?.isBefore(since) ?? true))
          item,
    ];
    if (batch.isEmpty) return null;
    final failed = [
      for (final item in batch)
        if (item.status == TransferStatus.failed) item,
    ];
    // One sentence speaks for every failure; Transfers has each one's.
    String why() => describeTransferError(failed.first.row.error);

    if (failed.length == batch.length) {
      return TransferSummary(
        title: '${Formatters.count(failed.length, 'transfer')} didn\'t finish',
        body: why(),
        payload: TransferNotifications.listPayload,
        actionId: TransferNotifications.retryAction,
        actionLabel: 'Retry',
      );
    }

    final uploads = [
      for (final item in batch)
        if (item.kind == TransferKind.upload && item.origin != TransferOrigin.fromChat) item,
    ];
    final copies = [
      for (final item in batch)
        if (item.origin == TransferOrigin.fromChat) item,
    ];
    final saves = [
      for (final item in batch)
        if (item.origin == TransferOrigin.save) item,
    ];
    final downloads = [
      for (final item in batch)
        if (item.kind == TransferKind.download && item.origin != TransferOrigin.save) item,
    ];
    final groups = <_Group>[
      if (uploads.isNotEmpty) (verb: 'Uploaded', items: uploads, tail: ''),
      if (copies.isNotEmpty) (verb: 'Saved', items: copies, tail: _fromTelegram),
      if (saves.isNotEmpty) (verb: 'Saved', items: saves, tail: ''),
      if (downloads.isNotEmpty) (verb: 'Downloaded', items: downloads, tail: ''),
    ];

    if (failed.isNotEmpty) {
      return TransferSummary(
        title: _sentence(groups),
        body: '${Formatters.number(failed.length)} didn\'t finish: ${why()}',
        payload: TransferNotifications.listPayload,
        actionId: TransferNotifications.retryAction,
        actionLabel: 'Retry',
      );
    }

    final uploaded = uploads.fold<int>(0, (sum, t) => sum + t.row.totalBytes);
    final inDrive = '${Formatters.bytes(uploaded)} in your drive';
    final place = _placeOf(saves);

    if (groups.length > 1) {
      return TransferSummary(
        title: _sentence(groups),
        body: [
          if (uploads.isNotEmpty) '$inDrive.',
          if (copies.isNotEmpty) _copiedInside,
          if (saves.isNotEmpty) 'Saved files are in $place.',
        ].join(' '),
        payload: TransferNotifications.listPayload,
      );
    }

    if (batch.length == 1) {
      final item = batch.single;
      if (copies.isNotEmpty) {
        return TransferSummary(
          title: 'Saved ${item.name}$_fromTelegram',
          body: _copiedInside,
          payload: TransferNotifications.listPayload,
        );
      }
      if (item.kind == TransferKind.upload) {
        return TransferSummary(
          title: 'Uploaded ${item.name}',
          body: inDrive,
          payload: TransferNotifications.listPayload,
        );
      }
      // A download, or a save to the phone's files, has a path to open; a
      // save to the gallery has none of its own.
      final opens = item.row.resultPath != null;
      final saved = item.origin == TransferOrigin.save;
      return TransferSummary(
        title: '${saved ? 'Saved' : 'Downloaded'} ${item.name}',
        body: saved ? 'In $place' : 'Tap to open it.',
        payload: opens
            ? TransferNotifications.openPayload(item.id)
            : TransferNotifications.listPayload,
        actionId: opens ? TransferNotifications.openAction : null,
        actionLabel: opens ? 'Open' : null,
      );
    }

    if (uploads.isNotEmpty) {
      return TransferSummary(
        title: 'Uploaded ${Formatters.count(uploads.length, 'file')}',
        body: inDrive,
        payload: TransferNotifications.listPayload,
      );
    }
    if (copies.isNotEmpty) {
      return TransferSummary(
        title: 'Saved ${Formatters.count(copies.length, 'file')}$_fromTelegram',
        body: _copiedInside,
        payload: TransferNotifications.listPayload,
      );
    }
    if (saves.isNotEmpty) {
      final onlyGallery = saves.every((t) => t.row.saveTo == SaveTarget.gallery);
      return TransferSummary(
        title: onlyGallery
            ? 'Saved ${_media(saves)} to your gallery'
            : 'Saved ${Formatters.count(saves.length, 'file')}',
        body: 'In $place',
        payload: TransferNotifications.listPayload,
      );
    }
    return TransferSummary(
      title: 'Downloaded ${Formatters.count(downloads.length, 'file')}',
      body: 'Tap to see them.',
      payload: TransferNotifications.listPayload,
    );
  }

  /// 'Uploaded 3 files and saved 12 from Telegram', or with failures
  /// 'Uploaded 2 of 3 files and saved 10 of 12 from Telegram': the first
  /// group names what was counted, the rest borrow it. A group's tail
  /// follows its count.
  static String _sentence(List<_Group> groups) {
    final parts = <String>[];
    for (final (:verb, :items, :tail) in groups) {
      final first = parts.isEmpty;
      final done = items.where((t) => t.status == TransferStatus.completed).length;
      String counted(int value) =>
          first ? Formatters.count(value, 'file') : Formatters.number(value);
      parts.add(
        '${first ? verb : verb.toLowerCase()} '
        '${done == items.length ? counted(done) : '${Formatters.number(done)} of ${counted(items.length)}'}'
        '$tail',
      );
    }
    if (parts.length == 1) return parts.single;
    return '${parts.take(parts.length - 1).join(', ')} and ${parts.last}';
  }

  /// Where [saves] went, in the words Transfers uses for them. Only
  /// finished saves are placed, and the queue forgets a finished offline
  /// copy, so those never reach a summary.
  static String _placeOf(List<TransferItem> saves) => [
    if (saves.any((t) => t.row.saveTo == SaveTarget.files)) DeviceStorage.location,
    if (saves.any((t) => t.row.saveTo == SaveTarget.gallery)) 'your photos',
  ].join(' and ');

  /// '12 photos', '3 videos' or '15 photos and videos'.
  static String _media(List<TransferItem> saves) {
    final videos = saves.where((t) => t.fileKind == FileKind.video).length;
    if (videos == 0) return Formatters.count(saves.length, 'photo');
    if (videos == saves.length) return Formatters.count(saves.length, 'video');
    return '${Formatters.number(saves.length)} photos and videos';
  }
}

/// Transfers of one kind in a batch: the verb that says what became of
/// them, and what follows their count.
typedef _Group = ({String verb, List<TransferItem> items, String tail});

/// The notifications about the person's own transfers, on the quiet
/// 'Finished transfers' channel: a summary when a batch finishes in the
/// background, 'Transfers paused' after Pause in the shade, and a word
/// when Android pauses everything at its time limit. Their buttons open
/// the app, which then does what they say.
abstract final class TransferNotifications {
  static const String retryAction = 'retry';
  static const String resumeAction = 'resume';
  static const String openAction = 'open';

  /// Opens Transfers.
  static const String listPayload = 'transfers';

  static const String _openPrefix = 'open:';

  /// Opens the result of transfer [id].
  static String openPayload(String id) => '$_openPrefix$id';

  /// The transfer [payload] opens, or null when it opens none.
  static String? openedId(String? payload) {
    if (payload == null || !payload.startsWith(_openPrefix)) return null;
    final id = payload.substring(_openPrefix.length);
    return id.isEmpty ? null : id;
  }

  static AndroidNotificationDetails _details({String? actionId, String? actionLabel}) =>
      AndroidNotificationDetails(
        AppNotifications.transfersDoneChannel,
        'Finished transfers',
        channelDescription: 'Tells you when uploads and downloads finish or pause in the background',
        importance: Importance.low,
        priority: Priority.low,
        playSound: false,
        icon: AppNotifications.icon,
        actions: [
          if (actionId != null && actionLabel != null)
            AndroidNotificationAction(actionId, actionLabel, showsUserInterface: true),
        ],
      );

  /// Posts [summary] in place of the last one.
  static Future<void> showSummary(TransferSummary summary) => AppNotifications.show(
    id: AppNotifications.transfersFinishedId,
    title: summary.title,
    body: summary.body,
    android: _details(actionId: summary.actionId, actionLabel: summary.actionLabel),
    payload: summary.payload,
  );

  /// Says that [count] transfers were paused from the shade, with Resume.
  static Future<void> showPaused(int count) => AppNotifications.show(
    id: AppNotifications.transfersPausedId,
    title: 'Transfers paused',
    body: count == 1
        ? '1 transfer waits where it stopped.'
        : '${Formatters.count(count, 'transfer')} wait where they stopped.',
    android: _details(actionId: resumeAction, actionLabel: 'Resume'),
    payload: listPayload,
  );

  static Future<void> clearPaused() => AppNotifications.cancel(AppNotifications.transfersPausedId);

  /// What the notice says when Android ends the background time for
  /// transfers: what happened, and that opening Telegrive carries on, which
  /// is what gives that time back.
  static const String timedOutTitle = 'Android paused background transfers';
  static const String timedOutBody =
      'Open Telegrive to carry on. Android limits transfers in the background to 6 hours a day.';

  /// Says that Android paused the transfers, the photo backup and the
  /// import at its time limit. A tap opens Transfers, and opening the app
  /// any way at all carries on.
  static Future<void> showTimedOut() => AppNotifications.show(
    id: AppNotifications.transfersTimedOutId,
    title: timedOutTitle,
    body: timedOutBody,
    android: _details(),
    payload: listPayload,
  );

  static Future<void> clearTimedOut() => AppNotifications.cancel(AppNotifications.transfersTimedOutId);
}
