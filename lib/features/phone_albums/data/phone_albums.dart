import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../infrastructure/storage/device_storage.dart';

/// Albums in the phone's own gallery, and getting one ready to go up into
/// the drive as a folder and an album of the same name.

/// Whether this phone has a gallery the app can read.
bool get phoneAlbumsSupported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

/// An album in the phone's gallery: a folder of the gallery on Android, an
/// album or smart album in Photos on iOS.
@immutable
class PhoneAlbum {
  const PhoneAlbum({
    required this.path,
    required this.name,
    required this.count,
    this.coverAssetId,
  });

  /// The gallery's own handle on the album, which lists what it holds.
  final AssetPathEntity path;

  /// The album's name as the gallery shows it, or Phone album when it has
  /// none, cut to what a folder name may be.
  final String name;

  /// Its photos and videos.
  final int count;

  /// Its newest photo or video, for the row's thumbnail.
  final String? coverAssetId;

  String get id => path.id;
}

/// The name a gallery album goes up under: its own, trimmed and cut to the
/// 128 characters a folder name may have, or Phone album when it has none.
@visibleForTesting
String albumFolderName(String name) {
  final clean = name.trim();
  if (clean.isEmpty) return 'Phone album';
  return clean.length > 128 ? clean.substring(0, 128).trim() : clean;
}

/// Newest first, the order backup goes in, so an album's cover is its
/// newest photo.
final _newestFirst = FilterOptionGroup(
  orders: [const OrderOption(type: OrderOptionType.createDate, asc: false)],
);

/// The gallery's albums with something in them, biggest first, as backup
/// lists the phone's folders. The album of everything is left out: that is
/// what photo backup is for.
final phoneAlbumsProvider = FutureProvider.autoDispose<List<PhoneAlbum>>((ref) async {
  if (!phoneAlbumsSupported) return const [];
  final paths = await PhotoManager.getAssetPathList(
    type: RequestType.common,
    hasAll: false,
    filterOption: _newestFirst,
  );
  final albums = <PhoneAlbum>[];
  for (final path in paths) {
    if (path.isAll) continue;
    final count = await path.assetCountAsync;
    if (count == 0) continue;
    final cover = await path.getAssetListRange(start: 0, end: 1);
    albums.add(
      PhoneAlbum(
        path: path,
        name: albumFolderName(path.name),
        count: count,
        coverAssetId: cover.firstOrNull?.id,
      ),
    );
  }
  albums.sort((a, b) => b.count.compareTo(a.count));
  return albums;
});

/// What becomes of one photo or video of an album going up.
sealed class AlbumItemFate {
  const AlbumItemFate();
}

/// Already in the drive as [fileId]: it joins the album where it is, with
/// nothing sent.
final class InDrive extends AlbumItemFate {
  const InDrive(this.fileId);
  final String fileId;
}

/// On its way up already, as upload [transferId] into another album or
/// none, by photo backup say: it joins the album once it lands.
final class JoinsOnLanding extends AlbumItemFate {
  const JoinsOnLanding(this.transferId);
  final String transferId;
}

/// On its way up into this album already, from an earlier upload of it
/// that is still going.
final class AlreadyGoing extends AlbumItemFate {
  const AlreadyGoing();
}

/// Not in the drive: it goes up.
final class GoesUp extends AlbumItemFate {
  const GoesUp();
}

/// An upload in the queue that comes from a photo in the gallery, and
/// whether it already goes into the album being uploaded.
typedef PendingAssetUpload = ({String transferId, bool inAlbum});

/// Decides what becomes of each photo of an album, by the rules photo
/// backup keeps to, so nothing goes up twice: a photo backup knows it sent,
/// or one the drive holds under the same name and size, is in the drive
/// already, as long as the file is still there and not in the trash.
class AlbumUploadPlanner {
  AlbumUploadPlanner({
    required this.backedUp,
    required this.fingerprints,
    required this.pending,
    required this.isLive,
  });

  /// The phone's media id to the drive file it went up as, for every photo
  /// backed up from this phone, small copies included.
  final Map<String, String> backedUp;

  /// `name|size` of every file in the drive to its id, as
  /// [DriveRepository.mediaFingerprints] gives it.
  final Map<String, ({String fileId, bool smallCopy})> fingerprints;

  /// Uploads still to land, by the phone's media id they come from.
  final Map<String, PendingAssetUpload> pending;

  /// Whether drive file [fileId] is in the index and out of the trash.
  final Future<bool> Function(String fileId) isLive;

  /// What becomes of photo [assetId] by what the phone knows of it, before
  /// its file is read; null when that has to be read to tell.
  Future<AlbumItemFate?> before(String assetId) async {
    if (pending[assetId] case final going?) {
      return going.inAlbum ? const AlreadyGoing() : JoinsOnLanding(going.transferId);
    }
    final fileId = backedUp[assetId];
    if (fileId != null && await isLive(fileId)) return InDrive(fileId);
    return null;
  }

  /// What becomes of a photo whose file is called [name] and is [size]
  /// bytes.
  Future<AlbumItemFate> after(String name, int size) async {
    final known = fingerprints['$name|$size'];
    if (known != null && await isLive(known.fileId)) return InDrive(known.fileId);
    return const GoesUp();
  }
}

/// A photo or video of an album, read and ready to go up.
@immutable
class PreparedUpload {
  const PreparedUpload({
    required this.assetId,
    required this.name,
    required this.path,
    required this.size,
    required this.ownsSource,
    required this.takenAt,
    this.thumbnailPath,
    this.durationSeconds,
  });

  final String assetId;
  final String name;
  final String path;
  final int size;

  /// [path] is a copy the gallery made for the app, deleted once it is up.
  final bool ownsSource;
  final DateTime takenAt;

  /// A JPEG of it for the drive file's thumbnail, so a video has a poster.
  final String? thumbnailPath;

  /// A video's length, as the gallery knows it.
  final int? durationSeconds;

  /// Deletes what the app made for this upload, for one that won't go up.
  Future<void> discard() async {
    if (ownsSource) await _deleteQuietly(path);
    await discardThumbnail();
  }

  /// Deletes the thumbnail made for this upload, for one whose file the
  /// upload has already let go.
  Future<void> discardThumbnail() async {
    if (thumbnailPath case final thumbnail?) await _deleteQuietly(thumbnail);
  }
}

/// An album read through, with what becomes of each photo in it.
@immutable
class AlbumUploadPlan {
  const AlbumUploadPlan({
    required this.total,
    required this.uploads,
    required this.inDrive,
    required this.joinOnLanding,
    required this.alreadyGoing,
    required this.unreadable,
    required this.outOfRoom,
  });

  /// Photos and videos the album holds.
  final int total;
  final List<PreparedUpload> uploads;

  /// Drive files that are photos of the album already.
  final List<String> inDrive;

  /// Uploads under way of photos of the album, which join it as they land.
  final List<String> joinOnLanding;

  /// Photos going up into this album already.
  final int alreadyGoing;

  /// Photos whose file the phone couldn't hand over.
  final int unreadable;

  /// Reading stopped with photos left, as the phone was running out of
  /// room for the copies the gallery makes.
  final bool outOfRoom;

  int get bytes => uploads.fold(0, (sum, upload) => sum + upload.size);
}

/// How much the phone keeps free while the gallery copies an album out for
/// the app: once less is left, the photos read so far go up and the rest
/// wait for the album to be uploaded again.
const int _roomKept = 1 << 30;

/// The most photos asked of the gallery at once.
const int _pageSize = 100;

/// Reads [album] and settles each of its photos and videos with
/// [planner], newest first. [onProgress] hears how many of them have been
/// looked at. Returns null, having deleted every copy made, once
/// [cancelled] says so.
///
/// Where the gallery copies each original out for the app, as iOS does, a
/// phone with less than a gigabyte free stops the reading there, so the
/// copies never fill it; on Android 11 and later the original is read
/// where it lies.
Future<AlbumUploadPlan?> prepareAlbumUpload({
  required PhoneAlbum album,
  required AlbumUploadPlanner planner,
  required DeviceStorage storage,
  required void Function(int done, int total) onProgress,
  required bool Function() cancelled,
}) async {
  final temp = (await getTemporaryDirectory()).path;
  final total = await album.path.assetCountAsync;
  final uploads = <PreparedUpload>[];
  final inDrive = <String>[];
  final joinOnLanding = <String>[];
  var alreadyGoing = 0;
  var unreadable = 0;
  var outOfRoom = false;
  // Whether the gallery hands over copies, which the phone has to have room
  // for; unknown until the first file is read.
  var copies = false;
  var done = 0;

  Future<AlbumUploadPlan?> giveUp() async {
    for (final upload in uploads) {
      await upload.discard();
    }
    return null;
  }

  onProgress(0, total);
  reading:
  for (var start = 0; start < total; start += _pageSize) {
    if (cancelled()) return giveUp();
    final page = await album.path.getAssetListRange(
      start: start,
      end: start + _pageSize > total ? total : start + _pageSize,
    );
    if (page.isEmpty) break;
    for (final asset in page) {
      if (cancelled()) return giveUp();
      if (asset.type != AssetType.image && asset.type != AssetType.video) {
        onProgress(++done, total);
        continue;
      }
      switch (await planner.before(asset.id)) {
        case InDrive(:final fileId):
          inDrive.add(fileId);
          onProgress(++done, total);
          continue;
        case JoinsOnLanding(:final transferId):
          joinOnLanding.add(transferId);
          onProgress(++done, total);
          continue;
        case AlreadyGoing():
          alreadyGoing++;
          onProgress(++done, total);
          continue;
        case GoesUp() || null:
          break;
      }

      if (copies) {
        final free = await storage.freeBytes();
        if (free != null && free < _roomKept) {
          outOfRoom = true;
          break reading;
        }
      }
      final File? file;
      try {
        file = await asset.originFile;
      } catch (e) {
        debugPrint('[Albums] ${asset.id}: $e');
        unreadable++;
        onProgress(++done, total);
        continue;
      }
      if (file == null || !await file.exists()) {
        unreadable++;
        onProgress(++done, total);
        continue;
      }
      final owned = file.path.startsWith(temp);
      copies = copies || owned;
      final name = await _nameOf(asset, file);
      final size = await file.length();
      if (await planner.after(name, size) case InDrive(:final fileId)) {
        if (owned) await _deleteQuietly(file.path);
        inDrive.add(fileId);
        onProgress(++done, total);
        continue;
      }
      final isVideo = asset.type == AssetType.video;
      uploads.add(
        PreparedUpload(
          assetId: asset.id,
          name: name,
          path: file.path,
          size: size,
          ownsSource: owned,
          takenAt: asset.createDateTime,
          thumbnailPath: await _thumbnailFor(asset, temp),
          durationSeconds: isVideo && asset.duration > 0 ? asset.duration : null,
        ),
      );
      onProgress(++done, total);
    }
  }
  if (cancelled()) return giveUp();
  return AlbumUploadPlan(
    total: total,
    uploads: uploads,
    inDrive: inDrive,
    joinOnLanding: joinOnLanding,
    alreadyGoing: alreadyGoing,
    unreadable: unreadable,
    outOfRoom: outOfRoom,
  );
}

/// The photo's own file name, as backup names it, or the file's.
Future<String> _nameOf(AssetEntity asset, File file) async {
  try {
    final title = (await asset.titleAsync).trim();
    if (title.isNotEmpty) return title;
  } catch (_) {}
  return p.basename(file.path);
}

/// A JPEG of [asset] at Telegram's 320 px ceiling for document thumbnails,
/// as backup makes one, or null when the phone can't make one that small.
Future<String?> _thumbnailFor(AssetEntity asset, String temp) async {
  try {
    final bytes = await asset.thumbnailDataWithSize(
      const ThumbnailSize(320, 320),
      quality: 90,
    );
    if (bytes == null || bytes.isEmpty || bytes.length > 200 * 1024) return null;
    final dir = Directory(p.join(temp, 'telegrive-album-thumbs'));
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, '${asset.id.hashCode}.jpg'));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  } catch (_) {
    return null;
  }
}

Future<void> _deleteQuietly(String path) async {
  try {
    await File(path).delete();
  } catch (_) {}
}
