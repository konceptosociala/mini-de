#!/bin/sh
# Bluetooth icon for polybar, printed on every change: off, on, or a device is connected.
# Colors come from polybar: NORMAL, ACTIVE (connected) and DIM (off).
last=unset

show() {
    # not --json: in systemd 255 it fails while headphones are connected
    all=$(busctl --system --timeout=3 call org.bluez / org.freedesktop.DBus.ObjectManager GetManagedObjects 2>/dev/null)
    case $all in
        *'"Powered" b true'*)
            case $all in
                *'"Connected" b true'*) out="%{F$ACTIVE}󰂱%{F-}" ;;
                *) out="%{F$NORMAL}󰂯%{F-}" ;;
            esac ;;
        *'"Powered" b false'*) out="%{F$DIM}󰂲%{F-}" ;;
        *) out= ;;               # no adapter: the module is hidden
    esac
    [ "$out" = "$last" ] || printf '%s\n' "$out"
    last=$out
}

show
gdbus monitor --system --dest org.bluez | while read -r line; do
    case $line in
        # scanning changes other properties of devices many times a second
        *org.bluez.Adapter1* | *"('org.bluez.Device1', "*"'Connected'"* | "The name "*) show ;;
    esac
done
