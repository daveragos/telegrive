#!/usr/bin/env bash
#
# Builds every file a release carries into build/release: an APK for each
# ABI, the app bundle, the unsigned IPA and SHA256SUMS.txt, ready to attach
# to a GitHub release. Runs on a Mac, which the IPA needs.
#
# It needs TDLib for both platforms (tool/build_tdlib_android.sh and
# tool/build_tdlib_ios.sh), the Telegram API credentials, and the upload key
# that android/key.properties names. Without that key Gradle signs with the
# debug key, and Android won't install such a build over the app people
# have, so the script stops. Extra arguments go to every flutter build, for
# example --dart-define-from-file=telegram_api.json.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

fail() {
  echo "$*" >&2
  exit 1
}

abis=(arm64-v8a armeabi-v7a x86_64)

[ -f android/key.properties ] || fail "android/key.properties is missing; release builds need the upload key"
for abi in "${abis[@]}"; do
  [ -f "android/app/src/main/jniLibs/$abi/libtdjson.so" ] ||
    fail "TDLib for $abi is missing; run tool/build_tdlib_android.sh first"
done

version="$(sed -n 's/^version: *\([^+]*\).*/\1/p' pubspec.yaml)"
out="build/release"
rm -rf "$out"
mkdir -p "$out"

flutter build apk --release --split-per-abi "$@"
flutter build appbundle --release "$@"

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
sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
apksigner="$(printf '%s\n' "$sdk"/build-tools/*/apksigner | sort -V | tail -1)"

for abi in "${abis[@]}"; do
  apk="build/app/outputs/flutter-apk/app-$abi-release.apk"
  certs="$("$apksigner" verify --print-certs "$apk")"
  if [ -n "$debug" ] && grep "SHA-256 digest: $debug" <<<"$certs" > /dev/null; then
    fail "$apk is signed with the debug key"
  fi
  cp "$apk" "$out/telegrive-$version-$abi.apk"
done

aab="build/app/outputs/bundle/release/app-release.aab"
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

cd "$out"
shasum -a 256 -- * > SHA256SUMS.txt
ls -l
