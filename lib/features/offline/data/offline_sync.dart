import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../infrastructure/database/app_database.dart';
import '../../drive/data/drive_repository.dart';
import '../../drive/data/drive_session.dart';
import '../../drive/data/drive_sync.dart';
import '../../drive/domain/drive_models.dart';
import '../../transfers/data/transfer_queue.dart';

/// Files and folders this phone keeps available offline: pinned items
/// are copied into the app's own store,
/// open without a connection, and survive clearing downloaded copies. New
/// files in a pinned folder follow on their own; files that leave the drive
/// (or the pin) lose their copy.
class OfflineSync extends Notifier<void> {
  Timer? _debounce;
  StreamSubscription<String>? _ingested;

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

  Future<void> pin({DriveFile? file, DriveFolder? folder}) async {
    await _db.pinOffline(file?.id ?? folder!.id, isFolder: folder != null);
    await reconcile();
  }

  Future<void> unpin({DriveFile? file, DriveFolder? folder}) async {
    await _db.unpinOffline(file?.id ?? folder!.id);
    await reconcile();
  }

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
  Future<void> reconcile() async {
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
            SaveRequest(item.file, target: SaveTarget.offline),
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
