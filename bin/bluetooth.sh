#!/bin/sh
# Bluetooth icon for polybar, printed on every change: off, on, or a device is connected.
# Colors come from polybar: NORMAL, ACTIVE (connected) and DIM (off).
last=unset

show() {
    all=$(busctl --system --timeout=3 --json=short call org.bluez / org.freedesktop.DBus.ObjectManager GetManagedObjects 2>/dev/null)
    case $all in
        *'"Powered":{"type":"b","data":true}'*)
            case $all in
                *'"Connected":{"type":"b","data":true}'*) out="%{F$ACTIVE}󰂱%{F-}" ;;
                *) out="%{F$NORMAL}󰂯%{F-}" ;;
            esac ;;
        *'"Powered":'*) out="%{F$DIM}󰂲%{F-}" ;;
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
