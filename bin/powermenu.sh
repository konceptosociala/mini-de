#!/bin/sh
bye() { "${XDG_CONFIG_HOME:-$HOME/.config}/openbox/event-sounds.sh" play logout; }   # off unless SOUND_LOGOUT=1
case "$(printf 'Lock\nLog out\nSuspend\nRestart\nShut down' | rofi -dmenu -i -p 'Power' -lines 5)" in
    Lock) loginctl lock-session ;;
    'Log out') bye; openbox --exit ;;
    Suspend) systemctl suspend ;;
    Restart) bye; systemctl reboot ;;
    'Shut down') bye; systemctl poweroff ;;
esac
