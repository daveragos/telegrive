import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/app_config.dart';
import '../../core/platform/app_platform.dart';

/// What this device is, for Telegram's Devices list: the model as Android
/// names it and the Android version, or the kind of computer and its
/// system's name and version.
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
    if (AppPlatform.isDesktop) return _computer();
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

  /// The kind of computer, and the system as people know it: "MacBook Pro"
  /// and "macOS 15.2", "Windows PC" and "Windows 11 Pro", "Linux PC" and
  /// "Ubuntu 24.04 LTS". Anything unreadable falls back to the app's name
  /// and the version string Dart has.
  static Future<({String model, String system})> _computer() async {
    String? model;
    String? system;
    try {
      if (Platform.isMacOS) {
        model = macModel(await _output('sysctl', ['-n', 'hw.model']));
        final version = await _output('sw_vers', ['-productVersion']);
        if (version != null) system = 'macOS $version';
      } else if (Platform.isWindows) {
        model = 'Windows PC';
        system = windowsName(Platform.operatingSystemVersion);
      } else if (Platform.isLinux) {
        model = 'Linux PC';
        system = linuxName(await File('/etc/os-release').readAsString());
      }
    } catch (e) {
      debugPrint('[DeviceInfo] $e');
    }
    return (
      model: model ?? AppConfig.appName,
      system: system ?? Platform.operatingSystemVersion,
    );
  }

  static Future<String?> _output(String command, List<String> args) async {
    final result = await Process.run(command, args);
    final out = (result.stdout as String).trim();
    return result.exitCode == 0 && out.isNotEmpty ? out : null;
  }

  /// The family a Mac's model identifier belongs to, as Apple names it:
  /// `MacBookPro18,3` is a MacBook Pro. Apple silicon models from 2023 on
  /// say only `Mac15,3`, which is a Mac.
  @visibleForTesting
  static String? macModel(String? identifier) {
    if (identifier == null) return null;
    const families = {
      'MacBookPro': 'MacBook Pro',
      'MacBookAir': 'MacBook Air',
      'MacBook': 'MacBook',
      'Macmini': 'Mac mini',
      'MacPro': 'Mac Pro',
      'iMacPro': 'iMac Pro',
      'iMac': 'iMac',
      'Mac': 'Mac',
    };
    final family = RegExp(r'^[A-Za-z]+').stringMatch(identifier);
    return families[family] ?? 'Mac';
  }

  /// Windows' name without the build: `"Windows 11 Pro" 10.0 (Build
  /// 26100)` is Windows 11 Pro.
  @visibleForTesting
  static String? windowsName(String version) =>
      RegExp('"([^"]+)"').firstMatch(version)?.group(1);

  /// PRETTY_NAME from os-release, as `Ubuntu 24.04 LTS`.
  @visibleForTesting
  static String? linuxName(String osRelease) {
    final line = RegExp(r'^PRETTY_NAME=(.*)$', multiLine: true).firstMatch(osRelease)?.group(1);
    final name = line?.trim().replaceAll(RegExp(r'''^["']|["']$'''), '');
    return name == null || name.isEmpty ? null : name;
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
