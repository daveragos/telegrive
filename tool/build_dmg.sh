#!/usr/bin/env bash
#
# Builds Telegrive for macOS into build/macos/dmg/telegrive-<version>-macos.dmg:
# one app for Apple silicon and Intel Macs, in a disk image whose window shows
# the app, an arrow to Applications beside it, and how to open it the first
# time. The window is drawn by tool/dmg_background.swift and laid out by
# dmgbuild from tool/dmg_settings.py; dmgbuild is installed into
# build/dmg-tools the first time, so that build needs the internet.
#
# The app is signed ad hoc, as Flutter signs a build with no Apple team, and
# isn't notarized, so a Mac asks before opening it the first time; the Mac
# guide on the site walks through Open Anyway. Extra arguments go to flutter
# build, for example --dart-define-from-file=telegram_api.json.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

fail() {
  echo "$*" >&2
  exit 1
}

[ -d macos/Frameworks/tdjson.xcframework ] ||
  fail "macos/Frameworks/tdjson.xcframework is missing; run tool/build_tdlib_macos.sh first"

app="build/macos/Build/Products/Release/Telegrive.app"
rm -rf "$app"
flutter build macos --release "$@"

version="$(plutil -extract CFBundleShortVersionString raw "$app/Contents/Info.plist")"
out="build/macos/dmg/telegrive-$version-macos.dmg"

# Every binary in the app runs on both kinds of Mac: the app's own, TDLib,
# mpv's libraries and each plugin's.
binaries=("$app/Contents/MacOS/Telegrive")
for framework in "$app"/Contents/Frameworks/*.framework; do
  binaries+=("$framework/$(basename "$framework" .framework)")
done
while IFS= read -r -d '' dylib; do
  binaries+=("$dylib")
done < <(find "$app/Contents/Frameworks" -name '*.dylib' -print0)
for binary in "${binaries[@]}"; do
  archs="$(lipo -archs "$binary")"
  [[ " $archs " == *" arm64 "* && " $archs " == *" x86_64 "* ]] ||
    fail "${binary#"$app/"} is built for $archs only"
done
[ -e "$app/Contents/Frameworks/tdjson.framework" ] || fail "$app doesn't carry TDLib"

codesign --verify --deep --strict "$app" || fail "$app isn't signed as a whole"
# The file picker asks the signature for this before it opens, sandbox or
# not, and every picker in the app fails without it.
codesign -d --entitlements - --xml "$app" 2>/dev/null | grep -q 'com.apple.security.files.user-selected.read-write' ||
  fail "$app lacks the user-selected files entitlement"

tools="build/dmg-tools"
if [ ! -x "$tools/bin/dmgbuild" ]; then
  python3 -m venv "$tools"
  "$tools/bin/pip" install --quiet --disable-pip-version-check "dmgbuild==2.0.0"
fi

art="$(mktemp -d)"
trap 'rm -rf "$art"' EXIT
swift tool/dmg_background.swift "$art"

mkdir -p "$(dirname "$out")"
rm -f "$out"
"$tools/bin/dmgbuild" -s tool/dmg_settings.py -D app="$app" -D background="$art/background.png" \
  Telegrive "$out" > /dev/null

echo "$out"
shasum -a 256 "$out"
