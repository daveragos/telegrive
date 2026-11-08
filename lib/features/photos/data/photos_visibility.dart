import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/files/file_kind.dart';
import '../../../core/format/formatters.dart';
import '../../../infrastructure/database/app_database.dart';
import '../../../infrastructure/storage/preferences.dart';
import '../../backup/data/backup_controller.dart';
import '../../drive/data/drive_repository.dart';
import '../../drive/domain/drive_models.dart';
import '../../takeout/domain/takeout_catalog.dart';

/// Every folder of [folders] that [marked] picks out, and every folder
/// inside one, by id, to the name of the outermost marked folder it is in.
/// A folder tree that loops ends anyway.
Map<String, String> markedSubtrees(
  List<FolderRow> folders,
  bool Function(FolderRow folder) marked,
) {
  final byId = {for (final folder in folders) folder.id: folder};
  final out = <String, String>{};
  for (final folder in folders) {
    FolderRow? top;
    final seen = <String>{};
    for (FolderRow? cursor = folder;
        cursor != null && seen.add(cursor.id);
        cursor = byId[cursor.parentId]) {
      if (marked(cursor)) top = cursor;
    }
    if (top != null) out[folder.id] = top.name;
  }
  return out;
}

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

/// [media] with one tile for each photo: a video beside a photo of the same
/// name, in the same folder, is that Live Photo's movement and goes, and an
/// original beside its edited copy (`IMG_1-edited.jpg`) goes, leaving the
/// edited one. Both stay in Files. The order is kept.
List<DriveFile> oneTilePerPhoto(List<DriveFile> media) {
  String stem(String name) {
    final dot = name.lastIndexOf('.');
    return (dot <= 0 ? name : name.substring(0, dot)).toLowerCase();
  }

  String place(DriveFile file) => '${file.folderId}/${stem(file.name)}';
  final photos = {
    for (final file in media)
      if (file.kind == FileKind.image) place(file),
  };
  return [
    for (final file in media)
      if (!(file.kind == FileKind.video && photos.contains(place(file))) &&
          !(file.kind == FileKind.image &&
              takeoutEditedSuffixes.any((suffix) => photos.contains('${place(file)}$suffix'))))
        file,
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

/// Folders kept out of the Photos view on every phone, each with the
/// folders inside it, by id with the name of the folder that was kept out.
/// Worked out from the live folder tree, so moves count.
final photosHiddenFoldersProvider = StreamProvider.autoDispose<Map<String, String>>(
  (ref) => ref
      .watch(appDatabaseProvider)
      .watchAllFolders()
      .map((rows) => markedSubtrees(rows, (folder) => folder.hiddenFromPhotos)),
);

/// Every folder the Photos view keeps out until it is shown: photo backup's
/// kept-out folders on this phone, and the folders kept out on every phone
/// with those inside them, by id with the name the line above the grid
/// gives them. Loading until both are known.
final keptOutFoldersProvider = Provider.autoDispose<AsyncValue<Map<String, String>>>((ref) {
  final backup = ref.watch(hiddenBackupFoldersProvider);
  final chosen = ref.watch(photosHiddenFoldersProvider);
  bool known(AsyncValue<Object?> value) => value.hasValue || value.hasError;
  if (!known(backup) || !known(chosen)) return const AsyncLoading();
  return AsyncData({...?backup.value, ...?chosen.value});
});

/// Whether the Photos view shows the kept-out folders after all. It lasts
/// until the app is closed or the account signs out.
class RevealHidden extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
}

final revealHiddenProvider = NotifierProvider<RevealHidden, bool>(RevealHidden.new);

/// The timeline as the Photos tab, its viewer, and Favorites and Videos show
/// it: without the kept-out folders unless they are revealed, and with one
/// tile for each photo. What is in Private never reaches it.
final photosTimelineProvider = Provider.autoDispose<AsyncValue<List<DriveFile>>>((ref) {
  final hidden = ref.watch(keptOutFoldersProvider);
  final reveal = ref.watch(revealHiddenProvider);
  final media = ref.watch(mediaTimelineProvider);
  // Until the folders are known, a kept-out screenshot would flash past.
  if (hidden.isLoading) return const AsyncLoading();
  final ids = (hidden.value ?? const {}).keys.toSet();
  return media.whenData((files) => oneTilePerPhoto(filterTimeline(files, ids, reveal: reveal)));
});

/// How many timeline files are in kept-out folders, and those folders'
/// names, sorted. The same whether or not they are revealed.
final keptOutSummaryProvider = Provider.autoDispose<({int count, List<String> names})>((ref) {
  final hidden = ref.watch(keptOutFoldersProvider).value ?? const {};
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

/// What the Photos tab shows of the timeline.
enum PhotosShow {
  all('All'),
  photos('Photos'),
  videos('Videos');

  const PhotosShow(this.label);

  final String label;
}

/// The Photos tab's choice of what to show and in which order, remembered.
@immutable
class PhotosView {
  const PhotosView({this.show = PhotosShow.all, this.oldestFirst = false});

  final PhotosShow show;
  final bool oldestFirst;
}

class PhotosViewChoice extends Notifier<PhotosView> {
  @override
  PhotosView build() {
    final prefs = ref.watch(preferencesProvider);
    return PhotosView(
      show: PhotosShow.values.where((s) => s.name == prefs.photosShow).firstOrNull ?? PhotosShow.all,
      oldestFirst: prefs.photosOldestFirst,
    );
  }

  void show(PhotosShow show) {
    if (show == state.show) return;
    state = PhotosView(show: show, oldestFirst: state.oldestFirst);
    ref.read(preferencesProvider).setPhotosShow(show.name);
  }

  void setOldestFirst(bool on) {
    if (on == state.oldestFirst) return;
    state = PhotosView(show: state.show, oldestFirst: on);
    ref.read(preferencesProvider).setPhotosOldestFirst(on);
  }
}

final photosViewProvider = NotifierProvider<PhotosViewChoice, PhotosView>(PhotosViewChoice.new);

/// [timeline], newest first, as [view] has the Photos tab show it: only
/// its photos or only its videos, and oldest first.
List<DriveFile> photosTab(List<DriveFile> timeline, PhotosView view) {
  final shown = switch (view.show) {
    PhotosShow.all => timeline,
    PhotosShow.photos => [for (final f in timeline) if (f.kind != FileKind.video) f],
    PhotosShow.videos => [for (final f in timeline) if (f.kind == FileKind.video) f],
  };
  return view.oldestFirst ? shown.reversed.toList() : shown;
}

/// The Photos tab's grid, and its viewer, which swipes in the same order.
final photosTabProvider = Provider.autoDispose<AsyncValue<List<DriveFile>>>((ref) {
  final view = ref.watch(photosViewProvider);
  return ref.watch(photosTimelineProvider).whenData((files) => photosTab(files, view));
});

