#!/usr/bin/env bash
#
# Builds an unsigned Telegrive IPA for sideloading into build/ios/ipa.
#
# Sideloadly, SideStore and AltStore sign the app with the installer's own
# Apple Account when they put it on the iPhone, so the IPA ships unsigned and
# needs no Apple team. Extra arguments go to flutter build, for example
# --dart-define-from-file=telegram_api.json.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

[ -d ios/Frameworks/tdjson.xcframework ] || {
  echo "ios/Frameworks/tdjson.xcframework is missing; run tool/build_tdlib_ios.sh first" >&2
  exit 1
}

# Xcode's product for the Release configuration. Flutter's copy in
# build/ios/iphoneos holds whichever mode was built last.
app="build/ios/Release-iphoneos/Runner.app"

# An unsigned build leaves the signature and provisioning profile of an
# earlier signed one in place, and a profile names its team and the devices
# it was made for, so the app is built afresh.
rm -rf "$app"
flutter build ios --release --no-codesign "$@"

version="$(plutil -extract CFBundleShortVersionString raw "$app/Info.plist")"
out="build/ios/ipa/telegrive-$version.ipa"

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
mkdir "$stage/Payload"
ditto "$app" "$stage/Payload/Runner.app"
rm -rf "$stage/Payload/Runner.app/_CodeSignature" "$stage/Payload/Runner.app/embedded.mobileprovision"

mkdir -p "$(dirname "$out")"
rm -f "$out"
(cd "$stage" && zip -qry "$root/$out" Payload)

echo "$out"
shasum -a 256 "$out"
