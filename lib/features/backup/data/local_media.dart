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

Future<AssetEntity?> _assetFor(Ref ref, String fileId, {required bool wait}) async {
  if (!_supported) return null;
  final assetId = wait
      ? (await ref.watch(_localAssetsProvider.future))[fileId]
      // Grids must not rebuild every tile each time backup finishes a photo,
      // so they only follow their own entry.
      : ref.watch(_localAssetsProvider.select((v) => v.value?[fileId]));
  if (assetId == null) return null;
  try {
    return await AssetEntity.fromId(assetId);
  } catch (_) {
    return null;
  }
}

/// A sharp ~480 px thumbnail from the phone's library, or null.
final localThumbnailProvider = FutureProvider.autoDispose.family<Uint8List?, String>((
  ref,
  fileId,
) async {
  final asset = await _assetFor(ref, fileId, wait: false);
  if (asset == null) return null;
  try {
    return await asset.thumbnailDataWithSize(
      const ThumbnailSize.square(480),
      quality: 88,
    );
  } catch (_) {
    return null;
  }
});

/// Path of the photo itself on this phone, so the viewer shows it at once
/// instead of downloading it from Telegram. Null when the phone has no copy.
final localOriginalProvider = FutureProvider.autoDispose.family<String?, String>((
  ref,
  fileId,
) async {
  final asset = await _assetFor(ref, fileId, wait: true);
  if (asset == null) return null;
  try {
    final file = await asset.file;
    return file != null && await file.exists() ? file.path : null;
  } catch (_) {
    return null;
  }
});
