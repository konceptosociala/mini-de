#!/usr/bin/python3
"""Full-screen launcher with the app folders from GNOME and a .hidden folder (Ctrl+H).
  launcher.py                         show / hide
  launcher.py --gapplication-service  stay in the background (autostart)"""
import ctypes as C
import math, os, sys, uuid
import cairo
import gi
gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
gi.require_version("GdkX11", "3.0")
from gi.repository import Gtk, Gdk, GdkX11, Gio, GLib, Pango

# ── Appearance ──────────────────────────────────────────────
ICON = 84            # app icon
MINI = 28            # icon inside a folder tile (3x3)
CELL_W, CELL_H = 172, 180
ZOOM = 1.16          # how much an icon grows under the pointer
PRESS = 0.92         # and shrinks when pressed
ANIM_MS = 160        # animation duration
TAP_MS = 600         # a Super press longer than this is not a tap
MAX_COLS = 9         # columns in the main grid
FOLDER_COLS = 6      # columns in an open folder
# Default colors; ~/.config/mini-de/colors.css overrides them
CSS = """
@define-color md_surface #1d2021;
@define-color md_panel #282828;
@define-color md_border #504945;
@define-color md_raised #3c3836;
@define-color md_fg #ebdbb2;
@define-color md_dim #928374;
@define-color md_accent #fabd2f;
@define-color md_accent_text #fabd2f;
@define-color md_on_accent #1d2021;
@define-color md_tile #504945;
#launcher { background: alpha(@md_surface, 0.90); }
#launcher.opaque { background: @md_surface; }
#launcher scrolledwindow, #launcher viewport, #launcher flowbox { background: transparent; border: none; }
#search { font: 18px "Inter"; color: @md_fg; background: @md_raised; caret-color: @md_accent;
          border: 2px solid @md_border; border-radius: 24px; padding: 8px 18px; box-shadow: none; }
#search:focus { border-color: @md_accent; }
#launcher flowboxchild { border-radius: 14px; padding: 0; background: transparent; outline: none;
                         transition: background 160ms ease-out; }
#launcher flowboxchild.hover { background: alpha(@md_fg, 0.10); }
#launcher flowboxchild:selected { background: alpha(@md_accent, 0.22); }
#launcher label { color: @md_fg; font: 14px "Inter"; }
#eye { color: @md_dim; background: transparent; border: none; box-shadow: none; border-radius: 24px; padding: 10px; }
#eye:hover { color: @md_fg; background: alpha(@md_fg, 0.10); }
#dim { background: rgba(0,0,0,0.55); }
#launcher menu { background: @md_panel; border: 1px solid @md_border; padding: 4px; }
#launcher menuitem { padding: 6px 12px; }
#launcher menuitem:hover { background: alpha(@md_accent, 0.35); }
#panel { background: @md_panel; border: 2px solid @md_border; border-radius: 20px; }
#launcher #title { font: 700 22px "Inter"; color: @md_accent_text; }
#launcher #empty { font: 18px "Inter"; color: @md_dim; }
"""
FOLDERS = "org.gnome.desktop.app-folders"
HIDDEN = ".hidden"      # id and name of the special folder
HIDDEN_FILE = os.path.join(GLib.get_user_config_dir(), "mini-de", "hidden-apps")   # one .desktop id per line
USER_CSS = os.path.join(GLib.get_user_config_dir(), "mini-de", "colors.css")   # theme variant
PLANK_DIR = os.path.join(GLib.get_user_config_dir(), "plank", "dock1", "launchers")
FOLDER_PATH = "/org/gnome/desktop/app-folders/folders/%s/"


def folder_name(s):
    name = s.get_string("name")
    if s.get_boolean("translate"):
        kf = GLib.KeyFile()
        try:
            kf.load_from_data_dirs("desktop-directories/" + name, GLib.KeyFileFlags.NONE)
            return kf.get_locale_string("Desktop Entry", "Name", None)
        except GLib.Error:
            return name.removesuffix(".directory").removeprefix("X-").replace("GNOME-", "")
    return name


class App:
    def __init__(self, info):
        self.info, self.id, self.name = info, info.get_id(), info.get_display_name()
        self.path = os.path.realpath(info.get_filename() or "")
        self.cats = set((info.get_categories() or "").split(";")) - {""}
        self.words = " ".join([self.name, info.get_generic_name() or "", info.get_executable() or "",
                               " ".join(info.get_keywords())]).casefold()
        self.pix = {}

    def icon(self, size):
        if size not in self.pix:
            theme, pb = Gtk.IconTheme.get_default(), None
            for g in (self.info.get_icon(), Gio.ThemedIcon.new("application-x-executable")):
                ii = theme.lookup_by_gicon(g, size, Gtk.IconLookupFlags.FORCE_SIZE) if g else None
                try:
                    pb = ii.load_icon() if ii else None
                except GLib.Error:
                    pb = None
                if pb:
                    break
            self.pix[size] = pb
        return self.pix[size]


class Folder:
    def __init__(self, name, apps, fid):
        self.name, self.apps, self.fid = name, apps, fid


def pinned_files():
    """Paths of the .desktop files pinned in Plank."""
    out = set()
    try:
        names = os.listdir(PLANK_DIR)
    except OSError:
        return out
    for n in names:
        kf = GLib.KeyFile()
        try:
            kf.load_from_file(os.path.join(PLANK_DIR, n), GLib.KeyFileFlags.NONE)
            uri = kf.get_string("PlankDockItemPreferences", "Launcher")
            out.add(os.path.realpath(GLib.filename_from_uri(uri)[0]))
        except GLib.Error:
            pass
    return out


def plank(method, info):
    """Add / Remove in the running Plank."""
    uri = GLib.filename_to_uri(info.get_filename(), None)
    Gio.bus_get_sync(Gio.BusType.SESSION).call(
        "net.launchpad.plank", "/net/launchpad/plank/dock1", "net.launchpad.plank.Items", method,
        GLib.Variant("(s)", (uri,)), None, Gio.DBusCallFlags.NO_AUTO_START, 3000, None, None)


def load_apps():
    return sorted((App(a) for a in Gio.AppInfo.get_all()
                   if isinstance(a, Gio.DesktopAppInfo) and a.should_show()),
                  key=lambda a: a.name.casefold())


def read_hidden():
    try:
        with open(HIDDEN_FILE) as f:
            return {l.strip() for l in f if l.strip()}
    except OSError:
        return set()


def set_hidden(app, hide):
    """Hide the app or show it again; its GNOME folder is remembered by GNOME itself."""
    ids = read_hidden()
    (ids.add if hide else ids.discard)(app.id)
    os.makedirs(os.path.dirname(HIDDEN_FILE), exist_ok=True)
    tmp = HIDDEN_FILE + ".new"
    with open(tmp, "w") as f:
        f.writelines(i + "\n" for i in sorted(ids))
    os.replace(tmp, HIDDEN_FILE)


def group(apps, pinned, hidden=frozenset()):
    """Sort into GNOME folders; hidden apps and apps pinned to the dock are left out of the grid."""
    shown = [a for a in apps if a.path not in pinned and a.id not in hidden]
    by_id, folders, used = {a.id: a for a in shown}, [], set()
    src = Gio.SettingsSchemaSource.get_default()
    if src.lookup(FOLDERS, True) and src.lookup(FOLDERS + ".folder", True):
        for fid in Gio.Settings.new(FOLDERS).get_strv("folder-children"):
            s = Gio.Settings.new_with_path(FOLDERS + ".folder", FOLDER_PATH % fid)
            skip, cats = set(s.get_strv("excluded-apps")), set(s.get_strv("categories"))
            found = [by_id[i] for i in dict.fromkeys(s.get_strv("apps")) if i in by_id and i not in skip]
            found += [a for a in shown if a.cats & cats and a.id not in skip and a not in found]
            found = [a for a in found if a.id not in used]
            if found:
                used |= {a.id for a in found}
                folders.append(Folder(folder_name(s), found, fid))
    folders.sort(key=lambda f: f.name.casefold())
    return folders, [a for a in shown if a.id not in used]


# ── editing folders: the same settings GNOME uses, so both see every change ──
def folder_settings(fid):
    return Gio.Settings.new_with_path(FOLDERS + ".folder", FOLDER_PATH % fid)


def set_folder(app, target):
    """Put the app into the folder with this id, or into no folder (None)."""
    if app.id in read_hidden():
        set_hidden(app, False)
    root = Gio.Settings.new(FOLDERS)
    children = root.get_strv("folder-children")
    for fid in children:
        s = folder_settings(fid)
        apps, skip = s.get_strv("apps"), s.get_strv("excluded-apps")
        by_category = bool(app.cats & set(s.get_strv("categories")))
        if fid == target:
            new_apps = apps if app.id in apps else apps + [app.id]
            new_skip = [i for i in skip if i != app.id]
        else:
            new_apps = [i for i in apps if i != app.id]
            new_skip = skip + [app.id] if by_category and app.id not in skip else skip
        if new_apps != apps:
            s.set_strv("apps", new_apps)
        if new_skip != skip:
            s.set_strv("excluded-apps", new_skip)
        if fid != target and apps and not new_apps and not s.get_strv("categories"):
            drop_folder(fid)                  # like in GNOME, an empty folder goes away
    Gio.Settings.sync()


def drop_folder(fid):
    """Remove the folder; its apps return to the grid."""
    root, s = Gio.Settings.new(FOLDERS), folder_settings(fid)
    root.set_strv("folder-children", [i for i in root.get_strv("folder-children") if i != fid])
    for key in ("name", "translate", "apps", "excluded-apps", "categories"):
        s.reset(key)
    Gio.Settings.sync()


def new_folder(name, apps):
    root, fid = Gio.Settings.new(FOLDERS), str(uuid.uuid4())
    s = folder_settings(fid)
    s.set_string("name", name)
    s.set_boolean("translate", False)
    root.set_strv("folder-children", root.get_strv("folder-children") + [fid])
    for a in apps:
        set_folder(a, fid)
    Gio.Settings.sync()


def rename_folder(fid, name):
    s = folder_settings(fid)
    s.set_string("name", name)
    s.set_boolean("translate", False)
    Gio.Settings.sync()


TARGETS = [Gtk.TargetEntry.new("application/x-mini-de-app", Gtk.TargetFlags.SAME_APP, 0)]


class Art(Gtk.DrawingArea):
    """App icon or folder tile with a smooth zoom."""
    AREA = int((ICON + 16) * ZOOM) + 4

    def __init__(self, item):
        super().__init__(halign=Gtk.Align.CENTER)
        self.item, self.scale, self.goal, self.tick = item, 1.0, 1.0, 0
        self.set_size_request(self.AREA, self.AREA)
        self.connect("draw", self.on_draw)

    def to(self, goal):
        if goal == self.goal:
            return
        self.goal = goal
        if not self.get_mapped() or not Gtk.Settings.get_default().get_property("gtk-enable-animations"):
            if self.tick:
                self.remove_tick_callback(self.tick)
                self.tick = 0
            self.scale = goal
            return self.queue_draw()
        self.start, self.t0 = self.scale, None
        if not self.tick:
            self.tick = self.add_tick_callback(self.on_tick)

    def on_tick(self, _w, clock):
        now = clock.get_frame_time()
        if self.t0 is None:
            self.t0 = now
        t = min(1.0, (now - self.t0) / (ANIM_MS * 1000))
        self.scale = self.start + (self.goal - self.start) * (1 - (1 - t) ** 3)
        self.queue_draw()
        if t >= 1.0:
            self.tick = 0
            return False
        return True

    def paint(self, cr, app, x, y, size):
        # crisp at rest, drawn from a larger image while animating
        pb = app.icon(size if self.scale == 1.0 else size * 2)
        if not pb:
            return
        w, h = pb.get_width(), pb.get_height()
        k = size / max(w, h)
        cr.save()
        cr.translate(x + (size - w * k) / 2, y + (size - h * k) / 2)
        cr.scale(k, k)
        Gdk.cairo_set_source_pixbuf(cr, pb, 0, 0)
        cr.get_source().set_filter(cairo.FILTER_GOOD)
        cr.paint()
        cr.restore()

    def on_draw(self, _w, cr):
        c = self.AREA / 2
        cr.translate(c, c)
        cr.scale(self.scale, self.scale)
        if isinstance(self.item, Folder):
            side, rad = ICON + 16, 18
            o = -side / 2
            cr.new_sub_path()
            for i, (cx, cy) in enumerate(((1, -1), (1, 1), (-1, 1), (-1, -1))):
                cr.arc(cx * (side / 2 - rad), cy * (side / 2 - rad), rad,
                       (i - 1) * math.pi / 2, i * math.pi / 2)
            cr.close_path()
            glow = (self.scale - 1) / (ZOOM - 1) if self.scale > 1 else 0
            _, tile = self.get_style_context().lookup_color("md_tile")
            cr.set_source_rgba(tile.red + .10 * glow, tile.green + .09 * glow, tile.blue + .08 * glow, 0.75 + .15 * glow)
            cr.fill()
            step, pad = MINI + 3, (side - 3 * MINI - 6) / 2
            for i, a in enumerate(self.item.apps[:9]):
                self.paint(cr, a, round(o + pad) + (i % 3) * step, round(o + pad) + (i // 3) * step, MINI)
        else:
            self.paint(cr, self.item, -ICON / 2, -ICON / 2, ICON)
        return False


class Cell(Gtk.FlowBoxChild):
    def __init__(self, item, owner=None):
        super().__init__(can_focus=False)
        self.owner = owner                    # the launcher, when dragging is possible here
        self.item, self.hover, self.pressed = item, False, False
        self.set_size_request(CELL_W, CELL_H)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2, margin=6)
        self.art = Art(item)
        label = Gtk.Label(label=item.name, justify=Gtk.Justification.CENTER, wrap=True, lines=2,
                          ellipsize=Pango.EllipsizeMode.END, max_width_chars=14,
                          wrap_mode=Pango.WrapMode.WORD_CHAR, valign=Gtk.Align.START)
        box.pack_start(self.art, False, False, 0)
        box.pack_start(label, False, False, 0)
        ev = Gtk.EventBox(visible_window=False, above_child=True)
        ev.add_events(Gdk.EventMask.ENTER_NOTIFY_MASK | Gdk.EventMask.LEAVE_NOTIFY_MASK
                      | Gdk.EventMask.BUTTON_PRESS_MASK | Gdk.EventMask.BUTTON_RELEASE_MASK)
        ev.connect("enter-notify-event", self.on_cross, True)
        ev.connect("leave-notify-event", self.on_cross, False)
        ev.connect("button-press-event", self.on_button, True)
        ev.connect("button-release-event", self.on_button, False)
        self.connect("state-flags-changed", lambda *_: self.update())
        ev.add(box)
        self.add(ev)
        if owner:
            if isinstance(item, App):
                ev.drag_source_set(Gdk.ModifierType.BUTTON1_MASK, TARGETS, Gdk.DragAction.MOVE)
                ev.connect("drag-begin", self.on_drag_begin)
                ev.connect("drag-data-get", lambda _w, _c, data, *_: data.set(data.get_target(), 8, b"app"))
                ev.connect("drag-end", lambda *_: owner.drag_ended())
            ev.drag_dest_set(0, TARGETS, Gdk.DragAction.MOVE)
            ev.connect("drag-motion", self.on_drag_motion)
            ev.connect("drag-leave", lambda *_: self.reset())
            ev.connect("drag-drop", self.on_drag_drop)

    def on_drag_begin(self, _w, ctx):
        self.reset()
        pb = self.item.icon(ICON)
        if pb:
            Gtk.drag_set_icon_pixbuf(ctx, pb, pb.get_width() // 2, pb.get_height() // 2)
        self.owner.dragged = self.item

    def on_drag_motion(self, _w, ctx, _x, _y, time):
        ok = self.owner.can_drop(self.item)
        self.hover = ok
        self.update()
        Gdk.drag_status(ctx, Gdk.DragAction.MOVE if ok else 0, time)
        return True                           # nothing behind this cell gets the drop

    def on_drag_drop(self, _w, ctx, _x, _y, time):
        ok = self.owner.can_drop(self.item)
        Gtk.drag_finish(ctx, ok, False, time)
        self.reset()
        if ok:
            self.owner.dropped(self.item)
        return True

    def on_cross(self, _w, e, inside):
        if e.detail != Gdk.NotifyType.INFERIOR:
            self.hover = inside
            self.pressed = self.pressed and inside
            self.update()
        return False

    def on_button(self, _w, e, down):
        if e.button == 1:
            self.pressed = down
            self.update()
        return False

    def update(self):
        ctx = self.get_style_context()
        (ctx.add_class if self.hover else ctx.remove_class)("hover")
        self.art.to(PRESS if self.pressed else ZOOM if self.hover or self.is_selected() else 1.0)

    def reset(self):
        self.hover = self.pressed = False
        self.update()


class Grid(Gtk.ScrolledWindow):
    """Scrollable grid, the selection is managed by Launcher."""
    def __init__(self, on_pick, owner=None):
        super().__init__(hscrollbar_policy=Gtk.PolicyType.NEVER)
        self.flow = Gtk.FlowBox(homogeneous=True, halign=Gtk.Align.CENTER, valign=Gtk.Align.START,
                                row_spacing=10, column_spacing=10, can_focus=False)
        self.flow.connect("child-activated", lambda _f, c: on_pick(c.item))
        self.add(self.flow)
        self.cols, self.owner = 1, owner

    def fill(self, items, cols):
        for c in self.flow.get_children():
            c.destroy()
        self.cols = max(1, cols)
        self.flow.set_max_children_per_line(self.cols)
        self.flow.set_min_children_per_line(self.cols)
        for it in items:
            self.flow.add(Cell(it, self.owner))
        self.flow.show_all()
        self.get_vadjustment().set_value(0)

    def reset(self):
        self.flow.unselect_all()
        for c in self.flow.get_children():
            c.reset()

    def selected(self):
        s = self.flow.get_selected_children()
        return s[0] if s else None

    def select(self, i):
        c = self.flow.get_child_at_index(i)
        if not c:
            return
        self.flow.select_child(c)
        al, adj = c.get_allocation(), self.get_vadjustment()
        adj.clamp_page(al.y, al.y + al.height)

    def move(self, dx, dy):
        n, cur = len(self.flow.get_children()), self.selected()
        if n == 0:
            return
        if cur is None:
            return self.select(0)
        i = cur.get_index() + dx + dy * self.cols
        if dy > 0 and i >= n and cur.get_index() // self.cols < (n - 1) // self.cols:
            i = n - 1
        if 0 <= i < n:
            self.select(i)


class Launcher(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, name="launcher", title="Applications", decorated=False,
                         skip_taskbar_hint=True, skip_pager_hint=True)
        self.set_keep_above(True)
        screen = self.get_screen()
        vis = screen.get_rgba_visual()
        if vis and screen.is_composited():
            self.set_visual(vis)
        else:
            self.get_style_context().add_class("opaque")

        self.search = Gtk.Entry(name="search", placeholder_text="Search…", halign=Gtk.Align.CENTER)
        self.search.set_size_request(460, -1)
        self.search.set_icon_from_icon_name(Gtk.EntryIconPosition.PRIMARY, "edit-find-symbolic")
        self.search.connect("changed", self.on_search)
        self.dragged, self.opened, self.dialog, self.show_hidden = None, None, None, False
        self.main, self.found = Grid(self.pick, self), Grid(self.pick)
        self.empty = Gtk.Label(label="Nothing found", name="empty")
        self.stack = Gtk.Stack()
        for n, w in (("main", self.main), ("found", self.found), ("empty", self.empty)):
            self.stack.add_named(w, n)
        page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=36,
                       margin_top=56, margin_bottom=40, margin_start=40, margin_end=40)
        page.pack_start(self.search, False, False, 0)
        page.pack_start(self.stack, True, True, 0)

        self.title = Gtk.Label(name="title")
        self.inside = Grid(self.pick, self)
        self.inside.set_propagate_natural_height(True)
        self.inside.set_propagate_natural_width(True)
        col = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=18, margin=26)
        col.pack_start(self.title, False, False, 0)
        col.pack_start(self.inside, True, True, 0)
        self.panel = Gtk.EventBox(name="panel", halign=Gtk.Align.CENTER, valign=Gtk.Align.CENTER)
        self.panel.add(col)
        self.dim = Gtk.EventBox(name="dim")
        self.dim.add(self.panel)
        # dropping an app outside the open folder takes it out; the panel itself accepts nothing
        for w, out in ((self.dim, True), (self.panel, False)):
            w.drag_dest_set(0, TARGETS, Gdk.DragAction.MOVE)
            w.connect("drag-motion", self.on_outside_motion, out)
            w.connect("drag-drop", self.on_outside_drop, out)

        self.eye = Gtk.Button(name="eye", relief=Gtk.ReliefStyle.NONE, can_focus=False, halign=Gtk.Align.END,
                              valign=Gtk.Align.START, margin=56, tooltip_text="Show or hide the .hidden folder (Ctrl+H)")
        self.eye.add(Gtk.Image())
        self.eye.connect("clicked", lambda *_: self.set_show_hidden(not self.show_hidden))
        over = Gtk.Overlay()
        over.add(page)
        over.add_overlay(self.eye)
        over.add_overlay(self.dim)
        self.add(over)
        over.show_all()
        self.dim.hide()

        self.add_events(Gdk.EventMask.BUTTON_PRESS_MASK | Gdk.EventMask.BUTTON_RELEASE_MASK)
        self.blank = None
        self.connect("button-press-event", self.on_press)
        self.connect("key-press-event", self.on_key)
        self.connect("button-release-event", self.on_click)
        self.connect("focus-in-event", self.on_focus, True)
        self.connect("focus-out-event", self.on_focus, False)
        self.connect("delete-event", lambda *_: self.close_all() or True)
        self.had_focus, self.width = False, 1920
        _, keys = Gdk.Keymap.get_for_display(Gdk.Display.get_default()).get_entries_for_keyval(Gdk.KEY_h)
        self.key_h = keys[0].keycode if keys else 0
        self.dirty, self.reload_id, self.regroup_id = True, 0, 0
        self.geo, self.menu = Gdk.Rectangle(), None
        self.reload()

    # ── data ──
    def reload(self):
        self.reload_id = 0
        self.apps = load_apps()
        for a in self.apps:          # warm up the icons
            a.icon(ICON)
        return self.regroup()

    def regroup(self):
        """Rebuild the grid (dock or folders changed) without rereading icons."""
        self.regroup_id = 0
        self.pinned = pinned_files()
        self.hidden = read_hidden()
        self.folders, self.rest = group(self.apps, self.pinned, self.hidden)
        self.hidden_folder = Folder(HIDDEN, [a for a in self.apps if a.id in self.hidden], HIDDEN)
        pos = self.main.get_vadjustment().get_value()
        opened = self.opened if self.dim.get_visible() else None
        self.refill()
        GLib.idle_add(lambda: self.main.get_vadjustment().set_value(pos) and False)
        f = next((f for f in [*self.folders, self.hidden_folder] if f.fid == opened and f.apps), None)
        if f:
            self.open_folder(f)
        return False

    def schedule_regroup(self, *_):
        if not self.regroup_id:
            self.regroup_id = GLib.timeout_add(150, self.regroup)

    def schedule_reload(self, *_):
        if not self.reload_id:
            self.reload_id = GLib.timeout_add(800, self.reload)

    def columns(self):
        return max(1, min(MAX_COLS, (self.width - 120) // (CELL_W + 26)))

    def refill(self):
        self.main.fill(self.folders + self.rest + ([self.hidden_folder] if self.show_hidden else []), self.columns())
        self.eye.get_child().set_from_icon_name("view-reveal-symbolic" if self.show_hidden else "view-conceal-symbolic",
                                                Gtk.IconSize.LARGE_TOOLBAR)
        self.dirty = False
        self.close_folder()
        self.on_search()

    def set_show_hidden(self, show):
        self.show_hidden = show
        self.refill()
        if show:                                  # the tile is the last one: bring it into view
            GLib.idle_add(lambda: self.main.get_vadjustment().set_value(1e6) and False)

    # ── showing ──
    def toggle(self):
        self.close_all() if self.get_visible() else self.open()

    def open(self):
        self.get_application().load_user_css()
        disp = Gdk.Display.get_default()
        _, x, y = disp.get_default_seat().get_pointer().get_position()
        mon = disp.get_monitor_at_point(x, y)
        n = next(i for i in range(disp.get_n_monitors()) if disp.get_monitor(i) == mon)
        g = mon.get_geometry()
        if g.width != self.width or self.dirty or self.show_hidden:
            self.width, self.show_hidden = g.width, False      # hidden apps are hidden again every time
            self.refill()
        self.geo = g
        self.search.set_text("")
        self.main.reset()
        self.main.get_vadjustment().set_value(0)
        self.had_focus = False
        self.fullscreen_on_monitor(self.get_screen(), n)
        self.show()
        self.present_with_time(GdkX11.x11_get_server_time(self.get_window()))
        self.search.grab_focus()

    def close_all(self):
        self.close_folder()
        self.hide()

    def open_folder(self, f):
        self.opened = f.fid
        self.title.set_text(f.name)
        self.inside.fill(f.apps, max(1, min(FOLDER_COLS, self.columns(), len(f.apps))))
        self.inside.set_max_content_height(int(self.geo.height * 0.65))
        self.dim.show()

    def close_folder(self):
        self.dim.hide()

    # ── folders ──
    def folder_of(self, app):
        return next((f for f in self.folders if app in f.apps), None)

    def can_drop(self, item):
        if self.dragged is None or item is self.dragged or self.dim.get_visible():
            return False
        return isinstance(item, (App, Folder))

    def dropped(self, item):
        app = self.dragged
        if item is self.hidden_folder:
            self.change(set_hidden, app, True)
        elif isinstance(item, Folder):
            self.change(set_folder, app, item.fid)
        else:
            GLib.idle_add(self.create_folder, [item, app])      # after the drag has ended

    def on_outside_motion(self, _w, ctx, _x, _y, time, out):
        Gdk.drag_status(ctx, Gdk.DragAction.MOVE if out and self.dragged else 0, time)
        return True

    def on_outside_drop(self, _w, ctx, _x, _y, time, out):
        app = self.dragged
        Gtk.drag_finish(ctx, bool(out and app), False, time)
        if out and app:
            self.change(*((set_hidden, app, False) if self.opened == HIDDEN else (set_folder, app, None)))
        return True

    def drag_ended(self):
        self.dragged = None

    def change(self, what, *args):
        """Edit the folders and show the result at once."""
        try:
            what(*args)
        except (GLib.Error, OSError) as e:
            n = Gio.Notification.new("The folder was not changed")
            n.set_body(getattr(e, "message", None) or str(e))
            self.get_application().send_notification(None, n)
        self.regroup()

    def ask_name(self, title, text=""):
        self.dialog = Gtk.Dialog(title=title, transient_for=self, modal=True, resizable=False)
        self.dialog.add_buttons("Cancel", Gtk.ResponseType.CANCEL, "OK", Gtk.ResponseType.OK)
        self.dialog.set_default_response(Gtk.ResponseType.OK)
        entry = Gtk.Entry(text=text, activates_default=True, width_chars=28, margin=16)
        self.dialog.get_content_area().add(entry)
        self.dialog.show_all()
        entry.grab_focus()
        ok = self.dialog.run() == Gtk.ResponseType.OK
        name = entry.get_text().strip()
        self.dialog.destroy()
        self.dialog = None
        self.present_with_time(GdkX11.x11_get_server_time(self.get_window()))
        return name if ok and name else None

    def unhide_all(self):
        for a in self.hidden_folder.apps:
            set_hidden(a, False)
        self.regroup()

    def create_folder(self, apps):
        name = self.ask_name("New folder", "New folder")
        if name:
            self.change(new_folder, name, apps)
        return False

    def rename(self, folder):
        name = self.ask_name("Rename folder", folder.name)
        if name and name != folder.name:
            self.change(rename_folder, folder.fid, name)

    # ── actions ──
    def pick(self, item):
        if isinstance(item, Folder):
            return self.open_folder(item) if item.apps else None
        self.close_all()
        ctx = Gdk.Display.get_default().get_app_launch_context()
        ctx.set_timestamp(Gtk.get_current_event_time())
        try:
            item.info.launch([], ctx)
        except GLib.Error as e:
            n = Gio.Notification.new("Could not launch " + item.name)
            n.set_body(e.message)
            self.get_application().send_notification(None, n)

    def on_search(self, *_):
        q = self.search.get_text().strip().casefold()
        if not q:
            return self.stack.set_visible_child_name("main")
        self.close_folder()
        parts = q.split()

        def rank(a):
            n = a.name.casefold()
            return (0 if n.startswith(q) else 1 if any(w.startswith(q) for w in n.split())
                    else 2 if q in n else 3, n)
        hits = sorted((a for a in self.apps if (self.show_hidden or a.id not in self.hidden)
                       and all(p in a.words for p in parts)), key=rank)
        hits = [f for f in self.folders if q in f.name.casefold()] + hits
        if len(q) > 1 and HIDDEN.startswith(q) and self.hidden_folder.apps:
            hits.insert(0, self.hidden_folder)
        self.found.fill(hits, self.columns())
        self.stack.set_visible_child_name("found" if hits else "empty")
        self.found.select(next((i for i, h in enumerate(hits) if isinstance(h, App)), 0))

    def current(self):
        if self.dim.get_visible():
            return self.inside
        return self.found if self.stack.get_visible_child_name() == "found" else self.main

    def on_key(self, _w, e):
        k, g = e.keyval, self.current()
        if k == Gdk.KEY_Escape:
            if self.dim.get_visible():
                self.close_folder()
            elif self.search.get_text():
                self.search.set_text("")
            else:
                self.close_all()
            return True
        if e.state & Gdk.ModifierType.CONTROL_MASK and e.hardware_keycode == self.key_h:      # in any layout
            self.set_show_hidden(not self.show_hidden)
            return True
        arrows = {Gdk.KEY_Left: (-1, 0), Gdk.KEY_Right: (1, 0), Gdk.KEY_Up: (0, -1), Gdk.KEY_Down: (0, 1)}
        if k in arrows:
            g.move(*arrows[k])
            return True
        if k in (Gdk.KEY_Tab, Gdk.KEY_ISO_Left_Tab):
            g.move(-1 if k == Gdk.KEY_ISO_Left_Tab else 1, 0)
            return True
        if k in (Gdk.KEY_Page_Up, Gdk.KEY_Page_Down):
            adj = g.get_vadjustment()
            adj.set_value(adj.get_value() + (1 if k == Gdk.KEY_Page_Down else -1) * adj.get_page_size())
            return True
        if k in (Gdk.KEY_Return, Gdk.KEY_KP_Enter):
            c = g.selected()
            if c:
                self.pick(c.item)
            return True
        if not self.search.has_focus():
            self.search.grab_focus_without_selecting()
        return False

    def cell_at(self, e):
        w = Gtk.get_event_widget(e)
        while w and not isinstance(w, Cell):
            w = w.get_parent()
        return w

    def popup(self, cell, e):
        self.menu = Gtk.Menu()

        def add(menu, label, action=None, *args):
            it = Gtk.MenuItem(label=label)
            if action:
                it.connect("activate", lambda *_: action(*args))
            menu.append(it)
            return it
        if cell.item is self.hidden_folder:
            if not cell.item.apps:
                return
            add(self.menu, "Show all apps again", self.unhide_all)
        elif isinstance(cell.item, Folder):
            add(self.menu, "Rename…", self.rename, cell.item)
            add(self.menu, "Remove folder", self.change, drop_folder, cell.item.fid)
        else:
            app, here = cell.item, self.folder_of(cell.item)
            pinned = app.path in self.pinned
            add(self.menu, "Unpin from dock" if pinned else "Pin to dock", self.on_pin, "Remove" if pinned else "Add", app)
            self.menu.append(Gtk.SeparatorMenuItem())
            sub = Gtk.Menu()
            for f in self.folders:
                if f is not here:
                    add(sub, f.name, self.change, set_folder, app, f.fid)
            if sub.get_children():
                sub.append(Gtk.SeparatorMenuItem())
            add(sub, "New folder…", self.create_folder, [app])
            add(self.menu, "Move to folder").set_submenu(sub)
            if here:
                add(self.menu, "Remove from folder", self.change, set_folder, app, None)
            self.menu.append(Gtk.SeparatorMenuItem())
            if app.id in self.hidden:
                add(self.menu, "Unhide", self.change, set_hidden, app, False)
            else:
                add(self.menu, "Hide", self.change, set_hidden, app, True)
        self.menu.attach_to_widget(self, None)
        self.menu.show_all()
        self.menu.popup_at_pointer(e)

    def on_pin(self, method, app):
        try:
            plank(method, app.info)      # the Plank directory monitor updates the grid
        except GLib.Error as e:
            n = Gio.Notification.new("Plank did not respond")
            n.set_body(e.message)
            self.get_application().send_notification(None, n)

    def blank_at(self, e):
        """Where the click landed: 'dim', 'page' (empty space) or None (something useful)."""
        w = Gtk.get_event_widget(e)
        for g in (self.main, self.found, self.inside):
            if w is not None and (w is g.flow or w.is_ancestor(g.flow)):
                _, rx, ry = self.get_window().get_origin()
                tl = g.flow.translate_coordinates(self, 0, 0)
                x, y = int(e.x_root) - rx - tl[0], int(e.y_root) - ry - tl[1]
                for c in g.flow.get_children():
                    al = c.get_allocation()
                    if al.x <= x < al.x + al.width and al.y <= y < al.y + al.height:
                        return None
                return None if g is self.inside else "page"
        while w:
            if isinstance(w, (Gtk.FlowBoxChild, Gtk.Entry, Gtk.Scrollbar, Gtk.Button)) or w is self.panel:
                return None
            if w is self.dim:
                return "dim"
            w = w.get_parent()
        return "page"

    def on_press(self, _w, e):
        cell = self.cell_at(e)
        if e.button == 3:
            self.blank = None
            if cell:
                self.popup(cell, e)
                return True
            return False
        self.blank = self.blank_at(e) if e.button == 1 and not cell else None
        return False

    def on_click(self, _w, e):
        blank, self.blank = self.blank, None
        if blank == "dim":
            self.close_folder()
        elif blank == "page":
            self.close_all()
        return blank is not None

    def on_focus(self, _w, _e, inside):
        if inside:
            self.had_focus = True
        elif (self.had_focus and self.get_visible() and not self.dialog and self.dragged is None
              and not (self.menu and self.menu.get_visible())):
            self.close_all()
        return False


class GenericCookie(C.Structure):
    _fields_ = [("type", C.c_int), ("serial", C.c_ulong), ("send_event", C.c_int), ("display", C.c_void_p),
                ("extension", C.c_int), ("evtype", C.c_int), ("cookie", C.c_uint), ("data", C.c_void_p)]


class XEvent(C.Union):
    _fields_ = [("type", C.c_int), ("cookie", GenericCookie), ("pad", C.c_long * 24)]


class RawEvent(C.Structure):     # start of XIRawEvent
    _fields_ = [("type", C.c_int), ("serial", C.c_ulong), ("send_event", C.c_int), ("display", C.c_void_p),
                ("extension", C.c_int), ("evtype", C.c_int), ("time", C.c_ulong),
                ("deviceid", C.c_int), ("sourceid", C.c_int), ("detail", C.c_int)]


class EventMask(C.Structure):
    _fields_ = [("deviceid", C.c_int), ("mask_len", C.c_int), ("mask", C.POINTER(C.c_ubyte))]


class SuperTap:
    """A short lone tap of Super. Only listens (XInput2 raw), grabs no keys."""
    KEY_DOWN, KEY_UP, BUTTON_DOWN = 13, 14, 15

    def __init__(self, callback, is_open):
        self.callback, self.is_open, self.alone, self.t0 = callback, is_open, None, 0
        X, XI = C.CDLL("libX11.so.6"), C.CDLL("libXi.so.6")
        P, UL, I = C.c_void_p, C.c_ulong, C.c_int
        X.XOpenDisplay.restype = P; X.XOpenDisplay.argtypes = [C.c_char_p]
        X.XDefaultRootWindow.restype = UL; X.XDefaultRootWindow.argtypes = [P]
        X.XKeysymToKeycode.restype = C.c_ubyte; X.XKeysymToKeycode.argtypes = [P, UL]
        X.XQueryExtension.argtypes = [P, C.c_char_p, P, P, P]
        X.XPending.argtypes = [P]; X.XNextEvent.argtypes = [P, P]
        X.XGetEventData.argtypes = [P, P]; X.XFreeEventData.argtypes = [P, P]
        X.XConnectionNumber.argtypes = [P]; X.XSync.argtypes = [P, I]
        X.XGrabKeyboard.argtypes = [P, UL, I, I, I, UL]; X.XUngrabKeyboard.argtypes = [P, UL]
        XI.XIQueryVersion.argtypes = [P, P, P]; XI.XISelectEvents.argtypes = [P, UL, P, I]
        self.X, self.d = X, X.XOpenDisplay(None)
        self.root = X.XDefaultRootWindow(self.d)
        op, a, b = I(), I(), I()
        X.XQueryExtension(self.d, b"XInputExtension", C.byref(op), C.byref(a), C.byref(b))
        self.op, major, minor = op.value, I(2), I(2)
        XI.XIQueryVersion(self.d, C.byref(major), C.byref(minor))
        bits = (C.c_ubyte * 4)()
        for ev in (self.KEY_DOWN, self.KEY_UP, self.BUTTON_DOWN):
            bits[ev >> 3] |= 1 << (ev & 7)
        mask = EventMask(1, 4, bits)       # 1 = XIAllMasterDevices
        XI.XISelectEvents(self.d, self.root, C.byref(mask), 1)
        X.XSync(self.d, 0)
        self.supers = {X.XKeysymToKeycode(self.d, k) for k in (0xFFEB, 0xFFEC)} - {0}
        GLib.io_add_watch(X.XConnectionNumber(self.d), GLib.PRIORITY_DEFAULT, GLib.IO_IN, self.pump)

    def keyboard_free(self):
        """Nobody grabs the keyboard (lock screen, menu, virtual machine)."""
        ok = self.X.XGrabKeyboard(self.d, self.root, 0, 1, 1, 0) == 0
        if ok:
            self.X.XUngrabKeyboard(self.d, 0)
        self.X.XSync(self.d, 0)
        return ok

    def handle(self, ev):
        if ev.evtype == self.KEY_DOWN:
            if ev.detail in self.supers and self.alone is None:
                self.alone, self.t0 = ev.detail, ev.time
            elif self.alone is not None and ev.detail != self.alone:
                self.alone = 0             # something else was pressed: a key combination
        elif ev.evtype == self.BUTTON_DOWN:
            if self.alone is not None:
                self.alone = 0
        elif ev.evtype == self.KEY_UP and ev.detail in self.supers:
            tap = self.alone == ev.detail and ev.time - self.t0 <= TAP_MS
            self.alone = None
            if tap and (self.is_open() or self.keyboard_free()):
                self.callback()
        elif ev.evtype == self.KEY_UP and self.alone == 0 and not self.super_down():
            self.alone = None

    def super_down(self):
        buf = (C.c_ubyte * 32)()
        self.X.XQueryKeymap(C.c_void_p(self.d), buf)
        return any(buf[k >> 3] & (1 << (k & 7)) for k in self.supers)

    def pump(self, *_):
        while self.X.XPending(self.d):
            e = XEvent()
            self.X.XNextEvent(self.d, C.byref(e))
            if e.type == 35 and e.cookie.extension == self.op and self.X.XGetEventData(self.d, C.byref(e)):
                r = C.cast(e.cookie.data, C.POINTER(RawEvent)).contents
                copy = RawEvent.from_buffer_copy(r)
                self.X.XFreeEventData(self.d, C.byref(e))
                self.handle(copy)
        return True


class Program(Gtk.Application):
    def __init__(self):
        super().__init__(application_id="local.openbox.Launcher")

    def do_startup(self):
        Gtk.Application.do_startup(self)
        self.hold()
        css = Gtk.CssProvider()
        css.load_from_data(CSS.encode())
        Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), css, 800)
        self.user_css, self.user_css_time = Gtk.CssProvider(), None
        Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), self.user_css, 801)
        self.win = Launcher(self)
        self.tap = SuperTap(self.win.toggle, self.win.get_visible)
        self.mon = Gio.AppInfoMonitor.get()
        self.mon.connect("changed", self.win.schedule_reload)
        Gtk.IconTheme.get_default().connect("changed", self.win.schedule_reload)
        os.makedirs(PLANK_DIR, exist_ok=True)
        self.dock = Gio.File.new_for_path(PLANK_DIR).monitor_directory(Gio.FileMonitorFlags.NONE, None)
        self.dock.connect("changed", self.win.schedule_regroup)
        self.sets = []
        if Gio.SettingsSchemaSource.get_default().lookup(FOLDERS, True):
            self.folder_list = Gio.Settings.new(FOLDERS)
            self.folder_list.connect("changed", self.watch_folders)
            self.watch_folders()

    def watch_folders(self, *_):
        """Follow every folder, including ones that were just created."""
        self.sets = [folder_settings(fid) for fid in self.folder_list.get_strv("folder-children")]
        for f in self.sets:
            f.connect("changed", self.win.schedule_regroup)
        self.win.schedule_regroup()

    def load_user_css(self):
        """Reload the theme variant if install.sh changed it."""
        try:
            t = os.stat(USER_CSS).st_mtime_ns
            if t != self.user_css_time:
                self.user_css.load_from_path(USER_CSS)
                self.user_css_time = t
        except (OSError, GLib.Error):
            pass

    def do_activate(self):
        self.win.toggle()


GLib.set_prgname("launcher")
Gdk.set_program_class("Launcher")
sys.exit(Program().run(sys.argv))
