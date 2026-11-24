#!/bin/sh
# Restarts polybar on every monitor (tray only on the primary one).
# Battery, adapter and backlight are detected; override them in local.conf.
CONF="${XDG_CONFIG_HOME:-$HOME/.config}"
BATTERY=; ADAPTER=; BACKLIGHT=
[ -r "$CONF/mini-de/local.conf" ] && . "$CONF/mini-de/local.conf"

supply() {   # first supply of the given type; mouse batteries etc. (scope=Device) are skipped
    for d in /sys/class/power_supply/*; do
        [ "$(cat "$d/type" 2>/dev/null)" = "$1" ] || continue
        [ "$(cat "$d/scope" 2>/dev/null)" = Device ] && continue
        basename "$d"
        return
    done
}
[ -n "$BATTERY" ] || BATTERY=$(supply Battery)
[ -n "$ADAPTER" ] || ADAPTER=$(supply Mains)
[ -n "$BACKLIGHT" ] || BACKLIGHT=$(ls /sys/class/backlight 2>/dev/null | head -n1)
export BATTERY="${BATTERY:-BAT0}" ADAPTER="${ADAPTER:-AC}" BACKLIGHT="${BACKLIGHT:-none}"

pkill -x polybar
i=0   # wait for the old ones to exit, 3 seconds at most
while pgrep -x polybar >/dev/null && [ $i -lt 30 ]; do sleep 0.1; i=$((i + 1)); done
primary=$(polybar --list-monitors | grep -m1 primary | cut -d: -f1)
[ -z "$primary" ] && primary=$(polybar --list-monitors | head -1 | cut -d: -f1)
for m in $(polybar --list-monitors | cut -d: -f1); do
    if [ "$m" = "$primary" ]; then MONITOR=$m polybar main &
    else MONITOR=$m polybar side &
    fi
done
