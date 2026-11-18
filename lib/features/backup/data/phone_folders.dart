import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/platform/app_platform.dart';
import 'desktop_folders.dart';

/// A folder the person picked in Android's folder picker, with the read
/// access Android keeps for it, or in a computer's own.
@immutable
class PickedFolder {
  const PickedFolder({required this.uri, required this.name});

  /// The tree URI, which lists the folder and gives the access back; on a
  /// computer, the folder's path.
  final String uri;

  /// The folder's own name, as the picker showed it.
  final String name;
}

/// One file in a picked folder, as its provider describes it. A size or
/// date the provider leaves out is 0, or the start of 1970.
@immutable
class PhoneDocument {
  const PhoneDocument({
    required this.id,
    required this.name,
    required this.mimeType,
    required this.size,
    required this.modifiedAt,
    this.dir = '',
    this.uri,
  });

  factory PhoneDocument.fromMap(Map<Object?, Object?> map) => PhoneDocument(
    id: map['id']! as String,
    name: map['name'] as String? ?? '',
    mimeType: map['mime'] as String? ?? '',
    size: (map['size'] as num? ?? 0).toInt(),
    modifiedAt: DateTime.fromMillisecondsSinceEpoch((map['modified'] as num? ?? 0).toInt()),
    dir: map['dir'] as String? ?? '',
    uri: map['uri'] as String?,
  );

  /// The provider's document id, which stays the same while the file keeps
  /// its name and place.
  final String id;
  final String name;

  /// The type the provider gives, or empty when it gives none.
  final String mimeType;
  final int size;
  final DateTime modifiedAt;

  /// The folders it is in below the picked one, as `Trip/Day 1`; empty for
  /// a file at the top.
  final String dir;

  /// Where it is read from while the app runs, through the folder's access.
  final String? uri;
}

/// Phone folders picked through Android's folder picker, reached through
/// the telegrive/folders channel. Nothing needs a storage permission: each
/// folder is read on the access granted when it was picked.
///
/// On a computer the folders are picked in the system's own picker and
/// read where they are, through [DesktopFolders], and their files go up
/// from there with no copy made.
class PhoneFolders {
  static const _channel = MethodChannel('telegrive/folders');

  /// The most files a listing goes through; a bigger tree comes back cut
  /// short, with `truncated` set.
  static const int listLimit = 20000;

  /// Whether folders can be picked and watched: on Android and on a
  /// computer. Elsewhere the Backup screen leaves the group out and nothing
  /// is checked.
  static bool get supported =>
      _supported ?? (!kIsWeb && (Platform.isAndroid || AppPlatform.isDesktop));
  static bool? _supported;

  /// Tests that render the group or run a check turn it on.
  @visibleForTesting
  static set supported(bool value) => _supported = value;

  /// Whether a file goes up from a copy in the app's cache, which needs
  /// room for it: on a phone, not on a computer.
  bool get copies => !AppPlatform.isDesktop;

  /// Opens the picker and waits for a folder, or null when the person backed
  /// out. With [keep] the folder stays readable after a restart, and a
  /// [PlatformException] coded `not_persisted` means Android wouldn't keep
  /// access to it; without, it is readable while the app runs.
  Future<PickedFolder?> pick({bool keep = true}) async {
    if (AppPlatform.isDesktop) {
      final path = await FilePicker.getDirectoryPath(dialogTitle: 'Choose a folder to upload from');
      return path == null ? null : PickedFolder(uri: path, name: p.basename(path));
    }
    final map = await _channel.invokeMapMethod<Object?, Object?>('pick', {'keep': keep});
    if (map == null) return null;
    return PickedFolder(uri: map['uri']! as String, name: map['name']! as String);
  }

  /// The files in folder [uri], and in its subfolders with [recursive]. A
  /// folder of more than [listLimit] files is cut short, and [truncated]
  /// says so.
  Future<({List<PhoneDocument> files, bool truncated})> list(
    String uri, {
    required bool recursive,
  }) async {
    if (AppPlatform.isDesktop) {
      return DesktopFolders.list(uri, recursive: recursive, skipHidden: true);
    }
    final map = await _channel.invokeMapMethod<Object?, Object?>('list', {
      'uri': uri,
      'recursive': recursive,
    });
    final files = (map?['files'] as List<Object?>? ?? const [])
        .map((file) => PhoneDocument.fromMap(file! as Map<Object?, Object?>))
        .toList();
    return (files: files, truncated: map?['truncated'] == true);
  }

  /// Where [doc] of folder [uri] goes up from: on a phone a copy in the
  /// app's cache, which the upload owns and deletes once it is sent; on a
  /// computer the file itself, as it is now.
  Future<({String path, int size, bool owned})> source(String uri, PhoneDocument doc) async {
    if (AppPlatform.isDesktop) {
      final file = File(doc.uri ?? p.joinAll([uri, ...doc.id.split('/')]));
      return (path: file.path, size: await file.length(), owned: false);
    }
    final copied = await copy(uri, doc);
    return (path: copied.path, size: copied.size, owned: true);
  }

  /// Copies [doc] from folder [uri] into the app's cache, for an upload
  /// that deletes the copy once it is sent.
  Future<({String path, int size})> copy(String uri, PhoneDocument doc) async {
    final map = await _channel.invokeMapMethod<Object?, Object?>('copy', {
      'uri': uri,
      'documentId': doc.id,
      'name': doc.name,
    });
    if (map == null) throw FileSystemException('Couldn\'t copy the file', doc.name);
    return (path: map['path']! as String, size: (map['size']! as num).toInt());
  }

  /// Gives back the access kept for folder [uri], and logs how many folders
  /// stay readable. Access that is already gone, or a phone with no
  /// picker, leaves nothing to give back.
  Future<void> release(String uri) async {
    if (AppPlatform.isDesktop) return;
    try {
      final left = await _channel.invokeMethod<int>('release', {'uri': uri});
      debugPrint('[Folders] Gave back $uri; $left still readable');
    } catch (e) {
      debugPrint('[Folders] $e');
    }
  }

  /// Whether folder [uri] can still be read: the access is kept and the
  /// folder is still there.
  Future<bool> canRead(String uri) async {
    if (AppPlatform.isDesktop) {
      try {
        await Directory(uri).list(followLinks: false).isEmpty;
        return true;
      } on FileSystemException {
        return false;
      }
    }
    try {
      return await _channel.invokeMethod<bool>('canRead', {'uri': uri}) ?? false;
    } catch (e) {
      debugPrint('[Folders] $e');
      return false;
    }
  }
}

final phoneFoldersProvider = Provider<PhoneFolders>((ref) => PhoneFolders());
