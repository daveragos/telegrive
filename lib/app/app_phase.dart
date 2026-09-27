import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;

import '../features/auth/data/auth_controller.dart';
import '../features/drive/data/drive_session.dart';
import '../features/setup/data/drive_setup.dart';
import '../infrastructure/telegram/telegram_client.dart';

/// Where the app is in its life, from the first frame to an open drive. The
/// router follows this; screens never navigate between these by hand.
enum AppPhase {
  starting('/splash'),
  welcome('/welcome'),
  phone('/sign-in/phone'),
  code('/sign-in/code'),
  password('/sign-in/password'),
  qr('/sign-in/qr'),
  unsupported('/sign-in/unsupported'),
  setup('/setup'),
  ready('/home');

  const AppPhase(this.location);

  final String location;

  /// Routes that belong to signing in; an open drive never shows them.
  static bool isGateLocation(String location) => values.any(
    (phase) => phase != ready && location.startsWith(phase.location),
  );

  /// Where a navigation to [location] goes in this phase, or null to let it
  /// through. Until the drive is open this phase's screen is the only one;
  /// once it is, the gate screens are out of reach and everything else is
  /// ordinary navigation. A redirect replaces the stack, so the gate a
  /// person just came through is not left under Home for back to return to.
  String? redirect(String location) {
    if (this == ready) return isGateLocation(location) ? ready.location : null;
    return location == this.location ? null : this.location;
  }
}

Provider<T> _listenable<T>(ValueListenable<T> Function(Ref) pick) =>
    Provider<T>((ref) {
      final listenable = pick(ref);
      void onChange() => ref.invalidateSelf();
      listenable.addListener(onChange);
      ref.onDispose(() => listenable.removeListener(onChange));
      return listenable.value;
    });

final fatalErrorProvider = _listenable<String?>(
  (ref) => ref.watch(telegramClientProvider).fatalError,
);

final appPhaseProvider = Provider<AppPhase>((ref) {
  if (ref.watch(fatalErrorProvider) != null) return AppPhase.starting;

  final ui = ref.watch(authControllerProvider);

  final auth = ref.watch(authStateProvider).value;
  switch (auth) {
    case td.AuthorizationStateWaitPhoneNumber():
      return ui.startedSignIn ? AppPhase.phone : AppPhase.welcome;
    case td.AuthorizationStateWaitOtherDeviceConfirmation():
      return ui.editingPhone ? AppPhase.phone : AppPhase.qr;
    case td.AuthorizationStateWaitCode():
      return ui.editingPhone ? AppPhase.phone : AppPhase.code;
    case td.AuthorizationStateWaitPassword():
      return AppPhase.password;
    case td.AuthorizationStateWaitRegistration() ||
        td.AuthorizationStateWaitEmailAddress() ||
        td.AuthorizationStateWaitEmailCode():
      return AppPhase.unsupported;
    case td.AuthorizationStateReady():
      final session = ref.watch(driveSessionProvider);
      final setup = ref.watch(driveSetupProvider);
      return session != null && setup.step == SetupStep.done
          ? AppPhase.ready
          : AppPhase.setup;
    default:
      return AppPhase.starting;
  }
});
