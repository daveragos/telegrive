#!/bin/sh
# Copies the renders that flutter_launcher_icons doesn't handle into place:
# the status-bar icon at each density, the drive channel's photo, and the
# mark the app shows.
set -e
cd "$(dirname "$0")/../.."
for pair in mdpi:24 hdpi:36 xhdpi:48 xxhdpi:72 xxxhdpi:96; do
  density=${pair%%:*}
  px=${pair##*:}
  sips -z "$px" "$px" tool/icon/out/notification.png \
    --out "android/app/src/main/res/drawable-$density/ic_stat_telegrive.png" >/dev/null
done
sips -s format jpeg -s formatOptions 92 tool/icon/out/channel_photo.png \
  --out assets/brand/channel_photo.jpg >/dev/null
cp tool/icon/out/mark.png assets/brand/mark.png
echo "Installed notification icons, channel photo and the app's mark."
