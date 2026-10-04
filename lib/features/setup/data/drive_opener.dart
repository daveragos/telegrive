import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;

import '../../../infrastructure/telegram/telegram_client.dart';
import '../../auth/data/auth_controller.dart';
import '../../drive/data/drive_session.dart';
import 'drive_setup.dart';

/// Opens the drive behind Home for someone this phone has opened it for
/// before. Home shows the drive from the index straight away; once TDLib
/// is signed in, this runs [DriveSetup] as the setup screen would, which
/// opens the session. A run already under way is joined rather than
/// started again.
///
/// TDLib asking for an account to sign in while the drive is saved means
/// the session went without this phone seeing it end, so there is no
/// telling how long ago. The drive leaves the phone then, as a sign-out
/// takes it, and the app goes to Welcome.
final driveOpenerProvider = Provider<void>((ref) {
  ref.listen<AsyncValue<td.AuthorizationState>>(authStateProvider, (_, next) {
    if (ref.read(driveSnapshotProvider) == null) return;
    final state = next.value;
    if (state is td.AuthorizationStateReady) {
      if (ref.read(driveSessionProvider) == null) {
        unawaited(ref.read(driveSetupProvider.notifier).run());
      }
    } else if (asksToSignIn(state)) {
      unawaited(ref.read(authControllerProvider.notifier).wipeDeviceState());
    }
  }, fireImmediately: true);
});
