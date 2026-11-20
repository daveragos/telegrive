#!/usr/bin/env bash
#
# Builds every file a release carries into build/release: an APK for each
# ABI, the app bundle, the unsigned IPA, the Mac disk image and
# SHA256SUMS.txt, ready to attach to a GitHub release. Runs on a Mac, which
# the IPA and the disk image need. Windows and Linux builds are made on
# those systems (tool/build_windows.ps1, tool/build_linux.sh) and added to
# the release with their own checksums.
#
# It needs TDLib for each platform (tool/build_tdlib_android.sh,
# tool/build_tdlib_ios.sh and tool/build_tdlib_macos.sh), the Telegram API
# credentials, and the upload key that android/key.properties names. Without
# that key Gradle signs with the debug key, and Android won't install such a
# build over the app people have, so the script stops. Extra arguments go to
# every flutter build, for example --dart-define-from-file=telegram_api.json.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

fail() {
  echo "$*" >&2
  exit 1
}

sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"

# Stops unless every native library in the app bundle it is given has its
# debug symbols stripped, as Flutter checks after building it. Flutter asks apkanalyzer,
# from the SDK's cmdline-tools; an SDK without them fails that check though
# the bundle is fine, so the libraries are read here with the NDK's
# llvm-readelf instead.
check_bundle_symbols() {
  local readelf libs so sections
  readelf="$(printf '%s\n' "$sdk"/ndk/*/toolchains/llvm/prebuilt/*/bin/llvm-readelf | sort -V | tail -1)"
  [ -x "$readelf" ] || fail "There is no NDK llvm-readelf in $sdk to check $1 for debug symbols"
  libs="$(mktemp -d)"
  unzip -q -o "$1" 'base/lib/*' -d "$libs"
  for so in "$libs"/base/lib/*/*.so; do
    # Read in full first: grep -q stops at the first match, and with
    # pipefail llvm-readelf cut off mid-write would make a match a pass.
    sections="$("$readelf" -S "$so")"
    if grep -q '\.debug_' <<<"$sections"; then
      rm -rf "$libs"
      fail "${so#"$libs/base/"} in $1 still has its debug symbols"
    fi
  done
  rm -rf "$libs"
  echo "Checked $1 with llvm-readelf: no native library keeps its debug symbols."
}

abis=(arm64-v8a armeabi-v7a x86_64)

[ -f android/key.properties ] || fail "android/key.properties is missing; release builds need the upload key"
[ -d macos/Frameworks/tdjson.xcframework ] || fail "TDLib for macOS is missing; run tool/build_tdlib_macos.sh first"
for abi in "${abis[@]}"; do
  [ -f "android/app/src/main/jniLibs/$abi/libtdjson.so" ] ||
    fail "TDLib for $abi is missing; run tool/build_tdlib_android.sh first"
done

version="$(sed -n 's/^version: *\([^+]*\).*/\1/p' pubspec.yaml)"
out="build/release"
rm -rf "$out"
mkdir -p "$out"

flutter build apk --release --split-per-abi "$@"
aab="build/app/outputs/bundle/release/app-release.aab"
rm -f "$aab"
log="$(mktemp)"
if ! flutter build appbundle --release "$@" 2>&1 | tee "$log"; then
  grep -q 'failed to strip debug symbols' "$log" && [ -f "$aab" ] || fail "The app bundle didn't build"
  check_bundle_symbols "$aab"
fi
rm -f "$log"

# keytool and apksigner need a JDK, and macOS's own java is a stub without
# one: take the one Flutter is set to, or else Android Studio's.
for home in "$(flutter config --list 2>/dev/null | sed -n 's/^ *jdk-dir: *//p')" \
  "${JAVA_HOME:-}" "/Applications/Android Studio.app/Contents/jbr/Contents/Home"; do
  if [ -n "$home" ] && [ -x "$home/bin/keytool" ]; then
    export JAVA_HOME="$home" PATH="$home/bin:$PATH"
    break
  fi
done

# The debug key's certificate, which no release file may carry.
debug=""
if [ -f "$HOME/.android/debug.keystore" ]; then
  debug="$(keytool -exportcert -keystore "$HOME/.android/debug.keystore" \
    -storepass android -alias androiddebugkey | shasum -a 256 | cut -d' ' -f1)"
fi
apksigner="$(printf '%s\n' "$sdk"/build-tools/*/apksigner | sort -V | tail -1)"

for abi in "${abis[@]}"; do
  apk="build/app/outputs/flutter-apk/app-$abi-release.apk"
  certs="$("$apksigner" verify --print-certs "$apk")"
  if [ -n "$debug" ] && grep "SHA-256 digest: $debug" <<<"$certs" > /dev/null; then
    fail "$apk is signed with the debug key"
  fi
  cp "$apk" "$out/telegrive-$version-$abi.apk"
done

if [ -n "$debug" ]; then
  fingerprint="$(tr a-f A-F <<<"$debug" | sed 's/../&:/g; s/:$//')"
  if keytool -printcert -jarfile "$aab" | grep "SHA256: $fingerprint" > /dev/null; then
    fail "$aab is signed with the debug key"
  fi
fi
cp "$aab" "$out/telegrive-$version.aab"

tool/build_ipa.sh "$@"
ipa="build/ios/ipa/telegrive-$version.ipa"
unzip -l "$ipa" | grep 'Payload/Runner.app/Frameworks/tdjson.framework/tdjson$' > /dev/null ||
  fail "$ipa doesn't carry TDLib"
cp "$ipa" "$out/"

tool/build_dmg.sh "$@"
cp "build/macos/dmg/telegrive-$version-macos.dmg" "$out/"

cd "$out"
shasum -a 256 -- * > SHA256SUMS.txt
ls -l
