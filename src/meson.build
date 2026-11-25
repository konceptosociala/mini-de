common_sources = files(
  'common/recent-order.vala',
  'common/rect.vala',
  'common/single-instance.vala',
  'x11/connection.vala',
  'x11/keymap-symbols.vala',
  'x11/names.vala',
  'x11/window.vala',
)

# Window handling that Openbox lacks; without GTK, so that it stays small
executable(
  'mini-de-wm',
  common_sources,
  'wm/deferred-task.vala',
  'wm/main.vala',
  'wm/resize-border.vala',
  'wm/resize-borders.vala',
  'wm/titlebar-keeper.vala',
  'wm/unmaximize.vala',
  dependencies: [glib, x11, posix, xl],
)

# Popups of the desktop
executable(
  'mini-de-shell',
  common_sources,
  'shell/app-icons.vala',
  'shell/launcher/app-folders.vala',
  'shell/launcher/dock.vala',
  'shell/launcher/hidden-apps.vala',
  'shell/launcher/item-art.vala',
  'shell/launcher/item-cell.vala',
  'shell/launcher/item-grid.vala',
  'shell/launcher/item-menu.vala',
  'shell/launcher/items.vala',
  'shell/launcher/launcher-model.vala',
  'shell/launcher/launcher.vala',
  'shell/launcher/string-lists.vala',
  'shell/main.vala',
  'common/notifications.vala',
  'shell/popup.vala',
  'shell/shell-service.vala',
  'shell/styles.vala',
  'shell/switchers/app-catalog.vala',
  'shell/switchers/layout-switcher.vala',
  'shell/switchers/window-cell.vala',
  'shell/switchers/window-switcher.vala',
  'x11/super-tap.vala',
  dependencies: [
    glib,
    gtk,
    x11,
    c_compiler.find_library('Xi'),
    c_compiler.find_library('m'),
    posix,
    xl,
  ],
)

# Menus of the panel
executable(
  'mini-de-menu',
  'common/command.vala',
  'common/notifications.vala',
  'menus/bluetooth-menu.vala',
  'menus/bluetooth.vala',
  'menus/bluez.vala',
  'menus/main.vala',
  'menus/network-manager.vala',
  'menus/pairing-agent.vala',
  'menus/rofi.vala',
  'menus/wifi-menu.vala',
  dependencies: [glib, gio],
)

executable(
  'mini-de-settings',
  'common/command.vala',
  'settings/files.vala',
  'settings/icon-theme.vala',
  'settings/icons-page.vala',
  'settings/local-conf.vala',
  'settings/main.vala',
  'settings/page.vala',
  'settings/settings-window.vala',
  'settings/sound/device-section.vala',
  'settings/sound/event-sounds.vala',
  'settings/sound/sound-page.vala',
  'settings/sound/sound-server.vala',
  'settings/titlebar-font.vala',
  'settings/wallpaper-page.vala',
  'settings/windows-page.vala',
  dependencies: [
    glib,
    gtk,
    posix,
    dependency('json-glib-1.0'),
    c_compiler.find_library('m'),
  ],
)

# Themes of other programs; only install.sh runs it
executable(
  'mini-de-theme',
  'themes/color.vala',
  'themes/main.vala',
  'themes/qt-theme.vala',
  'themes/telegram-theme.vala',
  dependencies: [
    glib,
    gio,
    dependency('gdk-pixbuf-2.0'),
    c_compiler.find_library('m'),
  ],
)
