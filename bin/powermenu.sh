#!/bin/sh
case "$(printf 'Lock\nLog out\nSuspend\nRestart\nShut down' | rofi -dmenu -i -p 'Power' -lines 5)" in
    Lock) loginctl lock-session ;;
    'Log out') openbox --exit ;;
    Suspend) systemctl suspend ;;
    Restart) systemctl reboot ;;
    'Shut down') systemctl poweroff ;;
esac
