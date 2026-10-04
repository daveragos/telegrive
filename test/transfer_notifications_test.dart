import 'package:flutter_test/flutter_test.dart';
import 'package:telegrive/app/launch_action.dart';
import 'package:telegrive/core/files/file_kind.dart';
import 'package:telegrive/features/backup/data/backup_notifications.dart';
import 'package:telegrive/features/backup/data/backup_worker.dart';
import 'package:telegrive/features/transfers/data/transfer_keep_alive.dart';
import 'package:telegrive/features/transfers/data/transfer_notifications.dart';
import 'package:telegrive/features/transfers/data/transfer_queue.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';

const _mb = 1024 * 1024;

final _since = DateTime(2026, 10, 4, 9);

TransferItem _item(
  String name, {
  TransferKind kind = TransferKind.upload,
  TransferOrigin origin = TransferOrigin.manual,
  TransferStatus status = TransferStatus.completed,
  SaveTarget? saveTo,
  String? resultPath,
  String? error,
  int size = _mb,
  DateTime? finishedAt,
}) => TransferItem(
  TransferRow(
    id: 'id-$name',
    kind: kind,
    status: status,
    name: name,
    mimeType: mimeTypeFor(name),
    fileId: 'file-$name',
    ownsSource: false,
    wifiOnly: false,
    totalBytes: size,
    doneBytes: status == TransferStatus.completed ? size : 0,
    partCount: 1,
    completedParts: status == TransferStatus.completed ? 1 : 0,
    createdAt: _since,
    finishedAt: status.isFinished
        ? (finishedAt ?? _since.add(const Duration(minutes: 5)))
        : null,
    origin: origin,
    saveTo: saveTo,
    resultPath: resultPath,
    error: error,
  ),
);

TransferItem _save(
  String name, {
  SaveTarget target = SaveTarget.files,
  TransferStatus status = TransferStatus.completed,
  String? error,
}) => _item(
  name,
  kind: TransferKind.download,
  origin: TransferOrigin.save,
  status: status,
  saveTo: target,
  resultPath: status == TransferStatus.completed && target == SaveTarget.files
      ? '/storage/emulated/0/Download/Telegrive/$name'
      : null,
  error: error,
);

TransferItem _copy(
  String name, {
  TransferStatus status = TransferStatus.completed,
  String? error,
}) => _item(name, origin: TransferOrigin.fromChat, status: status, error: error);

void main() {
  group('TransferSummary.of', () {
    test('one upload is named, with what it adds to the drive', () {
      final summary = TransferSummary.of([
        _item('Wedding highlights 4K.mp4', size: 1434 * _mb),
      ], _since)!;
      expect(summary.title, 'Uploaded Wedding highlights 4K.mp4');
      expect(summary.body, '1.4 GB in your drive');
      expect(summary.payload, 'transfers');
      expect(summary.actionId, isNull);
    });

    test('several uploads are counted', () {
      final summary = TransferSummary.of([
        _item('a.pdf', size: 2 * _mb),
        _item('b.pdf', size: 3 * _mb),
        _item('c.pdf', size: 5 * _mb),
      ], _since)!;
      expect(summary.title, 'Uploaded 3 files');
      expect(summary.body, '10.0 MB in your drive');
      expect(summary.actionId, isNull);
    });

    test('a single save to files says where it is, and opens it', () {
      final summary = TransferSummary.of([_save('Simien trek.png')], _since)!;
      expect(summary.title, 'Saved Simien trek.png');
      expect(summary.body, 'In Download › Telegrive');
      expect(summary.payload, 'open:id-Simien trek.png');
      expect(summary.actionId, 'open');
      expect(summary.actionLabel, 'Open');
    });

    test('a single download of your own opens too', () {
      final summary = TransferSummary.of([
        _item(
          'report.pdf',
          kind: TransferKind.download,
          resultPath: '/data/telegrive/report.pdf',
        ),
      ], _since)!;
      expect(summary.title, 'Downloaded report.pdf');
      expect(summary.body, 'Tap to open it.');
      expect(summary.payload, 'open:id-report.pdf');
      expect(summary.actionLabel, 'Open');
    });

    test('saves to the gallery say so', () {
      final summary = TransferSummary.of([
        for (var i = 0; i < 12; i++) _save('IMG_$i.jpg', target: SaveTarget.gallery),
      ], _since)!;
      expect(summary.title, 'Saved 12 photos to your gallery');
      expect(summary.body, 'In your photos');
      expect(summary.payload, 'transfers');
      expect(summary.actionId, isNull);
    });

    test('several saves to files and the gallery name both places', () {
      final summary = TransferSummary.of([
        _save('notes.txt'),
        _save('IMG_1.jpg', target: SaveTarget.gallery),
      ], _since)!;
      expect(summary.title, 'Saved 2 files');
      expect(summary.body, 'In Download › Telegrive and your photos');
    });

    test('uploads and saves together are one sentence', () {
      final summary = TransferSummary.of([
        _item('a.pdf'),
        _item('b.pdf'),
        _item('c.pdf'),
        for (var i = 0; i < 12; i++) _save('doc $i.pdf'),
      ], _since)!;
      expect(summary.title, 'Uploaded 3 files and saved 12');
      expect(summary.body, '3.0 MB in your drive. Saved files are in Download › Telegrive.');
      expect(summary.payload, 'transfers');
    });

    test('a partial failure counts what went and says why the rest didn\'t', () {
      final summary = TransferSummary.of([
        _item('a.pdf'),
        _item('b.pdf'),
        _item(
          'c.pdf',
          status: TransferStatus.failed,
          error: 'Not enough space on this phone.',
        ),
      ], _since)!;
      expect(summary.title, 'Uploaded 2 of 3 files');
      expect(summary.body, '1 didn\'t finish: Not enough space on this phone.');
      expect(summary.actionId, 'retry');
      expect(summary.actionLabel, 'Retry');
      expect(summary.payload, 'transfers');
    });

    test('a failed save among uploads counts in its own group', () {
      final summary = TransferSummary.of([
        _item('a.pdf'),
        _save('b.pdf'),
        _save(
          'c.pdf',
          status: TransferStatus.failed,
          error: 'Lost the connection to Telegram. Retry when you\'re back online.',
        ),
      ], _since)!;
      expect(summary.title, 'Uploaded 1 file and saved 1 of 2');
      expect(
        summary.body,
        '1 didn\'t finish: Lost the connection to Telegram. Retry when you\'re back online.',
      );
    });

    test('copies from chats are saved, never uploaded', () {
      final summary = TransferSummary.of([
        for (var i = 0; i < 12; i++) _copy('IMG_$i.jpg'),
      ], _since)!;
      expect(summary.title, 'Saved 12 files from Telegram');
      expect(summary.body, 'Copied inside Telegram.');
      expect(summary.payload, 'transfers');
      expect(summary.actionId, isNull);
      expect(
        TransferSummary.of([_copy('IMG_1.jpg')], _since)!.title,
        'Saved IMG_1.jpg from Telegram',
      );
    });

    test('copies and uploads together keep their own verbs', () {
      final summary = TransferSummary.of([
        _item('a.pdf', size: 2 * _mb),
        _item('b.pdf', size: 3 * _mb),
        _item('c.pdf', size: 5 * _mb),
        for (var i = 0; i < 12; i++) _copy('IMG_$i.jpg'),
      ], _since)!;
      expect(summary.title, 'Uploaded 3 files and saved 12 from Telegram');
      expect(summary.body, '10.0 MB in your drive. Copied inside Telegram.');
      expect(summary.actionId, isNull);
    });

    test('copies and saves to the phone are told apart', () {
      final summary = TransferSummary.of([
        _copy('a.jpg'),
        _copy('b.jpg'),
        _save('notes.txt'),
      ], _since)!;
      expect(summary.title, 'Saved 2 files from Telegram and saved 1');
      expect(
        summary.body,
        'Copied inside Telegram. Saved files are in Download › Telegrive.',
      );
    });

    test('a failed copy counts in its own group and offers Retry', () {
      final summary = TransferSummary.of([
        _copy('a.jpg'),
        _copy('b.jpg'),
        _copy(
          'c.jpg',
          status: TransferStatus.failed,
          error: 'Lost the connection to Telegram. Retry when you\'re back online.',
        ),
      ], _since)!;
      expect(summary.title, 'Saved 2 of 3 files from Telegram');
      expect(
        summary.body,
        '1 didn\'t finish: Lost the connection to Telegram. Retry when you\'re back online.',
      );
      expect(summary.actionId, 'retry');
      expect(summary.actionLabel, 'Retry');
      expect(summary.payload, 'transfers');

      final mixed = TransferSummary.of([
        _item('a.pdf'),
        _copy('b.jpg'),
        _copy('c.jpg', status: TransferStatus.failed),
      ], _since)!;
      expect(mixed.title, 'Uploaded 1 file and saved 1 of 2 from Telegram');
    });

    test('when nothing finished, it says how many didn\'t and why', () {
      final summary = TransferSummary.of([
        for (final name in ['a.pdf', 'b.pdf', 'c.pdf'])
          _item(
            name,
            status: TransferStatus.failed,
            error: 'The original file is no longer available.',
          ),
      ], _since)!;
      expect(summary.title, '3 transfers didn\'t finish');
      expect(summary.body, 'The original file is no longer available.');
      expect(summary.actionId, 'retry');
    });

    test('photo backup is left out', () {
      final summary = TransferSummary.of([
        _item('IMG_1.jpg', origin: TransferOrigin.backup),
        _item('IMG_2.jpg', origin: TransferOrigin.backup, status: TransferStatus.failed),
        _item('report.pdf'),
      ], _since)!;
      expect(summary.title, 'Uploaded report.pdf');
      expect(
        TransferSummary.of([_item('IMG_1.jpg', origin: TransferOrigin.backup)], _since),
        isNull,
      );
    });

    test('transfers that finished before the batch began are left out', () {
      final earlier = _since.subtract(const Duration(minutes: 1));
      final summary = TransferSummary.of([
        _item('old.pdf', finishedAt: earlier),
        _item('old failure.pdf', status: TransferStatus.failed, finishedAt: earlier),
        _item('new.pdf'),
      ], _since)!;
      expect(summary.title, 'Uploaded new.pdf');
      expect(summary.actionId, isNull);
    });

    test('nothing finished, nothing to say', () {
      expect(TransferSummary.of(const [], _since), isNull);
      expect(
        TransferSummary.of([
          _item('running.pdf', status: TransferStatus.running),
          _item('paused.pdf', status: TransferStatus.paused),
          _item('cancelled.pdf', status: TransferStatus.cancelled),
        ], _since),
        isNull,
      );
    });
  });

  group('LaunchRequest.fromNotification', () {
    test('the backup reminder and its button back up', () {
      expect(
        LaunchRequest.fromNotification('backup', null),
        const LaunchRequest(LaunchAction.backup),
      );
      expect(
        LaunchRequest.fromNotification('any', 'back_up_now'),
        const LaunchRequest(LaunchAction.backup),
      );
    });

    test('Open, and a tap on a single file, open that transfer', () {
      const open = LaunchRequest(LaunchAction.openTransfer, transferId: 'abc');
      expect(LaunchRequest.fromNotification('open:abc', 'open'), open);
      expect(LaunchRequest.fromNotification('open:abc', null), open);
    });

    test('a tap on a summary shows Transfers', () {
      expect(
        LaunchRequest.fromNotification('transfers', null),
        const LaunchRequest(LaunchAction.transfers),
      );
    });

    test('Retry and Resume say so whatever the payload', () {
      expect(
        LaunchRequest.fromNotification('x', 'retry'),
        const LaunchRequest(LaunchAction.retryFailed),
      );
      expect(
        LaunchRequest.fromNotification('transfers', 'resume'),
        const LaunchRequest(LaunchAction.resumePaused),
      );
    });

    test('anything else is a plain launch', () {
      expect(LaunchRequest.fromNotification(null, null), isNull);
      expect(LaunchRequest.fromNotification('something', null), isNull);
      expect(LaunchRequest.fromNotification('open:', null), isNull);
      expect(LaunchRequest.fromNotification(null, 'unknown'), isNull);
    });
  });

  group('the ongoing notification\'s buttons', () {
    test('Pause while an upload you started runs', () {
      final buttons = TransferKeepAlive.buttons(
        TransfersState([
          _item('a.pdf', status: TransferStatus.running),
          _item('IMG_1.jpg', origin: TransferOrigin.backup, status: TransferStatus.running),
        ]),
      );
      expect(buttons.map((b) => (b.id, b.text)), [('pause', 'Pause')]);
    });

    test('none while only photo backup runs', () {
      final buttons = TransferKeepAlive.buttons(
        TransfersState([
          _item('IMG_1.jpg', origin: TransferOrigin.backup, status: TransferStatus.running),
          _item('done.pdf'),
        ]),
      );
      expect(buttons, isEmpty);
    });
  });

  group('BackupWorker.shouldRemind', () {
    final now = DateTime(2026, 10, 4, 12);
    int at(Duration offset) => now.add(offset).millisecondsSinceEpoch;

    test('not while a swiped-away reminder is still put off', () {
      expect(
        BackupWorker.shouldRemind(
          count: 12,
          remindAfterMillis: at(const Duration(hours: 3)),
          now: now,
        ),
        isFalse,
      );
    });

    test('again once the day is over, for the same photos', () {
      expect(
        BackupWorker.shouldRemind(
          count: 12,
          remindAfterMillis: at(const Duration(hours: -1)),
          now: now,
        ),
        isTrue,
      );
    });

    test('not twice for the same photos', () {
      expect(BackupWorker.shouldRemind(count: 12, notifiedCount: 12, now: now), isFalse);
      expect(BackupWorker.shouldRemind(count: 13, notifiedCount: 12, now: now), isTrue);
    });

    test('not when nothing is new', () {
      expect(BackupWorker.shouldRemind(count: 0, now: now), isFalse);
    });
  });

  group('the new photos reminder', () {
    test('asks for a tap while backup waits for the app', () {
      expect(
        BackupNotifications.newMediaBody(unattended: false, wifiOnly: true),
        'Tap to back them up to Telegram.',
      );
    });

    test('says when they go up once backup runs on its own', () {
      expect(
        BackupNotifications.newMediaBody(unattended: true, wifiOnly: true),
        'They go up on their own next time the phone charges on Wi-Fi. Tap to back up now.',
      );
      expect(
        BackupNotifications.newMediaBody(unattended: true, wifiOnly: false),
        'They go up on their own next time the phone charges. Tap to back up now.',
      );
    });
  });
}
