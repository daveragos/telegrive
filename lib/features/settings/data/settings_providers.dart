import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:path_provider/path_provider.dart';

import '../../../infrastructure/storage/preferences.dart';
import '../../../infrastructure/telegram/telegram_client.dart';
import '../../transfers/data/transfer_queue.dart';

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ref.watch(preferencesProvider).themeMode;

  void set(ThemeMode mode) {
    state = mode;
    ref.read(preferencesProvider).setThemeMode(mode);
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

/// Space this device spends on copies of drive files: TDLib's download
/// cache, stitched split files, and leftover staging copies.
final cacheSizeProvider = FutureProvider.autoDispose<int>((ref) async {
  final client = ref.watch(telegramClientProvider);
  var total = 0;
  try {
    final stats = await client.send<td.StorageStatisticsFast>(
      const td.GetStorageStatisticsFast(),
    );
    total += stats.filesSize;
  } catch (_) {}
  for (final dir in await _ownCacheDirs()) {
    total += await _sizeOf(dir);
  }
  return total;
});

/// Frees the space counted by [cacheSizeProvider]. Nothing in the drive is
/// touched — everything can be downloaded again. Transfers waiting for room
/// look again once it is free.
Future<void> clearLocalCache(WidgetRef ref) async {
  final client = ref.read(telegramClientProvider);
  await client.send<td.StorageStatistics>(
    const td.OptimizeStorage(
      size: 0,
      ttl: 0,
      count: 0,
      immunityDelay: 0,
      fileTypes: [],
      chatIds: [],
      excludeChatIds: [],
      returnDeletedFileStatistics: false,
      chatLimit: 0,
    ),
    timeout: const Duration(minutes: 2),
  );
  for (final dir in await _ownCacheDirs()) {
    if (await dir.exists()) await dir.delete(recursive: true);
  }
  ref.invalidate(cacheSizeProvider);
  await ref.read(transferQueueProvider.notifier).recheckRoom();
}

Future<List<Directory>> _ownCacheDirs() async {
  final temp = await getTemporaryDirectory();
  return [
    await TransferQueue.downloadsDirectory(),
    Directory('${temp.path}/telegrive-parts'),
  ];
}

Future<int> _sizeOf(Directory dir) async {
  if (!await dir.exists()) return 0;
  var total = 0;
  await for (final entity in dir.list(recursive: true, followLinks: false)) {
    if (entity is File) total += await entity.length();
  }
  return total;
}
