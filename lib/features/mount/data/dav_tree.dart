import 'package:flutter/foundation.dart';

import '../../../infrastructure/storage/device_storage.dart';
import '../../backup/data/desktop_folders.dart';
import '../../drive/domain/drive_models.dart';

/// One thing in a folder of the mounted drive: a drive folder or file,
/// under the name the mount gives it.
@immutable
class DavEntry {
  const DavEntry.folder(this.name, DriveFolder this.folder) : file = null;
  const DavEntry.file(this.name, DriveFile this.file) : folder = null;

  /// Unique in its folder, ignoring case, and fit for any file system.
  final String name;
  final DriveFolder? folder;
  final DriveFile? file;

  bool get isFolder => folder != null;
}

/// [name] as a file system can take it: no slashes, colons, control
/// characters or the ones Windows refuses.
String davName(String name) => DeviceStorage.safeName(name).replaceAll(RegExp(r'[*?"<>|]'), '_');

/// [folders] and [files] of one drive folder under names the mount can
/// show. The drive lets two things share a name; a file system doesn't,
/// so the first of each name, folders before files and then by id, keeps
/// it, and the rest are numbered as a download would be, `Report (2).pdf`.
/// Going by id keeps a name with the same thing from one listing to the
/// next. Folders in Private aren't listed.
List<DavEntry> davEntries(List<DriveFolder> folders, List<DriveFile> files) {
  final shownFolders = [...folders.where((f) => !f.inPrivate)]..sort((a, b) => a.id.compareTo(b.id));
  final sortedFiles = [...files]..sort((a, b) => a.id.compareTo(b.id));
  final taken = <String>{};
  final entries = <DavEntry>[];
  String claim(String wanted, {required bool folder}) {
    var name = wanted;
    for (var n = 2; !taken.add(name.toLowerCase()); n++) {
      name = folder ? '$wanted ($n)' : DeviceStorage.numbered(wanted, n);
    }
    return name;
  }

  for (final folder in shownFolders) {
    entries.add(DavEntry.folder(claim(davName(folder.name), folder: true), folder));
  }
  for (final file in sortedFiles) {
    entries.add(DavEntry.file(claim(davName(file.name), folder: false), file));
  }
  return entries;
}

/// Whether a file or folder named [name] is one the system or an app
/// leaves behind rather than one the person means to keep: hidden names,
/// Finder's `._` and `.DS_Store`, Explorer's `Thumbs.db` and
/// `desktop.ini`, Office's `~$` lock files, and an app's temporary file
/// while it saves. The mount keeps these on the computer and never
/// uploads them.
bool davJunk(String name) => name.startsWith('.') || DesktopFolders.isClutter(name);
