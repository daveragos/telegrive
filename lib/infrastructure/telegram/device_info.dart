import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/config/app_config.dart';

/// What this phone is, for Telegram's Devices list: the model as Android
/// names it and the Android version.
abstract final class DeviceInfo {
  static const _channel = MethodChannel('telegrive/device');

  /// Asks Android once. A platform without the channel, or one that fails
  /// to answer, names the session after the app and the operating system
  /// instead, so the entry is still telling.
  static Future<({String model, String system})> read() async {
    try {
      final info = await _channel.invokeMapMethod<String, Object?>('deviceInfo');
      final model = info?['model'] as String?;
      final system = info?['system'] as String?;
      if (model != null && model.isNotEmpty && system != null && system.isNotEmpty) {
        return (model: model, system: system);
      }
    } on PlatformException catch (e) {
      debugPrint('[DeviceInfo] $e');
    } on MissingPluginException {
      // Not on Android, or in a test.
    }
    return (model: AppConfig.appName, system: Platform.operatingSystemVersion);
  }
}
