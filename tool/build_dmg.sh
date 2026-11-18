#!/usr/bin/env bash
#
# Builds Telegrive for macOS into build/macos/dmg/telegrive-<version>-macos.dmg:
# one app for Apple silicon and Intel Macs, in a disk image with Applications
# beside it to drag it to.
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

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
ditto "$app" "$stage/Telegrive.app"
ln -s /Applications "$stage/Applications"

mkdir -p "$(dirname "$out")"
rm -f "$out"
hdiutil create -quiet -volname Telegrive -srcfolder "$stage" -fs HFS+ -format UDZO "$out"

echo "$out"
shasum -a 256 "$out"
