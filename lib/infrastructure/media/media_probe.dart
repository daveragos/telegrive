import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Reads what a media file on this phone says about itself, through the
/// telegrive/media channel. Android answers from the file's own headers;
/// anywhere else, and whenever the file can't be read, the answer is null
/// and the caller carries on without it.
abstract final class MediaProbe {
  static const _channel = MethodChannel('telegrive/media');

  /// How long the video or audio file at [path] runs, in whole seconds, or
  /// null when it can't be told. A clip too short to round to a second
  /// counts as untold, so a length is never recorded as zero.
  static Future<int?> durationSeconds(String path) async {
    if (kIsWeb || !Platform.isAndroid) return null;
    try {
      final ms = await _channel.invokeMethod<int>('durationMs', {'path': path});
      if (ms == null) return null;
      final seconds = (ms / 1000).round();
      return seconds > 0 ? seconds : null;
    } catch (e) {
      debugPrint('[MediaProbe] $e');
      return null;
    }
  }
}
