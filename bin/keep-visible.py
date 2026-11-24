#!/usr/bin/python3 -SE
"""Keeps titlebars reachable: a window whose top ended up under the panel (or above the
screen) is moved below it, once no mouse button is pressed. Sleeps until windows change."""
import ctypes as C, select, sys, time

X, XI = C.CDLL("libX11.so.6"), C.CDLL("libXinerama.so.1")
P, UL, L, I, UI = C.c_void_p, C.c_ulong, C.c_long, C.c_int, C.c_uint
R = C.byref
BUTTONS = 0x1F00
SUBSTRUCTURE_NOTIFY, STRUCTURE_NOTIFY, PROPERTY_CHANGE = 1 << 19, 1 << 17, 1 << 22


class ClientMessage(C.Structure):
    _fields_ = [("type", I), ("serial", UL), ("send_event", I), ("display", P),
                ("window", UL), ("message_type", UL), ("format", I), ("data", L * 5)]


class XEvent(C.Union):
    _fields_ = [("type", I), ("client", ClientMessage), ("pad", L * 24)]


class Screen(C.Structure):
    _fields_ = [("number", I), ("x", C.c_short), ("y", C.c_short), ("w", C.c_short), ("h", C.c_short)]


X.XOpenDisplay.restype = P; X.XOpenDisplay.argtypes = [C.c_char_p]
X.XDefaultRootWindow.restype = UL; X.XDefaultRootWindow.argtypes = [P]
X.XInternAtom.restype = UL; X.XInternAtom.argtypes = [P, C.c_char_p, I]
X.XGetWindowProperty.argtypes = [P, UL, UL, L, L, I, UL, P, P, P, P, P]
X.XFree.argtypes = [P]; X.XSync.argtypes = [P, I]; X.XPending.argtypes = [P]; X.XNextEvent.argtypes = [P, P]
X.XConnectionNumber.argtypes = [P]; X.XSelectInput.argtypes = [P, UL, L]
X.XQueryPointer.argtypes = [P, UL] + [P] * 7
X.XGetGeometry.argtypes = [P, UL] + [P] * 7
X.XTranslateCoordinates.argtypes = [P, UL, UL, I, I, P, P, P]
X.XSendEvent.argtypes = [P, UL, I, L, P]
XI.XineramaQueryScreens.restype = C.POINTER(Screen); XI.XineramaQueryScreens.argtypes = [P, P]
HANDLER = C.CFUNCTYPE(I, P, P)
ignore = HANDLER(lambda *_: 0)        # windows may close at any moment
X.XSetErrorHandler(ignore)

d = X.XOpenDisplay(None) or sys.exit(1)
root = X.XDefaultRootWindow(d)
atoms = {}


def atom(name):
    if name not in atoms:
        atoms[name] = X.XInternAtom(d, name.encode(), 0)
    return atoms[name]


def prop(win, name):
    t, f, n, rest, data = UL(), I(), UL(), UL(), P()
    if X.XGetWindowProperty(d, win, atom(name), 0, 1024, 0, 0, R(t), R(f), R(n), R(rest), R(data)) or not data:
        return []
    out = list(C.cast(data, C.POINTER(UL))[:n.value]) if f.value == 32 else []
    X.XFree(data)
    return out


def geometry(win):
    """x, y, width, height of the client area on the screen, or None."""
    r, x, y, w, h, b, dep, ch = UL(), I(), I(), UI(), UI(), UI(), UI(), UL()
    if not X.XGetGeometry(d, win, R(r), R(x), R(y), R(w), R(h), R(b), R(dep)):
        return None
    if not X.XTranslateCoordinates(d, win, root, 0, 0, R(x), R(y), R(ch)):
        return None
    return x.value, y.value, w.value, h.value


def button_pressed():
    a, b, x, y, wx, wy, m = UL(), UL(), I(), I(), I(), I(), UI()
    X.XQueryPointer(d, root, R(a), R(b), R(x), R(y), R(wx), R(wy), R(m))
    return bool(m.value & BUTTONS)


def monitors():
    n = I()
    s = XI.XineramaQueryScreens(d, R(n))
    out = [(s[i].x, s[i].y, s[i].w, s[i].h) for i in range(n.value)] if s else []
    if s:
        X.XFree(s)
    return out


def overlap(a, b):
    return (max(0, min(a[0] + a[2], b[0] + b[2]) - max(a[0], b[0]))
            * max(0, min(a[1] + a[3], b[1] + b[3]) - max(a[1], b[1])))


def move_to(win, x, y):
    e = XEvent()
    c = e.client
    c.type, c.window, c.message_type, c.format = 33, win, atom("_NET_MOVERESIZE_WINDOW"), 32
    c.data = (L * 5)(1 | 1 << 8 | 1 << 9 | 2 << 12, x, y, 0, 0)      # north-west gravity: the frame's corner
    X.XSendEvent(d, root, 0, 1 << 19 | 1 << 20, R(e))
    X.XSync(d, 0)


fixed = {}      # window -> times of recent corrections: never fight an app that moves itself back


def check():
    screens = monitors()
    clients = prop(root, "_NET_CLIENT_LIST")
    dock = atom("_NET_WM_WINDOW_TYPE_DOCK")
    skip_types = {dock, *map(atom, ("_NET_WM_WINDOW_TYPE_DESKTOP", "_NET_WM_WINDOW_TYPE_SPLASH", "_NET_WM_WINDOW_TYPE_NOTIFICATION"))}
    skip_states = set(map(atom, ("_NET_WM_STATE_FULLSCREEN", "_NET_WM_STATE_HIDDEN", "_NET_WM_STATE_MAXIMIZED_VERT")))
    types = {w: set(prop(w, "_NET_WM_WINDOW_TYPE")) for w in clients}

    top = {m: m[1] for m in screens}      # lowest allowed top edge on every monitor
    for w in clients:
        strut = prop(w, "_NET_WM_STRUT_PARTIAL") or prop(w, "_NET_WM_STRUT")
        g = geometry(w) if dock in types[w] and len(strut) >= 4 and strut[2] else None
        if g:
            m = max(screens, key=lambda s: overlap(s, g), default=None)
            if m and g[1] <= m[1] + 8:
                top[m] = max(top[m], g[1] + g[3])

    for w in clients:
        if types[w] & skip_types or skip_states & set(prop(w, "_NET_WM_STATE")):
            continue
        g = geometry(w)
        if not g:
            continue
        l, r, t, b = (prop(w, "_NET_FRAME_EXTENTS") + [0] * 4)[:4]
        shadow = (prop(w, "_GTK_FRAME_EXTENTS") + [0] * 4)[2]        # invisible margin of client-side decorations
        x, y = g[0] - l, g[1] - t
        visible = (x, y + shadow, g[2] + l + r, g[3] + t + b - shadow)
        m = max(screens, key=lambda s: overlap(s, visible), default=None)
        if not m:
            continue
        if not overlap(m, visible):      # entirely off every screen: use the nearest one
            m = min(screens, key=lambda s: abs(s[0] + s[2] // 2 - x - visible[2] // 2) + abs(s[1] - y))
        if visible[1] >= top[m]:
            continue
        now = time.monotonic()
        recent = [t0 for t0 in fixed.get(w, []) if now - t0 < 5]
        if len(recent) < 3:
            fixed[w] = recent + [now]
            move_to(w, x, top[m] - shadow)
    for w in set(fixed) - set(clients):
        del fixed[w]


X.XSelectInput(d, root, SUBSTRUCTURE_NOTIFY | STRUCTURE_NOTIFY | PROPERTY_CHANGE)
X.XSync(d, 0)
fd, due = X.XConnectionNumber(d), time.monotonic()
MAP, CONFIGURE, PROPERTY = 19, 22, 28
while True:
    timeout = None if due is None else max(0, due - time.monotonic())
    if not X.XPending(d):
        select.select([fd], [], [], timeout)
    while X.XPending(d):
        e = XEvent()
        X.XNextEvent(d, R(e))
        if e.type in (MAP, CONFIGURE, PROPERTY):
            due = time.monotonic() + 0.15
    if due is not None and time.monotonic() >= due:
        if button_pressed():
            due = time.monotonic() + 0.1      # still dragging
        else:
            due = None
            check()
