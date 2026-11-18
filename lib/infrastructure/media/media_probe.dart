import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/platform/app_platform.dart';
import 'desktop_media.dart';

/// Reads what a media file on this device says about itself: on Android
/// through the telegrive/media channel, from the file's own headers; on a
/// computer through [DesktopMedia]. On iOS, and whenever the file can't be
/// read, the answer is null and the caller carries on without it.
abstract final class MediaProbe {
  static const _channel = MethodChannel('telegrive/media');

  static bool _asks = !kIsWeb && Platform.isAndroid;

  /// Tests that answer the channel themselves turn the asking on.
  @visibleForTesting
  static set asks(bool value) => _asks = value;

  /// How long the video or audio file at [path] runs, in whole seconds, or
  /// null when it can't be told. A clip too short to round to a second
  /// counts as untold, so a length is never recorded as zero.
  static Future<int?> durationSeconds(String path) async {
    if (AppPlatform.isDesktop) return (await DesktopMedia.probe(path)).seconds;
    if (!_asks) return null;
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

  /// Writes a JPEG preview of the photo or [video] at [path] to [out], small
  /// enough for a document's thumbnail on Telegram, and answers [out], or
  /// null when the file makes no picture.
  static Future<String?> thumbnail(String path, {required bool video, required String out}) async {
    if (AppPlatform.isDesktop) {
      return video
          ? (await DesktopMedia.probe(path, frameOut: out)).frame
          : DesktopMedia.photoThumbnail(path, out: out);
    }
    if (!_asks) return null;
    try {
      return await _channel.invokeMethod<String>('thumbnail', {'path': path, 'video': video, 'out': out});
    } catch (e) {
      debugPrint('[MediaProbe] $e');
      return null;
    }
  }

  /// Writes a JPEG of the photo at [path] to [out], no side over [side]
  /// pixels, decoded by Android, which reads RAW files and HEIC and AVIF
  /// photos the app's own decoder may not. Answers [out], or null when
  /// Android can't make a picture of it either.
  static Future<String?> picture(String path, {required int side, required String out}) async {
    if (!_asks) return null;
    try {
      return await _channel.invokeMethod<String>('picture', {'path': path, 'side': side, 'out': out});
    } catch (e) {
      debugPrint('[MediaProbe] $e');
      return null;
    }
  }

  /// When the photo or [video] at [path] was taken, from the date its
  /// camera wrote into it, or null when it holds none.
  static Future<DateTime?> takenAt(String path, {required bool video}) async {
    if (AppPlatform.isDesktop) return video ? null : DesktopMedia.photoTakenAt(path);
    if (!_asks) return null;
    try {
      final ms = await _channel.invokeMethod<int>('takenAtMs', {'path': path, 'video': video});
      return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
    } catch (e) {
      debugPrint('[MediaProbe] $e');
      return null;
    }
  }
}
