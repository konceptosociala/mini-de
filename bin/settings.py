#!/usr/bin/python3
"""Mini DE settings: settings.py [page]. Every page is a class with ID, TITLE and ICON added to PAGES."""
import json, os, re, shlex, shutil, subprocess, sys, tempfile, xml.dom.minidom
import gi
gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gtk, Gdk, GdkPixbuf, Gio, GLib, Pango

CONFIG = os.path.join(GLib.get_user_config_dir(), "mini-de", "local.conf")
WALLPAPERS = os.path.join(GLib.get_user_data_dir(), "mini-de", "wallpapers")
DEFAULT_WALLPAPER = "/usr/share/backgrounds/warty-final-ubuntu.png"
IMAGES = (".png", ".jpg", ".jpeg", ".webp", ".bmp")
THUMB_W, THUMB_H = 240, 150
CSS = b"""
.wallpaper { border-radius: 10px; padding: 5px; border: 3px solid transparent; outline: none; }
.wallpaper:hover { background: alpha(currentColor, 0.08); }
.wallpaper.current { border-color: @theme_selected_bg_color; }
.page-title { font-size: 20px; font-weight: 700; }
.section-title { font-size: 15px; font-weight: 600; }
"""


# ── local.conf ───────────────────────────────────────────────
def read_setting(name, default=""):
    """Value of a variable in local.conf, evaluated by the shell just like autostart does."""
    if not os.path.exists(CONFIG):
        return default
    r = subprocess.run(["sh", "-c", f'. "$1" >/dev/null 2>&1; printf %s "${name}"', "sh", CONFIG],
                       capture_output=True, text=True)
    return r.stdout or default


def write_setting(name, value):
    """Replace the variable in local.conf and keep everything else as it is."""
    path = os.path.realpath(CONFIG)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    lines = []
    if os.path.exists(path):
        with open(path) as f:
            lines = f.read().splitlines()
    new, hits = f"{name}={shlex.quote(value)}", [i for i, l in enumerate(lines) if re.match(rf"\s*(export\s+)?{name}=", l)]
    if hits:
        lines[hits[-1]] = new
    else:
        lines.append(new)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path))
    with os.fdopen(fd, "w") as f:
        f.write("\n".join(lines) + "\n")
    os.chmod(tmp, os.stat(path).st_mode & 0o777 if os.path.exists(path) else 0o644)
    os.replace(tmp, path)


# ── wallpaper ────────────────────────────────────────────────
class WallpaperPage(Gtk.Box):
    ID, TITLE, ICON = "wallpaper", "Wallpaper", "preferences-desktop-wallpaper"

    def __init__(self, window):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=14, margin=20)
        self.window, self.queue = window, []
        os.makedirs(WALLPAPERS, exist_ok=True)

        bar = Gtk.Box(spacing=8)
        title = Gtk.Label(label=self.TITLE, xalign=0)
        title.get_style_context().add_class("page-title")
        bar.pack_start(title, True, True, 0)
        for label, icon, action in (("Open folder", "folder-open-symbolic", self.open_folder),
                                    ("Add image…", "list-add-symbolic", self.add_image)):
            b = Gtk.Button(label=label, image=Gtk.Image.new_from_icon_name(icon, Gtk.IconSize.BUTTON), always_show_image=True)
            b.connect("clicked", action)
            bar.pack_start(b, False, False, 0)
        self.pack_start(bar, False, False, 0)

        self.error = Gtk.Label(xalign=0, no_show_all=True, wrap=True)
        self.error.get_style_context().add_class("error")
        self.pack_start(self.error, False, False, 0)

        self.flow = Gtk.FlowBox(homogeneous=True, valign=Gtk.Align.START, row_spacing=8, column_spacing=8,
                                min_children_per_line=2, max_children_per_line=8, selection_mode=Gtk.SelectionMode.NONE)
        scroll = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
        scroll.add(self.flow)
        self.pack_start(scroll, True, True, 0)

        self.monitor = Gio.File.new_for_path(WALLPAPERS).monitor_directory(Gio.FileMonitorFlags.NONE, None)
        self.monitor.connect("changed", self.on_folder_changed)
        self.reload_id = 0
        self.reload()

    def on_folder_changed(self, *_):
        if not self.reload_id:
            self.reload_id = GLib.timeout_add(400, self.reload)

    def reload(self):
        self.reload_id = 0
        self.current = os.path.realpath(read_setting("WALLPAPER", DEFAULT_WALLPAPER))
        files = sorted((os.path.join(WALLPAPERS, n) for n in os.listdir(WALLPAPERS)
                        if n.lower().endswith(IMAGES)), key=lambda p: os.path.basename(p).casefold())
        if self.current not in map(os.path.realpath, files) and os.path.exists(self.current):
            files.insert(0, self.current)          # chosen outside the folder
        for c in self.flow.get_children():
            c.destroy()
        self.queue = [self.add_tile(p) for p in files]
        self.flow.show_all()
        GLib.idle_add(self.load_next)
        return False

    def add_tile(self, path):
        image = Gtk.Image()
        image.set_size_request(THUMB_W, THUMB_H)
        name = re.sub(r"[-_]+", " ", os.path.splitext(os.path.basename(path))[0]).strip().capitalize()
        label = Gtk.Label(label=name, ellipsize=Pango.EllipsizeMode.END, max_width_chars=24)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        box.pack_start(image, False, False, 0)
        box.pack_start(label, False, False, 0)
        button = Gtk.Button(relief=Gtk.ReliefStyle.NONE, tooltip_text=path)
        button.get_style_context().add_class("wallpaper")
        button.add(box)
        button.path = path
        button.connect("clicked", self.choose)
        self.mark(button)
        self.flow.add(button)
        button.get_parent().set_can_focus(False)
        return path, image

    def load_next(self):
        """Load thumbnails one by one so the window opens at once."""
        if not self.queue:
            return False
        path, image = self.queue.pop(0)
        try:
            pb = GdkPixbuf.Pixbuf.new_from_file(path)
            k = max(THUMB_W / pb.get_width(), THUMB_H / pb.get_height())
            pb = pb.scale_simple(max(THUMB_W, round(pb.get_width() * k)), max(THUMB_H, round(pb.get_height() * k)),
                                 GdkPixbuf.InterpType.HYPER if k < 0.2 else GdkPixbuf.InterpType.BILINEAR)
            image.set_from_pixbuf(pb.new_subpixbuf((pb.get_width() - THUMB_W) // 2, (pb.get_height() - THUMB_H) // 2,
                                                   THUMB_W, THUMB_H))
        except GLib.Error:
            image.set_from_icon_name("image-missing", Gtk.IconSize.DIALOG)
        return bool(self.queue)

    def mark(self, button):
        ctx = button.get_style_context()
        (ctx.add_class if os.path.realpath(button.path) == self.current else ctx.remove_class)("current")

    def show_error(self, text):
        self.error.set_text(text)
        self.error.set_visible(bool(text))

    def choose(self, button):
        r = subprocess.run(["feh", "--no-fehbg", "--bg-fill", button.path], capture_output=True, text=True)
        if r.returncode:
            return self.show_error(r.stderr.strip() or "feh could not set this image")
        try:
            write_setting("WALLPAPER", button.path)
        except OSError as e:
            return self.show_error(f"The wallpaper is set, but could not be saved: {e}")
        self.show_error("")
        self.current = os.path.realpath(button.path)
        for c in self.flow.get_children():
            self.mark(c.get_child())

    def open_folder(self, _b):
        Gio.AppInfo.launch_default_for_uri(GLib.filename_to_uri(WALLPAPERS, None), None)

    def add_image(self, _b):
        dlg = Gtk.FileChooserDialog(title="Add images", transient_for=self.window, action=Gtk.FileChooserAction.OPEN,
                                    select_multiple=True)
        dlg.add_buttons("Cancel", Gtk.ResponseType.CANCEL, "Add", Gtk.ResponseType.ACCEPT)
        flt = Gtk.FileFilter()
        flt.set_name("Images")
        for ext in IMAGES:
            flt.add_pattern("*" + ext)
            flt.add_pattern("*" + ext.upper())
        dlg.add_filter(flt)
        files = dlg.get_filenames() if dlg.run() == Gtk.ResponseType.ACCEPT else []
        dlg.destroy()
        for src in files:
            stem, ext = os.path.splitext(os.path.basename(src))
            dst, n = os.path.join(WALLPAPERS, stem + ext), 2
            if os.path.realpath(src) == os.path.realpath(dst):
                continue
            while os.path.exists(dst):             # never overwrite an existing image
                dst, n = os.path.join(WALLPAPERS, f"{stem}-{n}{ext}"), n + 1
            try:
                shutil.copyfile(src, dst)
            except OSError as e:
                self.show_error(str(e))


# ── windows ──────────────────────────────────────────────────
OPENBOX = os.path.join(GLib.get_user_config_dir(), "openbox", "rc.xml")
THEMERC = os.path.expanduser("~/.themes/Gruvbox-Round/openbox-3/themerc")
TITLE_FONTS = os.path.join(GLib.get_user_config_dir(), "mini-de", "title-fonts")
TITLE_RE = re.compile(r'(<font place="(?:Active|Inactive)Window">\s*<name>[^<]*</name>\s*<size>)(\d+)(</size>.*?<weight>)(\w+)', re.S)


def title_fonts():
    """Supported sizes -> (padding.width, padding.height)."""
    with open(TITLE_FONTS) as f:
        rows = [l.split() for l in f if l.strip() and not l.startswith("#")]
    return {int(a): (int(b), int(c)) for a, b, c in rows}


def write_file(path, text):
    """Replace a file at once, so that a failure never leaves half of it."""
    path = os.path.realpath(path)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path))
    with os.fdopen(fd, "w") as f:
        f.write(text)
    os.chmod(tmp, os.stat(path).st_mode & 0o777)
    os.replace(tmp, path)


def set_title_font(size, weight):
    """Change rc.xml and the theme together; nothing is written unless both can be changed."""
    padx, pady = title_fonts()[size]
    with open(OPENBOX) as f:
        rc_old = f.read()
    with open(THEMERC) as f:
        theme_old = f.read()
    rc, n = TITLE_RE.subn(lambda m: m[1] + str(size) + m[3] + weight, rc_old)
    theme, w = re.subn(r"(?m)^padding\.width:.*$", f"padding.width: {padx}", theme_old)
    theme, h = re.subn(r"(?m)^padding\.height:.*$", f"padding.height: {pady}", theme)
    if (n, w, h) != (2, 1, 1):
        raise ValueError("rc.xml or the window theme was edited in a way this page does not understand")
    xml.dom.minidom.parseString(rc.encode())
    write_file(THEMERC, theme)
    try:
        write_file(OPENBOX, rc)
    except OSError:
        write_file(THEMERC, theme_old)
        raise
    write_setting("TITLE_FONT_SIZE", str(size))
    write_setting("TITLE_FONT_WEIGHT", weight)
    subprocess.run(["openbox", "--reconfigure"], capture_output=True)


class WindowsPage(Gtk.Box):
    ID, TITLE, ICON = "windows", "Windows", "preferences-system-windows"

    def __init__(self, window):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=18, margin=20)
        title = Gtk.Label(label=self.TITLE, xalign=0)
        title.get_style_context().add_class("page-title")
        self.pack_start(title, False, False, 0)
        self.error = Gtk.Label(xalign=0, no_show_all=True, wrap=True)
        self.error.get_style_context().add_class("error")
        self.pack_start(self.error, False, False, 0)
        self.timer = 0
        try:
            self.sizes = sorted(title_fonts())
            with open(OPENBOX) as f:
                found = TITLE_RE.search(f.read())
            size, weight = int(found[2]), found[4].lower()
        except (OSError, ValueError, TypeError) as e:
            self.show_error(f"The titlebar settings cannot be read: {e}")
            return
        self.applied = (size, weight)

        grid = Gtk.Grid(row_spacing=18, column_spacing=30)
        self.scale = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, self.sizes[0], self.sizes[-1], 1)
        self.scale.set_draw_value(False)
        self.scale.set_size_request(320, -1)
        for s in self.sizes:
            self.scale.add_mark(s, Gtk.PositionType.BOTTOM, str(s))
        self.scale.set_value(min(max(size, self.sizes[0]), self.sizes[-1]))
        self.bold = Gtk.Switch(active=weight == "bold", halign=Gtk.Align.START)
        for row, (text, widget) in enumerate((("Titlebar font size", self.scale), ("Bold titles", self.bold))):
            label = Gtk.Label(label=text, xalign=0)
            grid.attach(label, 0, row, 1, 1)
            grid.attach(widget, 1, row, 1, 1)
        self.pack_start(grid, False, False, 0)
        hint = Gtk.Label(label="The change is applied to all windows at once. The height of titlebars stays the same.", xalign=0, wrap=True)
        hint.get_style_context().add_class("dim-label")
        self.pack_start(hint, False, False, 0)
        self.scale.connect("value-changed", self.changed)
        self.bold.connect("notify::active", self.changed)

    def show_error(self, text):
        self.error.set_text(text)
        self.error.set_visible(bool(text))

    def changed(self, *_):
        """Wait for the slider to settle instead of reloading Openbox on every step."""
        if self.timer:
            GLib.source_remove(self.timer)
        self.timer = GLib.timeout_add(350, self.apply)

    def apply(self):
        self.timer = 0
        want = (int(round(self.scale.get_value())), "bold" if self.bold.get_active() else "normal")
        if want != self.applied:
            try:
                set_title_font(*want)
                self.applied = want
                self.show_error("")
            except Exception as e:
                self.show_error(f"Not changed: {e}")
        return False


# ── icons ────────────────────────────────────────────────────
ICONS_DIR = os.path.join(GLib.get_user_data_dir(), "icons")
XSETTINGS = os.path.join(GLib.get_user_config_dir(), "xsettingsd", "xsettingsd.conf")
DUNST = os.path.join(GLib.get_user_config_dir(), "dunst", "dunstrc")
ROFI = os.path.join(GLib.get_user_config_dir(), "rofi", "config.rasi")
PREVIEW = ("folder", "user-home", "folder-download", "firefox", "telegram", "discord", "gimp", "utilities-terminal", "preferences-system")
PREVIEW_SIZE = 40


def icon_themes():
    """Icon themes in ~/.local/share/icons: directory name -> display name."""
    found = {}
    for name in os.listdir(ICONS_DIR) if os.path.isdir(ICONS_DIR) else []:
        path = os.path.join(ICONS_DIR, name)
        kf = GLib.KeyFile()
        try:
            kf.load_from_file(os.path.join(path, "index.theme"), GLib.KeyFileFlags.NONE)
            dirs = kf.get_string("Icon Theme", "Directories")
        except GLib.Error:
            continue                                    # cursors only, or not a theme
        if name == "hicolor" or name.startswith(".") or not any(k in dirs for k in ("places", "apps")):
            continue
        if re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9 ._+-]*", name):
            found[name] = name.replace("-", " ")
    return dict(sorted(found.items(), key=lambda kv: kv[1].casefold()))


def current_icon_theme():
    with open(XSETTINGS) as f:
        m = re.search(r'(?m)^Net/IconThemeName "([^"]*)"', f.read())
    return m[1] if m else ""


def set_icon_theme(name):
    with open(XSETTINGS) as f:
        text, n = re.subn(r"(?m)^Net/IconThemeName .*$", f'Net/IconThemeName "{name}"', f.read())
    if n != 1:
        raise ValueError("xsettingsd.conf has no single Net/IconThemeName line")
    write_file(XSETTINGS, text)
    for path, pattern, new in ((DUNST, r"(?m)^(\s*icon_theme = ).*$", rf'\g<1>"{name}, Yaru, hicolor"'),
                               (ROFI, r"(?m)^(\s*icon-theme: ).*$", rf'\g<1>"{name}";')):
        if os.path.exists(path):                        # notifications read theirs after the next login
            with open(path) as f:
                write_file(path, re.sub(pattern, new, f.read()))
    write_setting("ICON_THEME", name)
    subprocess.run(["pkill", "-HUP", "-x", "xsettingsd"], capture_output=True)


class IconsPage(Gtk.Box):
    ID, TITLE, ICON = "icons", "Icons", "preferences-desktop-theme"

    def __init__(self, window):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=14, margin=20)
        title = Gtk.Label(label=self.TITLE, xalign=0)
        title.get_style_context().add_class("page-title")
        self.pack_start(title, False, False, 0)
        self.error = Gtk.Label(xalign=0, no_show_all=True, wrap=True)
        self.error.get_style_context().add_class("error")
        self.pack_start(self.error, False, False, 0)
        self.list = Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE)
        self.list.connect("row-activated", self.choose)
        scroll = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
        scroll.add(self.list)
        self.pack_start(scroll, True, True, 0)
        try:
            self.current = current_icon_theme()
        except OSError as e:
            return self.show_error(f"The icon theme cannot be read: {e}")
        self.queue = []
        for name, label in icon_themes().items():
            self.add_row(name, label)
        GLib.idle_add(self.load_next)

    def show_error(self, text):
        self.error.set_text(text)
        self.error.set_visible(bool(text))

    def add_row(self, name, label):
        box = Gtk.Box(spacing=16, margin=10)
        text = Gtk.Label(label=label, xalign=0)
        text.set_size_request(190, -1)
        icons = Gtk.Box(spacing=12)
        icons.set_size_request(-1, PREVIEW_SIZE)
        row = Gtk.ListBoxRow()
        row.name, row.check = name, Gtk.Image.new_from_icon_name("object-select-symbolic", Gtk.IconSize.BUTTON)
        row.check.set_opacity(1 if name == self.current else 0)
        box.pack_start(row.check, False, False, 0)
        box.pack_start(text, False, False, 0)
        box.pack_start(icons, False, False, 0)
        row.add(box)
        self.list.add(row)
        self.queue.append((name, icons))

    def load_next(self):
        """Previews are loaded one theme at a time so the window opens at once."""
        if not self.queue:
            return False
        name, box = self.queue.pop(0)
        theme = Gtk.IconTheme.new()
        theme.set_custom_theme(name)
        for icon in PREVIEW:
            try:
                image = Gtk.Image.new_from_pixbuf(theme.load_icon(icon, PREVIEW_SIZE, Gtk.IconLookupFlags.FORCE_SIZE))
            except GLib.Error:
                image = Gtk.Image()
            image.set_size_request(PREVIEW_SIZE, PREVIEW_SIZE)
            box.pack_start(image, False, False, 0)
        box.show_all()
        return bool(self.queue)

    def choose(self, _list, row):
        try:
            set_icon_theme(row.name)
        except (OSError, ValueError) as e:
            return self.show_error(f"Not changed: {e}")
        self.show_error("")
        self.current = row.name
        for r in self.list.get_children():
            r.check.set_opacity(1 if r.name == self.current else 0)


# ── sound ────────────────────────────────────────────────────
PACTL_ENV = dict(os.environ, LC_ALL="C.UTF-8")      # otherwise its JSON may have commas in numbers
EVENT_SOUNDS = os.path.join(os.path.dirname(os.path.realpath(__file__)), "event-sounds.sh")
# variable in local.conf, default, label, details, sound to play
EVENTS = (("SOUND_POWER", "1", "Charger", "connected and disconnected", "plug"),
          ("SOUND_BATTERY", "1", "Low battery", "20, 10 and 5 % left", "battery-20"),
          ("SOUND_BLUETOOTH", "1", "Bluetooth", "device connected and disconnected", "connected"),
          ("SOUND_LOGIN", "1", "Login", "", "login"),
          ("SOUND_LOGOUT", "0", "Logout and shutdown", "the computer waits two seconds for it", "logout"))


def pactl(*args):
    r = subprocess.run(["pactl", *args], capture_output=True, text=True, env=PACTL_ENV, timeout=5)
    if r.returncode:
        raise OSError(r.stderr.strip() or "pactl failed")
    return r.stdout


def device_title(dev):
    """Built-in cards are called by what they drive, everything else by its own name."""
    props = dev.get("properties", {})
    if props.get("device.bus") == "pci" and props.get("device.profile.description"):
        return props["device.profile.description"]
    return dev.get("description") or dev["name"]


def usable(dev):
    ports = dev.get("ports") or []
    return not ports or any(p.get("availability") != "not available" for p in ports)


class DeviceSection(Gtk.Box):
    """Outputs or inputs: choice of the default device, its volume and port."""
    def __init__(self, page, kind, title, icons):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        self.page, self.kind, self.icons = page, kind, icons
        self.device, self.shown, self.busy, self.volume_id, self.hold = None, None, False, 0, 0
        label = Gtk.Label(label=title, xalign=0)
        label.get_style_context().add_class("section-title")
        self.pack_start(label, False, False, 0)

        bar = Gtk.Box(spacing=8)
        self.mute = Gtk.ToggleButton(relief=Gtk.ReliefStyle.NONE, tooltip_text="Mute")
        self.mute.set_image(Gtk.Image.new_from_icon_name(icons[0], Gtk.IconSize.BUTTON))
        self.mute.connect("toggled", self.on_mute)
        self.scale = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 0, 100, 1)
        self.scale.set_value_pos(Gtk.PositionType.RIGHT)
        self.scale.connect("format-value", lambda _s, v: f"{v:.0f} %")
        self.scale.connect("value-changed", self.on_volume)
        bar.pack_start(self.mute, False, False, 0)
        bar.pack_start(self.scale, True, True, 0)
        self.bar = bar
        self.pack_start(bar, False, False, 0)

        self.list = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        self.pack_start(self.list, False, False, 0)
        self.port_row = Gtk.Box(spacing=8, no_show_all=True)
        self.port_label = Gtk.Label(label="Port", xalign=0)
        self.port = Gtk.ComboBoxText()
        self.port.connect("changed", self.on_port)
        self.port_row.pack_start(self.port_label, False, False, 0)
        self.port_row.pack_start(self.port, False, False, 0)
        self.pack_start(self.port_row, False, False, 0)

    def refresh(self, devices, default):
        self.busy = True         # the changes below are not made by the user
        try:
            devices = [d for d in devices if not d["name"].endswith(".monitor") and (usable(d) or d["name"] == default)]
            self.device = next((d for d in devices if d["name"] == default), None)
            shown = [(d["name"], device_title(d)) for d in devices]
            if shown != self.shown:
                self.shown = shown
                self.fill(shown)
            for b in self.list.get_children():
                if isinstance(b, Gtk.RadioButton):
                    b.set_active(b.device == default)
            self.bar.set_sensitive(self.device is not None)
            self.mute.set_active(bool(self.device and self.device["mute"]))
            self.mute.get_image().set_from_icon_name(self.icons[1 if self.mute.get_active() else 0], Gtk.IconSize.BUTTON)
            if self.device and not self.volume_id and GLib.get_monotonic_time() > self.hold:
                self.scale.set_value(max(self.levels(), default=0))
            ports = [p for p in (self.device or {}).get("ports") or [] if p.get("availability") != "not available"]
            self.port.remove_all()
            for p in ports:
                self.port.append(p["name"], p["description"])
            if self.device:
                self.port.set_active_id(self.device.get("active_port"))
            for w in (self.port_row, self.port_label, self.port):
                w.set_visible(len(ports) > 1)
        finally:
            self.busy = False

    def fill(self, shown):
        for c in self.list.get_children():
            c.destroy()
        group = Gtk.RadioButton()        # never shown: lets every visible button be off
        self.hidden = group
        for name, title in shown:
            b = Gtk.RadioButton.new_with_label_from_widget(group, title)
            b.device = name
            b.get_child().set_ellipsize(Pango.EllipsizeMode.END)
            b.connect("toggled", self.on_device)
            self.list.pack_start(b, False, False, 0)
        if not shown:
            self.list.pack_start(Gtk.Label(label="Nothing is connected", xalign=0), False, False, 0)
        self.list.show_all()

    def levels(self):
        return [int(v["value_percent"].rstrip("%")) for v in self.device["volume"].values()]

    def on_device(self, button):
        if not self.busy and button.get_active():
            self.page.run(f"set-default-{self.kind}", button.device)

    def on_mute(self, button):
        if not self.busy and self.device:
            self.page.run(f"set-{self.kind}-mute", self.device["name"], "1" if button.get_active() else "0")

    def on_volume(self, _scale):
        if not self.busy and self.device and not self.volume_id:
            self.volume_id = GLib.timeout_add(40, self.send_volume)

    def send_volume(self):
        self.volume_id = 0
        if self.device:
            self.hold = GLib.get_monotonic_time() + 300000      # its own echo must not move the slider back
            old, target = self.levels(), round(self.scale.get_value())
            top = max(old, default=0)                           # the balance is kept
            new = [round(v * target / top) if top else target for v in old]
            self.page.run(f"set-{self.kind}-volume", self.device["name"], *(f"{v}%" for v in new))
        return False

    def on_port(self, combo):
        if not self.busy and self.device and combo.get_active_id():
            self.page.run(f"set-{self.kind}-port", self.device["name"], combo.get_active_id())


class SoundPage(Gtk.ScrolledWindow):
    ID, TITLE, ICON = "sound", "Sound", "preferences-desktop-sound"

    def __init__(self, window):
        super().__init__(hscrollbar_policy=Gtk.PolicyType.NEVER)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=18, margin=20)
        self.add(box)
        title = Gtk.Label(label=self.TITLE, xalign=0)
        title.get_style_context().add_class("page-title")
        box.pack_start(title, False, False, 0)
        self.error = Gtk.Label(xalign=0, no_show_all=True, wrap=True)
        self.error.get_style_context().add_class("error")
        box.pack_start(self.error, False, False, 0)

        self.output = DeviceSection(self, "sink", "Output", ("audio-volume-high-symbolic", "audio-volume-muted-symbolic"))
        self.input = DeviceSection(self, "source", "Input", ("audio-input-microphone-symbolic", "microphone-sensitivity-muted-symbolic"))
        box.pack_start(self.output, False, False, 0)
        box.pack_start(Gtk.Separator(), False, False, 0)
        box.pack_start(self.input, False, False, 0)
        box.pack_start(Gtk.Separator(), False, False, 0)
        box.pack_start(self.events(), False, False, 0)

        self.refresh_id, self.watcher, self.closed = 0, None, False
        self.connect("destroy", self.on_destroy)
        self.refresh()
        self.watch()

    def events(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        label = Gtk.Label(label="Event sounds", xalign=0)
        label.get_style_context().add_class("section-title")
        box.pack_start(label, False, False, 0)
        for name, default, text, details, sound in EVENTS:
            row = Gtk.Box(spacing=10)
            row.pack_start(Gtk.Label(label=text, xalign=0), False, False, 0)
            about = Gtk.Label(label=details, xalign=0, ellipsize=Pango.EllipsizeMode.END)
            about.get_style_context().add_class("dim-label")
            row.pack_start(about, True, True, 0)
            play = Gtk.Button.new_from_icon_name("media-playback-start-symbolic", Gtk.IconSize.BUTTON)
            play.set_relief(Gtk.ReliefStyle.NONE)
            play.set_tooltip_text("Play")
            play.connect("clicked", self.on_play, sound)
            switch = Gtk.Switch(valign=Gtk.Align.CENTER, active=read_setting(name, default) == "1")
            switch.connect("notify::active", self.on_switch, name)
            row.pack_start(play, False, False, 0)
            row.pack_start(switch, False, False, 0)
            box.pack_start(row, False, False, 0)
        return box

    def on_play(self, _b, sound):
        self.spawn([EVENT_SOUNDS, "preview", sound])

    def on_switch(self, switch, _p, name):
        try:
            write_setting(name, "1" if switch.get_active() else "0")
            self.show_error("")
        except OSError as e:
            self.show_error(f"Could not be saved: {e}")

    def show_error(self, text):
        self.error.set_text(text)
        self.error.set_visible(bool(text))

    def spawn(self, argv):
        try:
            Gio.Subprocess.new(argv, Gio.SubprocessFlags.STDOUT_SILENCE).wait_async(None, None)
        except GLib.Error as e:
            self.show_error(e.message)

    def run(self, *args):
        try:
            pactl(*args)
            self.show_error("")
        except (OSError, subprocess.TimeoutExpired) as e:
            self.show_error(str(e))
        self.schedule()

    def schedule(self):
        if not self.refresh_id:
            self.refresh_id = GLib.timeout_add(80, self.refresh)

    def refresh(self):
        self.refresh_id = 0
        try:
            for section in (self.output, self.input):
                default = pactl(f"get-default-{section.kind}").strip()
                section.refresh(json.loads(pactl("-f", "json", "list", section.kind + "s")), default)
        except (OSError, ValueError, subprocess.TimeoutExpired) as e:
            self.show_error(f"No connection to the sound server: {e}")
        return False

    def watch(self):
        """Follow changes made elsewhere; pactl exits when the sound server restarts."""
        if self.closed:
            return False
        launcher = Gio.SubprocessLauncher.new(Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_SILENCE)
        launcher.setenv("LC_ALL", "C", True)
        try:
            self.watcher = launcher.spawnv(["pactl", "subscribe"])
        except GLib.Error as e:
            self.show_error(e.message)
            return False
        stream = Gio.DataInputStream.new(self.watcher.get_stdout_pipe())
        stream.read_line_async(GLib.PRIORITY_DEFAULT, None, self.on_event)
        return False

    def on_event(self, stream, result):
        try:
            line = stream.read_line_finish_utf8(result)[0]
        except GLib.Error:
            line = None
        if self.closed:
            return
        if line is None:
            GLib.timeout_add_seconds(2, self.watch)
            self.schedule()
            return
        if re.search(r" on (sink|source|card|server)\b(?!-)", line):
            self.schedule()
        stream.read_line_async(GLib.PRIORITY_DEFAULT, None, self.on_event)

    def on_destroy(self, _w):
        self.closed = True
        for i in (self.refresh_id, self.output.volume_id, self.input.volume_id):
            if i:
                GLib.source_remove(i)
        if self.watcher:
            self.watcher.force_exit()


PAGES = [WallpaperPage, IconsPage, WindowsPage, SoundPage]


# ── window ───────────────────────────────────────────────────
class Window(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Mini DE Settings", icon_name="preferences-desktop",
                         default_width=1040, default_height=640)
        self.stack = Gtk.Stack(transition_type=Gtk.StackTransitionType.CROSSFADE)
        self.side = Gtk.ListBox(selection_mode=Gtk.SelectionMode.BROWSE)
        self.side.set_size_request(190, -1)
        self.rows = {}
        self.side.connect("row-selected", lambda _l, row: row and self.stack.set_visible_child_name(row.page))
        for page in PAGES:
            self.stack.add_named(page(self), page.ID)
            box = Gtk.Box(spacing=10, margin=10)
            box.pack_start(Gtk.Image.new_from_icon_name(page.ICON, Gtk.IconSize.LARGE_TOOLBAR), False, False, 0)
            box.pack_start(Gtk.Label(label=page.TITLE, xalign=0), True, True, 0)
            row = Gtk.ListBoxRow()
            row.page = page.ID
            row.add(box)
            self.side.add(row)
            self.rows[page.ID] = row
        root = Gtk.Box()
        root.pack_start(self.side, False, False, 0)
        root.pack_start(Gtk.Separator(orientation=Gtk.Orientation.VERTICAL), False, False, 0)
        root.pack_start(self.stack, True, True, 0)
        self.add(root)
        self.show_all()
        self.show_page(PAGES[0].ID)

    def show_page(self, page):
        if page in self.rows:
            self.side.select_row(self.rows[page])


class Program(Gtk.Application):
    def __init__(self):
        super().__init__(application_id="local.minide.Settings",
                         flags=Gio.ApplicationFlags.HANDLES_COMMAND_LINE)

    def do_startup(self):
        Gtk.Application.do_startup(self)
        css = Gtk.CssProvider()
        css.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), css, 600)

    def do_command_line(self, line):
        window = self.get_active_window() or Window(self)
        for page in line.get_arguments()[1:2]:
            window.show_page(page)
        window.present()
        return 0


GLib.set_prgname("mini-de-settings")
Gdk.set_program_class("mini-de-settings")
sys.exit(Program().run(sys.argv))
