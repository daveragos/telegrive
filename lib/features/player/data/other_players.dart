import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../core/files/file_kind.dart';
import '../../drive/domain/drive_models.dart';

/// The other apps on this phone that can play a stream, asked through the
/// telegrive/media channel. Only Android hands a stream over this way.
abstract final class OtherPlayers {
  static const _channel = MethodChannel('telegrive/media');

  static bool get supported => !kIsWeb && Platform.isAndroid;

  /// The type to offer [file] to players as. A type the drive holds that
  /// says nothing, as a forwarded file's can, would find no player.
  static String typeOf(DriveFile file) {
    final family = file.kind == FileKind.audio ? 'audio/' : 'video/';
    return file.mimeType.startsWith(family) ? file.mimeType : '$family*';
  }

  /// Whether any app on this phone plays [mime] over HTTP.
  static Future<bool> canPlay(String mime) async {
    try {
      return await _channel.invokeMethod<bool>('canPlayStream', {'url': 'http://127.0.0.1/', 'mime': mime}) ?? false;
    } on PlatformException catch (e) {
      debugPrint('[OtherPlayers] $e');
      return false;
    }
  }

  /// Offers [url] to the apps that play [mime], under [title], and answers
  /// whether Android took it.
  static Future<bool> play(Uri url, {required String mime, required String title}) async {
    try {
      return await _channel.invokeMethod<bool>('playStream', {
            'url': url.toString(),
            'mime': mime,
            'title': title,
          }) ??
          false;
    } on PlatformException catch (e) {
      debugPrint('[OtherPlayers] $e');
      return false;
    }
  }
}
