#!/usr/bin/env bash
# Installs mini-de (Openbox + polybar + Plank) for the current user.
set -euo pipefail

REPO=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)
CONF=${XDG_CONFIG_HOME:-$HOME/.config}
DATA=${XDG_DATA_HOME:-$HOME/.local/share}
STATE=${XDG_STATE_HOME:-$HOME/.local/state}/mini-de
MANIFEST=$STATE/manifest          # lines: installed file <TAB> saved original or -

PACKAGES=(
    openbox polybar plank rofi picom feh dunst lxpolkit playerctl
    xss-lock i3lock xsettingsd flameshot alacritty nautilus
    network-manager-gnome pulseaudio-utils bluez upower libnotify-bin libglib2.0-bin curl ca-certificates xz-utils fontconfig dconf-cli dbus-bin
    x11-xserver-utils x11-xkb-utils xinput libxi6 libxinerama1 xdg-desktop-portal-gtk
    librsvg2-common python3 python3-gi python3-gi-cairo gir1.2-gtk-3.0 python3-xdg
    fonts-inter fonts-dejavu-core qt5-style-kvantum qt5-gtk-platformtheme qt6-gtk-platformtheme
    yaru-theme-gtk yaru-theme-icon ubuntu-wallpapers
)
THEME_PACKAGES=(git sassc)
KVANTUM=(https://github.com/GabePoel/KvLibadwaita 1f4e0bec44b13dabfa1fe4047aa8eeaccf2f3557)
GRUVBOX=(https://github.com/Fausto-Korpsvart/Gruvbox-GTK-Theme 578cd220b5ff6e86b078a6111d26bb20ec8c733f)
ADW=(https://github.com/lassekongo83/adw-gtk3/releases/download/v6.5/adw-gtk3v6.5.tar.xz a81780fadfc432be0fc3d89c4ebb41aa28e4f032d42c36f9789c57dd10cfa41c)
TGBASE=(https://raw.githubusercontent.com/telegramdesktop/tdesktop/837b256778dbc6824957af345941d6ac183f07e0/Telegram/Resources/night.tdesktop-theme 364fcd7288453377e16db9c733fd98699b161248bc62cc62f78d58d909951d3a)
QOGIR=(https://github.com/vinceliuice/Qogir-icon-theme c633057ba0d27a504b3255144071c9691ed0264a)

usage() {
    cat <<EOF
Usage: ./install.sh [options]
  --link        symlink to the repository instead of copying
  --no-apt      do not install packages
  --no-themes   do not download third-party GTK themes and icons
  --no-wallpapers
                do not install the wallpapers
  --variant V   theme: soft, medium, hard (Gruvbox) or intellij (remembered; medium at first)
  --yellow-button B
                which window button is yellow: minimize or maximize; the other one is green
                (remembered; minimize at first)
  --prompt      also use the colored bash prompt (adds one line to ~/.bashrc; remembered)
  --firefox     also style Firefox (userChrome.css in the default profile; remembered)
  --telegram    also build a Telegram Desktop theme file (remembered)
  --dry-run     show what would be done without changing anything
  --uninstall   remove what was installed and restore previous files (packages stay)
EOF
}

MODE=copy APT=1 THEMES=1 DRY=0 ACTION=install VARIANT= YELLOW_BUTTON= PROMPT=0 FIREFOX=0 TELEGRAM=0 WALLPAPERS=1
while (($#)); do
    a=$1; shift
    case $a in
        --variant) VARIANT=${1:-}; shift || true; [ -n "$VARIANT" ] || { echo "--variant: expected a name, see --help" >&2; exit 2; } ;;
        --variant=*) VARIANT=${a#*=} ;;
        --yellow-button) YELLOW_BUTTON=${1:-}; shift || true; [ -n "$YELLOW_BUTTON" ] || { echo "--yellow-button: expected minimize or maximize" >&2; exit 2; } ;;
        --yellow-button=*) YELLOW_BUTTON=${a#*=} ;;
        --link) MODE=link ;;
        --no-wallpapers) WALLPAPERS=0 ;;
        --prompt) PROMPT=1 ;;
        --firefox) FIREFOX=1 ;;
        --telegram) TELEGRAM=1 ;;
        --no-apt) APT=0 ;;
        --no-themes) THEMES=0 ;;
        --dry-run) DRY=1 ;;
        --uninstall) ACTION=uninstall ;;
        -h|--help) usage; exit ;;
        *) echo "Unknown option: $a" >&2; usage >&2; exit 2 ;;
    esac
done

say()  { printf '\033[1;33m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;31m!!\033[0m %s\n' "$*" >&2; }
run()  { if ((DRY)); then printf '    %s\n' "$*"; else "$@"; fi; }

[ "$(id -u)" -ne 0 ] || { warn "Run this as a regular user: it asks for sudo when needed."; exit 1; }

# ── theme variant ─────────────────────────────────────────────
VARIANTS_DIR=$REPO/variants
variant_names() { (cd "$VARIANTS_DIR" && ls -- *.conf) | sed 's/\.conf$//' | paste -sd ' '; }

pick_variant() {
    if [ -z "$VARIANT" ] && [ -r "$STATE/variant" ]; then VARIANT=$(cat "$STATE/variant"); fi
    if [ -z "$VARIANT" ] && [ -t 0 ] && ((!DRY)); then
        read -rp "Theme variant ($(variant_names)) [medium]: " VARIANT || true
    fi
    VARIANT=${VARIANT:-medium}
    [[ $VARIANT =~ ^[a-z0-9-]+$ && -r $VARIANTS_DIR/$VARIANT.conf ]] ||
        { warn "Unknown variant '$VARIANT': use one of $(variant_names)."; exit 2; }
    . "$VARIANTS_DIR/$VARIANT.conf"
    SURFACE_HEX=${SURFACE#\#} BG_HEX=${BG#\#} GREEN=$MAX GREEN_HI=$MAX_HOVER YELLOW_HI=$ICONIFY_HOVER      # before --yellow-button swaps them
    say "Theme variant: $VARIANT"

    if [ -z "$YELLOW_BUTTON" ] && [ -r "$STATE/yellow-button" ]; then YELLOW_BUTTON=$(cat "$STATE/yellow-button"); fi
    YELLOW_BUTTON=${YELLOW_BUTTON:-minimize}
    case $YELLOW_BUTTON in
        minimize) ;;      # as defined by the variants
        maximize)
            local k a b
            for k in "" _HOVER _PRESSED; do
                a=MAX$k b=ICONIFY$k
                set -- "${!a}" "${!b}"
                printf -v "$a" %s "$2"
                printf -v "$b" %s "$1"
            done ;;
        *) warn "Unknown --yellow-button '$YELLOW_BUTTON': use minimize or maximize."; exit 2 ;;
    esac
    say "Yellow button: $YELLOW_BUTTON"
}

TOKENS=(VARIANT BG BG_INACTIVE SURFACE SURFACE_HEX BG_HEX GREEN GREEN_HI YELLOW_HI BORDER BORDER_INACTIVE RAISED FG DIM ACCENT ACCENT_TEXT ON_ACCENT
        HILITE HILITE_FG TILE RED CLOSE CLOSE_HOVER CLOSE_PRESSED MAX MAX_HOVER MAX_PRESSED
        ICONIFY ICONIFY_HOVER ICONIFY_PRESSED BTN_OFF BTN_DISABLED ROFI GTK_THEME CONF
        BLUE YELLOW PURPLE TEAL ORANGE TITLE_SIZE TITLE_WEIGHT TITLE_PADX TITLE_PADY ICON_THEME)
# Titlebar font from local.conf (set by the settings app), with the paddings that fit it
pick_title_font() {
    local line conf=$CONF/mini-de/local.conf
    TITLE_SIZE= TITLE_WEIGHT=
    if [ -r "$conf" ]; then
        TITLE_SIZE=$(set +eu; . "$conf" >/dev/null 2>&1; echo "${TITLE_FONT_SIZE:-}") || true
        TITLE_WEIGHT=$(set +eu; . "$conf" >/dev/null 2>&1; echo "${TITLE_FONT_WEIGHT:-}") || true
    fi
    [ "$TITLE_WEIGHT" = normal ] || TITLE_WEIGHT=bold
    line=$(awk -v s="${TITLE_SIZE:-11}" '$1 == s' "$REPO/config/mini-de/title-fonts")
    [ -n "$line" ] || { warn "TITLE_FONT_SIZE=$TITLE_SIZE is not supported, using 11"; line=$(awk '$1 == 11' "$REPO/config/mini-de/title-fonts"); }
    read -r TITLE_SIZE TITLE_PADX TITLE_PADY <<< "$line"
}

# Icon theme from local.conf (set by the settings app)
pick_icon_theme() {
    local conf=$CONF/mini-de/local.conf
    ICON_THEME=
    if [ -r "$conf" ]; then ICON_THEME=$(set +eu; . "$conf" >/dev/null 2>&1; echo "${ICON_THEME:-}") || true; fi
    ICON_THEME=${ICON_THEME:-$ICONS}
    if [[ ! $ICON_THEME =~ ^[A-Za-z0-9][A-Za-z0-9\ ._+-]*$ ]] ||
        { [[ ! $ICON_THEME =~ ^Qogir(-Ubuntu)?(-Dark)?$ ]] && ! have_icons; }; then
        warn "Icon theme '$ICON_THEME' is not installed, using $ICONS"
        ICON_THEME=$ICONS
    fi
}

render() {   # template -> stdout
    local t args=()
    for t in "${TOKENS[@]}"; do args+=(-e "s|@$t@|${!t}|g"); done
    sed "${args[@]}" "$1"
}

# ── files ────────────────────────────────────────────────────
# Prints "file in the repository <TAB> destination"
file_map() {
    local f
    for f in "$REPO"/bin/*; do
        case ${f##*/} in
            polybar-launch.sh) printf '%s\t%s\n' "$f" "$CONF/polybar/launch.sh" ;;
            *) printf '%s\t%s\n' "$f" "$CONF/openbox/${f##*/}" ;;
        esac
    done
    find "$REPO/config" -type f -not -path "$REPO/config/plank/*" | sort | while read -r f; do
        # the override only makes sense where the system has this autostart entry
        if [[ $f == */autostart/* && ! -e /etc/xdg/autostart/${f##*/} ]]; then
            continue
        fi
        printf '%s\t%s\n' "$f" "$CONF/${f#"$REPO/config/"}"
    done
    find "$REPO/themes" -type f | sort | while read -r f; do
        printf '%s\t%s\n' "$f" "$HOME/.themes/${f#"$REPO/themes/"}"
    done
    for f in "$REPO"/sounds/*; do printf '%s\t%s\n' "$f" "$DATA/mini-de/sounds/${f##*/}"; done
    for f in "$REPO"/share/applications/*; do printf '%s\t%s\n' "$f" "$DATA/applications/${f##*/}"; done
    if ((FIREFOX)) && f=$(firefox_profile); then
        printf '%s\t%s\n' "$REPO/apps/firefox/userChrome.css.in" "$f/chrome/userChrome.css.in"
        printf '%s\t%s\n' "$REPO/apps/firefox/userContent.css.in" "$f/chrome/userContent.css.in"
    fi
}

# Directory of Firefox's default profile
firefox_profile() {
    local d p
    for d in "$CONF/mozilla/firefox" "$HOME/.mozilla/firefox" "$HOME/snap/firefox/common/.mozilla/firefox"; do
        [ -r "$d/profiles.ini" ] || continue
        p=$(awk -F= '/^\[/ {s=$0} s ~ /^\[Install/ && $1 == "Default" {print $2; exit}' "$d/profiles.ini")
        [ -n "$p" ] || p=$(awk -F= '/^\[/ {path=""} $1 == "Path" {path=$2} $1 == "Default" && $2 == 1 && path {print path; exit}' "$d/profiles.ini")
        if [ -n "$p" ] && [ -d "$d/$p" ]; then echo "$d/$p"; return; fi
    done
    return 1
}
FIREFOX_PREF='user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);'

in_manifest() { [ -f "$MANIFEST" ] && cut -f1 "$MANIFEST" | grep -qxF -- "$1"; }

place() {
    local src=$1 dst=$2 saved=- mode=$MODE
    if [[ $src == *.in ]]; then      # templates are always installed as rendered copies
        dst=${dst%.in} mode=copy
        render "$src" > "$RENDERED"
        src=$RENDERED
    fi
    if [ "$mode" = link ]; then
        [ -L "$dst" ] && [ "$(readlink -f "$dst")" = "$src" ] && return 0
    else
        [ ! -L "$dst" ] && cmp -s "$src" "$dst" && in_manifest "$dst" && return 0
    fi
    if [ -e "$dst" ] || [ -L "$dst" ]; then
        # a link into this repository needs no backup
        if [ -L "$dst" ] && [[ $(readlink -f "$dst") == "$REPO"/* ]]; then
            run rm -f "$dst"
        else
            saved=$BACKUP/${dst#"$HOME"/}
            run mkdir -p "$(dirname "$saved")"
            run mv "$dst" "$saved"
            BACKED=1
        fi
    fi
    run mkdir -p "$(dirname "$dst")"
    if [ "$mode" = link ]; then run ln -s "$src" "$dst"; else run cp --preserve=mode "$src" "$dst"; fi
    if ((!DRY)) && ! in_manifest "$dst"; then printf '%s\t%s\n' "$dst" "$saved" >> "$MANIFEST"; fi
    CHANGED=$((CHANGED + 1))
    CHANGED_FILES+=("$dst")
}

install_files() {
    say "Files ($([ "$MODE" = link ] && echo 'symlinks to the repository' || echo 'copies'))"
    BACKUP=$STATE/backup-$(date +%Y%m%d-%H%M%S) BACKED=0 CHANGED=0 CHANGED_FILES=()
    run mkdir -p "$STATE"
    local src dst
    RENDERED=$(mktemp); chmod 644 "$RENDERED"
    while IFS=$'\t' read -r src dst; do place "$src" "$dst"; done < <(file_map)
    rm -f "$RENDERED"
    ((DRY)) || { echo "$VARIANT" > "$STATE/variant"; echo "$YELLOW_BUTTON" > "$STATE/yellow-button"; }
    echo "    changed: $CHANGED"
    ((!BACKED)) || echo "    previous files: $BACKUP"
}

uninstall() {
    [ -f "$MANIFEST" ] || { warn "Nothing to uninstall: $MANIFEST not found."; exit 1; }
    say "Uninstalling"
    local dst saved src back left=0
    BACKUP=$STATE/removed-$(date +%Y%m%d-%H%M%S)
    while IFS=$'\t' read -r dst saved; do
        if [ -L "$dst" ]; then
            if [[ $(readlink "$dst") == "$REPO"/* ]]; then
                run rm -f "$dst"
            else
                warn "kept, the link no longer points to the repository: $dst"; left=1; continue
            fi
        elif [ -e "$dst" ]; then
            # the copy may have been edited by hand: set it aside instead of deleting
            src=$BACKUP/${dst#"$HOME"/}
            run mkdir -p "$(dirname "$src")"
            run mv "$dst" "$src"
        fi
        if [ "$saved" != - ] && [ -e "$saved" ]; then
            run mkdir -p "$(dirname "$dst")"
            run mv "$saved" "$dst"
        fi
    done < "$MANIFEST"
    if grep -qsF "# mini-de prompt" "$HOME/.bashrc"; then
        run sed -i --follow-symlinks "/# mini-de prompt\$/d" "$HOME/.bashrc"
        run rm -f "$STATE/prompt"
    fi
    local p
    if [ -e "$STATE/firefox" ] && p=$(firefox_profile) && [ -f "$p/user.js" ]; then
        run sed -i "\\|^user_pref(\"toolkit.legacyUserProfileCustomizations.stylesheets\", true);\$|d" "$p/user.js"
        run rm -f "$STATE/firefox"
    fi
    run rm -rf "$CONF/Kvantum/mini-de"
    run rmdir --ignore-fail-on-non-empty "$HOME/.themes/"{Gruvbox-Round/openbox-3,Gruvbox-Round,mini-de-IntelliJ/{gtk-2.0,gtk-3.0,plank},mini-de-IntelliJ} 2>/dev/null || true
    ((left)) || run rm -f "$MANIFEST"
    say "Done. Packages, downloaded themes, the dock and $CONF/mini-de/local.conf were kept."
    echo "    Log in to another session: the current Openbox no longer has these settings."
}

# ── wallpapers ───────────────────────────────────────────────
install_wallpapers() {
    local dir=$DATA/mini-de/wallpapers f new=0
    ((WALLPAPERS)) || return 0
    for f in "$REPO"/wallpapers/*; do
        [ -e "$dir/${f##*/}" ] && continue          # never replace the user's pictures
        ((new)) || { say "Wallpapers: $dir"; run mkdir -p "$dir"; }
        run cp "$f" "$dir/"
        new=$((new + 1))
    done
    ((!new)) || echo "    added: $new"
}

# ── apps ─────────────────────────────────────────────────────
PROMPT_LINE='[ -r ~/.config/mini-de/prompt.sh ] && . ~/.config/mini-de/prompt.sh   # mini-de prompt'
setup_prompt() {
    local rc=$HOME/.bashrc
    ((PROMPT)) || return 0
    if ! grep -qsF '# mini-de prompt' "$rc"; then
        say "Bash prompt: one line added to $rc"
        ((!DRY)) || return 0
        [ ! -e "$rc" ] || cp -p "$rc" "$STATE/bashrc-before-prompt"
        [ ! -s "$rc" ] || [ -z "$(tail -c1 "$rc")" ] || echo >> "$rc"
        echo "$PROMPT_LINE" >> "$rc"
    fi
    ((DRY)) || touch "$STATE/prompt"
}

# Qt theme: KvLibadwaita in the colors of the variant
setup_qt() {
    local args=() k
    have_kvantum || return 0
    say "Qt theme: $CONF/Kvantum/mini-de"
    ((!DRY)) || return 0
    for k in SURFACE BG RAISED BORDER DIM FG ACCENT ACCENT_TEXT ON_ACCENT HILITE HILITE_FG; do args+=("$k=${!k}"); done
    python3 -I "$REPO/apps/qt/build.py" "$DATA/mini-de/kvlibadwaita" "$CONF/Kvantum/mini-de" "${args[@]}" ||
        warn "The Qt theme could not be built"
}

setup_firefox() {
    local p
    ((FIREFOX)) || return 0
    p=$(firefox_profile) || { warn "No Firefox profile found: start Firefox once and run this again."; return 0; }
    say "Firefox: $p"
    if ! grep -qsxF -- "$FIREFOX_PREF" "$p/user.js" && ((!DRY)); then
        [ ! -s "$p/user.js" ] || [ -z "$(tail -c1 "$p/user.js")" ] || echo >> "$p/user.js"
        echo "$FIREFOX_PREF" >> "$p/user.js"
    fi
    ((DRY)) || touch "$STATE/firefox"
    echo "    restart Firefox and choose 'System theme' in Add-ons and themes"
}

setup_telegram() {
    local tmp out=$DATA/mini-de/mini-de-$VARIANT.tdesktop-theme args=() k
    ((TELEGRAM)) || return 0
    say "Telegram theme: $out"
    ((!DRY)) || return 0
    tmp=$(mktemp -d)
    for k in SURFACE BG RAISED BORDER DIM FG ACCENT ACCENT_TEXT ON_ACCENT HILITE HILITE_FG; do args+=("$k=${!k}"); done
    mkdir -p "$DATA/mini-de"
    if curl -fsSL -o "$tmp/night" "${TGBASE[0]}" && echo "${TGBASE[1]}  $tmp/night" | sha256sum -c --quiet - &&
        python3 -I "$REPO/apps/telegram/build.py" "$tmp/night" "$out" "${args[@]}"; then
        touch "$STATE/telegram"
        echo "    send this file to Saved Messages in Telegram, click it there and apply the theme"
    else
        warn "Could not build the Telegram theme"
    fi
    rm -rf "$tmp"
}

# ── packages ───────────────────────────────────────────────────
install_packages() {
    local want=("${PACKAGES[@]}") missing=() p
    if ((THEMES)) && need_themes; then want+=("${THEME_PACKAGES[@]}"); fi
    for p in "${want[@]}"; do
        dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q '^install ok installed' || missing+=("$p")
    done
    if ((${#missing[@]} == 0)); then say "Packages: everything is already installed"; return; fi
    say "Packages: ${missing[*]}"
    run sudo apt-get update
    run sudo apt-get install -y --no-install-recommends "${missing[@]}"
}

# ── third-party themes ─────────────────────────────────────────────
have_theme() { [ -e "$1" ] || [ -e "$2" ]; }
have_gruvbox() { have_theme "$HOME/.themes/Gruvbox-Dark/index.theme" /usr/share/themes/Gruvbox-Dark/index.theme; }
have_icons() { have_theme "$DATA/icons/$ICON_THEME/index.theme" "/usr/share/icons/$ICON_THEME/index.theme"; }
have_adw() { [ -e "$HOME/.themes/adw-gtk3-dark/gtk-3.0/gtk.css" ]; }
have_gtk() { if [ "$GTK_THEME" = mini-de-IntelliJ ]; then have_adw; else have_gruvbox; fi; }
have_kvantum() { [ -e "$DATA/mini-de/kvlibadwaita/src/KvLibadwaita/KvLibadwaitaDark.svg" ]; }
need_themes() { ! have_gtk || ! have_icons || ! have_kvantum; }

fetch() {   # URL, commit, directory
    git init -q "$3" && git -C "$3" fetch -q --depth 1 "$1" "$2" && git -C "$3" -c advice.detachedHead=false checkout -q FETCH_HEAD
}

install_themes() {
    if ! need_themes; then say "Themes: already installed"; return; fi
    if ((DRY)); then say "Themes: download the GTK theme, the base of the Qt theme and/or the $ICON_THEME icons"; return; fi
    local tmp
    tmp=$(mktemp -d)
    if [ "$GTK_THEME" = mini-de-IntelliJ ] && ! have_adw; then
        say "GTK theme adw-gtk3"
        { curl -fsSL -o "$tmp/adw.tar.xz" "${ADW[0]}" && echo "${ADW[1]}  $tmp/adw.tar.xz" | sha256sum -c --quiet - &&
          mkdir -p "$HOME/.themes" "$tmp/adw" && tar -xJf "$tmp/adw.tar.xz" -C "$tmp/adw" &&
          rm -rf "$HOME/.themes/adw-gtk3-dark" && mv "$tmp/adw/adw-gtk3-dark" "$HOME/.themes/" && have_adw; } ||
            warn "adw-gtk3 failed to install"
    fi
    if [ "$GTK_THEME" = Gruvbox-Dark ] && ! have_gruvbox; then
        say "GTK theme Gruvbox-Dark"
        { fetch "${GRUVBOX[@]}" "$tmp/gruvbox" && mkdir -p "$HOME/.themes" &&
          (cd "$tmp/gruvbox/themes" && ./install.sh -d "$HOME/.themes" -c dark -t default) >"$tmp/log" 2>&1 && have_gruvbox; } ||
            { warn "Gruvbox-Dark failed to install, the default GTK theme stays"; tail -n 5 "$tmp/log" 2>/dev/null >&2 || true; }
    fi
    if ! have_kvantum; then
        say "Base of the Qt theme: KvLibadwaita"
        { fetch "${KVANTUM[@]}" "$tmp/kv" && mkdir -p "$DATA/mini-de/kvlibadwaita/src/KvLibadwaita" &&
          cp "$tmp/kv/LICENSE" "$DATA/mini-de/kvlibadwaita/" &&
          cp "$tmp/kv/src/KvLibadwaita/KvLibadwaitaDark".* "$DATA/mini-de/kvlibadwaita/src/KvLibadwaita/"; } ||
            warn "KvLibadwaita failed to install, Qt programs keep their look"
    fi
    if ! have_icons; then
        local flavor=default
        [[ $ICON_THEME != Qogir-Ubuntu* ]] || flavor=ubuntu
        say "Icons $ICON_THEME (the download takes a while)"
        { fetch "${QOGIR[@]}" "$tmp/qogir" && mkdir -p "$DATA/icons" &&
          (cd "$tmp/qogir" && ./install.sh -d "$DATA/icons" -t "$flavor") >"$tmp/log" 2>&1 && have_icons; } ||
            { warn "Qogir failed to install, the default icons stay"; tail -n 5 "$tmp/log" 2>/dev/null >&2 || true; }
    fi
    rm -rf "$tmp"
}

# ── fonts ────────────────────────────────────────────────────
install_fonts() {
    local dir=$DATA/fonts/mini-de f new=0
    for f in "$REPO"/fonts/*.ttf; do
        [ ! -e "$dir/${f##*/}" ] || continue
        ((new)) || { say "Fonts: $dir"; run mkdir -p "$dir"; }
        run cp "$f" "$dir/"
        new=$((new + 1))
    done
    ((!new)) || run fc-cache "$dir" || true
}

# ── settings of this machine ────────────────────────────────────
detect_layouts() {   # "layouts variants": from GNOME, else from X, else us
    python3 - <<'PY' 2>/dev/null || echo "us -"
import re, subprocess
def out(*a):
    try: return subprocess.run(a, capture_output=True, text=True).stdout
    except OSError: return ""
found = re.findall(r"\('xkb', '([^']+)'\)", out("gsettings", "get", "org.gnome.desktop.input-sources", "sources"))
pairs = [(f.split("+") + [""])[:2] for f in found]
if not pairs:
    q = dict(l.split(":", 1) for l in out("setxkbmap", "-query").splitlines() if ":" in l)
    ls = q.get("layout", "us").strip().split(",")
    vs = (q.get("variant", "").strip().split(",") + [""] * 4)
    pairs = list(dict.fromkeys(zip(ls, vs)))
pairs = pairs[:4]
v = ",".join(p[1] for p in pairs)
print(",".join(p[0] for p in pairs), v if v.strip(",") else "-")
PY
}

install_local_conf() {
    local dst=$CONF/mini-de/local.conf layouts variants
    if [ -e "$dst" ]; then say "Machine settings: $dst already exists"; return; fi
    read -r layouts variants < <(detect_layouts)
    [ "$variants" != - ] || variants=
    say "Machine settings: $dst (layouts: $layouts)"
    ((!DRY)) || return 0
    mkdir -p "$(dirname "$dst")"
    sed -e "s/^LAYOUTS=.*/LAYOUTS=$layouts/" -e "s/^VARIANTS=.*/VARIANTS=$variants/" "$REPO/local.conf.example" > "$dst"
}

# ── dock ──────────────────────────────────────────────────────
install_dock() {
    local dir=$CONF/plank/dock1/launchers pat d f id list=()
    if compgen -G "$dir/*.dockitem" >/dev/null; then say "Dock: already configured, leaving it alone"; return; fi
    say "Dock"
    while read -r pat; do
        [[ -z $pat || $pat == \#* ]] && continue
        for d in "$DATA/applications" /usr/local/share/applications /usr/share/applications /var/lib/snapd/desktop/applications; do
            f=$(compgen -G "$d/$pat" | head -n 1) || true
            [ -n "$f" ] || continue
            id=$(basename "$f" .desktop)
            list+=("'$id.dockitem'")
            if ((!DRY)); then
                mkdir -p "$dir"
                printf '[PlankDockItemPreferences]\nLauncher=file://%s\n' "$f" > "$dir/$id.dockitem"
            fi
            break
        done
    done < "$REPO/config/plank/items"
    echo "    pinned: ${#list[@]}"
    ((!DRY)) || return 0
    local joined
    joined=$(IFS=,; echo "${list[*]:-}")
    local load=(dconf load /net/launchpad/plank/)
    [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ] || load=(dbus-run-session -- "${load[@]}")
    { cat "$REPO/config/plank/plank.dconf"; [ -z "$joined" ] || echo "dock-items=[$joined]"; } | "${load[@]}" ||
        warn "Could not write Plank settings, the defaults stay"
}

# ── running session ──────────────────────────────────────────
changed() { local f; for f in "${CHANGED_FILES[@]}"; do [[ $f == $1 ]] && return 0; done; return 1; }

# Apply only what really changed; the launcher and the layout popup reread their colors when they open.
reload_session() {
    ((!DRY)) && [ -n "${DISPLAY:-}" ] && [ "${XDG_CURRENT_DESKTOP:-}" = OPENBOX ] &&
        pgrep -u "$(id -u)" -x openbox >/dev/null || return 0
    if changed "*/openbox/rc.xml" || changed "*/openbox/menu.xml" || changed "*/openbox-3/*"; then openbox --reconfigure || true; fi
    if changed "*/xsettingsd.conf"; then pkill -HUP -x xsettingsd || true; fi
    if changed "*/polybar/config.ini"; then polybar-msg cmd restart >/dev/null 2>&1 || true; fi
    if changed "*/event-sounds.sh"; then
        pkill -u "$(id -u)" -f "$CONF/openbox/event-sounds.sh watch" || true
        (env -u ELECTRON_RUN_AS_NODE setsid -f "$CONF/openbox/event-sounds.sh" watch >/dev/null 2>&1) || true
    fi
    if changed "*/dunstrc" && pkill -x dunst; then (env -u ELECTRON_RUN_AS_NODE setsid -f dunst >/dev/null 2>&1) || true; fi
    if changed "*/picom/*" && pkill -x picom; then      # a clean restart: reloading with SIGUSR1 is suspected of a freeze
        local i
        for i in {1..20}; do pgrep -x picom >/dev/null || break; sleep 0.1; done
        (env -u ELECTRON_RUN_AS_NODE picom -b >/dev/null 2>&1) || warn "picom did not start again, run: picom -b"
    fi
}

# ── input method ─────────────────────────────────────────────
# Outside GNOME Ubuntu's im-config starts IBus, which resets the layouts and grabs Super+Space.
# GNOME manages IBus itself and ignores this file.
disable_ibus() {
    local f=$HOME/.xinputrc
    if [ -e "$f" ]; then
        grep -qE '^[[:space:]]*run_im[[:space:]]+none' "$f" ||
            warn "$f selects an input method; if layouts disappear after login, run: im-config -n none"
        return 0
    fi
    say "Input method: IBus will not be started ($f)"
    ((DRY)) || printf '# im-config: created by mini-de, see install.sh\nrun_im none\n' > "$f"
}

# ── tray ─────────────────────────────────────────────────────
# polybar has its own Wi-Fi menu; nm-applet stays only as the password agent, without an icon
# (only its --no-indicator mode, set in autostart, obeys this setting)
nm_applet_icon() {
    local cmd=(dconf write /org/gnome/nm-applet/show-applet "$1")
    [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ] || cmd=(dbus-run-session -- "${cmd[@]}")
    run "${cmd[@]}" || warn "Could not change the nm-applet icon setting"
}

# ── main ───────────────────────────────────────────────────
if [ "$ACTION" = uninstall ]; then
    uninstall
    nm_applet_icon true
    if grep -qs "created by mini-de" "$HOME/.xinputrc"; then run rm -f "$HOME/.xinputrc"; fi
    exit
fi

os=$(. /etc/os-release 2>/dev/null && echo "${ID:-}-${VERSION_ID:-}") || os=unknown   # subshell: it may define VARIANT
[ "$os" = ubuntu-24.04 ] || warn "Only tested on Ubuntu 24.04, this is $os."
pick_variant
pick_title_font
pick_icon_theme
[ ! -e "$STATE/prompt" ] || PROMPT=1
[ ! -e "$STATE/firefox" ] || FIREFOX=1
[ ! -e "$STATE/telegram" ] || TELEGRAM=1
((!APT)) || install_packages
((!THEMES)) || install_themes
if [ "$GTK_THEME" = mini-de-IntelliJ ] && ! have_adw && ((!DRY)); then
    warn "adw-gtk3 is missing, using the GTK theme Yaru-blue-dark"
    GTK_THEME=Yaru-blue-dark
fi
install_fonts
install_files
install_local_conf
install_dock
nm_applet_icon false
disable_ibus
setup_qt
setup_prompt
setup_firefox
setup_telegram
install_wallpapers
[ -e /usr/share/xsessions/openbox.desktop ] || warn "No Openbox session in /usr/share/xsessions: the login screen will not offer it."
reload_session
((DRY)) && { say "Dry run, nothing was changed."; exit; }
say "Done. Log out and pick 'Openbox' with the gear icon on the login screen."
