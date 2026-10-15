import 'dart:io';

import 'package:handy_tdlib/handy_tdlib.dart';

/// Opens TDLib's native library for [TdPlugin].
///
/// Both apps carry their own build of the TDLib commit handy_tdlib's API was
/// generated from: `libtdjson.so` on Android, built by
/// `tool/build_tdlib_android.sh` and packaged in place of handy_tdlib's, and
/// `tdjson.framework` on iOS, built by `tool/build_tdlib_ios.sh`.
Future<void> openTdLibrary() =>
    TdPlugin.initialize(Platform.isIOS ? 'tdjson.framework/tdjson' : null);
