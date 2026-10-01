import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../infrastructure/database/app_database.dart';

/// The phone's own copies of backed-up photos.
///
/// Telegram keeps document thumbnails at 320 px at most, which is soft in a
/// grid on a dense screen. For anything backed up from this phone and still
/// in its library, the phone has a sharp copy for free, so thumbnails and
/// the viewer use that, and only fall back to Telegram for files that live
/// nowhere else.

bool get _supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

final _localAssetsProvider = StreamProvider<Map<String, String>>(
  (ref) => ref.watch(appDatabaseProvider).watchLocalAssets(),
);

/// The phone's media id for drive file [fileId], when it was backed up
/// from here.
Future<String?> _assetIdFor(Ref ref, String fileId, {required bool wait}) async =>
    wait
    ? (await ref.watch(_localAssetsProvider.future))[fileId]
    // Grids must not rebuild every tile each time backup finishes a photo,
    // so they only follow their own entry.
    : ref.watch(_localAssetsProvider.select((v) => v.value?[fileId]));

Future<AssetEntity?> _asset(String? assetId) async {
  if (!_supported || assetId == null) return null;
  try {
    return await AssetEntity.fromId(assetId);
  } catch (_) {
    return null;
  }
}

/// A square thumbnail of the phone's photo [assetId], or null when the
/// phone no longer has it.
Future<Uint8List?> _thumbnail(String? assetId, {required int size, required int quality}) async {
  final asset = await _asset(assetId);
  if (asset == null) return null;
  try {
    return await asset.thumbnailDataWithSize(ThumbnailSize.square(size), quality: quality);
  } catch (_) {
    return null;
  }
}

/// A sharp ~480 px thumbnail from the phone's library, or null.
final localThumbnailProvider = FutureProvider.autoDispose.family<Uint8List?, String>((
  ref,
  fileId,
) async {
  if (!_supported) return null;
  return _thumbnail(await _assetIdFor(ref, fileId, wait: false), size: 480, quality: 88);
});

/// A row-sized thumbnail of a photo backup knows by its media id, for one
/// that has no drive file yet.
final assetThumbnailProvider = FutureProvider.autoDispose.family<Uint8List?, String>(
  (ref, assetId) => _thumbnail(assetId, size: 160, quality: 85),
);

/// The file name of the phone's photo [assetId], or Photo or Video when it
/// has none. Null when the phone no longer has it.
final assetTitleProvider = FutureProvider.autoDispose.family<String?, String>((
  ref,
  assetId,
) async {
  final asset = await _asset(assetId);
  if (asset == null) return null;
  try {
    final title = (await asset.titleAsync).trim();
    if (title.isNotEmpty) return title;
  } catch (_) {}
  return asset.type == AssetType.video ? 'Video' : 'Photo';
});

/// Path of the photo itself on this phone, so the viewer shows it at once
/// instead of downloading it from Telegram. Null when the phone has no copy.
final localOriginalProvider = FutureProvider.autoDispose.family<String?, String>((
  ref,
  fileId,
) async {
  if (!_supported) return null;
  final asset = await _asset(await _assetIdFor(ref, fileId, wait: true));
  if (asset == null) return null;
  try {
    final file = await asset.file;
    return file != null && await file.exists() ? file.path : null;
  } catch (_) {
    return null;
  }
});
