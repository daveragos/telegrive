import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;

import '../../../infrastructure/database/app_database.dart';
import '../../../infrastructure/network/network_status.dart';
import '../../../infrastructure/storage/device_storage.dart';
import '../../../infrastructure/telegram/telegram_client.dart';
import '../../../infrastructure/telegram/telegram_exception.dart';
import '../../transfers/data/room.dart';
import 'drive_session.dart';
import 'drive_sync.dart';

/// Fetches Telegram's thumbnails of the newest photos and videos while the
/// phone is on an unmetered network, so scrolling Photos later on mobile
/// data costs nothing. The state is how many it fetched in the current run,
/// which nothing shows.
///
/// It stays out of the way: one thumbnail at a time at the lowest priority,
/// newest first, stopping on mobile data, when the phone has less than
/// [minFree] free, or after [_cap] fetches in a run. Photos backed up from
/// this phone are skipped, since their tiles show the phone's own copy. The
/// daily trim keeps thumbnails, so what it fetches stays.
class ThumbnailPrefetch extends Notifier<int> {
  /// Whether this platform says when a network is metered. Elsewhere every
  /// network reads as unmetered, so prefetching could spend mobile data;
  /// tests turn it on.
  @visibleForTesting
  static bool enabled = !kIsWeb && Platform.isAndroid;

  /// How long one second of the prefetch's waits lasts; tests shorten it.
  @visibleForTesting
  static Duration unit = const Duration(seconds: 1);

  /// Fetches in one run, about 100 MB of thumbnails at most.
  static const int _cap = 5000;

  /// Space the phone keeps free whatever the prefetch would like.
  static const int minFree = 1 << 30;

  Timer? _start;
  bool _stop = false;
  bool _running = false;

  AppDatabase get _db => ref.read(appDatabaseProvider);
  TelegramClient get _client => ref.read(telegramClientProvider);

  @override
  int build() {
    ref.onDispose(() {
      _stop = true;
      _start?.cancel();
    });
    if (!enabled) return 0;
    ref.listen<DriveSession?>(driveSessionProvider, (_, session) {
      if (session != null) {
        _soon(unit * 30);
      } else {
        _stop = true;
        _start?.cancel();
      }
    }, fireImmediately: true);
    ref.listen<SyncState>(driveSyncProvider, (previous, next) {
      if ((previous?.running ?? false) && !next.running) _soon(unit * 5);
    });
    ref.listen<NetworkState>(networkStatusProvider, (previous, next) {
      if (_unmetered(next) && (previous == null || !_unmetered(previous))) {
        _soon(unit * 5);
      }
    });
    return 0;
  }

  static bool _unmetered(NetworkState network) => network.online && !network.metered;

  void _soon(Duration after) {
    _start?.cancel();
    _start = Timer(after, () => unawaited(_run()));
  }

  Future<void> _run() async {
    if (_running || ref.read(driveSessionProvider) == null) return;
    _running = true;
    _stop = false;
    state = 0;
    try {
      final onPhone = (await _db.watchLocalAssets().first).keys.toSet();
      final targets = [
        for (final media in await _db.mediaThumbnails())
          if (!onPhone.contains(media.fileId)) media.thumbnailFileId,
      ];
      for (final (index, id) in targets.indexed) {
        if (_stop || state >= _cap) break;
        if (index % 50 == 0 && !_unmetered(ref.read(networkStatusProvider))) break;
        if (index % 200 == 0 &&
            await Room.shortfall(ref.read(deviceStorageProvider), minFree) != null) {
          break;
        }
        try {
          final file = await _client.send<td.File>(td.GetFile(fileId: id));
          if (file.local.isDownloadingCompleted) continue;
          final fetched = await _client.send<td.File>(
            td.DownloadFile(fileId: id, priority: 1, offset: 0, limit: 0, synchronous: true),
            timeout: const Duration(minutes: 1),
          );
          // The drive may have closed while it came down.
          if (_stop) break;
          if (fetched.local.isDownloadingCompleted) state++;
        } on TelegramException catch (e) {
          // TDLib answers 400 about the one thumbnail it was asked for, such
          // as an id it forgot when its files were reset, and the rest can
          // still come down. Anything else holds for every thumbnail
          // (Telegram asking the account to slow down, not answering, or not
          // running), so the run ends and the next one starts over.
          if (e.code != 400) break;
        }
        await Future<void>.delayed(unit ~/ 10);
      }
    } catch (e) {
      debugPrint('[Prefetch] $e');
    } finally {
      _running = false;
    }
  }
}

/// Listened to while the drive is open, which keeps the prefetch going.
final thumbnailPrefetchProvider = NotifierProvider<ThumbnailPrefetch, int>(
  ThumbnailPrefetch.new,
);
