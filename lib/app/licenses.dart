import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The licenses Flutter can't find by itself, as they aren't a Dart
/// package's: Telegrive's own, the typeface's, and those of TDLib and the
/// OpenSSL linked into it, which tool/build_tdlib_android.sh and
/// tool/build_tdlib_ios.sh build from source.
const bundledLicenses = [
  (package: 'Telegrive', asset: 'LICENSE'),
  (package: 'IBM Plex Sans', asset: 'assets/fonts/OFL.txt'),
  (package: 'TDLib', asset: 'assets/licenses/TDLib.txt'),
  (package: 'OpenSSL', asset: 'assets/licenses/OpenSSL.txt'),
];

/// Adds [bundledLicenses] to what Settings › About › Open-source licenses
/// lists. They are read only when that page asks.
void registerBundledLicenses() => LicenseRegistry.addLicense(readBundledLicenses);

Stream<LicenseEntry> readBundledLicenses() async* {
  for (final license in bundledLicenses) {
    yield LicenseEntryWithLineBreaks([license.package], await rootBundle.loadString(license.asset));
  }
}
