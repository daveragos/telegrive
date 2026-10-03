import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:drift/drift.dart' show TableUpdateQuery;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../infrastructure/database/app_database.dart';
import '../../../infrastructure/network/network_status.dart';
import '../../../infrastructure/storage/preferences.dart';
import '../../drive/data/drive_repository.dart';
import '../../drive/data/drive_session.dart';
import '../../drive/data/drive_sync.dart';
import '../../drive/domain/drive_models.dart';
import '../../transfers/data/transfer_policy.dart';
import '../../transfers/data/transfer_queue.dart';
import '../../transfers/domain/transfer_wait.dart';

/// Files and folders this phone keeps available offline: pinned items are
/// copied into the app's own store, open without a connection, and survive
/// clearing downloaded copies. New files in a pinned folder follow on their
/// own, the big ones over Wi-Fi only; files that leave the drive (or the
/// pin) lose their copy, and stop downloading if they are still on their
/// way.
///
/// Its state is the Only over Wi-Fi switch. While it is on, every copy is
/// a Wi-Fi-only transfer, so the queue holds it on mobile data and starts it
/// again on Wi-Fi by itself.
class OfflineSync extends Notifier<bool> {
  Timer? _debounce;
  StreamSubscription<String>? _ingested;

  /// The pin, unpin or reconcile under way. Each starts after the one
  /// before, so a reconcile that reads a new pin never runs ahead of the
  /// pin's own and queues its copies under another rule.
  Future<void> _turn = Future.value();

  AppDatabase get _db => ref.read(appDatabaseProvider);
  DriveRepository get _repository => ref.read(driveRepositoryProvider);
  Preferences get _prefs => ref.read(preferencesProvider);

  @override
  bool build() {
    final wifiOnly = _prefs.offlineWifiOnly;
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return wifiOnly;
    ref.listen<DriveSession?>(driveSessionProvider, (_, session) {
      if (session != null) _soon();
    }, fireImmediately: true);
    ref.listen<SyncState>(driveSyncProvider, (previous, next) {
      if ((previous?.running ?? false) && !next.running) _soon();
    });
    _ingested = _repository.ingestedFileIds.listen((_) => _soon());
    ref.onDispose(() {
      _debounce?.cancel();
      _ingested?.cancel();
    });
    return wifiOnly;
  }

  /// Whether copies kept offline may download on [network], with Only over
  /// Wi-Fi set to [wifiOnly].
  static bool allowed({required bool wifiOnly, required NetworkState network}) =>
      !wifiOnly || TransferPolicy.onWifi(network);

  /// Turns Only over Wi-Fi on or off for everything kept offline, the
  /// copies already on their way included: on, they wait while the phone is
  /// on mobile data, and one running there steps back into the queue; off,
  /// those under [TransferPolicy.followUpOnDataBelow] download on any
  /// network. Bigger ones keep waiting for Wi-Fi, as a big file that follows
  /// into a kept folder does, until Download now releases them.
  Future<void> setWifiOnly(bool value) async {
    await _prefs.setOfflineWifiOnly(value);
    state = value;
    await _inTurn(() async {
      final queue = ref.read(transferQueueProvider.notifier);
      final offline = [
        for (final item in ref.read(transferQueueProvider).pending)
          if (item.row.saveTo == SaveTarget.offline) item,
      ];
      if (value) {
        await queue.waitForWifi([for (final item in offline) item.id]);
      } else {
        await queue.useMobileData([
          for (final item in offline)
            if (item.row.totalBytes < TransferPolicy.followUpOnDataBelow) item.id,
        ]);
      }
    });
  }

  /// Keeps [file] or [folder] on this phone. [wifiOnly] is what the person
  /// chose for its copies on mobile data. When nobody chose, and for every
  /// other pin, copies come the way later ones do. Only over Wi-Fi holds
  /// them all, whatever was chosen.
  Future<void> pin({DriveFile? file, DriveFolder? folder, bool? wifiOnly}) => _inTurn(() async {
    final id = file?.id ?? folder!.id;
    await _db.pinOffline(id, isFolder: folder != null);
    await _reconcile(pinned: id, wifiOnly: wifiOnly);
  });

  Future<void> unpin({DriveFile? file, DriveFolder? folder}) => _inTurn(() async {
    await _db.unpinOffline(file?.id ?? folder!.id);
    await _reconcile();
  });

  /// Drops every pin and every copy, and stops the copies on their way.
  Future<void> removeAll() => _inTurn(() async {
    await _db.clearOffline();
    final dir = await TransferQueue.offlineDirectory();
    if (await dir.exists()) await dir.delete(recursive: true);
    await _reconcile();
  });

  void _soon() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () => unawaited(reconcile()));
  }

  /// Brings the copies in line with the pins.
  Future<void> reconcile() => _inTurn(_reconcile);

  Future<void> _inTurn(Future<void> Function() work) {
    final next = _turn.then((_) => work());
    _turn = next.then((_) {}, onError: (Object _) {});
    return next;
  }

  /// Copies to make wait for Wi-Fi from [TransferPolicy.followUpOnDataBelow]
  /// up, so a big file landing in a pinned folder never spends mobile data
  /// unasked. Those of the pin [pinned] follow [wifiOnly] instead, when the
  /// person chose it, and with Only over Wi-Fi on every one waits. Copies
  /// still on their way for files no longer kept stop, rather than land
  /// only to be deleted.
  Future<void> _reconcile({String? pinned, bool? wifiOnly}) async {
    try {
      final pins = await _db.offlinePinList();
      final pinnedFiles = await _db.shownFiles(
        pins.where((p) => !p.isFolder).map((p) => p.itemId),
      );
      final pinnedFolders = <DriveFolder>[];
      for (final pin in pins.where((p) => p.isFolder)) {
        final row = await _db.folderById(pin.itemId);
        if (row == null) {
          await _db.unpinOffline(pin.itemId);
        } else if (!row.hidden) {
          pinnedFolders.add(DriveFolder.fromRow(row));
        }
      }
      final wanted = pins.isEmpty
          ? const <SaveItem>[]
          : await _repository.collectForSaving(
              files: pinnedFiles.map(DriveFile.fromRow).toList(),
              folders: pinnedFolders,
            );
      final wantedIds = {for (final item in wanted) item.file.id};
      final chosen = wifiOnly == null
          ? const <String>{}
          : {
              for (final item in await _repository.collectForSaving(
                files: [
                  for (final row in pinnedFiles) if (row.id == pinned) DriveFile.fromRow(row),
                ],
                folders: [for (final folder in pinnedFolders) if (folder.id == pinned) folder],
              ))
                item.file.id,
            };

      final queue = ref.read(transferQueueProvider.notifier);
      for (final item in ref.read(transferQueueProvider).pending) {
        if (item.row.saveTo == SaveTarget.offline && !wantedIds.contains(item.row.fileId)) {
          await queue.remove(item.id);
        }
      }

      final have = <String>{};
      for (final copy in await _db.offlineCopyList()) {
        final exists = await File(copy.path).exists();
        if (!wantedIds.contains(copy.fileId) || !exists) {
          await _deleteCopy(copy);
        } else {
          have.add(copy.fileId);
        }
      }

      // A copy that failed waits for a retry from Transfers or the Offline
      // screen rather than being queued again on every sync.
      final failed = {
        for (final item in ref.read(transferQueueProvider).finished)
          if (item.row.saveTo == SaveTarget.offline && item.status == TransferStatus.failed)
            item.row.fileId,
      };
      final everyOnWifi = state;
      final missing = [
        for (final item in wanted)
          if (!have.contains(item.file.id) && !failed.contains(item.file.id))
            SaveRequest(
              item.file,
              target: SaveTarget.offline,
              wifiOnly:
                  everyOnWifi ||
                  (chosen.contains(item.file.id)
                      ? wifiOnly!
                      : item.file.size >= TransferPolicy.followUpOnDataBelow),
            ),
      ];
      if (missing.isNotEmpty) await queue.enqueueSaves(missing);
    } catch (e) {
      debugPrint('[Offline] $e');
    }
  }

  Future<void> _deleteCopy(OfflineCopyRow copy) async {
    try {
      final dir = File(copy.path).parent;
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
    await _db.deleteOfflineCopy(copy.fileId);
  }
}

/// Whether Only over Wi-Fi is on; reading it keeps the pins and copies in
/// line while the drive is open.
final offlineSyncProvider = NotifierProvider<OfflineSync, bool>(OfflineSync.new);

/// Ids of pinned files and folders.
final offlinePinsProvider = StreamProvider<Set<String>>(
  (ref) => ref.watch(appDatabaseProvider).watchOfflinePins(),
);

/// File id to its offline copy.
final offlineCopiesProvider = StreamProvider<Map<String, String>>(
  (ref) => ref.watch(appDatabaseProvider).watchOfflineCopies(),
);

/// How many files are kept offline, and how much space they take.
final offlineUsageProvider = StreamProvider.autoDispose<(int, int)>(
  (ref) => ref.watch(appDatabaseProvider).watchOfflineCopies().asyncMap((copies) async {
    var bytes = 0;
    for (final copy in await ref.read(appDatabaseProvider).offlineCopyList()) {
      bytes += copy.size;
    }
    return (copies.length, bytes);
  }),
);

/// One pinned file or folder as the Offline screen counts it: how many of
/// the files it keeps are on this phone, and what the rest are doing.
@immutable
class OfflinePinStatus {
  const OfflinePinStatus({
    this.folder,
    this.file,
    required this.wanted,
    required this.bytes,
    required this.kept,
    required this.keptBytes,
    required this.downloading,
    required this.waiting,
    required this.paused,
    required this.leftBytes,
    required this.failedTransferIds,
  }) : assert((folder == null) != (file == null));

  /// The pinned folder, or else [file].
  final DriveFolder? folder;
  final DriveFile? file;

  /// Files the pin keeps (everything in the folder and below, or the one
  /// file), and their size.
  final int wanted;
  final int bytes;

  /// Of [wanted], those with a copy on this phone, and the copies' size.
  final int kept;
  final int keptBytes;

  /// Of the rest: downloading or about to, held for Wi-Fi, and paused.
  final int downloading;
  final int waiting;
  final int paused;

  /// What is still to come for the files not kept yet, failed ones aside.
  final int leftBytes;

  /// Copies that failed, for Retry.
  final List<String> failedTransferIds;

  String get name => file?.name ?? folder!.name;
}

/// Everything kept offline, for the Offline screen: one [OfflinePinStatus]
/// per pin, newest first, and the copies and their transfers as one line.
@immutable
class OfflineOverview {
  const OfflineOverview({
    required this.pins,
    required this.keptFiles,
    required this.keptBytes,
    required this.downloading,
    required this.downloadingLeft,
    required this.speed,
    required this.waitingTransferIds,
    required this.waitingLeft,
    required this.paused,
    required this.pausedLeft,
    required this.progress,
  });

  final List<OfflinePinStatus> pins;

  /// Copies on this phone, and their size.
  final int keptFiles;
  final int keptBytes;

  /// Copies downloading or about to, what they still have to fetch, and how
  /// fast they come.
  final int downloading;
  final int downloadingLeft;
  final double speed;

  /// Copies held for Wi-Fi, for Download now, and what they have to fetch.
  final List<String> waitingTransferIds;
  final int waitingLeft;

  /// Copies paused, and what they have to fetch.
  final int paused;
  final int pausedLeft;

  /// How much of what is kept or on its way is on this phone, by size.
  final double progress;

  int get waiting => waitingTransferIds.length;

  /// Copies on this phone or on their way.
  int get files => keptFiles + downloading + waiting + paused;

  /// Counts [pins] against what each keeps ([wantedByPin], by pin id), the
  /// [copies] there are (by file id) and the transfers bringing copies
  /// ([offlineTransfers]). A pin whose folder or file is missing from
  /// [folders] or [files] has left the drive, and is left out. A file with
  /// a copy is kept; otherwise its transfer still on its way speaks for it,
  /// over one that failed. Pins come newest first.
  static OfflineOverview compute({
    required List<OfflinePinRow> pins,
    required Map<String, List<DriveFile>> wantedByPin,
    required Map<String, OfflineCopyRow> copies,
    required List<TransferItem> offlineTransfers,
    required Map<String, DriveFolder> folders,
    required Map<String, DriveFile> files,
  }) {
    int left(TransferItem item) => math.max(0, item.row.totalBytes - item.row.doneBytes);
    final byFile = <String, TransferItem>{};
    for (final item in offlineTransfers) {
      final seen = byFile[item.row.fileId];
      if (seen == null || (!seen.status.isPending && item.status.isPending)) {
        byFile[item.row.fileId] = item;
      }
    }

    final statuses = <OfflinePinStatus>[];
    for (final pin in [...pins]..sort((a, b) => b.pinnedAt.compareTo(a.pinnedAt))) {
      final folder = pin.isFolder ? folders[pin.itemId] : null;
      final file = pin.isFolder ? null : files[pin.itemId];
      if (folder == null && file == null) continue;
      final wanted = wantedByPin[pin.itemId] ?? const <DriveFile>[];
      var bytes = 0;
      var kept = 0;
      var keptBytes = 0;
      var downloading = 0;
      var waiting = 0;
      var paused = 0;
      var leftBytes = 0;
      final failed = <String>[];
      for (final want in wanted) {
        bytes += want.size;
        final copy = copies[want.id];
        if (copy != null) {
          kept++;
          keptBytes += copy.size;
          continue;
        }
        final transfer = byFile[want.id];
        if (transfer == null || transfer.status == TransferStatus.cancelled) {
          // Not queued yet: the next pass over the pins queues it.
          leftBytes += want.size;
        } else if (transfer.status == TransferStatus.failed) {
          failed.add(transfer.id);
        } else if (transfer.status == TransferStatus.paused) {
          paused++;
          leftBytes += left(transfer);
        } else if (transfer.wait is WaitingForWifi) {
          waiting++;
          leftBytes += left(transfer);
        } else if (transfer.status.isActive) {
          downloading++;
          leftBytes += left(transfer);
        }
      }
      statuses.add(
        OfflinePinStatus(
          folder: folder,
          file: file,
          wanted: wanted.length,
          bytes: bytes,
          kept: kept,
          keptBytes: keptBytes,
          downloading: downloading,
          waiting: waiting,
          paused: paused,
          leftBytes: leftBytes,
          failedTransferIds: failed,
        ),
      );
    }

    var keptBytes = 0;
    for (final copy in copies.values) {
      keptBytes += copy.size;
    }
    var downloading = 0;
    var downloadingLeft = 0;
    var speed = 0.0;
    final waiting = <String>[];
    var waitingLeft = 0;
    var paused = 0;
    var pausedLeft = 0;
    var total = keptBytes;
    var done = keptBytes;
    for (final item in offlineTransfers.where((t) => t.status.isPending)) {
      // The copy is written before the queue lets its transfer go, so a
      // file with a copy counts once, as kept.
      if (copies.containsKey(item.row.fileId)) continue;
      total += item.row.totalBytes;
      done += item.row.doneBytes;
      if (item.status == TransferStatus.paused) {
        paused++;
        pausedLeft += left(item);
      } else if (item.wait is WaitingForWifi) {
        waiting.add(item.id);
        waitingLeft += left(item);
      } else {
        downloading++;
        downloadingLeft += left(item);
        speed += item.bytesPerSecond;
      }
    }

    return OfflineOverview(
      pins: statuses,
      keptFiles: copies.length,
      keptBytes: keptBytes,
      downloading: downloading,
      downloadingLeft: downloadingLeft,
      speed: speed,
      waitingTransferIds: waiting,
      waitingLeft: waitingLeft,
      paused: paused,
      pausedLeft: pausedLeft,
      progress: total == 0 ? 0 : done / total,
    );
  }
}

/// What [OfflineOverview.compute] counts besides the transfers and copies.
typedef _Kept = ({
  List<OfflinePinRow> pins,
  Map<String, List<DriveFile>> wantedByPin,
  Map<String, DriveFolder> folders,
  Map<String, DriveFile> files,
});

/// The pins and what each keeps, read again half a second after pins, files
/// or folders change, and at most that often: a pinned folder gains and
/// loses files as the drive changes, and a sync writes many rows in a row,
/// so a read waits for the burst without a steady trickle putting it off.
/// Reads run one after another, so an older one never lands last.
final _keptOfflineProvider = StreamProvider.autoDispose<_Kept>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final repository = ref.watch(driveRepositoryProvider);
  final kept = StreamController<_Kept>();
  var reading = Future<void>.value();
  Timer? soon;

  Future<void> read() async {
    try {
      final pins = await db.offlinePinList();
      final shown = {
        for (final row in await db.shownFiles([
          for (final pin in pins)
            if (!pin.isFolder) pin.itemId,
        ]))
          row.id: DriveFile.fromRow(row),
      };
      final folders = <String, DriveFolder>{};
      final files = <String, DriveFile>{};
      final wantedByPin = <String, List<DriveFile>>{};
      for (final pin in pins) {
        if (pin.isFolder) {
          final row = await db.folderById(pin.itemId);
          if (row == null || row.hidden) continue;
          final folder = folders[pin.itemId] = DriveFolder.fromRow(row);
          wantedByPin[pin.itemId] = [
            for (final item in await repository.collectForSaving(folders: [folder])) item.file,
          ];
        } else if (shown[pin.itemId] case final file?) {
          files[pin.itemId] = file;
          wantedByPin[pin.itemId] = [file];
        }
      }
      if (kept.isClosed) return;
      kept.add((pins: pins, wantedByPin: wantedByPin, folders: folders, files: files));
    } catch (e, stack) {
      if (!kept.isClosed) kept.addError(e, stack);
    }
  }

  void again() => reading = reading.then((_) => read());
  final changes = db
      .tableUpdates(TableUpdateQuery.onAllTables([db.offlinePins, db.driveFiles, db.folders]))
      .listen((_) {
        soon ??= Timer(const Duration(milliseconds: 500), () {
          soon = null;
          again();
        });
      });
  again();
  ref.onDispose(() {
    soon?.cancel();
    changes.cancel();
    kept.close();
  });
  return kept.stream;
});

/// The copies by file id, read the moment one is added or removed. A
/// finished transfer leaves the queue right after its copy is written, so a
/// copy that waited would leave its file in neither for a while, and the
/// counts and the bar would step back.
final _offlineCopyRowsProvider = StreamProvider.autoDispose<Map<String, OfflineCopyRow>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return db.watchOfflineCopies().asyncMap(
    (_) async => {for (final copy in await db.offlineCopyList()) copy.fileId: copy},
  );
});

/// Everything kept offline and how far along it is, for the Offline screen.
/// The transfers and the copies are counted afresh as they move, which is
/// cheap; the pins and what they keep are read only when those change.
final offlineOverviewProvider = Provider.autoDispose<AsyncValue<OfflineOverview>>((ref) {
  final transfers = [
    for (final item in ref.watch(transferQueueProvider).items)
      if (item.row.saveTo == SaveTarget.offline) item,
  ];
  final copies = ref.watch(_offlineCopyRowsProvider);
  return ref.watch(_keptOfflineProvider).when(
    data: (kept) => copies.whenData(
      (copies) => OfflineOverview.compute(
        pins: kept.pins,
        wantedByPin: kept.wantedByPin,
        copies: copies,
        offlineTransfers: transfers,
        folders: kept.folders,
        files: kept.files,
      ),
    ),
    error: (error, stack) => AsyncError(error, stack),
    loading: () => const AsyncLoading(),
  );
});
