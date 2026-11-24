#!/usr/bin/python3
"""Window switcher: Alt+Tab with large icons, most recently used first. Tab, Shift+Tab and arrows
move, releasing Alt or a click switches, Esc cancels."""
import ctypes as C, fcntl, os, sys
import gi
gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gtk, Gdk, GdkPixbuf, Gio, GLib, Pango

ICON = 84            # px
CELL = 160           # width of one window
SHOW_AFTER = 110     # ms: a quick Alt+Tab switches without showing anything

lock = open(os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"),
            "alt-tab%s.lock" % os.environ.get("DISPLAY", "").replace("/", "_")), "w")
try:
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
except OSError:
    sys.exit(0)      # already running

X = C.CDLL("libX11.so.6")
P, UL, L, I, UI = C.c_void_p, C.c_ulong, C.c_long, C.c_int, C.c_uint
R = C.byref
KEY_PRESS, KEY_RELEASE, PROPERTY = 2, 3, 28
SHIFT, LOCK, MOD1, MOD2 = 1, 2, 8, 16


class KeyEvent(C.Structure):
    _fields_ = [("type", I), ("serial", UL), ("send_event", I), ("display", P), ("window", UL), ("root", UL),
                ("subwindow", UL), ("time", UL), ("x", I), ("y", I), ("x_root", I), ("y_root", I),
                ("state", UI), ("keycode", UI), ("same_screen", I)]


class PropertyEvent(C.Structure):
    _fields_ = [("type", I), ("serial", UL), ("send_event", I), ("display", P), ("window", UL), ("atom", UL)]


class ClientMessage(C.Structure):
    _fields_ = [("type", I), ("serial", UL), ("send_event", I), ("display", P),
                ("window", UL), ("message_type", UL), ("format", I), ("data", L * 5)]


class XEvent(C.Union):
    _fields_ = [("type", I), ("key", KeyEvent), ("property", PropertyEvent), ("client", ClientMessage), ("pad", L * 24)]


X.XOpenDisplay.restype = P; X.XOpenDisplay.argtypes = [C.c_char_p]
X.XDefaultRootWindow.restype = UL; X.XDefaultRootWindow.argtypes = [P]
X.XInternAtom.restype = UL; X.XInternAtom.argtypes = [P, C.c_char_p, I]
X.XGetWindowProperty.argtypes = [P, UL, UL, L, L, I, UL, P, P, P, P, P]
X.XFree.argtypes = [P]; X.XSync.argtypes = [P, I]; X.XPending.argtypes = [P]; X.XNextEvent.argtypes = [P, P]
X.XConnectionNumber.argtypes = [P]; X.XSelectInput.argtypes = [P, UL, L]
X.XKeysymToKeycode.restype = C.c_ubyte; X.XKeysymToKeycode.argtypes = [P, UL]
X.XGrabKey.argtypes = [P, I, UI, UL, I, I, I]
X.XGrabKeyboard.argtypes = [P, UL, I, I, I, UL]; X.XUngrabKeyboard.argtypes = [P, UL]
X.XQueryPointer.argtypes = [P, UL] + [P] * 7
X.XSendEvent.argtypes = [P, UL, I, L, P]
X.XkbSetDetectableAutoRepeat.argtypes = [P, I, P]

Gtk.init()
errors = 0
HANDLER = C.CFUNCTYPE(I, P, P)


def on_error(_d, _e):
    global errors
    errors += 1
    return 0


handler = HANDLER(on_error)
X.XSetErrorHandler(handler)
d = X.XOpenDisplay(None)
root = X.XDefaultRootWindow(d)
atoms = {}


def atom(name):
    if name not in atoms:
        atoms[name] = X.XInternAtom(d, name.encode(), 0)
    return atoms[name]


def raw(win, name, length=1024):
    """(format, bytes) of a property."""
    t, f, n, rest, data = UL(), I(), UL(), UL(), P()
    if X.XGetWindowProperty(d, win, atom(name), 0, length, 0, 0, R(t), R(f), R(n), R(rest), R(data)) or not data:
        return 0, b""
    out = C.string_at(data, n.value * {8: 1, 16: 2, 32: 8}.get(f.value, 1))
    X.XFree(data)
    return f.value, out


def longs(win, name, length=1024):
    f, b = raw(win, name, length)
    return list((UL * (len(b) // 8)).from_buffer_copy(b)) if f == 32 and b else []


def text(win, name):
    f, b = raw(win, name)
    return b.decode("utf-8", "replace") if f == 8 else ""


def keycode(sym):
    return X.XKeysymToKeycode(d, sym)


K = {n: keycode(s) for n, s in dict(tab=0xFF09, esc=0xFF1B, left=0xFF51, up=0xFF52, right=0xFF53, down=0xFF54,
                                    enter=0xFF0D).items()}
X.XkbSetDetectableAutoRepeat(d, 1, None)
for extra in (0, LOCK, MOD2, LOCK | MOD2):
    for m in (MOD1, MOD1 | SHIFT):
        X.XGrabKey(d, K["tab"], m | extra, root, 0, 1, 1)
X.XSelectInput(d, root, 1 << 22)
X.XSync(d, 0)
if errors:
    sys.exit("Alt+Tab is already taken by another program")


# ── windows ──
desktop_files = {}


def index_apps(*_):
    """Window class -> desktop entry."""
    desktop_files.clear()
    # visible entries win over hidden ones, such as the URL handler of VS Code
    for a in sorted(Gio.AppInfo.get_all(), key=lambda a: not a.should_show()):
        if isinstance(a, Gio.DesktopAppInfo):
            name = (a.get_id() or "").removesuffix(".desktop").lower()
            for k in (a.get_startup_wm_class(), name, name.rpartition(".")[2], os.path.basename(a.get_executable() or "")):
                if k:
                    desktop_files.setdefault(k.lower(), a)


def app_of(win):
    parts = [p for p in text(win, "WM_CLASS").split("\0") if p]
    for p in reversed(parts):
        if p.lower() in desktop_files:
            return desktop_files[p.lower()], p
    return None, parts[-1] if parts else ""


def window_icon(win):
    """The best _NET_WM_ICON of the window."""
    data, i, best = longs(win, "_NET_WM_ICON", 400000), 0, None
    while i + 2 < len(data):
        w, h = data[i], data[i + 1]
        if not 0 < w <= 1024 or not 0 < h <= 1024 or i + 2 + w * h > len(data):
            break
        if best is None or abs(w - ICON * 1.5) < abs(best[0] - ICON * 1.5):
            best = (w, h, i + 2)
        i += 2 + w * h
    if not best:
        return None
    w, h, at = best
    out = bytearray(w * h * 4)
    for n, v in enumerate(data[at:at + w * h]):
        out[n * 4:n * 4 + 4] = bytes(((v >> 16) & 255, (v >> 8) & 255, v & 255, (v >> 24) & 255))
    pb = GdkPixbuf.Pixbuf.new_from_bytes(GLib.Bytes.new(bytes(out)), GdkPixbuf.Colorspace.RGB, True, 8, w, h, w * 4)
    k = min(ICON / max(w, h), 2)      # a tiny icon would be a blur
    return pb.scale_simple(max(1, round(w * k)), max(1, round(h * k)), GdkPixbuf.InterpType.BILINEAR)


icons = {}


def icon_of(win, info, cls):
    key = info.get_id() if info else win
    if key not in icons:
        theme, pb = Gtk.IconTheme.get_default(), None
        gicon = info.get_icon() if info else None
        ii = theme.lookup_by_gicon(gicon, ICON, Gtk.IconLookupFlags.FORCE_SIZE) if gicon else None
        for load in (lambda: ii and ii.load_icon(),
                     lambda: cls and theme.load_icon(cls.lower(), ICON, Gtk.IconLookupFlags.FORCE_SIZE),
                     lambda: window_icon(win),
                     lambda: theme.load_icon("application-x-executable", ICON, Gtk.IconLookupFlags.FORCE_SIZE)):
            try:
                pb = load()
            except GLib.Error:
                pb = None
            if pb:
                break
        icons[key] = pb
    return icons[key]


mru = []


def track():
    """Keep the most recently used order: new windows last, the active one first."""
    for w in reversed(longs(root, "_NET_CLIENT_LIST_STACKING")):
        if w not in mru:
            mru.append(w)
    active = (longs(root, "_NET_ACTIVE_WINDOW") or [0])[0]
    if active in mru:
        mru.remove(active)
        mru.insert(0, active)
    return active


def windows():
    track()
    clients = set(longs(root, "_NET_CLIENT_LIST"))
    mru[:] = [w for w in mru if w in clients]
    for k in [k for k in icons if isinstance(k, int) and k not in clients]:
        del icons[k]
    here = (longs(root, "_NET_CURRENT_DESKTOP") or [0])[0]
    skip = set(map(atom, ("_NET_WM_WINDOW_TYPE_DOCK", "_NET_WM_WINDOW_TYPE_DESKTOP", "_NET_WM_WINDOW_TYPE_SPLASH",
                          "_NET_WM_WINDOW_TYPE_NOTIFICATION")))
    out = []
    for w in mru:
        if skip & set(longs(w, "_NET_WM_WINDOW_TYPE")) or atom("_NET_WM_STATE_SKIP_TASKBAR") in longs(w, "_NET_WM_STATE"):
            continue
        if (longs(w, "_NET_WM_DESKTOP") or [here])[0] in (here, 0xFFFFFFFF, 0xFFFFFFFFFFFFFFFF):
            out.append(w)
    return out


def activate(win):
    e = XEvent()
    c = e.client
    c.type, c.window, c.message_type, c.format = 33, win, atom("_NET_ACTIVE_WINDOW"), 32
    c.data = (L * 5)(2, 0, 0, 0, 0)
    X.XSendEvent(d, root, 0, 1 << 19 | 1 << 20, R(e))
    X.XSync(d, 0)


# ── popup ──
css = Gtk.CssProvider()
css.load_from_data(b"""
@define-color md_panel #282828;
@define-color md_border #504945;
@define-color md_fg #ebdbb2;
@define-color md_dim #928374;
@define-color md_accent #fabd2f;
#alttab { background: transparent; }
#alttab #frame { background: alpha(@md_panel, 0.97); border: 1px solid @md_border; border-radius: 16px; padding: 14px; }
#alttab label { color: @md_fg; font: 14px "Inter"; }
#alttab #title { color: @md_dim; font: 13px "Inter"; padding: 6px 10px 2px 10px; }
#alttab .cell { border-radius: 12px; padding: 12px 8px; border: 2px solid transparent; }
#alttab .cell.sel { background: alpha(@md_accent, 0.22); border-color: @md_accent; }
#alttab .cell.hidden image { opacity: 0.45; }
""")
screen = Gdk.Screen.get_default()
Gtk.StyleContext.add_provider_for_screen(screen, css, 800)
USER_CSS = os.path.join(GLib.get_user_config_dir(), "mini-de", "colors.css")   # theme variant
user_css, user_css_time = Gtk.CssProvider(), None
Gtk.StyleContext.add_provider_for_screen(screen, user_css, 801)

win = Gtk.Window(type=Gtk.WindowType.POPUP, name="alttab", app_paintable=True,
                 type_hint=Gdk.WindowTypeHint.NOTIFICATION)      # no rectangular shadow from picom
if screen.get_rgba_visual():
    win.set_visual(screen.get_rgba_visual())
frame = Gtk.Box(name="frame", orientation=Gtk.Orientation.VERTICAL, spacing=6)
win.add(frame)
grid = Gtk.Grid(row_spacing=4, column_spacing=4, halign=Gtk.Align.CENTER)
title = Gtk.Label(name="title", ellipsize=Pango.EllipsizeMode.END, max_width_chars=60, xalign=0.5)
frame.pack_start(grid, False, False, 0)
frame.pack_start(title, False, False, 0)

active, items, idx, cols, show_id, cells = False, [], 0, 1, 0, []


def load_user_css():
    global user_css_time
    try:
        t = os.stat(USER_CSS).st_mtime_ns
        if t != user_css_time:
            user_css.load_from_path(USER_CSS)
            user_css_time = t
    except (OSError, GLib.Error):
        pass


class Cell(Gtk.EventBox):
    """Always CELL wide, so that a long name is cut instead of widening it."""
    __gtype_name__ = "AltTabCell"

    def do_get_preferred_width(self):
        return CELL, CELL

    def do_get_preferred_width_for_height(self, _height):
        return CELL, CELL


def build():
    """Create the cells; called only when the popup is really shown."""
    global cols, cells
    load_user_css()
    disp = Gdk.Display.get_default()
    _, px, py = disp.get_default_seat().get_pointer().get_position()
    m = disp.get_monitor_at_point(px, py).get_geometry()
    for c in grid.get_children():
        c.destroy()
    cols = max(1, min(len(items), (m.width - 160) // (CELL + 4)))
    cells = []
    for n, w in enumerate(items):
        info, cls = app_of(w)
        label = Gtk.Label(label=info.get_display_name() if info else cls or text(w, "_NET_WM_NAME"),
                          ellipsize=Pango.EllipsizeMode.END, xalign=0.5)
        image = Gtk.Image.new_from_pixbuf(icon_of(w, info, cls))
        image.set_size_request(ICON, ICON)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        box.pack_start(image, False, False, 0)
        box.pack_start(label, False, False, 0)
        box.get_style_context().add_class("cell")     # an event box ignores padding
        cell = Cell()
        if atom("_NET_WM_STATE_HIDDEN") in longs(w, "_NET_WM_STATE"):
            box.get_style_context().add_class("hidden")
        cell.add(box)
        cell.add_events(Gdk.EventMask.BUTTON_RELEASE_MASK | Gdk.EventMask.POINTER_MOTION_MASK)
        cell.connect("button-release-event", lambda _w, _e, n=n: (select(n), finish()))
        cell.connect("motion-notify-event", lambda _w, _e, n=n: select(n) if n != idx else None)
        grid.attach(cell, n % cols, n // cols, 1, 1)
        cells.append(box)
    frame.show_all()
    paint()
    w, h = frame.get_preferred_size()[1].width, frame.get_preferred_size()[1].height
    win.resize(w, h)
    win.move(m.x + (m.width - w) // 2, m.y + (m.height - h) // 2)
    win.show_all()


def show():
    global show_id
    show_id = 0
    if active:
        build()
    return False


def paint():
    for n, c in enumerate(cells):
        ctx = c.get_style_context()
        (ctx.add_class if n == idx else ctx.remove_class)("sel")
    if items:
        title.set_text(text(items[idx], "_NET_WM_NAME") or text(items[idx], "WM_NAME"))


def select(n):
    global idx
    idx = n % len(items)
    if win.get_visible():
        paint()


def alt_held():
    a, b, x, y, wx, wy, m = UL(), UL(), I(), I(), I(), I(), UI()
    X.XQueryPointer(d, root, R(a), R(b), R(x), R(y), R(wx), R(wy), R(m))
    return bool(m.value & MOD1)


def finish(cancel=False):
    global active, show_id, cells
    if not active:
        return
    active = False
    if show_id:
        GLib.source_remove(show_id)
        show_id = 0
    X.XUngrabKeyboard(d, 0)
    X.XSync(d, 0)
    win.hide()
    cells = []
    if not cancel and items:
        activate(items[idx])


def start(back):
    global active, items, idx, show_id
    current = track()
    items = windows()
    if not items:
        return
    active = True
    X.XGrabKeyboard(d, root, 0, 1, 1, 0)
    X.XSync(d, 0)
    # the first step goes to the previous window, or to the first one when none is active
    idx = 0
    if len(items) > 1 and items[0] == current:
        idx = len(items) - 1 if back else 1
    show_id = GLib.timeout_add(SHOW_AFTER, show)
    if not alt_held():                # a tap faster than the grab
        finish()


def on_key(k, state):
    if k == K["tab"]:
        select(idx + (-1 if state & SHIFT else 1))
    elif k == K["right"]:
        select(idx + 1)
    elif k == K["left"]:
        select(idx - 1)
    elif k == K["down"] and idx + cols < len(items):
        select(idx + cols)
    elif k == K["up"] and idx - cols >= 0:
        select(idx - cols)
    elif k == K["esc"]:
        finish(cancel=True)
    elif k == K["enter"]:
        finish()


def pump(*_):
    while X.XPending(d):
        e = XEvent()
        X.XNextEvent(d, R(e))
        if e.type == KEY_PRESS:
            if active:
                on_key(e.key.keycode, e.key.state)
            elif e.key.keycode == K["tab"]:
                start(e.key.state & SHIFT)
        elif e.type == KEY_RELEASE and active and not alt_held():
            finish()
        elif e.type == PROPERTY and e.property.atom == atom("_NET_ACTIVE_WINDOW") and not active:
            track()
    return True


def watchdog():                       # never leave the keyboard grabbed
    if active and not alt_held():
        finish()
    pump()
    return True


index_apps()
monitor = Gio.AppInfoMonitor.get()
monitor.connect("changed", index_apps)
Gtk.IconTheme.get_default().connect("changed", lambda *_: icons.clear())
track()
GLib.io_add_watch(X.XConnectionNumber(d), GLib.PRIORITY_DEFAULT, GLib.IO_IN, pump)
GLib.timeout_add(400, watchdog)
Gtk.main()
