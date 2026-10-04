import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../infrastructure/database/app_database.dart';
import '../../../infrastructure/storage/device_storage.dart';
import '../../../infrastructure/telegram/telegram_client.dart';
import '../../drive/data/previews.dart';
import '../../preview/data/pdf_block_cache.dart';
import '../../transfers/data/transfer_queue.dart';

/// What Telegrive keeps on this phone, by what it is for, in bytes.
@immutable
class PhoneUsage {
  const PhoneUsage({
    required this.openedFiles,
    required this.thumbnails,
    required this.leftovers,
    required this.offline,
    required this.index,
    required this.telegramDatabase,
    required this.budget,
  });

  /// Telegram's copies of files opened, played or downloaded here, split
  /// files joined back together, and the pages of PDFs read in the app.
  /// They download again when needed.
  final int openedFiles;

  /// Pictures for rows, grids and chats, fetched again as they are shown.
  final int thumbnails;

  /// Copies made for uploads that nothing needs any more.
  final int leftovers;

  /// Files kept available offline, on purpose.
  final int offline;

  /// The drive's local index, with the words search read in documents.
  final int index;

  /// Telegram's own database of messages, chats and settings.
  final int telegramDatabase;

  /// What the daily trim keeps opened files within, from
  /// [openedFilesBudget].
  final int budget;

  int get total => openedFiles + thumbnails + leftovers + offline + index + telegramDatabase;
}

/// The most and the least the daily trim leaves for opened files.
const int _budgetCeiling = 1 << 30;
const int _budgetFloor = 100 << 20;

/// Room for opened files that the daily trim keeps them within: a tenth of
/// the phone's storage and a third of what is free, but never more than
/// 1 GB or less than 100 MB. A figure the phone can't give is left out.
int openedFilesBudget({required int? free, required int? total}) => [
  _budgetCeiling,
  if (total != null) total ~/ 10,
  if (free != null) free ~/ 3,
].reduce(math.min).clamp(_budgetFloor, _budgetCeiling);

/// What Telegrive keeps on this phone, measured while Space shows it.
/// Telegram walks its files to give exact figures, which takes a few
/// seconds on a big cache.
final phoneUsageProvider = FutureProvider.autoDispose<PhoneUsage>((ref) async {
  final client = ref.watch(telegramClientProvider);
  final db = ref.watch(appDatabaseProvider);
  final storage = ref.watch(deviceStorageProvider);
  final queue = ref.read(transferQueueProvider.notifier);

  final stats = await client.send<td.StorageStatistics>(
    const td.GetStorageStatistics(chatLimit: 1),
    timeout: const Duration(minutes: 2),
  );
  var opened = 0;
  var thumbnails = 0;
  for (final chat in stats.byChat) {
    for (final type in chat.byFileType) {
      if (type.fileType is td.FileTypeThumbnail || type.fileType is td.FileTypeProfilePhoto) {
        thumbnails += type.size;
      } else {
        opened += type.size;
      }
    }
  }
  final fast = await client.send<td.StorageStatisticsFast>(
    const td.GetStorageStatisticsFast(),
  );
  final support = await getApplicationSupportDirectory();
  var index = 0;
  for (final suffix in ['', '-wal', '-shm']) {
    index += await _sizeOf(File(p.join(support.path, 'telegrive.sqlite$suffix')));
  }
  final offline = (await db.offlineCopyList()).fold(0, (sum, copy) => sum + copy.size);
  final leftovers = (await queue.leftovers()).fold(0, (sum, leftover) => sum + leftover.bytes);

  return PhoneUsage(
    openedFiles:
        opened +
        await _sizeOf(await TransferQueue.downloadsDirectory()) +
        await pdfBlockCacheBytes(),
    thumbnails: thumbnails,
    leftovers: leftovers,
    offline: offline,
    index: index,
    telegramDatabase: fast.databaseSize,
    budget: openedFilesBudget(free: await storage.freeBytes(), total: await storage.totalBytes()),
  );
});

/// The kinds of file Telegram keeps that are pictures of something else,
/// which [phoneUsageProvider] counts as thumbnails.
const _thumbnailTypes = <td.FileType>[td.FileTypeThumbnail(), td.FileTypeProfilePhoto()];

/// Every other kind of file Telegram keeps, which it counts as opened
/// files. Secret thumbnails can't be deleted, so they aren't asked for.
const _openedTypes = <td.FileType>[
  td.FileTypeAnimation(),
  td.FileTypeAudio(),
  td.FileTypeDocument(),
  td.FileTypeNotificationSound(),
  td.FileTypePhoto(),
  td.FileTypePhotoStory(),
  td.FileTypeSecret(),
  td.FileTypeSecure(),
  td.FileTypeSticker(),
  td.FileTypeUnknown(),
  td.FileTypeVideo(),
  td.FileTypeVideoNote(),
  td.FileTypeVideoStory(),
  td.FileTypeVoiceNote(),
  td.FileTypeWallpaper(),
];

/// Deletes Telegram's copies of opened files, the split files joined back
/// together and the pages of PDFs read in the app. Thumbnails stay, and so
/// do files kept offline and those saved to Download, which live elsewhere.
/// A photo's own sizes can stand in for its thumbnail and go with the rest,
/// so tiles resolve their pictures again rather than stay blank. Space
/// offers it only while no transfer runs, since a download writes into
/// both.
Future<void> clearOpenedFiles(WidgetRef ref) async {
  await _deleteFromTelegram(ref, _openedTypes);
  ref.invalidate(thumbnailPathProvider);
  final downloads = await TransferQueue.downloadsDirectory();
  if (await downloads.exists()) await downloads.delete(recursive: true);
  await deletePdfBlockCache();
  await _cleared(ref);
}

/// Deletes Telegram's thumbnails and profile photos. The paths tiles have
/// already resolved are forgotten with them, so each one fetches its
/// picture again rather than stay blank.
Future<void> clearThumbnails(WidgetRef ref) async {
  await _deleteFromTelegram(ref, _thumbnailTypes);
  ref.invalidate(thumbnailPathProvider);
  await _cleared(ref);
}

/// Deletes the copies made for uploads that nothing needs any more.
Future<void> clearLeftovers(WidgetRef ref) async {
  await ref.read(transferQueueProvider.notifier).clearLeftovers();
  await _cleared(ref);
}

/// Everything of [types] that Telegram keeps, except what it made in the
/// last minute.
Future<void> _deleteFromTelegram(WidgetRef ref, List<td.FileType> types) =>
    ref.read(telegramClientProvider).send<td.StorageStatistics>(
      td.OptimizeStorage(
        size: 0,
        ttl: 0,
        count: 0,
        immunityDelay: 60,
        fileTypes: types,
        chatIds: const [],
        excludeChatIds: const [],
        returnDeletedFileStatistics: false,
        chatLimit: 0,
      ),
      timeout: const Duration(minutes: 2),
    );

/// The figures are measured again, and transfers waiting for room look
/// for it again.
Future<void> _cleared(WidgetRef ref) async {
  ref.invalidate(phoneUsageProvider);
  await ref.read(transferQueueProvider.notifier).recheckRoom();
}

/// The bytes in [entity]: a file's length, or everything in a folder.
/// Nothing there counts as nothing.
Future<int> _sizeOf(FileSystemEntity entity) async {
  if (entity is File) return await entity.exists() ? await entity.length() : 0;
  final dir = Directory(entity.path);
  if (!await dir.exists()) return 0;
  var total = 0;
  await for (final child in dir.list(recursive: true, followLinks: false)) {
    if (child is File) total += await child.length();
  }
  return total;
}
