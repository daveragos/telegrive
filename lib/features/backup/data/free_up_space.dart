import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../core/format/formatters.dart';
import '../../../infrastructure/database/app_database.dart';
import '../../../infrastructure/storage/device_storage.dart';
import '../../../infrastructure/storage/preferences.dart';
import '../../drive/domain/drive_models.dart';
import 'backup_controller.dart';

/// How much of the newest Free up space leaves on the phone when it
/// deletes the rest.
enum KeepWindow {
  days30('30 days', Duration(days: 30)),
  days90('90 days', Duration(days: 90)),
  nothing('Nothing', null);

  const KeepWindow(this.label, this.span);

  final String label;

  /// How far back everything stays on the phone; null when nothing does.
  final Duration? span;

  /// The start of the day [span] before [now], so "from before Aug 27"
  /// leaves all of Aug 27 on the phone. Null when nothing is kept.
  DateTime? cutoff(DateTime now) =>
      span == null ? null : DateTime(now.year, now.month, now.day - span!.inDays);
}

/// The window Free up space keeps, remembered on this phone; 30 days until
/// the person picks another.
class FreeUpKeep extends Notifier<KeepWindow> {
  @override
  KeepWindow build() {
    final saved = ref.watch(preferencesProvider).freeUpKeep;
    return KeepWindow.values.where((w) => w.name == saved).firstOrNull ?? KeepWindow.days30;
  }

  Future<void> set(KeepWindow window) async {
    state = window;
    await ref.read(preferencesProvider).setFreeUpKeep(window.name);
  }
}

final freeUpKeepProvider = NotifierProvider<FreeUpKeep, KeepWindow>(FreeUpKeep.new);

/// A photo or video this phone has, and its complete drive copy.
@immutable
class FreeableItem {
  const FreeableItem({required this.assetId, required this.file});

  final String assetId;
  final DriveFile file;

  int get bytes => file.size;

  /// When it was taken, or when it was backed up for a photo that doesn't
  /// say, which keeps such a photo among the recent ones.
  DateTime get momentAt => file.momentAt;
}

/// Photos and videos on this phone that are safely in the drive.
@immutable
class Freeable {
  const Freeable(this.items);

  static const none = Freeable([]);

  final List<FreeableItem> items;

  List<String> get assetIds => [for (final item in items) item.assetId];
  int get bytes => items.fold(0, (sum, item) => sum + item.bytes);
  int get count => items.length;
  bool get isEmpty => items.isEmpty;

  /// When the oldest of them was taken; null when there are none.
  DateTime? get oldest => items.isEmpty
      ? null
      : items.map((item) => item.momentAt).reduce((a, b) => a.isBefore(b) ? a : b);

  /// Their drive copies, newest first, as the Photos grid orders them.
  List<DriveFile> get files =>
      [for (final item in items) item.file]..sort((a, b) => b.momentAt.compareTo(a.momentAt));

  /// The ones taken before [cutoff]; all of them when there is no cutoff.
  Freeable before(DateTime? cutoff) => cutoff == null
      ? this
      : Freeable([for (final item in items) if (item.momentAt.isBefore(cutoff)) item]);
}

/// What Free up space would delete while keeping [window], as its sheet
/// says it. [all] is everything safe to delete, so a window that leaves
/// nothing to delete can say that everything is newer than its cutoff,
/// and a phone with nothing backed up can say how that changes.
String describeFreeable(Freeable all, Freeable candidates, KeepWindow window, DateTime now) {
  final cutoff = window.cutoff(now);
  if (candidates.isEmpty) {
    return cutoff == null || all.isEmpty
        ? 'Photos and videos backed up from this phone show up here once they '
              'are safely in your drive.'
        : 'Everything backed up from this phone is newer than '
              '${Formatters.date(cutoff, now: now)}.';
  }
  final one = candidates.count == 1;
  final year = DateFormat.y().format(candidates.oldest!);
  return '${Formatters.count(candidates.count, 'photo or video', 'photos and videos')} '
      '${cutoff == null ? 'on this phone' : 'from before ${Formatters.date(cutoff, now: now)}'} '
      '${one ? 'is' : 'are'} backed up to your drive · ${Formatters.bytes(candidates.bytes)}, '
      '${one ? 'from' : 'oldest from'} $year. ${one ? 'It\'ll' : 'They\'ll'} be deleted '
      'from this phone and stay in Telegrive, where you can download '
      '${one ? 'it' : 'them'} again any time.';
}

/// What Free up space would delete while keeping [window], in a few words
/// for the row on the Backup screen that opens it.
String summarizeFreeable(Freeable candidates, KeepWindow window, DateTime now) {
  final cutoff = window.cutoff(now);
  final size = Formatters.bytes(candidates.bytes);
  return cutoff == null
      ? '$size of backed-up photos are on this phone'
      : '$size of photos from before ${Formatters.date(cutoff, now: now)} are backed up';
}

/// Makes a provider work itself out again each time a backup pass ends,
/// rather than with every photo the pass sends.
void _afterEachPass(Ref ref) => ref.watch(
  backupControllerProvider.select((b) => (b.phase == BackupPhase.upToDate, b.lastCompleted)),
);

/// Everything Free up space could delete: what was backed up from this
/// phone whose drive copy is complete and not in the trash, and that the
/// phone still has. Sizes are the drive copies', which are the originals.
/// It reads the whole photo library, so it is worked out again only when a
/// backup pass ends.
final freeableProvider = FutureProvider.autoDispose<Freeable>((ref) async {
  if (kIsWeb) return Freeable.none;
  _afterEachPass(ref);
  final safe = await ref.watch(appDatabaseProvider).safelyBackedUp();
  if (safe.isEmpty) return Freeable.none;
  final permission = await PhotoManager.getPermissionState(
    requestOption: BackupController.permissionOption,
  );
  if (!permission.hasAccess) return Freeable.none;
  final onPhone = await _phoneAssetIds();
  return Freeable([
    for (final MapEntry(key: assetId, value: row) in safe.entries)
      if (onPhone.contains(assetId)) FreeableItem(assetId: assetId, file: DriveFile.fromRow(row)),
  ]);
});

/// What Free up space would delete with the remembered window: the
/// freeable photos taken before its cutoff.
final freeUpCandidatesProvider = Provider.autoDispose<AsyncValue<Freeable>>((ref) {
  final window = ref.watch(freeUpKeepProvider);
  return ref.watch(freeableProvider).whenData((all) => all.before(window.cutoff(DateTime.now())));
});

/// Whether a phone with [free] bytes left of [total] is short of room:
/// under 2 GB free, or under a tenth of its storage when that is known.
bool isLowSpace(int free, int? total) =>
    free < 2 * 1024 * 1024 * 1024 || (total != null && free < total * 0.10);

/// Whether this phone is low on space, checked again whenever a backup
/// pass ends and after Free up space. False when the phone won't say.
final lowSpaceProvider = FutureProvider.autoDispose<bool>((ref) async {
  _afterEachPass(ref);
  final storage = ref.watch(deviceStorageProvider);
  final free = await storage.freeBytes();
  if (free == null) return false;
  return isLowSpace(free, await storage.totalBytes());
});

Future<Set<String>> _phoneAssetIds() async {
  final paths = await PhotoManager.getAssetPathList(type: RequestType.common, onlyAll: true);
  if (paths.isEmpty) return const {};
  final all = paths.first;
  final count = await all.assetCountAsync;
  final ids = <String>{};
  for (var page = 0; page * 500 < count; page++) {
    final assets = await all.getAssetListPaged(page: page, size: 500);
    ids.addAll(assets.map((a) => a.id));
  }
  return ids;
}

/// Deletes [freeable] from the phone. Android 11+ and iOS show their own
/// confirmation first. Returns how many went.
Future<int> freeUpSpace(Freeable freeable) => deleteFromPhone(freeable.assetIds);

/// Deletes the photos and videos [assetIds] from the phone's library.
/// Android 11+ and iOS show their own confirmation first, which needs the
/// app in front. Returns how many went.
Future<int> deleteFromPhone(List<String> assetIds) async {
  var deleted = 0;
  for (var i = 0; i < assetIds.length; i += 500) {
    final gone = await PhotoManager.editor.deleteWithIds(
      assetIds.sublist(i, math.min(i + 500, assetIds.length)),
    );
    // An empty answer means the person said no.
    if (gone.isEmpty) break;
    deleted += gone.length;
  }
  return deleted;
}

/// Of [assetIds], the photos and videos the phone's library still has.
/// Backup's records outlive the phone's copies, which Free up space or the
/// gallery may have deleted since, and Android refuses a whole delete that
/// names one it no longer has.
///
/// A few are looked up one by one. More than a page of them reads the
/// library a page at a time instead, since a lookup each for thousands of
/// photos keeps the person waiting for seconds.
Future<Set<String>> stillOnPhone(Iterable<String> assetIds) async {
  final ids = assetIds.toList();
  if (ids.length > 500) {
    final library = await _phoneAssetIds();
    return {for (final id in ids) if (library.contains(id)) id};
  }
  final assets = await Future.wait(ids.map(AssetEntity.fromId));
  return {
    for (final (index, asset) in assets.indexed)
      if (asset != null) ids[index],
  };
}
