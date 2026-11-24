#!/usr/bin/python3
"""mini-de settings. Every page is a class with ID, TITLE and ICON added to PAGES."""
import os, re, shlex, shutil, subprocess, sys, tempfile, xml.dom.minidom
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


PAGES = [WallpaperPage, IconsPage, WindowsPage]


# ── window ───────────────────────────────────────────────────
class Window(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="mini-de settings", icon_name="preferences-desktop",
                         default_width=1040, default_height=640)
        self.stack = Gtk.Stack(transition_type=Gtk.StackTransitionType.CROSSFADE)
        self.side = Gtk.ListBox(selection_mode=Gtk.SelectionMode.BROWSE)
        self.side.set_size_request(190, -1)
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
        root = Gtk.Box()
        root.pack_start(self.side, False, False, 0)
        root.pack_start(Gtk.Separator(orientation=Gtk.Orientation.VERTICAL), False, False, 0)
        root.pack_start(self.stack, True, True, 0)
        self.add(root)
        self.show_all()
        self.side.select_row(self.side.get_row_at_index(0))


class Program(Gtk.Application):
    def __init__(self):
        super().__init__(application_id="local.minide.Settings")

    def do_startup(self):
        Gtk.Application.do_startup(self)
        css = Gtk.CssProvider()
        css.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), css, 600)

    def do_activate(self):
        (self.get_active_window() or Window(self)).present()


GLib.set_prgname("mini-de-settings")
Gdk.set_program_class("mini-de-settings")
sys.exit(Program().run(sys.argv))
