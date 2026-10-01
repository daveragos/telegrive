import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../infrastructure/database/app_database.dart';
import '../../drive/data/drive_repository.dart';
import '../../drive/data/drive_session.dart';
import '../../drive/data/drive_sync.dart';
import '../../drive/domain/drive_models.dart';
import '../../transfers/data/transfer_policy.dart';
import '../../transfers/data/transfer_queue.dart';

/// Files and folders this phone keeps available offline: pinned items are
/// copied into the app's own store, open without a connection, and survive
/// clearing downloaded copies. New files in a pinned folder follow on their
/// own, the big ones over Wi-Fi only; files that leave the drive (or the
/// pin) lose their copy.
class OfflineSync extends Notifier<void> {
  Timer? _debounce;
  StreamSubscription<String>? _ingested;

  /// The pin, unpin or reconcile under way. Each starts after the one
  /// before, so a reconcile that reads a new pin never runs ahead of the
  /// pin's own and queues its copies under another rule.
  Future<void> _turn = Future.value();

  AppDatabase get _db => ref.read(appDatabaseProvider);
  DriveRepository get _repository => ref.read(driveRepositoryProvider);

  @override
  void build() {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
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
  }

  /// Keeps [file] or [folder] on this phone. [wifiOnly] is what the person
  /// chose for its copies when asked about mobile data. When nobody asked,
  /// and for every other pin, copies come the way later ones do.
  Future<void> pin({DriveFile? file, DriveFolder? folder, bool? wifiOnly}) => _inTurn(() async {
    final id = file?.id ?? folder!.id;
    await _db.pinOffline(id, isFolder: folder != null);
    await _reconcile(pinned: id, wifiOnly: wifiOnly);
  });

  Future<void> unpin({DriveFile? file, DriveFolder? folder}) => _inTurn(() async {
    await _db.unpinOffline(file?.id ?? folder!.id);
    await _reconcile();
  });

  /// Drops every pin and every copy.
  Future<void> removeAll() async {
    await _db.clearOffline();
    final dir = await TransferQueue.offlineDirectory();
    if (await dir.exists()) await dir.delete(recursive: true);
  }

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
  /// person chose it.
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

      final have = <String>{};
      for (final copy in await _db.offlineCopyList()) {
        final exists = await File(copy.path).exists();
        if (!wantedIds.contains(copy.fileId) || !exists) {
          await _deleteCopy(copy);
        } else {
          have.add(copy.fileId);
        }
      }

      // A copy that failed waits for a retry from Transfers rather than
      // being queued again on every sync.
      final failed = {
        for (final item in ref.read(transferQueueProvider).finished)
          if (item.row.saveTo == SaveTarget.offline && item.status == TransferStatus.failed)
            item.row.fileId,
      };
      final missing = [
        for (final item in wanted)
          if (!have.contains(item.file.id) && !failed.contains(item.file.id))
            SaveRequest(
              item.file,
              target: SaveTarget.offline,
              wifiOnly: chosen.contains(item.file.id)
                  ? wifiOnly!
                  : item.file.size >= TransferPolicy.followUpOnDataBelow,
            ),
      ];
      if (missing.isNotEmpty) {
        await ref.read(transferQueueProvider.notifier).enqueueSaves(missing);
      }
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

final offlineSyncProvider = NotifierProvider<OfflineSync, void>(OfflineSync.new);

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
