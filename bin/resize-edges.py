#!/usr/bin/python3 -SE
"""Invisible resize borders around windows, like in GNOME: Openbox itself only reacts on the
1 px frame. Every resizable window gets one transparent input window, a little larger than the
frame and stacked right below it, so only the ring around the frame receives the pointer."""
import ctypes as C, select, sys, time

EDGE, CORNER = 7, 18       # width of the ring and length of its corners, px

X = C.CDLL("libX11.so.6")
P, UL, L, I, UI = C.c_void_p, C.c_ulong, C.c_long, C.c_int, C.c_uint
R = C.byref
BUTTONS, BUTTON1 = 0x1F00, 1 << 8
BUTTON_PRESS, MOTION, LEAVE, UNMAP, MAP, REPARENT, CONFIGURE, PROPERTY, DESTROY = 4, 6, 8, 18, 19, 21, 22, 28, 17
# _NET_WM_MOVERESIZE directions and the matching cursors of the X cursor font
CURSORS = {0: 134, 1: 138, 2: 136, 3: 96, 4: 14, 5: 16, 6: 12, 7: 70}
CANCEL = 11


class ClientMessage(C.Structure):
    _fields_ = [("type", I), ("serial", UL), ("send_event", I), ("display", P),
                ("window", UL), ("message_type", UL), ("format", I), ("data", L * 5)]


class PointerEvent(C.Structure):      # XButtonEvent and XMotionEvent start the same way
    _fields_ = [("type", I), ("serial", UL), ("send_event", I), ("display", P), ("window", UL), ("root", UL),
                ("subwindow", UL), ("time", UL), ("x", I), ("y", I), ("x_root", I), ("y_root", I), ("state", UI), ("button", UI)]


class AnyWindowEvent(C.Structure):    # event window first, then the window it is about
    _fields_ = [("type", I), ("serial", UL), ("send_event", I), ("display", P), ("event", UL), ("window", UL)]


class XEvent(C.Union):
    _fields_ = [("type", I), ("client", ClientMessage), ("pointer", PointerEvent), ("any", AnyWindowEvent), ("pad", L * 24)]


class Attributes(C.Structure):        # XSetWindowAttributes
    _fields_ = [("bg_pixmap", UL), ("bg", UL), ("border_pixmap", UL), ("border", UL), ("bit_gravity", I), ("win_gravity", I),
                ("backing_store", I), ("planes", UL), ("pixel", UL), ("save_under", I), ("event_mask", L),
                ("no_propagate", L), ("override_redirect", I), ("colormap", UL), ("cursor", UL)]


class Changes(C.Structure):           # XWindowChanges
    _fields_ = [("x", I), ("y", I), ("width", I), ("height", I), ("border", I), ("sibling", UL), ("stack_mode", I)]


X.XOpenDisplay.restype = P; X.XOpenDisplay.argtypes = [C.c_char_p]
X.XDefaultRootWindow.restype = UL; X.XDefaultRootWindow.argtypes = [P]
X.XInternAtom.restype = UL; X.XInternAtom.argtypes = [P, C.c_char_p, I]
X.XGetWindowProperty.argtypes = [P, UL, UL, L, L, I, UL, P, P, P, P, P]
X.XFree.argtypes = [P]; X.XSync.argtypes = [P, I]; X.XFlush.argtypes = [P]
X.XPending.argtypes = [P]; X.XNextEvent.argtypes = [P, P]; X.XConnectionNumber.argtypes = [P]
X.XSelectInput.argtypes = [P, UL, L]
X.XQueryPointer.argtypes = [P, UL] + [P] * 7
X.XGetGeometry.argtypes = [P, UL] + [P] * 7
X.XQueryTree.argtypes = [P, UL, P, P, P, P]
X.XSendEvent.argtypes = [P, UL, I, L, P]
X.XCreateWindow.restype = UL; X.XCreateWindow.argtypes = [P, UL, I, I, UI, UI, UI, I, UI, P, UL, P]
X.XConfigureWindow.argtypes = [P, UL, UI, P]
X.XMapWindow.argtypes = [P, UL]; X.XUnmapWindow.argtypes = [P, UL]; X.XDestroyWindow.argtypes = [P, UL]
X.XCreateFontCursor.restype = UL; X.XCreateFontCursor.argtypes = [P, UI]
X.XDefineCursor.argtypes = [P, UL, UL]; X.XUngrabPointer.argtypes = [P, UL]
HANDLER = C.CFUNCTYPE(I, P, P)
ignore = HANDLER(lambda *_: 0)        # windows may close at any moment
X.XSetErrorHandler(ignore)

d = X.XOpenDisplay(None) or sys.exit(1)
root = X.XDefaultRootWindow(d)
cursors = {k: X.XCreateFontCursor(d, v) for k, v in CURSORS.items()}
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


def tree(win):
    """(parent, children bottom to top) or None."""
    r, p, ch, n = UL(), UL(), C.POINTER(UL)(), UI()
    if not X.XQueryTree(d, win, R(r), R(p), R(ch), R(n)):
        return None
    kids = list(ch[:n.value]) if n.value else []
    if ch:
        X.XFree(ch)
    return p.value, kids


def frame_of(client):
    """The ancestor that is a direct child of the root window."""
    w = client
    for _ in range(8):
        t = tree(w)
        if not t or not t[0]:
            return None
        if t[0] == root:
            return w
        w = t[0]
    return None


def geometry(win):
    r, x, y, w, h, b, dep = UL(), I(), I(), UI(), UI(), UI(), UI()
    if not X.XGetGeometry(d, win, R(r), R(x), R(y), R(w), R(h), R(b), R(dep)):
        return None
    return x.value, y.value, w.value + 2 * b.value, h.value + 2 * b.value


def pointer():
    a, b, x, y, wx, wy, m = UL(), UL(), I(), I(), I(), I(), UI()
    X.XQueryPointer(d, root, R(a), R(b), R(x), R(y), R(wx), R(wy), R(m))
    return x.value, y.value, m.value


def send(win, name, *data):
    e = XEvent()
    c = e.client
    c.type, c.window, c.message_type, c.format = 33, win, atom(name), 32
    c.data = (L * 5)(*data)
    X.XSendEvent(d, root, 0, 1 << 19 | 1 << 20, R(e))
    X.XSync(d, 0)


class Ring:
    def __init__(self, client):
        self.client, self.geo, self.mapped, self.cursor = client, None, False, None
        a = Attributes()
        a.override_redirect = 1
        a.event_mask = 1 << 2 | 1 << 6                      # ButtonPress, PointerMotion
        self.win = X.XCreateWindow(d, root, -100, -100, 1, 1, 0, 0, 2, None, 1 << 9 | 1 << 11, R(a))      # InputOnly

    def place(self, frame, geo, order):
        c, mask = Changes(), 0
        if geo != self.geo:
            c.x, c.y, c.width, c.height = geo[0] - EDGE, geo[1] - EDGE, geo[2] + 2 * EDGE, geo[3] + 2 * EDGE
            mask |= 1 | 2 | 4 | 8
        try:
            right_below = order[order.index(frame) - 1] == self.win and order.index(frame) > 0
        except ValueError:
            return
        if not right_below:
            c.sibling, c.stack_mode = frame, 1              # Below
            mask |= 1 << 5 | 1 << 6
        if mask:
            X.XConfigureWindow(d, self.win, mask, R(c))
        self.geo = geo
        if not self.mapped:
            X.XMapWindow(d, self.win)
            self.mapped = True

    def hide(self):
        if self.mapped:
            X.XUnmapWindow(d, self.win)
            self.mapped = False

    def direction(self, x, y):
        fx, fy, fw, fh = self.geo
        left, right, top, bottom = x < fx, x >= fx + fw, y < fy, y >= fy + fh
        near_l, near_r = x < fx + min(CORNER, fw // 3), x >= fx + fw - min(CORNER, fw // 3)
        near_t, near_b = y < fy + min(CORNER, fh // 3), y >= fy + fh - min(CORNER, fh // 3)
        if (top and near_l) or (left and near_t): return 0
        if (top and near_r) or (right and near_t): return 2
        if (bottom and near_r) or (right and near_b): return 4
        if (bottom and near_l) or (left and near_b): return 6
        return 1 if top else 3 if right else 5 if bottom else 7

    def hover(self, x, y):
        k = self.direction(x, y)
        if k != self.cursor:
            X.XDefineCursor(d, self.win, cursors[k])
            self.cursor = k

    def press(self, x, y):
        X.XUngrabPointer(d, 0)                              # let Openbox grab it
        send(self.client, "_NET_ACTIVE_WINDOW", 2, 0, 0, 0, 0)
        send(self.client, "_NET_WM_MOVERESIZE", x, y, self.direction(x, y), 1, 2)
        time.sleep(0.02)
        if not pointer()[2] & BUTTON1:                      # released meanwhile
            send(self.client, "_NET_WM_MOVERESIZE", x, y, CANCEL, 1, 2)


rings = {}          # client -> Ring


def sync():
    clients = prop(root, "_NET_CLIENT_LIST")
    skip_states = set(map(atom, ("_NET_WM_STATE_FULLSCREEN", "_NET_WM_STATE_HIDDEN", "_NET_WM_STATE_SHADED",
                                 "_NET_WM_STATE_MAXIMIZED_VERT", "_NET_WM_STATE_MAXIMIZED_HORZ")))
    skip_types = set(map(atom, ("_NET_WM_WINDOW_TYPE_DOCK", "_NET_WM_WINDOW_TYPE_DESKTOP", "_NET_WM_WINDOW_TYPE_SPLASH",
                                "_NET_WM_WINDOW_TYPE_NOTIFICATION")))
    resize = atom("_NET_WM_ACTION_RESIZE")
    desktop = (prop(root, "_NET_CURRENT_DESKTOP") or [0])[0]
    for w in set(rings) - set(clients):
        X.XDestroyWindow(d, rings.pop(w).win)
    t = tree(root)
    if not t:
        return
    order = t[1]
    for w in clients:
        on = (prop(w, "_NET_WM_DESKTOP") or [desktop])[0]
        ok = (resize in prop(w, "_NET_WM_ALLOWED_ACTIONS") and not skip_types & set(prop(w, "_NET_WM_WINDOW_TYPE"))
              and not skip_states & set(prop(w, "_NET_WM_STATE")) and on in (desktop, 0xFFFFFFFF, 0xFFFFFFFFFFFFFFFF))
        frame = frame_of(w) if ok else None
        geo = geometry(frame) if frame else None
        if not geo:
            if w in rings:
                rings[w].hide()
            continue
        if w not in rings:
            rings[w] = Ring(w)
            X.XSelectInput(d, w, 1 << 22)                   # state changes of the client
        rings[w].place(frame, geo, order)
    X.XFlush(d)


X.XSelectInput(d, root, 1 << 19 | 1 << 22)                  # SubstructureNotify, PropertyChange
X.XSync(d, 0)
fd, due = X.XConnectionNumber(d), time.monotonic()
while True:
    if not X.XPending(d):
        select.select([fd], [], [], None if due is None else max(0, due - time.monotonic()))
    mine = {r.win: r for r in rings.values()}
    while X.XPending(d):
        e = XEvent()
        X.XNextEvent(d, R(e))
        if e.type == MOTION:
            r = mine.get(e.pointer.window)
            if r and r.geo:
                r.hover(e.pointer.x_root, e.pointer.y_root)
        elif e.type == BUTTON_PRESS:
            r = mine.get(e.pointer.window)
            if r and r.geo and e.pointer.button == 1:
                r.press(e.pointer.x_root, e.pointer.y_root)
        elif e.type == PROPERTY or (e.type in (MAP, UNMAP, DESTROY, REPARENT, CONFIGURE) and e.any.window not in mine):
            due = min(due or 1e18, time.monotonic() + 0.06)
    if due is not None and time.monotonic() >= due:
        if pointer()[2] & BUTTONS:
            due = time.monotonic() + 0.1                    # wait until the drag ends
        else:
            due = None
            sync()
