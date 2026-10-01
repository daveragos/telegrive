import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../drive/data/drive_repository.dart';
import '../../drive/domain/drive_models.dart';

/// Every folder by id, so a list can say where each of its files lives
/// from one map rather than a query per row.
final folderIndexProvider = StreamProvider.autoDispose<Map<String, DriveFolder>>(
  (ref) => ref
      .watch(driveRepositoryProvider)
      .watchAllFolders()
      .map((all) => {for (final folder in all) folder.id: folder}),
);

/// Where a file in [folderId] lives, as 'Work › Invoices', or 'Files' at
/// the root. A file whose folder is gone shows at the root, so it reads
/// 'Files' too. With [fromRoot] the path starts at 'Files' either way.
String locationOf(
  Map<String, DriveFolder> byId,
  String? folderId, {
  bool fromRoot = false,
}) {
  final names = <String>[];
  final seen = <String>{};
  var cursor = folderId;
  while (cursor != null && seen.add(cursor)) {
    final folder = byId[cursor];
    if (folder == null) break;
    names.insert(0, folder.name);
    cursor = folder.parentId;
  }
  if (names.isEmpty || fromRoot) names.insert(0, 'Files');
  return names.join(' › ');
}
