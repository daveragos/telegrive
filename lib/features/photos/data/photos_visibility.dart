import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format/formatters.dart';
import '../../../infrastructure/database/app_database.dart';
import '../../../infrastructure/storage/preferences.dart';
import '../../backup/data/backup_controller.dart';
import '../../drive/data/drive_repository.dart';
import '../../drive/domain/drive_models.dart';

/// The drive folders whose photos stay out of the Photos view, by id with
/// their names: each folder named in [hiddenNames] that sits directly inside
/// a top-level [rootName] folder. Every top-level [rootName] counts, since a
/// reinstall can leave two, and names are compared without regard to case.
/// A folder moved out from under [rootName] shows in Photos again.
Map<String, String> hiddenBackupFolders(
  List<FolderRow> folders,
  Set<String> hiddenNames,
  String rootName,
) {
  final root = rootName.toLowerCase();
  final roots = {
    for (final folder in folders)
      if (folder.parentId == null && folder.name.toLowerCase() == root) folder.id,
  };
  final names = {for (final name in hiddenNames) name.toLowerCase()};
  return {
    for (final folder in folders)
      if (roots.contains(folder.parentId) && names.contains(folder.name.toLowerCase()))
        folder.id: folder.name,
  };
}

/// [media] without the files inside [hiddenIds], unless the person asked to
/// see them. Files at the root have no folder and always stay.
List<DriveFile> filterTimeline(
  List<DriveFile> media,
  Set<String> hiddenIds, {
  required bool reveal,
}) {
  if (reveal || hiddenIds.isEmpty) return media;
  return [
    for (final file in media)
      if (!hiddenIds.contains(file.folderId)) file,
  ];
}

/// The line above the Photos grid for the kept-out folders [names] (sorted,
/// at least one). Kept out it names up to two folders; revealed it names the
/// first and counts the rest, which keeps it short.
String keptOutSentence(List<String> names, {required bool revealed}) {
  String others(int count) => Formatters.count(count, 'other folder');
  if (revealed) {
    return names.length == 1
        ? 'Showing ${names.first}'
        : 'Showing ${names.first} and ${others(names.length - 1)}';
  }
  return switch (names) {
    [final only] => '$only is kept out of this view',
    [final first, final second] => '$first and $second are kept out of this view',
    _ => '${names.first} and ${others(names.length - 1)} are kept out of this view',
  };
}

/// Photo backup folders kept out of the Photos view, by id with their
/// names. Worked out from the live folder tree, so renames and moves count.
final hiddenBackupFoldersProvider = StreamProvider.autoDispose<Map<String, String>>((ref) {
  final names = ref.watch(preferencesProvider).photosHiddenFolders;
  return ref
      .watch(appDatabaseProvider)
      .watchAllFolders()
      .map((rows) => hiddenBackupFolders(rows, names, BackupController.rootFolder));
});

/// Whether the Photos view shows the kept-out folders after all. It lasts
/// until the app is closed.
class RevealHidden extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
}

final revealHiddenProvider = NotifierProvider<RevealHidden, bool>(RevealHidden.new);

/// The timeline as the Photos tab, its viewer, and Favorites and Videos show
/// it: without the kept-out folders unless they are revealed.
final photosTimelineProvider = Provider.autoDispose<AsyncValue<List<DriveFile>>>((ref) {
  final hidden = ref.watch(hiddenBackupFoldersProvider);
  final reveal = ref.watch(revealHiddenProvider);
  final media = ref.watch(mediaTimelineProvider);
  // Until the folders are known, a kept-out screenshot would flash past.
  if (!hidden.hasValue && !hidden.hasError) return const AsyncLoading();
  final ids = (hidden.value ?? const {}).keys.toSet();
  return media.whenData((files) => filterTimeline(files, ids, reveal: reveal));
});

/// How many timeline files are in kept-out folders, and those folders'
/// names, sorted. The same whether or not they are revealed.
final keptOutSummaryProvider = Provider.autoDispose<({int count, List<String> names})>((ref) {
  final hidden = ref.watch(hiddenBackupFoldersProvider).value ?? const {};
  final media = ref.watch(mediaTimelineProvider).value ?? const [];
  var count = 0;
  // Two backup roots can each hold a Screenshots folder; it is named once.
  final names = <String, String>{};
  if (hidden.isNotEmpty) {
    for (final file in media) {
      final name = hidden[file.folderId];
      if (name == null) continue;
      count++;
      names.putIfAbsent(name.toLowerCase(), () => name);
    }
  }
  final sorted = names.keys.toList()..sort();
  return (count: count, names: [for (final key in sorted) names[key]!]);
});
