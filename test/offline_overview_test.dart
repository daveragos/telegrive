import 'package:flutter_test/flutter_test.dart';
import 'package:telegrive/core/files/file_kind.dart';
import 'package:telegrive/features/drive/domain/drive_models.dart';
import 'package:telegrive/features/offline/data/offline_sync.dart';
import 'package:telegrive/features/transfers/data/transfer_queue.dart';
import 'package:telegrive/features/transfers/domain/transfer_wait.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';
import 'package:telegrive/infrastructure/network/network_status.dart';

final _now = DateTime(2026, 10, 4, 9);

DriveFile _file(String id, int size, {String? folderId = 'trips'}) => DriveFile(
  id: id,
  folderId: folderId,
  name: '$id.jpg',
  mimeType: 'image/jpeg',
  kind: FileKind.image,
  size: size,
  createdAt: _now,
  modifiedAt: _now,
  partCount: 1,
  starred: false,
);

final _trips = DriveFolder(
  id: 'trips',
  parentId: null,
  name: 'Trips',
  createdAt: _now,
  modifiedAt: _now,
);

/// A copy of [fileId] on its way to the offline store.
TransferItem _transfer(
  String id,
  String fileId, {
  required TransferStatus status,
  int total = 200,
  int done = 0,
  double speed = 0,
  TransferWait? wait,
}) => TransferItem(
  TransferRow(
    id: id,
    kind: TransferKind.download,
    status: status,
    name: '$fileId.jpg',
    mimeType: 'image/jpeg',
    fileId: fileId,
    ownsSource: false,
    wifiOnly: wait is WaitingForWifi,
    totalBytes: total,
    doneBytes: done,
    partCount: 1,
    completedParts: 0,
    createdAt: _now,
    origin: TransferOrigin.save,
    saveTo: SaveTarget.offline,
  ),
  bytesPerSecond: speed,
  wait: wait,
);

void main() {
  group('OfflineOverview.compute', () {
    // Trips wants three photos: one is on the phone, one is downloading and
    // one failed. The report was pinned on its own later, and is kept.
    final a = _file('a', 100);
    final b = _file('b', 200);
    final c = _file('c', 300);
    final report = _file('report', 10, folderId: null);
    final pins = [
      OfflinePinRow(itemId: 'trips', isFolder: true, pinnedAt: _now),
      OfflinePinRow(
        itemId: 'report',
        isFolder: false,
        pinnedAt: _now.add(const Duration(minutes: 5)),
      ),
    ];
    const copies = {
      'a': OfflineCopyRow(fileId: 'a', path: '/offline/a/a.jpg', size: 100),
      'report': OfflineCopyRow(fileId: 'report', path: '/offline/report/report.jpg', size: 10),
    };

    OfflineOverview compute(
      List<TransferItem> transfers, {
      List<OfflinePinRow>? only,
      Map<String, OfflineCopyRow>? kept,
    }) => OfflineOverview.compute(
      pins: only ?? pins,
      wantedByPin: {
        'trips': [a, b, c],
        'report': [report],
      },
      copies: kept ?? copies,
      offlineTransfers: transfers,
      folders: {'trips': _trips},
      files: {'report': report},
    );

    final running = _transfer('t-b', 'b', status: TransferStatus.running, done: 50, speed: 10);
    final failed = _transfer('t-c', 'c', status: TransferStatus.failed, total: 300);

    test('counts copies, what is downloading and what failed', () {
      final overview = compute([running, failed]);

      expect(overview.keptFiles, 2);
      expect(overview.keptBytes, 110);
      expect(overview.downloading, 1);
      expect(overview.downloadingLeft, 150);
      expect(overview.speed, 10);
      expect(overview.waiting, 0);
      expect(overview.paused, 0);
      expect(overview.files, 3);
      // What is kept or on its way, by size: 110 + 50 of 110 + 200.
      expect(overview.progress, closeTo(160 / 310, 1e-9));
    });

    test('lists each pin, newest first, with what its row says', () {
      final [first, second] = compute([running, failed]).pins;

      expect(first.file, report);
      expect(first.name, 'report.jpg');
      expect(first.wanted, 1);
      expect(first.kept, 1);
      expect(first.keptBytes, 10);
      expect(first.failedTransferIds, isEmpty);

      expect(second.folder, _trips);
      expect(second.wanted, 3);
      expect(second.bytes, 600);
      expect(second.kept, 1);
      expect(second.keptBytes, 100);
      expect(second.downloading, 1);
      expect(second.leftBytes, 150);
      expect(second.failedTransferIds, ['t-c']);
    });

    test('a copy held for Wi-Fi waits, and a paused one is paused', () {
      final overview = compute([
        _transfer('t-b', 'b', status: TransferStatus.queued, wait: const WaitingForWifi()),
        _transfer('t-c', 'c', status: TransferStatus.paused, total: 300, done: 100),
      ]);
      final trips = overview.pins.last;

      expect(overview.downloading, 0);
      expect(overview.waitingTransferIds, ['t-b']);
      expect(overview.waitingLeft, 200);
      expect(overview.paused, 1);
      expect(overview.pausedLeft, 200);
      expect(trips.waiting, 1);
      expect(trips.paused, 1);
      expect(trips.leftBytes, 400);
      expect(trips.failedTransferIds, isEmpty);
    });

    test('a copy waiting for room on the phone moves nothing, and counts apart', () {
      final overview = compute([
        running,
        _transfer(
          't-c',
          'c',
          status: TransferStatus.queued,
          total: 300,
          done: 100,
          speed: 5,
          wait: const WaitingForRoom(400, 50),
        ),
      ]);
      final trips = overview.pins.last;

      expect(overview.downloading, 1);
      expect(overview.downloadingLeft, 150);
      expect(overview.speed, 10);
      expect(overview.needRoom, 1);
      expect(overview.needRoomLeft, 200);
      expect(overview.files, 4);
      expect(trips.downloading, 1);
      expect(trips.needRoom, 1);
      expect(trips.leftBytes, 350);
    });

    test('a transfer on its way speaks for its file over one that failed', () {
      final overview = compute([
        failed,
        _transfer('t-c2', 'c', status: TransferStatus.queued, total: 300),
      ]);

      expect(overview.pins.last.failedTransferIds, isEmpty);
      expect(overview.pins.last.downloading, 1);
    });

    test('a file nothing is bringing yet counts as still to come', () {
      final trips = compute(const []).pins.last;

      expect(trips.kept, 1);
      expect(trips.downloading, 0);
      expect(trips.leftBytes, 500);
    });

    test('a file with a copy is kept, whether or not its transfer has left the queue', () {
      // The copy is written first; the finished transfer follows it out.
      final withB = {
        ...copies,
        'b': const OfflineCopyRow(fileId: 'b', path: '/offline/b/b.jpg', size: 200),
      };
      final finishing = _transfer('t-b', 'b', status: TransferStatus.running, done: 200);

      for (final transfers in [const <TransferItem>[], [finishing]]) {
        final overview = compute(transfers, kept: withB);

        expect(overview.keptFiles, 3);
        expect(overview.keptBytes, 310);
        expect(overview.downloading, 0);
        expect(overview.files, 3);
        expect(overview.progress, 1);
        expect(overview.pins.last.kept, 2);
        expect(overview.pins.last.downloading, 0);
      }
    });

    test('a pin whose folder left the drive is left out', () {
      final overview = OfflineOverview.compute(
        pins: pins,
        wantedByPin: const {},
        copies: copies,
        offlineTransfers: const [],
        folders: const {},
        files: {'report': report},
      );

      expect([for (final pin in overview.pins) pin.name], ['report.jpg']);
    });
  });

  group('OfflineSync.allowed', () {
    const wifi = NetworkState(online: true, metered: false);
    const mobile = NetworkState(online: true, metered: true);
    const none = NetworkState(online: false, metered: false);

    test('with Only over Wi-Fi on, copies download on Wi-Fi alone', () {
      expect(OfflineSync.allowed(wifiOnly: true, network: mobile), isFalse);
      expect(OfflineSync.allowed(wifiOnly: true, network: none), isFalse);
      expect(OfflineSync.allowed(wifiOnly: true, network: wifi), isTrue);
    });

    test('with it off, any network will do', () {
      expect(OfflineSync.allowed(wifiOnly: false, network: mobile), isTrue);
      expect(OfflineSync.allowed(wifiOnly: false, network: wifi), isTrue);
      expect(OfflineSync.allowed(wifiOnly: false, network: none), isTrue);
    });
  });
}
