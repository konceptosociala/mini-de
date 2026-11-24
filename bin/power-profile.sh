#!/bin/sh
# Power profiles (the same service as in GNOME): performance, balanced, power-saver.
#   power-profile.sh watch   print an icon for polybar on every change
#   power-profile.sh next    switch to the next profile
#   power-profile.sh menu    choose one in rofi
BUS=net.hadess.PowerProfiles
OBJ=/net/hadess/PowerProfiles

get()  { busctl --system get-property $BUS $OBJ $BUS ActiveProfile 2>/dev/null | cut -d'"' -f2; }
list() { powerprofilesctl list | sed -n 's/^[* ] \([a-z-]*\):$/\1/p'; }
name() {
    case $1 in
        performance) echo 'Performance' ;;
        balanced) echo 'Balanced' ;;
        power-saver) echo 'Power saver' ;;
        *) echo "$1" ;;
    esac
}
icon() {   # FontAwesome: rocket, balance scale, leaf
    case $1 in
        performance) printf '%%{F%s}\357\204\265%%{F-}\n' "${HOT:--}" ;;
        balanced) printf '\357\211\216\n' ;;
        power-saver) printf '%%{F%s}\357\201\254%%{F-}\n' "${COOL:--}" ;;
        *) echo ;;
    esac
}
set_profile() {
    if err=$(powerprofilesctl set "$1" 2>&1); then
        notify-send -t 2000 -h string:x-dunst-stack-tag:power-profile 'Power mode' "$(name "$1")"
    else
        notify-send -u critical 'Power mode was not changed' "$err"
    fi
}

case $1 in
    watch)
        icon "$(get)"
        gdbus monitor --system --dest $BUS --object-path $OBJ | while read -r line; do
            case $line in *ActiveProfile*) icon "$(get)" ;; esac
        done ;;
    next)
        cur=$(get)
        next=$(list | awk -v c="$cur" '{p[NR]=$0; if ($0 == c) i=NR} END {if (NR) print p[i % NR + 1]}')
        [ -n "$next" ] && set_profile "$next" ;;
    menu)
        cur=$(get)
        row=$(list | grep -nxF -- "$cur" | cut -d: -f1)
        pick=$(list | while read -r p; do name "$p"; done | rofi -dmenu -i -p 'Power mode' -l 3 -a "$((${row:-1} - 1))" -selected-row "$((${row:-1} - 1))" -format i)
        [ -n "$pick" ] && set_profile "$(list | sed -n "$((pick + 1))p")" ;;
    *) sed -n '2,5s/^# *//p' "$0" >&2; exit 2 ;;
esac
