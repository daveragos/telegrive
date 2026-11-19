import 'dart:io';

import 'package:flutter/foundation.dart';

/// What kind of device the app runs on, for the choices that follow it: a
/// phone, with the camera roll, mobile data and Android's or iOS's own
/// services; or a computer, with a mouse, a keyboard and folders on disk.
abstract final class AppPlatform {
  /// Whether this is a Mac, a Windows PC or a Linux desktop.
  static bool get isDesktop =>
      debugDesktop ?? (!kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux));

  /// Whether this is an Android phone or an iPhone.
  static bool get isMobile => !isDesktop && !kIsWeb;

  /// Stands in for the platform in tests: true for a computer, false for a
  /// phone, null for the one the tests run on.
  @visibleForTesting
  static bool? debugDesktop;

  /// What the person holds, as "this phone" or "this computer" name it.
  static String get device => isDesktop ? 'computer' : 'phone';

  /// [device] with "this", for "Space on this computer" and the like.
  static String get thisDevice => 'this $device';

  /// Whether the device can ask who is there before showing the drive:
  /// a phone's biometrics or screen lock, Touch ID or the Mac's password,
  /// Windows Hello. Linux has nothing the app can ask.
  static bool get canLock => !isDesktop || debugDesktop != null || !Platform.isLinux;

  /// What app lock asks for, as "Ask for … to open Telegrive" says it.
  static String get unlockMethods {
    if (isDesktop && debugDesktop == null) {
      if (Platform.isMacOS) return 'Touch ID or your Mac\'s password';
      if (Platform.isWindows) return 'Windows Hello or your PIN';
    }
    return 'your fingerprint, face or screen lock';
  }

  /// Whether the system's share sheet can take files: not on Linux, where
  /// there is none.
  static bool get canShareFiles => !isDesktop || debugDesktop != null || !Platform.isLinux;

  /// Where an app that keeps running without a window shows: a Mac's menu
  /// bar, Windows' notification area, or a Linux desktop's tray.
  static String get tray {
    if (debugDesktop == null && !kIsWeb) {
      if (Platform.isMacOS) return 'menu bar';
      if (Platform.isWindows) return 'notification area';
    }
    return 'tray';
  }

  /// The word for pressing something on screen, to start a sentence:
  /// "Tap" on a phone, "Click" on a computer.
  static String get tapWord => isDesktop ? 'Click' : 'Tap';

  /// The file manager's name, for "Show in Finder" and the like.
  static String get fileManager {
    if (debugDesktop == null && !kIsWeb) {
      if (Platform.isMacOS) return 'Finder';
      if (Platform.isWindows) return 'File Explorer';
    }
    return 'Files';
  }
}
