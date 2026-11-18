import 'dart:io';

import 'package:handy_tdlib/handy_tdlib.dart';
import 'package:path/path.dart' as p;

/// Opens TDLib's native library for [TdPlugin].
///
/// Every app carries its own build of the TDLib commit handy_tdlib's API was
/// generated from, made by the matching `tool/build_tdlib_*` script:
/// `libtdjson.so` on Android, packaged in place of handy_tdlib's;
/// `tdjson.framework` on iOS and macOS; `tdjson.dll` beside the exe on
/// Windows; and `lib/libtdjson.so` in the bundle on Linux.
Future<void> openTdLibrary() => TdPlugin.initialize(tdLibraryPath());

/// Where [openTdLibrary] finds TDLib on this platform, or null for the
/// name handy_tdlib opens by default, as Android does.
String? tdLibraryPath() {
  if (Platform.isIOS) return 'tdjson.framework/tdjson';
  if (Platform.isAndroid) return null;
  final bundle = p.dirname(Platform.resolvedExecutable);
  if (Platform.isMacOS) {
    return p.join(bundle, '..', 'Frameworks', 'tdjson.framework', 'tdjson');
  }
  if (Platform.isWindows) return p.join(bundle, 'tdjson.dll');
  return p.join(bundle, 'lib', 'libtdjson.so');
}
