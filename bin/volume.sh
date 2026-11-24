#!/bin/sh
# Volume of the default output, never above 100 %: volume.sh up|down [step, %]
# Absolute values are set, so key repeat cannot overshoot; the balance is kept.
LIMIT=100
step=${2:-5}
case $1 in
    up) ;;
    down) step=-$step ;;
    *) echo "usage: volume.sh up|down [step]" >&2; exit 2 ;;
esac
new=$(LC_ALL=C pactl get-sink-volume @DEFAULT_SINK@ | awk -v step="$step" -v limit="$LIMIT" '
    /^Volume:/ {
        for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+%$/) { v[++n] = $i + 0; if (v[n] > max) max = v[n] }
        target = max + step
        if (target > limit) target = limit
        if (target < 0) target = 0
        for (i = 1; i <= n; i++) { x = v[i] + target - max; printf "%d%% ", x < 0 ? 0 : x }
    }')
[ -n "$new" ] || exit 1
exec pactl set-sink-volume @DEFAULT_SINK@ $new
