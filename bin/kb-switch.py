#!/usr/bin/python3
"""GNOME-like layout switcher: Super+Space, most recently used order,
on-screen popup. Shift goes back, Esc cancels."""
import ctypes as C, fcntl, os, subprocess, sys
import gi
gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gtk, Gdk, GLib

lock = open(os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"),
            "kb-switch%s.lock" % os.environ.get("DISPLAY", "").replace("/", "_")), "w")
try:
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
except OSError:
    sys.exit("kb-switch is already running")

X = C.CDLL("libX11.so.6")
P, UL, UI, I = C.c_void_p, C.c_ulong, C.c_uint, C.c_int
KeyPress, KeyRelease = 2, 3
Shift, Lock, Mod2, Mod4 = 1, 2, 16, 64
XKB_CORE = 0x100
SUPER = (0xFFEB, 0xFFEC)
SPACE, ESC = 0x20, 0xFF1B


class XKeyEvent(C.Structure):
    _fields_ = [("type", I), ("serial", UL), ("send_event", I), ("display", P),
                ("window", UL), ("root", UL), ("subwindow", UL), ("time", UL),
                ("x", I), ("y", I), ("x_root", I), ("y_root", I),
                ("state", UI), ("keycode", UI), ("same_screen", I)]


class XEvent(C.Union):
    _fields_ = [("type", I), ("key", XKeyEvent), ("pad", C.c_long * 24)]


class XkbState(C.Structure):
    _fields_ = [("group", C.c_ubyte), ("locked_group", C.c_ubyte),
                ("base_group", C.c_ushort), ("latched_group", C.c_ushort),
                ("pad", C.c_ubyte * 32)]


X.XOpenDisplay.restype = P; X.XOpenDisplay.argtypes = [C.c_char_p]
X.XDefaultRootWindow.restype = UL; X.XDefaultRootWindow.argtypes = [P]
X.XKeysymToKeycode.restype = C.c_ubyte; X.XKeysymToKeycode.argtypes = [P, UL]
X.XGrabKey.argtypes = [P, I, UI, UL, I, I, I]
X.XGrabKeyboard.argtypes = [P, UL, I, I, I, UL]
X.XUngrabKeyboard.argtypes = [P, UL]
X.XPending.argtypes = [P]; X.XNextEvent.argtypes = [P, P]
X.XSync.argtypes = [P, I]; X.XConnectionNumber.argtypes = [P]
X.XQueryKeymap.argtypes = [P, P]
X.XkbLockGroup.argtypes = [P, UI, UI]; X.XkbGetState.argtypes = [P, UI, P]
X.XkbSetDetectableAutoRepeat.argtypes = [P, I, P]

Gtk.init()
HANDLER = C.CFUNCTYPE(I, P, P)
grab_failed = False


def on_error(_d, _e):
    global grab_failed
    grab_failed = True
    return 0


handler = HANDLER(on_error)
X.XSetErrorHandler(handler)
d = X.XOpenDisplay(None)
root = X.XDefaultRootWindow(d)
code = lambda sym: X.XKeysymToKeycode(d, sym)
K_SPACE, K_ESC, K_SUPER = code(SPACE), code(ESC), [c for c in map(code, SUPER) if c]
X.XkbSetDetectableAutoRepeat(d, 1, None)
for extra in (0, Lock, Mod2, Lock | Mod2):
    for m in (Mod4, Mod4 | Shift):
        X.XGrabKey(d, K_SPACE, m | extra, root, 0, 1, 1)
X.XSync(d, 0)
if grab_failed:
    sys.exit("Super+Space is already taken by another program")

out = subprocess.run(["setxkbmap", "-query"], capture_output=True, text=True).stdout
names = [l.split(":")[1].strip() for l in out.splitlines() if l.startswith("layout")][0].split(",")
mru = list(range(len(names)))
active, idx, start = False, 0, 0


def group():
    s = XkbState()
    X.XkbGetState(d, XKB_CORE, C.byref(s))
    return s.group


def set_group(g):
    X.XkbLockGroup(d, XKB_CORE, g)
    X.XSync(d, 0)


def to_front(g):
    if g in mru:
        mru.remove(g)
        mru.insert(0, g)


def super_held():
    buf = (C.c_ubyte * 32)()
    X.XQueryKeymap(d, buf)
    return any(buf[k >> 3] & (1 << (k & 7)) for k in K_SUPER)


css = Gtk.CssProvider()
css.load_from_data(b"""
@define-color md_surface #1d2021;
@define-color md_border #504945;
@define-color md_fg #ebdbb2;
@define-color md_accent #fabd2f;
@define-color md_on_accent #1d2021;
#kbosd { background: @md_surface; border: 2px solid @md_border; }
#kbosd label { color: @md_fg; font: 600 22px "Ubuntu Sans"; padding: 14px 22px; margin: 8px; }
#kbosd label.sel { color: @md_on_accent; background: @md_accent; border-radius: 8px; }
""")
Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), css, 800)
USER_CSS = os.path.join(GLib.get_user_config_dir(), "mini-de", "colors.css")   # theme variant
user_css, user_css_time = Gtk.CssProvider(), None
Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), user_css, 801)


def load_user_css():
    """Reload the theme variant if install.sh changed it."""
    global user_css_time
    try:
        t = os.stat(USER_CSS).st_mtime_ns
        if t != user_css_time:
            user_css.load_from_path(USER_CSS)
            user_css_time = t
    except (OSError, GLib.Error):
        pass


win = Gtk.Window(type=Gtk.WindowType.POPUP, name="kbosd")
box = Gtk.Box()
win.add(box)
labels = [Gtk.Label(label=n) for n in names]
hide_id = 0


def draw():
    load_user_css()
    for w in box.get_children():
        box.remove(w)
    for i, g in enumerate(mru):
        ctx = labels[g].get_style_context()
        (ctx.add_class if i == idx else ctx.remove_class)("sel")
        box.add(labels[g])
    win.show_all()
    disp = Gdk.Display.get_default()
    _, px, py = disp.get_default_seat().get_pointer().get_position()
    m = disp.get_monitor_at_point(px, py).get_geometry()
    w, h = win.get_size()
    win.move(m.x + (m.width - w) // 2, m.y + (m.height - h) // 2)


def hide():
    global hide_id
    hide_id = 0
    win.hide()
    return False


def finish(cancel=False):
    global active, hide_id
    if cancel:
        set_group(start)
    else:
        to_front(mru[idx])
    active = False
    X.XUngrabKeyboard(d, 0)
    X.XSync(d, 0)
    hide_id = GLib.timeout_add(400, hide)


def step(back):
    global active, idx, start, hide_id
    if not active:
        start = group()
        to_front(start)
        idx, active = 0, True
        X.XGrabKeyboard(d, root, 0, 1, 1, 0)
        if hide_id:
            GLib.source_remove(hide_id)
            hide_id = 0
    idx = (idx + (-1 if back else 1)) % len(mru)
    set_group(mru[idx])
    draw()
    if not super_held():          # Super was released before the grab
        finish()


def pump(*_):
    while X.XPending(d):
        e = XEvent()
        X.XNextEvent(d, C.byref(e))
        k = e.key
        if e.type == KeyPress:
            if k.keycode == K_SPACE:
                step(k.state & Shift)
            elif active and k.keycode == K_ESC:
                finish(cancel=True)
        elif e.type == KeyRelease and active and k.keycode in K_SUPER:
            finish()
    return True


def watchdog():                   # safety net: never leave the keyboard grabbed
    if active and not super_held():
        finish()
    pump()
    return True


GLib.io_add_watch(X.XConnectionNumber(d), GLib.PRIORITY_DEFAULT, GLib.IO_IN, pump)
GLib.timeout_add(500, watchdog)
Gtk.main()
