import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The files on the system clipboard, as Copy in Finder leaves them, for
/// Paste to upload. Only a Mac answers; elsewhere the clipboard holds none.
abstract final class ClipboardFiles {
  static const _channel = MethodChannel('telegrive/clipboard');

  /// Whether this computer's clipboard can be read for files.
  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  /// The paths of the files and folders copied, in the order they were.
  static Future<List<String>> read() async {
    if (!supported) return const [];
    try {
      final paths = await _channel.invokeListMethod<String>('files');
      return [for (final path in paths ?? const <String>[]) if (path.isNotEmpty) path];
    } on MissingPluginException {
      return const [];
    } on PlatformException catch (e) {
      debugPrint('[Clipboard] Could not read the files: $e');
      return const [];
    }
  }
}
