#!/usr/bin/env bash
#
# Builds Telegrive for Linux into build/linux-release:
#
#   telegrive-<version>-linux-<arch>.tar.gz   the app's folder, to unpack anywhere
#   Telegrive-<version>-<arch>.AppImage       one file that runs on its own
#
#   tool/build_linux.sh [x64|arm64] [flutter build arguments…]
#
# It builds inside an Ubuntu 22.04 container, as TDLib's script does, so the
# app runs on any Linux with glibc 2.35 or newer whatever machine built it,
# and needs Docker and TDLib for the architecture (tool/build_tdlib_linux.sh).
# The container works on a copy of the repository, so Flutter's files for
# the machine outside are left alone. On a Mac, Docker runs x64 through
# emulation, which is slow. Extra arguments go to flutter build, for example
# --dart-define-from-file=telegram_api.json.
#
# The folder needs GTK 3, libsecret, AppIndicator and libmpv from the system
# (on Debian and Ubuntu: libgtk-3-0 libsecret-1-0 libayatana-appindicator3-1
# and libmpv1 or libmpv2); the AppImage carries them, except GTK's own
# libraries, which come with the desktop.
set -euo pipefail

# The Flutter release the app is built with; keep it in step with the one
# the other platforms are built with.
FLUTTER_VERSION=3.47.4

IMAGE=ubuntu:22.04

# linuxdeploy gathers the libraries into the AppImage, and appimagetool packs
# it. Both publish their builds as a continuous release.
LINUXDEPLOY=https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous
APPIMAGETOOL=https://github.com/AppImage/appimagetool/releases/download/continuous

root="$(cd "$(dirname "$0")/.." && pwd)"

case "${1:-$(uname -m)}" in
  x64 | x86_64 | amd64) arch=x64 machine=x86_64 docker_platform=linux/amd64 ;;
  arm64 | aarch64) arch=arm64 machine=aarch64 docker_platform=linux/arm64 ;;
  *) echo "usage: $0 [x64|arm64] [flutter build arguments…]" >&2; exit 1 ;;
esac
shift || true

out="build/linux-release"

# Outside the container: start it on this script, with the repository
# mounted, and come back once the files are in place.
if [ "${LINUX_IN_CONTAINER:-}" != 1 ]; then
  command -v docker > /dev/null || { echo "docker is required" >&2; exit 1; }
  [ -f "$root/linux/tdlib/linux-$arch/libtdjson.so" ] ||
    { echo "TDLib for $arch is missing; run tool/build_tdlib_linux.sh $arch first" >&2; exit 1; }
  docker run --rm --platform "$docker_platform" \
    -e LINUX_IN_CONTAINER=1 -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
    -v "$root:/src" -w /src "$IMAGE" tool/build_linux.sh "$arch" "$@"
  ls -l "$root/$out"
  exit 0
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
  ca-certificates curl git unzip xz-utils zip file rsync \
  clang cmake ninja-build pkg-config libstdc++-12-dev \
  libgtk-3-dev liblzma-dev libsecret-1-dev libayatana-appindicator3-dev \
  libmpv-dev libepoxy-dev > /dev/null

git clone -q --depth 1 --branch "$FLUTTER_VERSION" https://github.com/flutter/flutter.git /opt/flutter
export PATH="/opt/flutter/bin:$PATH"
git config --global --add safe.directory /opt/flutter
flutter config --no-analytics > /dev/null
flutter precache --linux > /dev/null

# A copy without what the machine outside built.
rsync -a --exclude .git --exclude .dart_tool --exclude build \
  --exclude 'macos/Pods' --exclude 'ios/Pods' --exclude 'linux/flutter/ephemeral' /src/ /work/
cd /work
flutter build linux --release "$@"

version="$(sed -n 's/^version: *\([^+]*\).*/\1/p' pubspec.yaml)"
bundle="build/linux/$arch/release/bundle"
[ -f "$bundle/lib/libtdjson.so" ] || { echo "$bundle doesn't carry TDLib" >&2; exit 1; }

mkdir -p "/src/$out"

# The folder, as telegrive/ in the archive.
stage="$(mktemp -d)"
cp -a "$bundle" "$stage/telegrive"
tar -C "$stage" -czf "/src/$out/telegrive-$version-linux-$arch.tar.gz" telegrive

# The AppImage: the folder under usr/bin, with what it links to gathered
# into usr/lib by linuxdeploy, and a desktop entry and icon for menus.
appdir="$stage/Telegrive.AppDir"
mkdir -p "$appdir/usr/bin" "$appdir/usr/share/applications" "$appdir/usr/share/icons/hicolor/512x512/apps"
cp -a "$bundle/." "$appdir/usr/bin/"
cat > "$appdir/usr/share/applications/dev.ragoose.telegrive.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Telegrive
Comment=Your files, kept in your own Telegram
Exec=telegrive
Icon=dev.ragoose.telegrive
Categories=Utility;FileTools;
Terminal=false
DESKTOP
cp assets/brand/mark.png "$appdir/usr/share/icons/hicolor/512x512/apps/dev.ragoose.telegrive.png"

tools="$(mktemp -d)"
curl -fsSL -o "$tools/linuxdeploy" "$LINUXDEPLOY/linuxdeploy-$machine.AppImage"
curl -fsSL -o "$tools/appimagetool" "$APPIMAGETOOL/appimagetool-$machine.AppImage"
chmod +x "$tools/linuxdeploy" "$tools/appimagetool"
# Docker has no FUSE, so both run unpacked.
export APPIMAGE_EXTRACT_AND_RUN=1
"$tools/linuxdeploy" --appdir "$appdir" \
  --executable "$appdir/usr/bin/telegrive" \
  --library "$appdir/usr/bin/lib/libtdjson.so" \
  --desktop-file "$appdir/usr/share/applications/dev.ragoose.telegrive.desktop" \
  --icon-file "$appdir/usr/share/icons/hicolor/512x512/apps/dev.ragoose.telegrive.png"
ARCH="$machine" "$tools/appimagetool" "$appdir" "/src/$out/Telegrive-$version-$arch.AppImage"

cd "/src/$out"
sha256sum -- *"$version"*"$arch"* > "SHA256SUMS-linux-$arch.txt"
chown -R "$HOST_UID:$HOST_GID" "/src/$out"
