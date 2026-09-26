import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Something the app was opened to do — today only "back up the new
/// photos", from the backup notification. The shell carries it out once the
/// drive is open.
enum LaunchAction { backup }

class PendingLaunchAction extends Notifier<LaunchAction?> {
  @override
  LaunchAction? build() => null;

  // ignore: use_setters_to_change_properties
  void set(LaunchAction? action) => state = action;
}

final pendingLaunchActionProvider =
    NotifierProvider<PendingLaunchAction, LaunchAction?>(PendingLaunchAction.new);
