import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A folder the person picked in Android's folder picker, with the read
/// access Android keeps for it.
@immutable
class PickedFolder {
  const PickedFolder({required this.uri, required this.name});

  /// The tree URI, which lists the folder and gives the access back.
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
  });

  factory PhoneDocument.fromMap(Map<Object?, Object?> map) => PhoneDocument(
    id: map['id']! as String,
    name: map['name'] as String? ?? '',
    mimeType: map['mime'] as String? ?? '',
    size: (map['size'] as num? ?? 0).toInt(),
    modifiedAt: DateTime.fromMillisecondsSinceEpoch((map['modified'] as num? ?? 0).toInt()),
  );

  /// The provider's document id, which stays the same while the file keeps
  /// its name and place.
  final String id;
  final String name;

  /// The type the provider gives, or empty when it gives none.
  final String mimeType;
  final int size;
  final DateTime modifiedAt;
}

/// Phone folders picked through Android's folder picker, reached through
/// the telegrive/folders channel. Nothing needs a storage permission: each
/// folder is read on the access granted when it was picked.
class PhoneFolders {
  static const _channel = MethodChannel('telegrive/folders');

  /// The most files a listing goes through; a bigger tree comes back cut
  /// short, with `truncated` set.
  static const int listLimit = 20000;

  /// Whether this phone has the folder picker. Off Android the Backup
  /// screen leaves the group out and nothing is checked.
  static bool get supported => _supported;
  static bool _supported = !kIsWeb && Platform.isAndroid;

  /// Tests that render the group or run a check turn it on.
  @visibleForTesting
  static set supported(bool value) => _supported = value;

  /// Opens the picker and waits for a folder, or null when the person backed
  /// out. A [PlatformException] coded `not_persisted` means Android
  /// wouldn't keep access to the folder that was picked.
  Future<PickedFolder?> pick() async {
    final map = await _channel.invokeMapMethod<Object?, Object?>('pick');
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
    final map = await _channel.invokeMapMethod<Object?, Object?>('list', {
      'uri': uri,
      'recursive': recursive,
    });
    final files = (map?['files'] as List<Object?>? ?? const [])
        .map((file) => PhoneDocument.fromMap(file! as Map<Object?, Object?>))
        .toList();
    return (files: files, truncated: map?['truncated'] == true);
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
    try {
      return await _channel.invokeMethod<bool>('canRead', {'uri': uri}) ?? false;
    } catch (e) {
      debugPrint('[Folders] $e');
      return false;
    }
  }
}

final phoneFoldersProvider = Provider<PhoneFolders>((ref) => PhoneFolders());
