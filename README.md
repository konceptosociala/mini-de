# mini-de

A small desktop for Ubuntu 24.04 on X11: Openbox, polybar, Plank and picom, tied together with a few
Python and shell scripts. It installs next to GNOME as a separate session and leaves GNOME in place.

## What is in it

- **Window frames** with smooth round buttons. Openbox only draws 1-bit button images, so a picom shader
  finds the circles in the titlebar and repaints them antialiased.
- **App launcher** on a tap of `Super`: full screen, search, and the same app folders GNOME uses.
  Drag an app onto a folder or onto another app; right-click to move, rename, hide or pin to the dock.
  Hidden apps live in a `.hidden` folder, shown with the eye button or `Ctrl+H`.
  Apps pinned to the dock are left out of the grid.
- **Keyboard layouts** on `Super+Space` in most recently used order, with an on-screen popup.
- **Panel** with per-core CPU load, brightness, volume, microphone, Wi-Fi and Bluetooth menus, power
  profiles, and a battery that changes color at 20, 10 and 5 %.
- **Event sounds** for the charger, low battery, Bluetooth devices, login and (off by default) logout.
- **Window handling** Openbox lacks: dragging maximized windows, wide invisible resize borders, and
  windows that cannot get stuck under the panel.
- **Settings app** for sound devices, event sounds, the wallpaper, icon theme and titlebar font.
- **Themes** for GTK 3, Qt 5, rofi, dunst, Plank and Alacritty, plus optional ones for Firefox, Telegram,
  the bash prompt and the LightDM login screen.

## Requirements

Ubuntu 24.04 with an X11 session. Other systems are not tested; the installer uses `apt`.
Smooth buttons need picom's `glx` backend; without it they are just pixelated.

## Install

```bash
git clone https://github.com/konceptosociala/mini-de
cd mini-de
./install.sh --variant intellij
```

Then log out and pick **Openbox** with the gear icon on the login screen.

The installer asks for `sudo` to install packages, copies the configuration to your home directory and
saves every file it replaces in `~/.local/state/mini-de/`. It may be run again at any time. To see what
it would do, use `./install.sh --dry-run`.

| Option | |
|---|---|
| `--variant V` | `soft`, `medium`, `hard` (Gruvbox) or `intellij` (IntelliJ New UI Dark) |
| `--yellow-button B` | which window button is yellow: `minimize` or `maximize` |
| `--prompt` | colored bash prompt; adds one line to `~/.bashrc` |
| `--firefox` | style Firefox; choose *System theme* in it afterwards |
| `--telegram` | build a Telegram Desktop theme file |
| `--link` | symlink to the repository instead of copying |
| `--no-apt`, `--no-themes`, `--no-wallpapers` | skip packages, downloaded themes or wallpapers |
| `--uninstall` | remove everything and restore the previous files; packages stay |

Choices are remembered, so a plain `./install.sh` keeps them.

### Login screen (optional)

```bash
login/install.sh               # or: login/install.sh path/to/wallpaper.png
login/install.sh --uninstall   # back to GDM
```

Replaces GDM with a themed LightDM after a reboot. It needs the `intellij` variant to be installed first.
GNOME's own screen lock depends on GDM and does not work with LightDM.

## Keys

| Keys | Action |
|---|---|
| `Super` | app launcher; `Ctrl+H` in it shows hidden apps |
| `Super+Space` | keyboard layout; hold `Super` to go further, `Shift` back, `Esc` cancel |
| `Super+Enter` or `Ctrl+Alt+T`, `Super+E` | terminal, files |
| `Super+Tab`, `Alt+Tab` | window list; switch windows (large icons, most recent first) |
| `Super+←` / `→` | left / right half of the screen |
| `Super+↑` / `↓` | maximize / minimize |
| `Super+Q` | close the window |
| `Super+L`, `Super+Esc` | lock, power menu |
| `Alt+F2` | run a command |
| `Print` | screenshot |
| `Alt` + left / right drag | move / resize a window from anywhere |

## Configuration

Settings of one machine live in `~/.config/mini-de/local.conf`, which the installer creates and never
overwrites: layouts, wallpaper, icon theme, titlebar font, event sounds, DPI, monitor layout. See
[local.conf.example](local.conf.example). The settings app writes to the same file.

Everything else is edited here and deployed with `./install.sh --no-apt`. Files ending in `.in` are
templates: `@NAME@` is replaced with a color of the chosen variant. A new palette is one file in
[variants/](variants/), plus its titlebar and hover colors in
[round-buttons.glsl](config/picom/round-buttons.glsl).

| Directory | |
|---|---|
| `bin/` | launcher, layout switcher, settings, window helpers, panel scripts |
| `config/` | Openbox, polybar, picom, rofi, dunst, Plank, Alacritty and others |
| `themes/` | Openbox theme and the recolored GTK theme |
| `variants/` | color palettes |
| `apps/`, `login/` | Qt, Firefox and Telegram themes, LightDM |
| `fonts/`, `wallpapers/`, `sounds/` | bundled fonts, pictures and sounds |

## License

[Apache License 2.0](LICENSE). Bundled fonts, wallpapers, sounds and other third-party files keep their own
licenses, see [THIRD-PARTY.md](THIRD-PARTY.md).
