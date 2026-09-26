import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../../../infrastructure/storage/preferences.dart';

/// How long the app may be away before it locks again.
enum LockAfter {
  immediately(Duration.zero, 'Immediately'),
  oneMinute(Duration(minutes: 1), 'After 1 minute'),
  fiveMinutes(Duration(minutes: 5), 'After 5 minutes');

  const LockAfter(this.delay, this.label);

  final Duration delay;
  final String label;
}

@immutable
class AppLockState {
  const AppLockState({
    this.enabled = false,
    this.locked = false,
    this.after = LockAfter.oneMinute,
  });

  final bool enabled;
  final bool locked;
  final LockAfter after;

  AppLockState copyWith({bool? enabled, bool? locked, LockAfter? after}) => AppLockState(
    enabled: enabled ?? this.enabled,
    locked: locked ?? this.locked,
    after: after ?? this.after,
  );
}

/// Asks for the phone's fingerprint, face or screen lock before showing the
/// drive: when the app starts, and when it comes back after [LockAfter].
/// Uses the phone's own lock, so there is no separate PIN to forget.
class AppLock extends Notifier<AppLockState> with WidgetsBindingObserver {
  static const _security = MethodChannel('telegrive/security');

  final _auth = LocalAuthentication();
  DateTime? _leftAt;
  bool _authenticating = false;

  Preferences get _prefs => ref.read(preferencesProvider);

  @override
  AppLockState build() {
    final prefs = ref.watch(preferencesProvider);
    WidgetsBinding.instance.addObserver(this);
    ref.onDispose(() => WidgetsBinding.instance.removeObserver(this));
    final enabled = prefs.appLock;
    _privateRecents(enabled);
    return AppLockState(
      enabled: enabled,
      locked: enabled,
      after: LockAfter.values.where((a) => a.name == prefs.appLockAfter).firstOrNull ??
          LockAfter.oneMinute,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The fingerprint prompt itself sends the app to the background on
    // some phones; that isn't leaving.
    final lock = this.state;
    if (_authenticating || !lock.enabled) return;
    switch (state) {
      case AppLifecycleState.hidden || AppLifecycleState.paused:
        _leftAt ??= DateTime.now();
      case AppLifecycleState.resumed:
        final left = _leftAt;
        _leftAt = null;
        if (left != null && DateTime.now().difference(left) >= lock.after.delay) {
          this.state = lock.copyWith(locked: true);
        }
      default:
        break;
    }
  }

  /// Shows the system prompt; unlocks when it passes.
  Future<bool> unlock() async {
    if (!state.locked) return true;
    final passed = await _authenticate('Unlock Telegrive');
    if (passed) state = state.copyWith(locked: false);
    return passed;
  }

  /// Turning it on checks the person can unlock first. Returns false, with
  /// nothing changed, if the phone has no lock set up or the check failed.
  Future<bool> setEnabled(bool enabled) async {
    if (enabled) {
      if (!await _auth.isDeviceSupported()) return false;
      if (!await _authenticate('Turn on app lock')) return false;
    }
    await _prefs.setAppLock(enabled);
    _privateRecents(enabled);
    state = state.copyWith(enabled: enabled, locked: false);
    return true;
  }

  Future<void> setAfter(LockAfter after) async {
    await _prefs.setAppLockAfter(after.name);
    state = state.copyWith(after: after);
  }

  Future<bool> _authenticate(String reason) async {
    if (_authenticating) return false;
    _authenticating = true;
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        persistAcrossBackgrounding: true,
      );
    } catch (e) {
      debugPrint('[AppLock] $e');
      return false;
    } finally {
      _authenticating = false;
      _leftAt = null;
    }
  }

  void _privateRecents(bool enabled) {
    if (kIsWeb || !Platform.isAndroid) return;
    unawaited(
      _security.invokeMethod<void>('setPrivateRecents', enabled).catchError((Object _) {}),
    );
  }
}

final appLockProvider = NotifierProvider<AppLock, AppLockState>(AppLock.new);
