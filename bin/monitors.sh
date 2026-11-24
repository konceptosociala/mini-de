#!/bin/sh
# The built-in screen is primary on the left, the others follow to its right.
# Set your own layout in local.conf: MONITORS_CMD='xrandr --output ...'
CONF="${XDG_CONFIG_HOME:-$HOME/.config}"
MONITORS_CMD=
[ -r "$CONF/mini-de/local.conf" ] && . "$CONF/mini-de/local.conf"
if [ -n "$MONITORS_CMD" ]; then
    eval "$MONITORS_CMD"
    exit
fi
on=$(xrandr | awk '$2 == "connected" {print $1}')
[ "$(echo "$on" | wc -l)" -gt 1 ] || exit 0
first=$(echo "$on" | grep -m1 -E '^(eDP|LVDS|DSI)' ||
        xrandr | awk '$2 == "connected" && $3 == "primary" {print $1; exit}')
[ -n "$first" ] || first=$(echo "$on" | head -n1)
set -- --output "$first" --primary --auto --pos 0x0
prev=$first
for m in $on; do
    [ "$m" = "$first" ] && continue
    set -- "$@" --output "$m" --auto --right-of "$prev"
    prev=$m
done
exec xrandr "$@"
