import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../infrastructure/database/app_database.dart';
import 'backup_controller.dart';

/// Photos and videos on this phone that are safely in the drive.
@immutable
class Freeable {
  const Freeable(this.assetIds, this.bytes);

  static const none = Freeable([], 0);

  final List<String> assetIds;
  final int bytes;

  int get count => assetIds.length;
  bool get isEmpty => assetIds.isEmpty;
}

/// What "Free up space" would delete: everything backed up from this phone
/// whose drive copy is complete and not in the trash, and that the phone
/// still has. Sizes are the drive copies', which are the originals.
final freeableProvider = FutureProvider.autoDispose<Freeable>((ref) async {
  if (kIsWeb) return Freeable.none;
  // Worked out again as backup moves along.
  ref.watch(backupControllerProvider.select((b) => (b.phase, b.done)));
  final safe = await ref.watch(appDatabaseProvider).safelyBackedUp();
  if (safe.isEmpty) return Freeable.none;
  final permission = await PhotoManager.getPermissionState(
    requestOption: BackupController.permissionOption,
  );
  if (!permission.hasAccess) return Freeable.none;
  final onPhone = await _phoneAssetIds();
  final ids = [for (final id in safe.keys) if (onPhone.contains(id)) id];
  return Freeable(ids, ids.fold(0, (sum, id) => sum + safe[id]!));
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
Future<int> freeUpSpace(Freeable freeable) async {
  final ids = freeable.assetIds;
  var deleted = 0;
  for (var i = 0; i < ids.length; i += 500) {
    final gone = await PhotoManager.editor.deleteWithIds(
      ids.sublist(i, math.min(i + 500, ids.length)),
    );
    // An empty answer means the person said no.
    if (gone.isEmpty) break;
    deleted += gone.length;
  }
  return deleted;
}
