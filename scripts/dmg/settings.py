# dmgbuild settings for the MarkdownPeek installer window.
# Used by scripts/make-dmg.sh; https://dmgbuild.readthedocs.io/en/latest/settings.html
#
# Positions are icon centres in window points (top-left origin) and must match
# the artwork drawn by scripts/dmg/make-background.swift.
import os.path

app = defines["app"]  # noqa: F821  (dmgbuild injects `defines`)
app_name = os.path.basename(app)

# Volume
format = "ULFO"  # LZFSE-compressed, read-only (macOS 10.11+)
filesystem = "HFS+"
files = [app]
symlinks = {"Applications": "/Applications"}
icon = os.path.join(app, "Contents", "Resources", "AppIcon.icns")
hide_extensions = [app_name]

# Window
background = defines["background"]  # noqa: F821
# Height = background (440) + title bar (28). With Finder's tab bar turned on
# the bottom ~40 pt is hidden, which the artwork leaves empty.
window_rect = ((200, 140), (660, 468))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
include_icon_view_settings = True
include_list_view_settings = False

# Icons
arrange_by = None
icon_size = 128
text_size = 13
label_pos = "bottom"
icon_locations = {
    app_name: (170, 205),
    "Applications": (490, 205),
}
