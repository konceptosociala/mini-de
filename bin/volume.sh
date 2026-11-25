#!/bin/sh
# Volume of the default output or input, never above 100 %: volume.sh up|down [step, %] [sink|source]
# Absolute values are set, so key repeat cannot overshoot; the balance is kept.
LIMIT=100
step=${2:-5}
kind=${3:-sink}
case $1 in
    up) ;;
    down) step=-$step ;;
    *) echo "usage: volume.sh up|down [step] [sink|source]" >&2; exit 2 ;;
esac
case $kind in
    sink) dev=@DEFAULT_SINK@ ;;
    source) dev=@DEFAULT_SOURCE@ ;;
    *) echo "volume.sh: expected sink or source, got $kind" >&2; exit 2 ;;
esac
new=$(LC_ALL=C pactl "get-$kind-volume" $dev | awk -v step="$step" -v limit="$LIMIT" '
    /^Volume:/ {
        for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+%$/) { v[++n] = $i + 0; if (v[n] > max) max = v[n] }
        target = max + step
        if (target > limit) target = limit
        if (target < 0) target = 0
        for (i = 1; i <= n; i++) { x = v[i] + target - max; printf "%d%% ", x < 0 ? 0 : x }
    }')
[ -n "$new" ] || exit 1
exec pactl "set-$kind-volume" $dev $new
