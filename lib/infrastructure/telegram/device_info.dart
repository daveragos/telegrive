import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/app_config.dart';

/// What this phone is, for Telegram's Devices list: the model as Android
/// names it and the Android version.
abstract final class DeviceInfo {
  static const _channel = MethodChannel('telegrive/device');

  /// The last answer, kept for the background backup job's engine, which
  /// has none of the app's own channels; without it, the job's connection
  /// would rename this phone in Telegram's Devices list.
  static const String _modelKey = 'device_model';
  static const String _systemKey = 'device_system';

  /// Asks Android once. A platform without the channel, or one that fails
  /// to answer, takes the answer kept from the last time, or else names the
  /// session after the app and the operating system, so the entry is still
  /// telling.
  static Future<({String model, String system})> read() async {
    try {
      final info = await _channel.invokeMapMethod<String, Object?>('deviceInfo');
      final model = info?['model'] as String?;
      final system = info?['system'] as String?;
      if (model != null && model.isNotEmpty && system != null && system.isNotEmpty) {
        await _keep(model, system);
        return (model: model, system: system);
      }
    } on PlatformException catch (e) {
      debugPrint('[DeviceInfo] $e');
    } on MissingPluginException {
      // Not on Android, in a test, or on the background job's engine.
    }
    return await _kept() ?? (model: AppConfig.appName, system: Platform.operatingSystemVersion);
  }

  static Future<void> _keep(String model, String system) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_modelKey, model);
      await prefs.setString(_systemKey, system);
    } catch (e) {
      debugPrint('[DeviceInfo] Could not keep the answer: $e');
    }
  }

  static Future<({String model, String system})?> _kept() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final model = prefs.getString(_modelKey);
      final system = prefs.getString(_systemKey);
      if (model == null || system == null) return null;
      return (model: model, system: system);
    } catch (_) {
      return null;
    }
  }
}
