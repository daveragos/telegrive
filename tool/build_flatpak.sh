#!/usr/bin/env bash
# Build Telegrive as a self-contained Flatpak bundle for Linux Mint.
# Usage: tool/build_flatpak.sh [x64|arm64] [flutter build arguments...]
set -euo pipefail

FLATPAK_BRANCH=24.08
APP_ID=dev.ragoose.telegrive
root="$(cd "$(dirname "$0")/.." && pwd)"

case "${1:-$(uname -m)}" in
  x64 | x86_64 | amd64) arch=x64; flatpak_arch=x86_64 ;;
  arm64 | aarch64) arch=arm64; flatpak_arch=aarch64 ;;
  *) echo "usage: $0 [x64|arm64] [flutter build arguments…]" >&2; exit 1 ;;
esac
shift || true

command -v flatpak >/dev/null || { echo "flatpak is required; install flatpak and flatpak-builder" >&2; exit 1; }
command -v flatpak-builder >/dev/null || { echo "flatpak-builder is required" >&2; exit 1; }

# Build the app and its AppImage. The AppImage's AppDir contains the same
# Flutter bundle plus the system libraries collected by linuxdeploy; those
# libraries are copied into /app/lib below so the Flatpak does not depend on
# host AppIndicator/libsecret/mpv packages.
"$root/tool/build_tdlib_linux.sh" "$arch"
"$root/tool/build_linux.sh" "$arch" "$@"

version="$(sed -n 's/^version: *\([^+]*\).*/\1/p' "$root/pubspec.yaml")"
appimage="$root/build/linux-release/Telegrive-$version-$arch.AppImage"
[ -f "$appimage" ] || { echo "AppImage not found: $appimage" >&2; exit 1; }

work="$(mktemp -d "${TMPDIR:-/tmp}/telegrive-flatpak.XXXXXX")"
trap 'rm -rf "$work"' EXIT
(
  cd "$work"
  chmod +x "$appimage"
  "$appimage" --appimage-extract >/dev/null
)
appdir="$work/squashfs-root"
[ -x "$appdir/usr/bin/telegrive" ] || { echo "AppImage did not contain the Telegrive executable" >&2; exit 1; }

# Flatpak builds use the Freedesktop runtime. Ensure both the runtime and SDK
# are installed (the SDK is needed by flatpak build-init).
flatpak install --user --or-update flathub \
  "org.freedesktop.Platform//$FLATPAK_BRANCH" \
  "org.freedesktop.Sdk//$FLATPAK_BRANCH"

builddir="$work/build"
repo="$work/repo"
flatpak build-init "$builddir" "$APP_ID" \
  org.freedesktop.Platform org.freedesktop.Sdk "$FLATPAK_BRANCH"

mkdir -p "$builddir/files/telegrive" "$builddir/files/lib" \
  "$builddir/files/bin" "$builddir/files/share/applications" \
  "$builddir/files/share/icons/hicolor/512x512/apps"
cp -a "$appdir/usr/bin/." "$builddir/files/telegrive/"
if [ -d "$appdir/usr/lib" ]; then
  cp -a "$appdir/usr/lib/." "$builddir/files/lib/"
fi
cp "$appdir/usr/share/applications/$APP_ID.desktop" \
  "$builddir/files/share/applications/$APP_ID.desktop"
cp "$appdir/usr/share/icons/hicolor/512x512/apps/$APP_ID.png" \
  "$builddir/files/share/icons/hicolor/512x512/apps/$APP_ID.png"

cat > "$builddir/files/bin/telegrive" <<'LAUNCHER'
#!/bin/sh
export LD_LIBRARY_PATH="/app/lib:/app/telegrive/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export GTK_USE_PORTAL=1
exec /app/telegrive/telegrive "$@"
LAUNCHER
chmod 0755 "$builddir/files/bin/telegrive"

# Use the XDG file chooser portal for user-selected files rather than exposing
# the whole home directory. The session bus permissions support the desktop
# keyring, notifications, and status-notifier tray.
flatpak build-finish "$builddir" \
  --command=telegrive \
  --share=network \
  --socket=x11 --socket=wayland --device=dri \
  --filesystem=xdg-download \
  --talk-name=org.freedesktop.secrets \
  --talk-name=org.freedesktop.Notifications \
  --talk-name=org.kde.StatusNotifierWatcher

flatpak build-export --arch="$flatpak_arch" "$repo" "$builddir" "$FLATPAK_BRANCH"
out="$root/build/linux-release/Telegrive-$version-$arch.flatpak"
flatpak build-bundle "$repo" "$out" "$APP_ID" "$FLATPAK_BRANCH"
echo "Built $out"
