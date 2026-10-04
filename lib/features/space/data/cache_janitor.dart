import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;

import '../../../infrastructure/storage/device_storage.dart';
import '../../../infrastructure/storage/preferences.dart';
import '../../../infrastructure/telegram/telegram_client.dart';
import '../../drive/data/drive_session.dart';
import '../../drive/data/previews.dart';
import '../../transfers/data/transfer_queue.dart';
import 'phone_usage.dart';

/// Keeps what Telegrive leaves on the phone in check without being asked.
///
/// Once a day, from a little after the drive opens for as long as it stays
/// open, Telegram's copies of files are trimmed to [openedFilesBudget],
/// those opened longest ago first and every one untouched for two weeks.
/// The split files joined back together to open them go once they are two
/// weeks old, and the copies uploads no longer need go with them. A phone
/// with under 300 MB free is trimmed harder, down to 100 MB and a day,
/// whenever the drive opens and each day after. Nothing younger than an
/// hour goes, and nothing goes while a transfer runs, since a download
/// writes into the same cache.
class CacheJanitor extends Notifier<void> {
  static const Duration _afterOpen = Duration(seconds: 30);
  static const Duration _whileBusy = Duration(minutes: 10);
  static const Duration _every = Duration(days: 1);
  static const int _nearlyFull = 300 << 20;
  static const int _nearlyFullBudget = 100 << 20;

  Timer? _timer;

  static bool get _supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  void build() {
    ref.onDispose(() => _timer?.cancel());
    if (!_supported) return;
    ref.listen<DriveSession?>(driveSessionProvider, (_, session) {
      _timer?.cancel();
      if (session != null) _timer = Timer(_afterOpen, () => unawaited(run()));
    }, fireImmediately: true);
  }

  /// Trims now if it is due and looks again in a day, or tries again in a
  /// while if a transfer is running.
  Future<void> run() async {
    _timer?.cancel();
    if (ref.read(transferQueueProvider).activeCount > 0) {
      _timer = Timer(_whileBusy, () => unawaited(run()));
      return;
    }
    await _trimIfDue();
    // A drive that opened again meanwhile has set its own time.
    if (ref.mounted && ref.read(driveSessionProvider) != null && !(_timer?.isActive ?? false)) {
      _timer = Timer(_every, () => unawaited(run()));
    }
  }

  /// The nearly full phone's trim if that is what it needs, otherwise the
  /// day's if a day has passed since the last.
  Future<void> _trimIfDue() async {
    final queue = ref.read(transferQueueProvider.notifier);
    final prefs = ref.read(preferencesProvider);
    final storage = ref.read(deviceStorageProvider);
    try {
      final free = await storage.freeBytes();
      final now = DateTime.now();
      final last = prefs.cacheSweptAt;
      final int deleted;
      if (free != null && free < _nearlyFull) {
        const untouchedFor = Duration(days: 1);
        deleted = await _trim(size: _nearlyFullBudget, untouchedFor: untouchedFor);
        await queue.clearOldDownloads(olderThan: untouchedFor);
      } else if (last == null || now.difference(last) >= _every) {
        const untouchedFor = Duration(days: 14);
        deleted = await _trim(
          size: openedFilesBudget(free: free, total: await storage.totalBytes()),
          untouchedFor: untouchedFor,
        );
        await queue.clearOldDownloads(olderThan: untouchedFor);
        await queue.clearLeftovers();
        await prefs.setCacheSweptAt(now);
      } else {
        return;
      }
      // A photo's own sizes can stand in for its thumbnail, and they are
      // fair game here, so tiles resolve their pictures again.
      if (deleted > 0) ref.invalidate(thumbnailPathProvider);
      await queue.recheckRoom();
    } catch (e) {
      debugPrint('[Janitor] Could not trim the cache: $e');
    }
  }

  /// Asks Telegram to keep its files within [size], deleting those not
  /// opened for [untouchedFor] whatever their size, and returns how many
  /// went. With no types named it leaves thumbnails, profile photos,
  /// stickers and wallpapers be.
  Future<int> _trim({required int size, required Duration untouchedFor}) async {
    final deleted = await ref.read(telegramClientProvider).send<td.StorageStatistics>(
      td.OptimizeStorage(
        size: size,
        ttl: untouchedFor.inSeconds,
        count: -1,
        immunityDelay: const Duration(hours: 1).inSeconds,
        fileTypes: const [],
        chatIds: const [],
        excludeChatIds: const [],
        returnDeletedFileStatistics: true,
        chatLimit: 0,
      ),
      timeout: const Duration(minutes: 2),
    );
    return deleted.count;
  }
}

/// Watched while the drive is open, which keeps the daily trim scheduled.
final cacheJanitorProvider = NotifierProvider<CacheJanitor, void>(CacheJanitor.new);
