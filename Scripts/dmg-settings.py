# dmgbuild settings for the disk image published by the release workflow.
#
#   dmgbuild -s Scripts/dmg-settings.py -D app=<path> "Invoices <version>" <out.dmg>
#
# What this buys over `hdiutil create -srcfolder`: a .DS_Store. A disk image
# without one opens at whatever size and view the Finder happened to use last,
# with the icons wherever it decides to drop them — which is why the first
# release mounted as a near-full-screen window with the Applications alias
# sitting to the left of the app. Every Mac installer that looks like an
# installer is an image carrying the window it wants.
#
# dmgbuild writes those bytes itself. The other common tool, create-dmg, poses
# the window by scripting the Finder over AppleScript, which needs a desktop
# session and an automation permission — neither of which a CI runner has.

import os.path

application = defines["app"]
appname = os.path.basename(application)

# Contents: the app, and the alias you drag it onto.
files = [application]
symlinks = {"Applications": "/Applications"}

# The volume shows the app's own icon rather than the generic white disk, in
# the title bar and wherever the mounted volume is listed. Xcode compiles the
# asset catalog into this .icns, so there is nothing to render here.
icon = os.path.join(application, "Contents", "Resources", "AppIcon.icns")

# No background image on purpose. dmgbuild ships the classic drag-here arrow,
# but it is opaque and light: on a Mac in dark mode it lands as a white slab
# inside a dark window. With no image the window is whatever the Finder's
# current appearance is, and the instruction survives without artwork — an app
# on the left, the Applications folder with its alias badge on the right.
background = None

# ((x, y), (width, height)). Taller than the icons need: a window sized to
# them alone hides the labels behind the path bar and the status bar, which
# plenty of people leave switched on. Those are Finder-wide toggles — the
# show_* settings below are recorded in the .DS_Store, but a Finder told to
# show a path bar shows one here too — so the height has to make room for
# them rather than assume them away.
window_rect = ((100, 100), (620, 400))
default_view = "icon-view"

show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False

icon_size = 128
text_size = 12
label_pos = "bottom"
arrange_by = None

# Source on the left, destination on the right: the direction the drag goes.
icon_locations = {
    appname: (150, 150),
    "Applications": (470, 150),
}

# Matches what the workflow published before: zlib-compressed, read-only.
format = "UDZO"
