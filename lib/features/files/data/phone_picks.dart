import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A file picked in Android's document picker, not copied anywhere yet.
@immutable
class PickedDocument {
  const PickedDocument({required this.uri, required this.name, this.size});

  /// The content URI the picker gave, readable while the app runs.
  final String uri;
  final String name;

  /// Null when the provider wouldn't say.
  final int? size;
}

/// Files picked for upload through the telegrive/picks channel. The picker
/// gives back where each file is, and each is copied only when its upload
/// starts, so picking hundreds at once copies nothing up front.
abstract final class PhonePicks {
  static const _channel = MethodChannel('telegrive/picks');

  /// Whether this phone picks this way. Elsewhere the file picker plugin
  /// makes its copies at once.
  static bool get supported => !kIsWeb && Platform.isAndroid;

  /// Opens the picker, for photos and videos only with [media], and waits
  /// for the files picked; none when the person backed out.
  static Future<List<PickedDocument>> pick({required bool media}) async {
    final picked = await _channel.invokeListMethod<Object?>('pick', {'media': media});
    return [
      for (final item in picked ?? const <Object?>[])
        if (item case final Map<Object?, Object?> map)
          PickedDocument(
            uri: map['uri']! as String,
            name: map['name'] as String? ?? 'File',
            size: switch ((map['size'] as num?)?.toInt()) {
              final size? when size >= 0 => size,
              _ => null,
            },
          ),
    ];
  }

  /// Copies the picked file at [uri] to [path].
  static Future<void> copy(String uri, String path) async {
    await _channel.invokeMethod<int>('copy', {'uri': uri, 'out': path});
  }
}
