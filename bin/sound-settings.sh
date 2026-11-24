#!/bin/sh
# Sound settings. GNOME's own refuse to start outside GNOME, unless told that this is it.
if command -v pavucontrol >/dev/null; then
    exec pavucontrol
elif command -v gnome-control-center >/dev/null; then
    XDG_CURRENT_DESKTOP=GNOME exec gnome-control-center sound
else
    exec notify-send "No sound settings" "Install pavucontrol"
fi
