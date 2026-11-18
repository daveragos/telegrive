import 'dart:async';

import 'package:telegrive/core/platform/app_platform.dart';

/// Every test runs as on a phone, whatever computer runs the tests. A test
/// of the desktop app sets [AppPlatform.debugDesktop] to true, and back to
/// false when it ends.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  AppPlatform.debugDesktop = false;
  await testMain();
}
