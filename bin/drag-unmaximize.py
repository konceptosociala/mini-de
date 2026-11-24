#!/usr/bin/python3 -SE
"""Dragging a maximized window: restore its normal size with the titlebar under
the pointer, then hand the move over to Openbox (called from rc.xml)."""
import ctypes as C, sys, time

X = C.CDLL("libX11.so.6")
P, UL, L, I, UI = C.c_void_p, C.c_ulong, C.c_long, C.c_int, C.c_uint
R = C.byref
BUTTON1 = 1 << 8
MOVE, CANCEL = 8, 11


class ClientMessage(C.Structure):
    _fields_ = [("type", I), ("serial", UL), ("send_event", I), ("display", P),
                ("window", UL), ("message_type", UL), ("format", I), ("data", L * 5)]


class XEvent(C.Union):
    _fields_ = [("client", ClientMessage), ("pad", L * 24)]


X.XOpenDisplay.restype = P; X.XOpenDisplay.argtypes = [C.c_char_p]
X.XDefaultRootWindow.restype = UL; X.XDefaultRootWindow.argtypes = [P]
X.XInternAtom.restype = UL; X.XInternAtom.argtypes = [P, C.c_char_p, I]
X.XGetWindowProperty.argtypes = [P, UL, UL, L, L, I, UL, P, P, P, P, P]
X.XFree.argtypes = [P]; X.XSync.argtypes = [P, I]
X.XQueryPointer.argtypes = [P, UL] + [P] * 7
X.XGetGeometry.argtypes = [P, UL] + [P] * 7
X.XTranslateCoordinates.argtypes = [P, UL, UL, I, I, P, P, P]
X.XSendEvent.argtypes = [P, UL, I, L, P]
HANDLER = C.CFUNCTYPE(I, P, P)
ignore = HANDLER(lambda *_: 0)        # the window may close meanwhile
X.XSetErrorHandler(ignore)

d = X.XOpenDisplay(None) or sys.exit(1)
root = X.XDefaultRootWindow(d)
atom = lambda n: X.XInternAtom(d, n.encode(), 0)


def prop(win, name):
    t, f, n, rest, data = UL(), I(), UL(), UL(), P()
    if X.XGetWindowProperty(d, win, atom(name), 0, 64, 0, 0, R(t), R(f), R(n), R(rest), R(data)) or not data:
        return []
    out = list(C.cast(data, C.POINTER(UL))[:n.value]) if f.value == 32 else []
    X.XFree(data)
    return out


def pointer():
    a, b, x, y, wx, wy, m = UL(), UL(), I(), I(), I(), I(), UI()
    X.XQueryPointer(d, root, R(a), R(b), R(x), R(y), R(wx), R(wy), R(m))
    return x.value, y.value, bool(m.value & BUTTON1)


def frame(win):
    """x, y, width and height of the window including its frame."""
    r, x, y, w, h, b, dep = UL(), I(), I(), UI(), UI(), UI(), UI()
    X.XGetGeometry(d, win, R(r), R(x), R(y), R(w), R(h), R(b), R(dep))
    ch = UL()
    X.XTranslateCoordinates(d, win, root, 0, 0, R(x), R(y), R(ch))
    l, rt, t, bt = (prop(win, "_NET_FRAME_EXTENTS") + [0] * 4)[:4]
    return x.value - l, y.value - t, w.value + l + rt, h.value + t + bt


def send(win, name, *data):
    e = XEvent()
    c = e.client
    c.type, c.window, c.message_type, c.format = 33, win, atom(name), 32
    c.data = (L * 5)(*data)
    X.XSendEvent(d, root, 0, (1 << 19) | (1 << 20), R(e))
    X.XSync(d, 0)


MAX = {atom("_NET_WM_STATE_MAXIMIZED_HORZ"), atom("_NET_WM_STATE_MAXIMIZED_VERT")}
win = (prop(root, "_NET_ACTIVE_WINDOW") or [0])[0]
px, py, held = pointer()
if not win or not held or not MAX & set(prop(win, "_NET_WM_STATE")):
    sys.exit()
fx, fy, fw, fh = frame(win)
share, dy = (px - fx) / max(fw, 1), py - fy      # where the titlebar was grabbed

send(win, "_NET_WM_STATE", 0, *MAX, 2, 0)
before, end = (fw, fh), time.monotonic() + 0.4
while time.monotonic() < end:                    # wait for Openbox to resize it
    if not MAX & set(prop(win, "_NET_WM_STATE")) and frame(win)[2:] != before:
        break
    time.sleep(0.005)

_, _, w, h = frame(win)
px, py, held = pointer()
if not held:
    sys.exit()
dx = min(max(share * w, 40), max(w - 110, 40))   # stay clear of the buttons on the right
title = (prop(win, "_NET_FRAME_EXTENTS") + [0] * 4)[2]
if "title" in sys.argv and title:                # dragged by the titlebar: hold its middle
    dy = title // 2
dy = min(dy, h - 10)
send(win, "_NET_MOVERESIZE_WINDOW", 1 | 1 << 8 | 1 << 9 | 2 << 12, int(px - dx), int(py - dy), 0, 0)
end = time.monotonic() + 0.2
while time.monotonic() < end and abs(frame(win)[0] - int(px - dx)) > 2:
    time.sleep(0.005)
if pointer()[2]:
    send(win, "_NET_WM_MOVERESIZE", px, py, MOVE, 1, 2)
    time.sleep(0.02)
    if not pointer()[2]:                         # the button was released just now
        send(win, "_NET_WM_MOVERESIZE", px, py, CANCEL, 1, 2)
