# dmgbuild settings for the installer disk image. Run through scripts/notarize.sh, which passes
# the app's path as -D app=... and this folder as -D assets=... ; background.png (and background@2x.png) come from make-background.py.
import os

# dmgbuild runs this file without __file__, so the folder and the app arrive as -D defines.
here = defines["assets"]  # noqa: F821
app = defines["app"]  # noqa: F821

format = "UDZO"
filesystem = "HFS+"
files = [app]
symlinks = {"Applications": "/Applications"}
background = os.path.join(here, "background.png")
icon_locations = {os.path.basename(app): (180, 195), "Applications": (480, 195)}
window_rect = ((200, 160), (660, 400))
icon_size = 128
text_size = 13
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
default_view = "icon-view"
include_icon_view_settings = "auto"
arrange_by = None
