import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Keeps a computer from going to sleep on its own while files go up or
/// come down; the screen may still turn off, and closing a laptop's lid
/// still puts it to sleep. A Mac runs `caffeinate`, Linux holds a systemd
/// sleep inhibitor, and Windows marks the app's thread as needing the
/// system. Each lets go by itself if the app ends: `caffeinate` and the
/// inhibitor follow the app's process, and Windows forgets a thread's mark
/// when it ends.
abstract final class KeepAwake {
  static Process? _holder;
  static bool _held = false;

  static bool get held => _held;

  /// Keeps the computer awake until [release]. Nothing where none of the
  /// three is to hand.
  static Future<void> hold() async {
    if (_held) return;
    _held = true;
    try {
      if (Platform.isMacOS) {
        _holder = await Process.start('caffeinate', ['-i', '-w', '$pid']);
      } else if (Platform.isLinux) {
        _holder = await Process.start('systemd-inhibit', [
          '--what=sleep:idle',
          '--who=Telegrive',
          '--why=Transferring files',
          '--mode=block',
          'tail',
          '--pid=$pid',
          '-f',
          '/dev/null',
        ]);
      } else if (Platform.isWindows) {
        _setThreadExecutionState(_esContinuous | _esSystemRequired);
      }
    } catch (e) {
      debugPrint('[Awake] Could not keep the computer awake: $e');
    }
  }

  /// Lets the computer sleep again as it would.
  static Future<void> release() async {
    if (!_held) return;
    _held = false;
    _holder?.kill();
    _holder = null;
    if (Platform.isWindows) {
      try {
        _setThreadExecutionState(_esContinuous);
      } catch (e) {
        debugPrint('[Awake] $e');
      }
    }
  }

  static const int _esContinuous = 0x80000000;
  static const int _esSystemRequired = 0x00000001;

  static final int Function(int) _setThreadExecutionState = DynamicLibrary.open('kernel32.dll')
      .lookupFunction<Uint32 Function(Uint32), int Function(int)>('SetThreadExecutionState');
}
