import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/files/zip_reader.dart';

/// A zip file the person picked, as Android names it.
@immutable
class PickedArchive {
  const PickedArchive({required this.uri, required this.name, required this.size});

  final String uri;
  final String name;
  final int size;
}

/// The zip files of a Google Photos export, through the telegrive/archives
/// channel: Android's picker for them, reading them where they lie, and
/// deleting them once they're done with. Android only; elsewhere [pick]
/// finds nothing.
class TakeoutFiles {
  const TakeoutFiles();

  static const _channel = MethodChannel('telegrive/archives');

  static bool get supported => !kIsWeb && Platform.isAndroid;

  /// Opens Android's picker for zip files. Backing out answers an empty
  /// list, and a file Android won't keep access to is left out.
  Future<List<PickedArchive>> pick() async {
    if (!supported) return const [];
    final picked = await _channel.invokeListMethod<Map<Object?, Object?>>('pick') ?? const [];
    return [
      for (final map in picked)
        PickedArchive(uri: map['uri']! as String, name: map['name']! as String, size: (map['size']! as num).toInt()),
    ];
  }

  /// The zip at [uri], [length] bytes long, to read where it lies.
  ZipSource open(String uri, int length) => _DocumentZipSource(uri, length);

  /// Whether Telegrive can still read [uri].
  Future<bool> canRead(String uri) async =>
      supported && (await _channel.invokeMethod<bool>('canRead', {'uri': uri}) ?? false);

  /// Gives back the access kept for [uri].
  Future<void> release(String uri) async {
    if (!supported) return;
    try {
      final left = await _channel.invokeMethod<int>('release', {'uri': uri});
      debugPrint('[Takeout] released a part; $left grants held');
    } on PlatformException catch (e) {
      debugPrint('[Takeout] release: ${e.message}');
    }
  }

  /// Deletes [uri] from the phone. False when its app won't let Telegrive.
  Future<bool> delete(String uri) async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('delete', {'uri': uri}) ?? false;
    } on PlatformException catch (e) {
      debugPrint('[Takeout] delete: ${e.message}');
      return false;
    }
  }

  /// Lets go of the parts held open between reads.
  Future<void> closeAll() async {
    if (!supported) return;
    await _channel.invokeMethod<bool>('closeAll');
  }
}

final takeoutFilesProvider = Provider<TakeoutFiles>((ref) => const TakeoutFiles());

/// What a channel error code means for the part it came from.
ZipProblem? _problemOf(PlatformException e) => switch (e.code) {
  'incomplete' => ZipProblem.incomplete,
  'damaged' => ZipProblem.damaged,
  'unsupported' => ZipProblem.unsupported,
  _ => null,
};

/// Thrown when Android no longer lets Telegrive read a part.
class TakeoutAccessException implements Exception {
  const TakeoutAccessException(this.message);

  final String message;

  @override
  String toString() => 'TakeoutAccessException: $message';
}

class _DocumentZipSource implements ZipSource {
  _DocumentZipSource(this.uri, this.length);

  final String uri;

  @override
  final int length;

  @override
  Future<List<Uint8List>> read(List<ByteRange> ranges) => _call(() async {
    final answer = await TakeoutFiles._channel.invokeListMethod<Uint8List>('read', {
      'uri': uri,
      'ranges': [
        for (final range in ranges) [range.offset, range.length],
      ],
    });
    return answer ?? const [];
  });

  @override
  Future<void> extract(ZipEntry entry, int dataOffset, String path) => _call(() async {
    await TakeoutFiles._channel.invokeMethod<int>('extract', {
      'uri': uri,
      'offset': dataOffset,
      'compressedSize': entry.compressedSize,
      'method': entry.method,
      'size': entry.size,
      'crc': entry.crc,
      'path': path,
    });
  });

  /// Runs [call], turning the channel's errors into what the zip reader and
  /// the import tell apart.
  Future<T> _call<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on PlatformException catch (e) {
      if (e.code == 'no_access') throw TakeoutAccessException(e.message ?? 'Can\'t read the part');
      if (_problemOf(e) case final problem?) throw ZipFormatException(problem, e.message ?? problem.name);
      rethrow;
    }
  }
}
