#!/bin/sh
# Screen brightness through systemd-logind (no root needed): brightness.sh up|down [step, %]
CONF="${XDG_CONFIG_HOME:-$HOME/.config}"
BACKLIGHT=
[ -r "$CONF/mini-de/local.conf" ] && . "$CONF/mini-de/local.conf"
dev=${BACKLIGHT:-$(ls /sys/class/backlight 2>/dev/null | head -n1)}
[ -n "$dev" ] || exit 1
max=$(cat "/sys/class/backlight/$dev/max_brightness")
cur=$(cat "/sys/class/backlight/$dev/brightness")
step=${2:-5}
pct=$(((cur * 100 + max / 2) / max))
case $1 in
    up) pct=$((pct + step)) ;;
    down) pct=$((pct - step)) ;;
    *) echo "usage: brightness.sh up|down [step]" >&2; exit 2 ;;
esac
[ $pct -gt 100 ] && pct=100
[ $pct -lt 1 ] && pct=1
exec busctl --system call org.freedesktop.login1 /org/freedesktop/login1/session/auto \
    org.freedesktop.login1.Session SetBrightness ssu backlight "$dev" $((max * pct / 100))
