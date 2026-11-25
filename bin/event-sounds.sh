#!/bin/sh
# Sounds of the charger, battery, Bluetooth, login and logout.
#   event-sounds.sh watch          play them when something happens
#   event-sounds.sh play EVENT     play one, unless its group is turned off in local.conf
#   event-sounds.sh preview EVENT  play one anyway
#   events: plug unplug battery-20 battery-10 battery-5 connected disconnected login logout
CONF="${XDG_CONFIG_HOME:-$HOME/.config}"
SOUNDS="${XDG_DATA_HOME:-$HOME/.local/share}/mini-de/sounds"
UPOWER=org.freedesktop.UPower

find_sound() {   # sets file and group
    case $1 in
        plug) group=SOUND_POWER file=power-plug ;;
        unplug) group=SOUND_POWER file=power-unplug ;;
        battery-20) group=SOUND_BATTERY file=battery-caution ;;
        battery-10) group=SOUND_BATTERY file=battery-low ;;
        battery-5) group=SOUND_BATTERY file=dialog-error-serious ;;
        connected) group=SOUND_BLUETOOTH file=device-added ;;
        disconnected) group=SOUND_BLUETOOTH file=device-removed ;;
        login) group=SOUND_LOGIN file=desktop-login ;;
        logout) group=SOUND_LOGOUT file=desktop-logout ;;
        *) echo "event-sounds.sh: unknown event '$1'" >&2; return 1 ;;
    esac
    file=$SOUNDS/$file.oga
}

# local.conf is read every time, so changes apply at once
enabled() (
    SOUND_POWER=1 SOUND_BATTERY=1 SOUND_BLUETOOTH=1 SOUND_LOGIN=1 SOUND_LOGOUT=0
    [ -r "$CONF/mini-de/local.conf" ] && . "$CONF/mini-de/local.conf" >/dev/null 2>&1
    eval "[ \"\$$1\" = 1 ]"
)

preview() {
    find_sound "$1" || return
    timeout 5 paplay --property=media.role=event "$file" </dev/null >/dev/null 2>&1
}
play() {
    find_sound "$1" || return
    if enabled "$group"; then preview "$1"; fi
}

level() {   # 0 to 3: how many of the warnings a charge has passed
    if [ "$1" -le 5 ]; then echo 3
    elif [ "$1" -le 10 ]; then echo 2
    elif [ "$1" -le 20 ]; then echo 1
    else echo 0
    fi
}
charge() {
    c=$(busctl --system --timeout=3 get-property $UPOWER /org/freedesktop/UPower/devices/DisplayDevice $UPOWER.Device Percentage 2>/dev/null)
    c=${c#d }
    c=${c%%.*}
    echo "${c:-100}"
}

watch() {
    on_battery=$(busctl --system --timeout=3 get-property $UPOWER /org/freedesktop/UPower $UPOWER OnBattery 2>/dev/null)
    on_battery=${on_battery#b }
    warned=$(level "$(charge)")      # no warning for what was already so
    { gdbus monitor --system --dest $UPOWER & gdbus monitor --system --dest org.bluez & wait; } | while read -r line; do
        event=
        case $line in
            "/org/freedesktop/UPower: "*"'OnBattery': <true>"*)
                [ "$on_battery" = true ] || event=unplug
                on_battery=true
                warned=$(level "$(charge)") ;;
            "/org/freedesktop/UPower: "*"'OnBattery': <false>"*)
                [ "$on_battery" = false ] || event=plug
                on_battery=false ;;
            "/org/freedesktop/UPower/devices/DisplayDevice: "*"'Percentage': <"*)
                [ "$on_battery" = true ] || continue
                pct=${line#*"'Percentage': <"}
                now=$(level "${pct%%[.>]*}")
                [ "$now" -gt "$warned" ] || continue
                warned=$now
                case $now in 1) event=battery-20 ;; 2) event=battery-10 ;; 3) event=battery-5 ;; esac ;;
            # other interfaces of the same device have a property with this name too
            "/org/bluez/"*"('org.bluez.Device1', "*"'Connected': <true>"*) event=connected ;;
            "/org/bluez/"*"('org.bluez.Device1', "*"'Connected': <false>"*) event=disconnected ;;
        esac
        [ -n "$event" ] || continue
        xset q >/dev/null 2>&1 || exit 0      # the session is over
        play "$event" &
    done
}

case $1 in
    watch) watch ;;
    play)
        if [ "$2" = login ]; then      # the sound card appears a moment after the sound server
            i=0
            while [ $i -lt 20 ]; do
                case $(pactl get-default-sink 2>/dev/null) in '' | auto_null | @DEFAULT_SINK@) ;; *) break ;; esac
                sleep 0.5
                i=$((i + 1))
            done
        fi
        play "$2" ;;
    preview) preview "$2" ;;
    *) sed -n '2,6s/^# *//p' "$0" >&2; exit 2 ;;
esac
