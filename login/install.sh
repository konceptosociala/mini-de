#!/usr/bin/env bash
# LightDM login screen in mini-de style. Run as a regular user, it asks for sudo.
#   login/install.sh [wallpaper.png]   install LightDM, its theme and make it the login screen
#   login/install.sh --uninstall       go back to GDM
# Takes effect after a reboot; the running session is not touched.
set -euo pipefail
REPO=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)
DATA=${XDG_DATA_HOME:-$HOME/.local/share}
THEME=/usr/share/themes/mini-de-login
BACKGROUND=/usr/share/backgrounds/mini-de-login.png
CONF=/etc/lightdm/lightdm-gtk-greeter.conf.d/90-mini-de.conf
SEAT=/etc/lightdm/lightdm.conf.d/90-mini-de.conf
WRAPPER=/usr/local/lib/mini-de-greeter
LOCALES=/usr/share/locale          # <language>@minide: a catalog with one shorter message
LOCAL_CONF=${XDG_CONFIG_HOME:-$HOME/.config}/mini-de/local.conf
say()  { printf '\033[1;33m==>\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m!!\033[0m %s\n' "$*" >&2; exit 1; }
[ "$(id -u)" -ne 0 ] || die "Run this as a regular user: it asks for sudo when needed."

# $1: package (lightdm or gdm3), $2: its binary
choose_dm() {
    [ -x "$2" ] || die "$2 is missing, the login screen was not changed."
    echo "$1 shared/default-x-display-manager select $1" | sudo debconf-set-selections
    echo "$2" | sudo tee /etc/X11/default-display-manager >/dev/null
    sudo DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true dpkg-reconfigure "$1" 2>/dev/null || true
    # the alias decides what systemd starts at boot
    local unit=/usr/lib/systemd/system/$1.service
    [ -e "$unit" ] || unit=/usr/lib/systemd/system/gdm.service
    sudo ln -sfn "$unit" /etc/systemd/system/display-manager.service
    [ "$(cat /etc/X11/default-display-manager)" = "$2" ] || die "The default login screen could not be set."
}

if [ "${1:-}" = --uninstall ]; then
    say "Back to GDM"
    choose_dm gdm3 /usr/sbin/gdm3
    sudo rm -rf "$THEME" "$BACKGROUND" "$CONF" "$SEAT" "$WRAPPER" "$LOCALES"/*@minide
    say "Done, reboot to see it. The LightDM packages stay: sudo apt remove lightdm lightdm-gtk-greeter"
    exit
fi

wallpaper=${1:-$DATA/mini-de/wallpapers/misty-cliffs.png}
[ -r "$wallpaper" ] || die "No wallpaper at $wallpaper: run ./install.sh first or pass a picture."
adw=$HOME/.themes/adw-gtk3-dark
[ -d "$adw" ] || die "adw-gtk3 is missing: run ./install.sh --variant intellij first."

say "Packages"
echo "lightdm shared/default-x-display-manager select $(basename "$(cat /etc/X11/default-display-manager 2>/dev/null || echo /usr/sbin/gdm3)")" | sudo debconf-set-selections
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends lightdm lightdm-gtk-greeter gettext fonts-inter yaru-theme-icon

say "Theme"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/gtk-3.0"
cp -r "$adw/gtk-3.0/." "$tmp/gtk-3.0/"
mv "$tmp/gtk-3.0/gtk.css" "$tmp/gtk-3.0/adw.css"
{ echo '@import url("adw.css");'; grep '^@define-color' "$REPO/themes/mini-de-IntelliJ/gtk-3.0/gtk.css"; cat "$REPO/login/mini-de.css"; } > "$tmp/gtk-3.0/gtk.css"
cp "$tmp/gtk-3.0/gtk.css" "$tmp/gtk-3.0/gtk-dark.css"
printf '[Desktop Entry]\nType=X-GNOME-Metatheme\nName=mini-de-login\n' > "$tmp/index.theme"
sudo rm -rf "$THEME"
sudo install -d "$THEME"
sudo cp -r "$tmp/." "$THEME/"
sudo chown -R root:root "$THEME"
sudo chmod -R u=rwX,go=rX "$THEME"
sudo install -m 644 "$wallpaper" "$BACKGROUND"

say "Messages"
# "Your password is incorrect. Please try again." does not wrap and stretches the login window
for message in 'en=Wrong password' 'uk=Неправильний пароль' 'ru=Неверный пароль'; do
    catalog=$tmp/locale/${message%%=*}@minide/LC_MESSAGES
    mkdir -p "$catalog"
    msgfmt -o "$catalog/lightdm-gtk-greeter.mo" - <<EOF
msgid ""
msgstr "Content-Type: text/plain; charset=UTF-8\nContent-Transfer-Encoding: 8bit\n"

msgid "Your password is incorrect. Please try again."
msgstr "${message#*=}"
EOF
done
cat > "$tmp/greeter" <<'EOF'
#!/bin/sh
# Starts the LightDM greeter with the messages of mini-de. Installed by login/install.sh.
lang=${LANGUAGE:-${LC_ALL:-${LC_MESSAGES:-$LANG}}}
lang=${lang%%[:_.@]*}
[ ! -d "/usr/share/locale/$lang@minide" ] || export LANGUAGE="$lang@minide:${LANGUAGE:-${LANG%%.*}}"
[ ! -x /usr/lib/lightdm/lightdm-greeter-session ] || exec /usr/lib/lightdm/lightdm-greeter-session "$@"
exec "$@"
EOF
sudo cp -r "$tmp/locale/." "$LOCALES/"
sudo chmod -R u=rwX,go=rX "$LOCALES"/*@minide
sudo install -D -m 755 "$tmp/greeter" "$WRAPPER"

say "Configuration"
# Keyboard layouts from local.conf, only these are offered; none without at least two of them
LAYOUTS=us; VARIANTS=
[ ! -r "$LOCAL_CONF" ] || . "$LOCAL_CONF"
IFS=, read -ra layouts <<< "$LAYOUTS"
IFS=, read -ra variants <<< "$VARIANTS"
list=; layout=
for i in "${!layouts[@]}"; do
    list+="${layouts[i]}${variants[i]:+\\t${variants[i]}};"
done
((${#layouts[@]} < 2)) || layout='~layout;'
sudo install -d "$(dirname "$CONF")" "$(dirname "$SEAT")"
sudo tee "$CONF" >/dev/null <<EOF
[greeter]
background=$BACKGROUND
user-background=false
theme-name=mini-de-login
icon-theme-name=Yaru
cursor-theme-name=Yaru
cursor-theme-size=24
font-name=Inter 12
xft-antialias=true
xft-hintstyle=hintslight
xft-rgba=rgb
xft-dpi=96
position=50%,center 50%,center
clock-format=%a %d %b   %H:%M
# menus are far from each other: moving the pointer over a neighbour opens it
indicators=~host;~session;~spacer;~clock;$layout~spacer;~power
keyboard-layouts=$list
hide-user-image=false
round-user-image=true
EOF
sudo tee "$SEAT" >/dev/null <<EOF
[Seat:*]
greeter-session=lightdm-gtk-greeter
user-session=openbox
greeter-wrapper=$WRAPPER
EOF
choose_dm lightdm /usr/sbin/lightdm
say "Done. LightDM will start after a reboot."
echo "    If it does not work: Ctrl+Alt+F3, log in, then: $REPO/login/install.sh --uninstall && sudo reboot"
