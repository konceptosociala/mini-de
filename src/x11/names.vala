/* Names that window managers and programs agreed on (EWMH). */
namespace X11 {
    namespace WindowType {
        public const string DESKTOP = "_NET_WM_WINDOW_TYPE_DESKTOP";
        public const string DOCK = "_NET_WM_WINDOW_TYPE_DOCK";
        public const string NOTIFICATION = "_NET_WM_WINDOW_TYPE_NOTIFICATION";
        public const string SPLASH = "_NET_WM_WINDOW_TYPE_SPLASH";
    }

    namespace WindowState {
        public const string FULLSCREEN = "_NET_WM_STATE_FULLSCREEN";
        public const string HIDDEN = "_NET_WM_STATE_HIDDEN";
        public const string MAXIMIZED_HORIZONTALLY = "_NET_WM_STATE_MAXIMIZED_HORZ";
        public const string MAXIMIZED_VERTICALLY = "_NET_WM_STATE_MAXIMIZED_VERT";
        public const string SHADED = "_NET_WM_STATE_SHADED";
        public const string SKIP_TASKBAR = "_NET_WM_STATE_SKIP_TASKBAR";
    }

    namespace WindowAction {
        public const string RESIZE = "_NET_WM_ACTION_RESIZE";
    }

    namespace Keysym {
        public const ulong SPACE = 0x0020;
        public const ulong TAB = 0xFF09;
        public const ulong ENTER = 0xFF0D;
        public const ulong ESCAPE = 0xFF1B;
        public const ulong LEFT = 0xFF51;
        public const ulong UP = 0xFF52;
        public const ulong RIGHT = 0xFF53;
        public const ulong DOWN = 0xFF54;
        public const ulong SUPER_LEFT = 0xFFEB;
        public const ulong SUPER_RIGHT = 0xFFEC;
    }

    /* Directions of _NET_WM_MOVERESIZE. */
    public enum DragKind {
        TOP_LEFT = 0,
        TOP = 1,
        TOP_RIGHT = 2,
        RIGHT = 3,
        BOTTOM_RIGHT = 4,
        BOTTOM = 5,
        BOTTOM_LEFT = 6,
        LEFT = 7,
        MOVE = 8,
        CANCEL = 11
    }

    public struct Pointer {
        public int x;
        public int y;
        public uint mask;

        const uint ANY_BUTTON = 0x1F00;

        public bool left_button {
            get { return (mask & Xl.BUTTON1_MASK) != 0; }
        }

        public bool any_button {
            get { return (mask & ANY_BUTTON) != 0; }
        }

        public bool alt_key {
            get { return (mask & Xl.MOD1_MASK) != 0; }
        }
    }

    public struct FrameExtents {
        public int left;
        public int right;
        public int top;
        public int bottom;
    }
}
