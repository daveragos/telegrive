import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:media_kit/media_kit.dart';

/// What a photo or video on a computer says about itself, read by the app:
/// photos by Flutter's own decoder and their EXIF, videos by mpv. It stands
/// in for what Android reads for [MediaProbe] on a phone, so a file
/// uploaded from a computer goes up with a preview, a length and the date
/// it was taken, as one from a phone does.
abstract final class DesktopMedia {
  /// Telegram's largest side for a document's thumbnail.
  static const int thumbnailSide = 320;

  /// Photos bigger than this are left without a preview rather than read
  /// whole into memory.
  static const int _largestPhoto = 80 << 20;

  /// How long a video gets to say how long it runs, and to reach the frame
  /// its preview is taken from.
  static const Duration _videoWait = Duration(seconds: 8);

  /// How long mpv gets, all told, before a probe gives up on a file.
  static const Duration _probeWait = Duration(seconds: 30);

  /// A JPEG of the photo at [path], no side over [thumbnailSide], written
  /// to [out]; null when the file makes no picture.
  static Future<String?> photoThumbnail(String path, {required String out}) async {
    try {
      final file = File(path);
      if (await file.length() > _largestPhoto) return null;
      final jpeg = await jpegOf(await file.readAsBytes(), side: thumbnailSide);
      return jpeg == null ? null : await _write(out, jpeg);
    } catch (e) {
      debugPrint('[DesktopMedia] $path: $e');
      return null;
    }
  }

  /// [encoded], any picture Flutter decodes, as a JPEG no side over [side].
  static Future<Uint8List?> jpegOf(Uint8List encoded, {required int side}) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(encoded);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    try {
      final scale = math.min(1.0, side / math.max(descriptor.width, descriptor.height));
      final codec = await descriptor.instantiateCodec(
        targetWidth: math.max(1, (descriptor.width * scale).round()),
        targetHeight: math.max(1, (descriptor.height * scale).round()),
      );
      final frame = await codec.getNextFrame();
      codec.dispose();
      final picture = frame.image;
      final pixels = await picture.toByteData(format: ui.ImageByteFormat.rawRgba);
      final (width, height) = (picture.width, picture.height);
      picture.dispose();
      if (pixels == null) return null;
      final image = img.Image.fromBytes(
        width: width,
        height: height,
        bytes: pixels.buffer,
        numChannels: 4,
        order: img.ChannelOrder.rgba,
      );
      return img.encodeJpg(img.Image.from(image).convert(numChannels: 3), quality: 82);
    } finally {
      descriptor.dispose();
      buffer.dispose();
    }
  }

  /// When the photo at [path] was taken, from the DateTimeOriginal its
  /// camera wrote into its EXIF; null for a photo without one.
  static Future<DateTime?> photoTakenAt(String path) async {
    try {
      final file = File(path);
      if (await file.length() > _largestPhoto) return null;
      final exif = img.decodeJpgExif(await file.readAsBytes());
      final written = exif?.exifIfd[0x9003]?.toString() ?? exif?.imageIfd[0x0132]?.toString();
      return written == null ? null : exifDate(written);
    } catch (e) {
      debugPrint('[DesktopMedia] $path: $e');
      return null;
    }
  }

  /// `2026:10:03 14:22:05`, EXIF's way of writing a moment, read as local
  /// time, as cameras write it.
  @visibleForTesting
  static DateTime? exifDate(String written) {
    final match = RegExp(r'^(\d{4}):(\d{2}):(\d{2})[ T](\d{2}):(\d{2}):(\d{2})').firstMatch(written.trim());
    if (match == null) return null;
    final parts = [for (var i = 1; i <= 6; i++) int.parse(match.group(i)!)];
    if (parts[0] < 1900 || parts[1] == 0 || parts[2] == 0) return null;
    return DateTime(parts[0], parts[1], parts[2], parts[3], parts[4], parts[5]);
  }

  /// How long the video or audio at [path] runs, in whole seconds, and,
  /// for a video when [frame] is wanted, a JPEG of it a tenth of the way
  /// in, written to [frameOut]. Either is null when mpv can't tell.
  static Future<({int? seconds, String? frame})> probe(
    String path, {
    String? frameOut,
  }) async {
    const nothing = (seconds: null, frame: null);
    final player = Player(configuration: const PlayerConfiguration(muted: true, title: 'Telegrive'));
    try {
      return await _probe(player, path, frameOut).timeout(_probeWait, onTimeout: () => nothing);
    } catch (e) {
      debugPrint('[DesktopMedia] $path: $e');
      return nothing;
    } finally {
      await player.dispose().timeout(_videoWait, onTimeout: () {});
    }
  }

  static Future<({int? seconds, String? frame})> _probe(
    Player player,
    String path,
    String? frameOut,
  ) async {
    final mpv = player.platform;
    final wantsFrame = frameOut != null && mpv is NativePlayer;
    if (wantsFrame) {
      // mpv decodes the video and keeps its frames without drawing them
      // anywhere, so a preview needs no window, no video controller and no
      // frame of the app's to be drawn first.
      await mpv.setProperty('vid', 'auto');
      await mpv.setProperty('vo', 'null');
    }
    await player.open(Media(Uri.file(path).toString()), play: false);
    final duration = await player.stream.duration
        .firstWhere((d) => d > Duration.zero)
        .timeout(_videoWait, onTimeout: () => Duration.zero);
    final seconds = (duration.inMilliseconds / 1000).round();
    String? frame;
    if (wantsFrame && duration > Duration.zero) {
      final at = duration * 0.1;
      final landed = player.stream.position
          .firstWhere((p) => p >= at - const Duration(milliseconds: 100))
          .timeout(_videoWait, onTimeout: () => Duration.zero);
      await player.seek(at);
      await landed;
      final shot = await player.screenshot(format: 'image/jpeg');
      final jpeg = shot == null ? null : await jpegOf(shot, side: thumbnailSide);
      if (jpeg != null) frame = await _write(frameOut, jpeg);
    }
    return (seconds: seconds > 0 ? seconds : null, frame: frame);
  }

  static Future<String> _write(String out, Uint8List bytes) async {
    final file = File(out);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    return out;
  }
}
