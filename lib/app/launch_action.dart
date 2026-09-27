import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Something the app was opened to do: back up the new photos, from the
/// backup notification, or show the transfers, from the transfer
/// notification. The shell carries it out once the drive is open, so a
/// screen opened this way sits over Home and back lands there.
enum LaunchAction {
  backup,
  transfers;

  /// The route the transfer notification launches the app with. Android
  /// hands it over as the initial route; the router does not start there
  /// (it would be the only screen, and back would close the app) but maps
  /// it to [transfers].
  static const String transfersRoute = '/transfers';

  /// The action a launch route stands for, or null for a plain launch.
  static LaunchAction? fromRoute(String route) =>
      route == transfersRoute ? transfers : null;
}

class PendingLaunchAction extends Notifier<LaunchAction?> {
  @override
  LaunchAction? build() => null;

  // ignore: use_setters_to_change_properties
  void set(LaunchAction? action) => state = action;
}

final pendingLaunchActionProvider =
    NotifierProvider<PendingLaunchAction, LaunchAction?>(PendingLaunchAction.new);
