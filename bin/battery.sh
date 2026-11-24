#!/bin/sh
# Battery for polybar: icon and color by charge (20, 10 and 5 %), blinking at 5 % and below.
# Colors come from polybar: NORMAL (icon), WARN, LOW, CRIT and ON_CRIT (text while blinking).
DIR=${BATTERY_DIR:-/sys/class/power_supply/${BATTERY:-BAT0}}
LEVELS="󰁺 󰁺 󰁻 󰁼 󰁽 󰁾 󰁿 󰂀 󰂁 󰂂 󰁹"
CHARGING="󰢜 󰢜 󰂆 󰂇 󰂈 󰢝 󰂉 󰢞 󰂊 󰂋 󰂅"

blink=0
last=
while [ -r "$DIR/capacity" ]; do
    read -r pct < "$DIR/capacity"
    read -r status < "$DIR/status"
    case $status in Charging | Full | "Not charging") icons=$CHARGING plugged=1 ;; *) icons=$LEVELS plugged=0 ;; esac
    # shellcheck disable=SC2086  # split into words on purpose
    set -- $icons
    shift $(((pct > 100 ? 100 : pct) / 10))
    icon=$1 color= pause=3
    if [ $plugged = 1 ]; then color=$NORMAL
    elif [ "$pct" -le 5 ]; then color=$CRIT pause=1 blink=$((1 - blink))
    elif [ "$pct" -le 10 ]; then color=$LOW
    elif [ "$pct" -le 20 ]; then color=$WARN
    fi
    if [ $plugged = 1 ] || [ "$pct" -gt 20 ]; then
        out="%{F$NORMAL}%{T2}$icon%{T-}%{F-} $pct%"
    elif [ "$pct" -le 5 ] && [ $blink = 1 ]; then
        out="%{B$color}%{F$ON_CRIT} %{T2}$icon%{T-} $pct% %{F-}%{B-}"
    elif [ "$pct" -le 5 ]; then
        out="%{F$color} %{T2}$icon%{T-} $pct% %{F-}"
    else
        out="%{F$color}%{T2}$icon%{T-} $pct%%{F-}"
    fi
    [ "$out" = "$last" ] || printf '%s\n' "$out"
    last=$out
    sleep $pause
done
