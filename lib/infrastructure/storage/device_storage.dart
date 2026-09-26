import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';

/// The phone's own storage, where downloads to this phone are kept.
///
/// * **Android** — `Download/Telegrive/…`, written through MediaStore, so the
///   Files app and every file manager see it.
/// * **iOS** — the app's Documents folder, which the Files app shows as
///   On My iPhone › Telegrive.
///
/// Photos and videos can go to the gallery instead.
class DeviceStorage {
  static const _channel = MethodChannel('telegrive/device_storage');
  static const _folder = 'Telegrive';

  /// Where saved files are, in words a person can follow to find them.
  static String get location =>
      Platform.isIOS ? 'Files › On My iPhone › Telegrive' : 'Download › Telegrive';

  /// Space left on the phone, or null when it can't be read.
  Future<int?> freeBytes() async {
    try {
      return await _channel.invokeMethod<int>('freeBytes');
    } catch (_) {
      return null;
    }
  }

  /// Asks for whatever access saving needs. Only Android 9 and older need a
  /// permission for files; the gallery needs photo access on iOS.
  Future<bool> ensureAccess({required bool gallery}) async {
    if (Platform.isAndroid) {
      try {
        return await _channel.invokeMethod<bool>('ensureWriteAccess') ?? false;
      } catch (_) {
        return false;
      }
    }
    if (!gallery) return true;
    final state = await PhotoManager.requestPermissionExtend(
      requestOption: const PermissionRequestOption(
        iosAccessLevel: IosAccessLevel.readWrite,
      ),
    );
    return state.hasAccess;
  }

  /// Copies [source] into [folders] under the save location as [name]. A
  /// file already there with that name and size is taken to be this one;
  /// any other clash gets a numbered name. Returns where the copy is.
  Future<String> saveFile(
    String source, {
    required List<String> folders,
    required String name,
    required String mimeType,
  }) async {
    final dirs = [for (final folder in folders) safeName(folder)];
    final fileName = safeName(name);
    if (Platform.isAndroid) {
      final saved = await _channel.invokeMethod<String>('saveToDownloads', {
        'source': source,
        'relativePath': ['Download', _folder, ...dirs].join('/'),
        'name': fileName,
        'mimeType': mimeType,
      });
      if (saved == null) throw FileSystemException('Couldn\'t save the file', name);
      return saved;
    }

    final documents = await getApplicationDocumentsDirectory();
    final dir = Directory(p.joinAll([documents.path, ...dirs]));
    await dir.create(recursive: true);
    final size = await File(source).length();
    var target = File(p.join(dir.path, fileName));
    for (var n = 1; await target.exists(); n++) {
      if (await target.length() == size) return target.path;
      target = File(p.join(dir.path, numbered(fileName, n)));
    }
    // A clone on APFS: instant, and no extra space until one side changes.
    await File(source).copy(target.path);
    return target.path;
  }

  /// Puts a photo or video into the gallery, dated [takenAt]. On Android it
  /// goes back into [album] (the phone folder it was backed up from) when
  /// known. Returns the gallery's id for it.
  Future<String> saveToGallery(
    String source, {
    required String name,
    required bool video,
    String? album,
    DateTime? takenAt,
  }) async {
    final relativePath = switch (album) {
      'Camera' || 'Camera Roll' => 'DCIM/Camera',
      null => video ? 'Movies/$_folder' : 'Pictures/$_folder',
      final folder => video ? 'Movies/${safeName(folder)}' : 'Pictures/${safeName(folder)}',
    };
    final asset = video
        ? await PhotoManager.editor.saveVideo(
            File(source),
            title: name,
            relativePath: relativePath,
            creationDate: takenAt,
          )
        : await PhotoManager.editor.saveImageWithPath(
            source,
            title: name,
            relativePath: relativePath,
            creationDate: takenAt,
          );
    return asset.id;
  }

  /// Whether the gallery still has item [assetId].
  Future<bool> inGallery(String assetId) async {
    try {
      return await AssetEntity.fromId(assetId) != null;
    } catch (_) {
      return false;
    }
  }

  /// [name] made safe to use as one file or folder name.
  static String safeName(String name) {
    final clean = name.replaceAll(RegExp(r'[\\/:\x00-\x1f]'), '_').trim();
    return clean.isEmpty || clean == '.' || clean == '..' ? '_' : clean;
  }

  /// `photo.jpg`, 2 → `photo (2).jpg`.
  static String numbered(String name, int n) {
    final extension = p.extension(name);
    final base = name.substring(0, name.length - extension.length);
    return '$base ($n)$extension';
  }
}

final deviceStorageProvider = Provider<DeviceStorage>((_) => DeviceStorage());
