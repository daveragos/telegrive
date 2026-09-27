import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:telegrive/core/files/file_kind.dart';
import 'package:telegrive/features/drive/data/drive_session.dart';
import 'package:telegrive/features/transfers/data/transfer_policy.dart';
import 'package:telegrive/features/transfers/data/transfer_queue.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';
import 'package:telegrive/infrastructure/network/network_status.dart';
import 'package:telegrive/infrastructure/telegram/telegram_client.dart';

import 'support/fake_telegram.dart';

const _wifi = NetworkState(online: true, metered: false);
const _mobile = NetworkState(online: true, metered: true);
const _mb = 1 << 20;
final _now = DateTime(2026, 9, 27, 12);

/// Hands out unfetched files, and fetches any of them to [path] on request,
/// remembering which were asked for.
class _FakeTelegram extends FakeTelegram {
  _FakeTelegram(this.path);

  final String path;
  final List<int> downloads = [];

  @override
  Future<td.TdObject?> answer(td.TdFunction function) async {
    switch (function) {
      case td.GetFile(:final fileId):
        return tdFile(fileId);
      case td.DownloadFile(:final fileId):
        downloads.add(fileId);
        return tdFile(fileId, path: path, downloaded: true);
      default:
        return null;
    }
  }
}

/// A phone on mobile data, until the test moves it.
class _TestNetwork extends NetworkStatus {
  @override
  NetworkState build() => _mobile;

  void set(NetworkState next) => state = next;
}

TransferRow _row({bool wifiOnly = false, String fileId = 'report'}) => TransferRow(
  id: fileId,
  kind: TransferKind.download,
  status: TransferStatus.queued,
  name: '$fileId.pdf',
  mimeType: 'application/pdf',
  fileId: fileId,
  ownsSource: false,
  wifiOnly: wifiOnly,
  totalBytes: 10,
  doneBytes: 0,
  partCount: 1,
  completedParts: 0,
  createdAt: _now,
  origin: TransferOrigin.manual,
);

void main() {
  group('shouldAsk', () {
    test('asks from 50 MB on mobile data', () {
      expect(TransferPolicy.shouldAsk(network: _mobile, bytes: 50 * _mb - 1), isFalse);
      expect(TransferPolicy.shouldAsk(network: _mobile, bytes: 50 * _mb), isTrue);
    });

    test('never asks on an unmetered network, or before the phone has said', () {
      expect(TransferPolicy.shouldAsk(network: _wifi, bytes: 5 * 1024 * _mb), isFalse);
      expect(
        TransferPolicy.shouldAsk(network: NetworkState.unknown, bytes: 5 * 1024 * _mb),
        isFalse,
      );
    });
  });

  group('wifiOnlyFor', () {
    test('from 200 MB a transfer waits for Wi-Fi when big ones do', () {
      expect(TransferPolicy.wifiOnlyFor(199 * _mb, bigWaitForWifi: true), isFalse);
      expect(TransferPolicy.wifiOnlyFor(200 * _mb, bigWaitForWifi: true), isTrue);
    });

    test('with the setting off, no size waits', () {
      expect(TransferPolicy.wifiOnlyFor(200 * _mb, bigWaitForWifi: false), isFalse);
      expect(TransferPolicy.wifiOnlyFor(2 * 1024 * _mb, bigWaitForWifi: false), isFalse);
    });
  });

  group('mayRun', () {
    test('runs when nothing holds it', () {
      expect(TransferPolicy.mayRun(_row(), now: _now, network: _mobile), isTrue);
      expect(TransferPolicy.mayRun(_row(wifiOnly: true), now: _now, network: _wifi), isTrue);
    });

    test("waits out Telegram's pause, and not a moment longer", () {
      bool may(DateTime notBefore) =>
          TransferPolicy.mayRun(_row(), now: _now, network: _wifi, notBefore: notBefore);
      expect(may(_now.add(const Duration(seconds: 1))), isFalse);
      expect(may(_now), isTrue);
      expect(may(_now.subtract(const Duration(seconds: 1))), isTrue);
    });

    test('a row that waits for Wi-Fi does not start on mobile data', () {
      expect(TransferPolicy.mayRun(_row(wifiOnly: true), now: _now, network: _mobile), isFalse);
      expect(TransferPolicy.mayRun(_row(), now: _now, network: _mobile), isTrue);
    });

    test('before the phone has said, the network counts as unmetered', () {
      expect(
        TransferPolicy.mayRun(_row(wifiOnly: true), now: _now, network: NetworkState.unknown),
        isTrue,
      );
    });

    test('nothing starts without room for it', () {
      expect(
        TransferPolicy.mayRun(_row(), now: _now, network: _wifi, hasRoom: false),
        isFalse,
      );
    });
  });

  group('the queue asks before it starts a row', () {
    late Directory dir;
    late AppDatabase db;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('telegrive_policy');
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
      await dir.delete(recursive: true);
    });

    Future<void> addFile(String id, int tdFileId) => db.upsertFilePart(
      DriveFilesCompanion.insert(
        id: id,
        name: '$id.pdf',
        mimeType: 'application/pdf',
        kind: FileKind.document,
        size: 10,
        createdAt: _now,
        modifiedAt: _now,
        partCount: const Value(1),
      ),
      FilePartsCompanion.insert(
        fileId: id,
        partIndex: 0,
        messageId: tdFileId,
        tdFileId: tdFileId,
        size: 10,
      ),
    );

    Future<void> until(bool Function() condition) async {
      for (var i = 0; i < 200 && !condition(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(condition(), isTrue);
    }

    test('a download that waits for Wi-Fi stays queued on mobile data, then goes', () async {
      final fetched = File('${dir.path}/report.pdf')..writeAsStringSync('0123456789');
      await addFile('plain', 7);
      await addFile('held', 8);
      // Saved before the queue loads, the way rows from an earlier run are.
      await db.saveTransfers([
        _row(fileId: 'plain'),
        _row(fileId: 'held', wifiOnly: true),
      ]);

      final telegram = _FakeTelegram(fetched.path);
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          telegramClientProvider.overrideWithValue(telegram),
          driveSessionProvider.overrideWith(TestSession.new),
          networkStatusProvider.overrideWith(_TestNetwork.new),
        ],
      );
      addTearDown(container.dispose);
      container.listen(transferQueueProvider, (_, _) {});
      TransferStatus? statusOf(String id) =>
          container.read(transferQueueProvider).byId(id)?.status;

      await until(() => statusOf('plain') == TransferStatus.completed);
      expect(telegram.downloads, [7]);
      expect(statusOf('held'), TransferStatus.queued);

      (container.read(networkStatusProvider.notifier) as _TestNetwork).set(_wifi);
      await until(() => statusOf('held') == TransferStatus.completed);
      expect(telegram.downloads, [7, 8]);
    });
  });
}
