#!/bin/sh
# Microphone for polybar: prints the volume of the default input on every change.
# Colors come from polybar: NORMAL (icon) and DIM (muted).
export LC_ALL=C
last=unset

show() {
    out=
    case $(pactl get-default-source 2>/dev/null) in
        '' | *.monitor) ;;       # no microphone: the module is hidden
        *)
            pct=$(pactl get-source-volume @DEFAULT_SOURCE@ 2>/dev/null | grep -o '[0-9]*%' | head -n1)
            case $(pactl get-source-mute @DEFAULT_SOURCE@ 2>/dev/null) in
                *yes) out="%{F$DIM}%{T2}󰍭%{T-} $pct%{F-}" ;;
                *) out="%{F$NORMAL}%{T2}󰍬%{T-}%{F-} $pct" ;;
            esac ;;
    esac
    [ "$out" = "$last" ] || printf '%s\n' "$out"
    last=$out
}

while :; do      # pactl exits when the sound server restarts
    show
    pactl subscribe 2>/dev/null | while read -r line; do
        case $line in *" on source #"* | *" on server"*) show ;; esac
    done
    sleep 2
    last=unset
done
