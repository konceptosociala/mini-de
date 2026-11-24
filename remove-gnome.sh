#!/usr/bin/env bash
# Removes GNOME from this machine without breaking the Openbox desktop. Run as a regular user.
#   remove-gnome.sh [-n] apps     GNOME apps, GNOME Flashback and Evolution services; GDM and gnome-shell stay
#   remove-gnome.sh [-n] shell    GDM and gnome-shell; refuses unless LightDM is running
#   -n   only show what would happen
# Never runs autoremove: packages that would become unused are marked as manually installed first.
set -euo pipefail
export LC_ALL=C
DRY=0; [ "${1:-}" != -n ] || { DRY=1; shift; }

APPS=(gnome-clocks gnome-terminal nautilus-extension-gnome-terminal gnome-tweaks gnome-shell-extension-manager
      chrome-gnome-shell gnome-browser-connector gnome-sound-recorder gnome-characters gnome-logs
      gnome-power-manager gnome-font-viewer cheese gnome-initial-setup gnome-remote-desktop
      gnome-startup-applications gnome-user-docs gnome-user-docs-uk ubuntu-docs yelp
      gnome-session-flashback gnome-flashback gnome-panel gnome-applets evolution-data-server
      ubuntu-desktop-minimal)     # the last one is a metapackage
SHELL_PKGS=(gdm3 gnome-shell gnome-shell-extension-prefs gnome-shell-extension-appindicator
      gnome-shell-extension-desktop-icons-ng gnome-shell-extension-ubuntu-dock
      gnome-shell-extension-ubuntu-tiling-assistant ubuntu-session gnome-session-canberra
      xdg-desktop-portal-gnome yaru-theme-gnome-shell)
KEEP=(openbox polybar plank rofi picom feh dunst lxpolkit xss-lock i3lock xsettingsd flameshot alacritty nautilus
      network-manager network-manager-gnome xorg xserver-xorg xserver-xorg-core xserver-xorg-input-libinput xinput x11-xserver-utils
      xdg-desktop-portal xdg-desktop-portal-gtk gnome-keyring libpam-gnome-keyring gnome-control-center
      gnome-settings-daemon gvfs gvfs-backends pipewire wireplumber pipewire-pulse power-profiles-daemon upower
      polkitd dbus systemd-sysv accountsservice bluez cups ubuntu-minimal ubuntu-standard
      yaru-theme-gtk yaru-theme-icon fonts-inter bamfdaemon gedit evince eog file-roller seahorse)

installed() { [ "$(dpkg-query -W -f='${db:Status-Status}' "$1" 2>/dev/null)" = installed ]; }
removed()   { apt-get -s remove "$@" | awk '/^Remv/{print $2}' | sort; }
die() { echo "!! $*" >&2; exit 1; }

case ${1:-} in
    apps)  want=("${APPS[@]}"); KEEP+=(gdm3 gnome-shell gnome-session-bin) ;;
    shell) want=("${SHELL_PKGS[@]}"); KEEP+=(lightdm lightdm-gtk-greeter)
           if ! systemctl is-active -q lightdm || [ "$(cat /etc/X11/default-display-manager)" != /usr/sbin/lightdm ]; then
               ((DRY)) && echo "(dry run: LightDM is not running, the real run would stop here)" ||
                   die "LightDM is not the running login screen. Run login/install.sh, reboot, log in through it, then repeat."
           fi ;;
    *) sed -n '2,6s/^# \{0,1\}//p' "$0"; exit 1 ;;
esac

list=(); for p in "${want[@]}"; do ! installed "$p" || list+=("$p"); done
((${#list[@]})) || { echo "Nothing to remove."; exit; }
mapfile -t gone < <(removed "${list[@]}")
((${#gone[@]})) || die "apt found no way to do it."

# nothing important may go
for k in "${KEEP[@]}"; do
    if printf '%s\n' "${gone[@]}" | grep -qx "$k"; then die "$k would be removed as well, stopping."; fi
done
# nothing that was not asked for, either
extra=$(comm -23 <(printf '%s\n' "${gone[@]}") <(printf '%s\n' "${list[@]}" | sort))
[ -z "$extra" ] || die "These would be removed too: $extra"

# everything else autoremove would take is kept
mapfile -t orphans < <(comm -13 <(printf '%s\n' "${gone[@]}") \
    <(apt-get -s remove --autoremove "${list[@]}" | awk '/^Remv/{print $2}' | sort))
keep=(); for p in "${KEEP[@]}" "${orphans[@]}"; do ! installed "$p" || keep+=("$p"); done

echo "To be removed (${#gone[@]}): ${gone[*]}"
echo "To be kept as manually installed: ${#keep[@]} packages"
((!DRY)) || exit 0
read -rp "Go on? [y/N] " a; [ "$a" = y ] || exit 1

saved=$HOME/gnome-removed-$1-$(date +%Y%m%d-%H%M%S).txt
printf '%s\n' "${gone[@]}" > "$saved"
sudo apt-mark manual "${keep[@]}" >/dev/null
sudo apt-get -s autoremove | grep -q '^Remv' && echo "note: apt already had unused packages"
sudo apt-get remove --no-auto-remove "${list[@]}"      # asks once more
if [ "$1" = apps ]; then
    sudo update-alternatives --set x-terminal-emulator /usr/bin/alacritty
fi
echo "Done. To undo: sudo apt install \$(cat $saved)"
echo "Check that apt has nothing dangerous left to clean up: apt-get -s autoremove"
