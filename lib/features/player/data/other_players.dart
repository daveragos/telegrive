import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../core/files/file_kind.dart';
import '../../../core/platform/app_platform.dart';
import '../../drive/domain/drive_models.dart';

/// The other apps that can play a stream: on Android, those the
/// telegrive/media channel finds; on a computer, a player installed where
/// it usually is, IINA, VLC or mpv, started with the stream's address.
abstract final class OtherPlayers {
  static const _channel = MethodChannel('telegrive/media');

  static bool get supported => !kIsWeb && (Platform.isAndroid || AppPlatform.isDesktop);

  /// The type to offer [file] to players as. A type the drive holds that
  /// says nothing, as a forwarded file's can, would find no player.
  static String typeOf(DriveFile file) {
    final family = file.kind == FileKind.audio ? 'audio/' : 'video/';
    return file.mimeType.startsWith(family) ? file.mimeType : '$family*';
  }

  /// Whether any app on this device plays [mime] over HTTP.
  static Future<bool> canPlay(String mime) async {
    if (AppPlatform.isDesktop) return await _desktopPlayer() != null;
    try {
      return await _channel.invokeMethod<bool>('canPlayStream', {'url': 'http://127.0.0.1/', 'mime': mime}) ?? false;
    } on PlatformException catch (e) {
      debugPrint('[OtherPlayers] $e');
      return false;
    }
  }

  /// Offers [url] to the apps that play [mime], under [title], and answers
  /// whether one took it.
  static Future<bool> play(Uri url, {required String mime, required String title}) async {
    if (AppPlatform.isDesktop) {
      final player = await _desktopPlayer();
      if (player == null) return false;
      try {
        await Process.start(player.first, [...player.skip(1), url.toString()], mode: ProcessStartMode.detached);
        return true;
      } on ProcessException catch (e) {
        debugPrint('[OtherPlayers] $e');
        return false;
      }
    }
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

  /// The command that starts a player on this computer, without the
  /// address: IINA, VLC or mpv on a Mac, VLC or mpv elsewhere, the first
  /// one installed. Null when none is.
  static Future<List<String>?> _desktopPlayer() async {
    if (Platform.isMacOS) {
      final home = Platform.environment['HOME'] ?? '';
      for (final app in const ['IINA', 'VLC', 'mpv']) {
        for (final folder in ['/Applications', '$home/Applications']) {
          if (await Directory('$folder/$app.app').exists()) return ['open', '-a', app];
        }
      }
      return await _onPath('mpv') ? ['mpv'] : null;
    }
    if (Platform.isWindows) {
      for (final root in [Platform.environment['ProgramFiles'], Platform.environment['ProgramFiles(x86)']]) {
        if (root == null) continue;
        final vlc = '$root\\VideoLAN\\VLC\\vlc.exe';
        if (await File(vlc).exists()) return [vlc];
      }
      return await _onPath('mpv') ? ['mpv'] : null;
    }
    for (final player in const ['vlc', 'mpv', 'celluloid']) {
      if (await _onPath(player)) return [player];
    }
    return null;
  }

  /// Whether [command] is on the PATH.
  static Future<bool> _onPath(String command) async {
    try {
      final found = await Process.run(Platform.isWindows ? 'where' : 'which', [command]);
      return found.exitCode == 0;
    } on ProcessException {
      return false;
    }
  }
}
