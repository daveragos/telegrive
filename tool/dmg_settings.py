# How Telegrive's disk image looks when a Mac opens it, read by dmgbuild
# (see tool/build_dmg.sh, which passes the app and the background drawn by
# tool/dmg_background.swift):
#
#   dmgbuild -s tool/dmg_settings.py -D app=<Telegrive.app> \
#     -D background=<folder>/background.png Telegrive <out.dmg>
#
# The app sits on the left and Applications on the right, where the
# background's arrow runs between them. The window has no toolbar or
# sidebar, and the disk's own icon is the app's on a disk.
import os.path

app = defines["app"]
name = os.path.basename(app)

format = "ULFO"
filesystem = "HFS+"
files = [app]
symlinks = {"Applications": "/Applications"}
badge_icon = os.path.join(app, "Contents", "Resources", "AppIcon.icns")

background = defines["background"]
# The window's height takes in its title bar.
window_rect = ((200, 120), (660, 428))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
icon_size = 112
text_size = 13
label_pos = "bottom"
# The same centres as tool/dmg_background.swift's.
icon_locations = {
    name: (170, 190),
    "Applications": (490, 190),
}
