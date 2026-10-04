import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'preferences.dart';

/// How much memory this phone has, as Android reports it once at start.
@immutable
class DeviceProfile {
  const DeviceProfile({
    required this.lowRam,
    required this.memoryClassMb,
    required this.totalRamBytes,
  });

  /// A phone that couldn't say, which counts as an ordinary one.
  static const unknown = DeviceProfile(lowRam: false, memoryClassMb: 0, totalRamBytes: 0);

  static const _channel = MethodChannel('telegrive/device');

  /// Below this much memory a phone saves memory unless told otherwise:
  /// 2.5 GiB, where a grid of thousands of photos starts to stutter and
  /// Android ends apps in the background.
  static const int _smallRam = 5 << 29;

  /// Android runs this phone as a low-memory device.
  final bool lowRam;

  /// How many megabytes Android lets one app's heap grow to.
  final int memoryClassMb;

  /// All of the phone's memory, or 0 when it isn't known.
  final int totalRamBytes;

  /// Whether this phone should start with Save memory on.
  bool get suggestSaveMemory => lowRam || (totalRamBytes > 0 && totalRamBytes < _smallRam);

  /// Asks Android once. Any failure, or a platform without the channel,
  /// gives [unknown], so the app starts the same way it would on an
  /// ordinary phone.
  static Future<DeviceProfile> read() async {
    try {
      final profile = await _channel.invokeMapMethod<String, Object?>('profile');
      if (profile == null) return unknown;
      return DeviceProfile(
        lowRam: profile['lowRam'] == true,
        memoryClassMb: (profile['memoryClassMb'] as num?)?.toInt() ?? 0,
        totalRamBytes: (profile['totalRamBytes'] as num?)?.toInt() ?? 0,
      );
    } catch (e) {
      debugPrint('[DeviceProfile] $e');
      return unknown;
    }
  }
}

/// This phone's profile, read before the first frame and put in place by
/// main.dart. Without that, as in tests, the phone counts as an ordinary
/// one.
final deviceProfileProvider = Provider<DeviceProfile>((ref) => DeviceProfile.unknown);

/// Whether Telegrive saves memory: fewer transfers at once, a smaller
/// image cache and previews drawn without blur. It follows the phone until
/// the person turns it on or off in Settings, and from then on keeps their
/// choice. Lives here rather than with Settings so the transfer queue can
/// read it without importing Settings, which imports the queue.
class SaveMemoryNotifier extends Notifier<bool> {
  @override
  bool build() =>
      ref.watch(preferencesProvider).saveMemory ??
      ref.watch(deviceProfileProvider).suggestSaveMemory;

  void set(bool on) {
    state = on;
    ref.read(preferencesProvider).setSaveMemory(on);
  }
}

final saveMemoryProvider = NotifierProvider<SaveMemoryNotifier, bool>(SaveMemoryNotifier.new);
