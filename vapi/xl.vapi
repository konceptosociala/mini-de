/* The part of Xlib that mini-de uses, with plain C names. Only src/x11 calls it. */
[CCode (cheader_filename = "X11/Xlib.h,X11/Xutil.h,X11/XKBlib.h")]
namespace Xl {
    // ── types ───────────────────────────────────────────────
    [Compact]
    [CCode (cname = "Display", free_function = "XCloseDisplay")]
    public class Display {
        [CCode (cname = "XOpenDisplay")]
        public Display(string? name = null);
    }

    // The members of the XEvent union are reached by their C path.
    [CCode (cname = "XEvent", has_type_id = false, has_destroy_function = false, has_copy_function = false)]
    public struct Event {
        public int type;
        [CCode (cname = "xany.window")]
        public ulong window;
        // the window that a substructure event is about
        [CCode (cname = "xmap.window")]
        public ulong subject;
        [CCode (cname = "xkey.keycode")]
        public uint keycode;
        [CCode (cname = "xkey.state")]
        public uint key_modifiers;
        [CCode (cname = "xbutton.button")]
        public uint button;
        [CCode (cname = "xbutton.x_root")]
        public int x_root;
        [CCode (cname = "xbutton.y_root")]
        public int y_root;
        [CCode (cname = "xproperty.atom")]
        public ulong property;
        [CCode (cname = "xcookie.extension")]
        public int cookie_extension;
        [CCode (cname = "xcookie.evtype")]
        public int cookie_type;
        [CCode (cname = "xcookie.data")]
        public void* cookie_data;
        [CCode (cname = "xclient.window")]
        public ulong client_window;
        [CCode (cname = "xclient.message_type")]
        public ulong client_type;
        [CCode (cname = "xclient.format")]
        public int client_format;
        [CCode (cname = "xclient.data.l")]
        public long client_data[5];
    }

    [CCode (cname = "XSetWindowAttributes", has_type_id = false, has_destroy_function = false, has_copy_function = false)]
    public struct SetWindowAttributes {
        public long event_mask;
        public int override_redirect;
    }

    [CCode (cname = "XWindowChanges", has_type_id = false, has_destroy_function = false, has_copy_function = false)]
    public struct WindowChanges {
        public int x;
        public int y;
        public int width;
        public int height;
        public ulong sibling;
        public int stack_mode;
    }

    [CCode (cname = "XineramaScreenInfo", cheader_filename = "X11/extensions/Xinerama.h", has_type_id = false, has_destroy_function = false, has_copy_function = false)]
    public struct ScreenInfo {
        public int screen_number;
        public short x_org;
        public short y_org;
        public short width;
        public short height;
    }

    [CCode (cname = "XkbStateRec", has_type_id = false, has_destroy_function = false, has_copy_function = false)]
    public struct KeyboardState {
        public uchar group;
    }

    [CCode (cname = "XkbDescRec", has_type_id = false, has_destroy_function = false, has_copy_function = false)]
    public struct KeyboardDescription {
        // only after get_keyboard_names()
        [CCode (cname = "names->symbols")]
        public ulong symbols;
    }

    [CCode (cname = "XIEventMask", cheader_filename = "X11/extensions/XInput2.h", has_type_id = false, has_destroy_function = false, has_copy_function = false)]
    public struct InputMask {
        public int deviceid;
        public int mask_len;
        [CCode (cname = "mask")]
        public uint8* bits;
    }

    [CCode (cname = "XIRawEvent", cheader_filename = "X11/extensions/XInput2.h", has_type_id = false, has_destroy_function = false, has_copy_function = false)]
    public struct RawInput {
        public int evtype;
        public ulong time;
        public int detail;
    }

    [CCode (cname = "XErrorHandler", has_target = false)]
    public delegate int ErrorHandler(Display display, void* error);

    // ── connection ──────────────────────────────────────────
    [CCode (cname = "XSetErrorHandler")]
    public void set_error_handler(ErrorHandler handler);
    [CCode (cname = "XDefaultRootWindow")]
    public ulong default_root_window(Display display);
    [CCode (cname = "XConnectionNumber")]
    public int connection_number(Display display);
    [CCode (cname = "XPending")]
    public int pending(Display display);
    [CCode (cname = "XNextEvent")]
    public int next_event(Display display, out Event event);
    [CCode (cname = "XFlush")]
    public int flush(Display display);
    [CCode (cname = "XSync")]
    public int sync(Display display, bool discard);
    [CCode (cname = "XFree")]
    public int free(void* data);
    [CCode (cname = "XInternAtom")]
    public ulong intern_atom(Display display, string name, bool only_if_exists);
    [CCode (cname = "XGetAtomName")]
    public char* get_atom_name(Display display, ulong atom);
    [CCode (cname = "XineramaQueryScreens", cheader_filename = "X11/extensions/Xinerama.h")]
    public ScreenInfo* query_screens(Display display, out int count);

    // ── windows ─────────────────────────────────────────────
    [CCode (cname = "XGetWindowProperty")]
    public int get_window_property(
        Display display,
        ulong window,
        ulong property,
        long offset,
        long length,
        bool delete,
        ulong requested_type,
        out ulong type,
        out int format,
        out ulong count,
        out ulong bytes_left,
        out uint8* data
    );
    [CCode (cname = "XGetGeometry")]
    public int get_geometry(
        Display display,
        ulong window,
        out ulong root,
        out int x,
        out int y,
        out uint width,
        out uint height,
        out uint border,
        out uint depth
    );
    [CCode (cname = "XTranslateCoordinates")]
    public int translate_coordinates(
        Display display,
        ulong from,
        ulong to,
        int from_x,
        int from_y,
        out int to_x,
        out int to_y,
        out ulong child
    );
    [CCode (cname = "XQueryTree")]
    public int query_tree(
        Display display,
        ulong window,
        out ulong root,
        out ulong parent,
        out ulong* children,
        out uint count
    );
    [CCode (cname = "XSelectInput")]
    public int select_input(Display display, ulong window, long mask);
    [CCode (cname = "XSendEvent")]
    public int send_event(Display display, ulong window, bool propagate, long mask, Event* event);
    [CCode (cname = "XCreateWindow")]
    public ulong create_window(
        Display display,
        ulong parent,
        int x,
        int y,
        uint width,
        uint height,
        uint border,
        int depth,
        uint window_class,
        void* visual,
        ulong mask,
        SetWindowAttributes* attributes
    );
    [CCode (cname = "XConfigureWindow")]
    public int configure_window(Display display, ulong window, uint mask, WindowChanges* changes);
    [CCode (cname = "XMapWindow")]
    public int map_window(Display display, ulong window);
    [CCode (cname = "XUnmapWindow")]
    public int unmap_window(Display display, ulong window);
    [CCode (cname = "XDestroyWindow")]
    public int destroy_window(Display display, ulong window);
    [CCode (cname = "XCreateFontCursor")]
    public ulong create_font_cursor(Display display, uint shape);
    [CCode (cname = "XDefineCursor")]
    public int define_cursor(Display display, ulong window, ulong cursor);

    // ── pointer and keyboard ────────────────────────────────
    [CCode (cname = "XQueryPointer")]
    public int query_pointer(
        Display display,
        ulong window,
        out ulong root,
        out ulong child,
        out int root_x,
        out int root_y,
        out int window_x,
        out int window_y,
        out uint mask
    );
    [CCode (cname = "XUngrabPointer")]
    public int ungrab_pointer(Display display, ulong time);
    [CCode (cname = "XKeysymToKeycode")]
    public uchar keysym_to_keycode(Display display, ulong keysym);
    [CCode (cname = "XQueryKeymap")]
    public int query_keymap(Display display, [CCode (array_length = false, type = "char*")] uint8[] keys);
    [CCode (cname = "XGrabKey")]
    public int grab_key(
        Display display,
        int keycode,
        uint modifiers,
        ulong window,
        bool owner_events,
        int pointer_mode,
        int keyboard_mode
    );
    [CCode (cname = "XGrabKeyboard")]
    public int grab_keyboard(
        Display display,
        ulong window,
        bool owner_events,
        int pointer_mode,
        int keyboard_mode,
        ulong time
    );
    [CCode (cname = "XUngrabKeyboard")]
    public int ungrab_keyboard(Display display, ulong time);
    [CCode (cname = "XkbSetDetectableAutoRepeat")]
    public bool set_detectable_auto_repeat(Display display, bool detectable, out bool supported);
    [CCode (cname = "XkbGetState")]
    public int get_keyboard_state(Display display, uint device, out KeyboardState state);
    [CCode (cname = "XkbGetMap")]
    public KeyboardDescription* get_keyboard_map(Display display, uint parts, uint device);
    [CCode (cname = "XkbGetNames")]
    public int get_keyboard_names(Display display, uint parts, KeyboardDescription* description);
    [CCode (cname = "XkbFreeKeyboard")]
    public void free_keyboard(KeyboardDescription* description, uint parts, bool free_all);
    [CCode (cname = "XkbLockGroup")]
    public bool lock_group(Display display, uint device, uint group);

    // ── XInput2 ─────────────────────────────────────────────
    [CCode (cname = "XQueryExtension")]
    public bool query_extension(Display display, string name, out int opcode, out int event, out int error);
    [CCode (cname = "XIQueryVersion", cheader_filename = "X11/extensions/XInput2.h")]
    public int query_input_version(Display display, ref int major, ref int minor);
    [CCode (cname = "XISelectEvents", cheader_filename = "X11/extensions/XInput2.h")]
    public int select_input_events(Display display, ulong window, InputMask* masks, int count);
    // both take the cookie of an event
    [CCode (cname = "XGetEventData")]
    public bool get_event_data(Display display, void* cookie);
    [CCode (cname = "XFreeEventData")]
    public void free_event_data(Display display, void* cookie);

    // ── constants ───────────────────────────────────────────
    [CCode (cname = "KeyPress")]
    public const int KEY_PRESS;
    [CCode (cname = "KeyRelease")]
    public const int KEY_RELEASE;
    [CCode (cname = "ButtonPress")]
    public const int BUTTON_PRESS;
    [CCode (cname = "MotionNotify")]
    public const int MOTION;
    [CCode (cname = "DestroyNotify")]
    public const int DESTROY;
    [CCode (cname = "UnmapNotify")]
    public const int UNMAP;
    [CCode (cname = "MapNotify")]
    public const int MAP;
    [CCode (cname = "ReparentNotify")]
    public const int REPARENT;
    [CCode (cname = "ConfigureNotify")]
    public const int CONFIGURE;
    [CCode (cname = "PropertyNotify")]
    public const int PROPERTY;
    [CCode (cname = "ClientMessage")]
    public const int CLIENT_MESSAGE;

    [CCode (cname = "GenericEvent")]
    public const int GENERIC_EVENT;
    [CCode (cname = "XI_RawKeyPress", cheader_filename = "X11/extensions/XInput2.h")]
    public const int RAW_KEY_PRESS;
    [CCode (cname = "XI_RawKeyRelease", cheader_filename = "X11/extensions/XInput2.h")]
    public const int RAW_KEY_RELEASE;
    [CCode (cname = "XI_RawButtonPress", cheader_filename = "X11/extensions/XInput2.h")]
    public const int RAW_BUTTON_PRESS;
    [CCode (cname = "XIAllMasterDevices", cheader_filename = "X11/extensions/XInput2.h")]
    public const int ALL_MASTER_DEVICES;

    [CCode (cname = "ButtonPressMask")]
    public const long BUTTON_PRESS_MASK;
    [CCode (cname = "PointerMotionMask")]
    public const long POINTER_MOTION_MASK;
    [CCode (cname = "StructureNotifyMask")]
    public const long STRUCTURE_MASK;
    [CCode (cname = "SubstructureNotifyMask")]
    public const long SUBSTRUCTURE_MASK;
    [CCode (cname = "SubstructureRedirectMask")]
    public const long REDIRECT_MASK;
    [CCode (cname = "PropertyChangeMask")]
    public const long PROPERTY_MASK;

    [CCode (cname = "CWX")]
    public const uint CW_X;
    [CCode (cname = "CWY")]
    public const uint CW_Y;
    [CCode (cname = "CWWidth")]
    public const uint CW_WIDTH;
    [CCode (cname = "CWHeight")]
    public const uint CW_HEIGHT;
    [CCode (cname = "CWSibling")]
    public const uint CW_SIBLING;
    [CCode (cname = "CWStackMode")]
    public const uint CW_STACK_MODE;
    [CCode (cname = "CWOverrideRedirect")]
    public const ulong CW_OVERRIDE_REDIRECT;
    [CCode (cname = "CWEventMask")]
    public const ulong CW_EVENT_MASK;
    [CCode (cname = "InputOnly")]
    public const uint INPUT_ONLY;
    [CCode (cname = "Below")]
    public const int BELOW;

    [CCode (cname = "GrabSuccess")]
    public const int GRAB_SUCCESS;
    [CCode (cname = "GrabModeAsync")]
    public const int GRAB_ASYNC;
    [CCode (cname = "XkbSymbolsNameMask")]
    public const uint SYMBOLS_NAME;
    [CCode (cname = "XkbUseCoreKbd")]
    public const uint CORE_KEYBOARD;
    [CCode (cname = "ShiftMask")]
    public const uint SHIFT_MASK;
    [CCode (cname = "LockMask")]
    public const uint LOCK_MASK;
    [CCode (cname = "Mod1Mask")]
    public const uint MOD1_MASK;
    [CCode (cname = "Mod2Mask")]
    public const uint MOD2_MASK;
    [CCode (cname = "Mod4Mask")]
    public const uint MOD4_MASK;
    [CCode (cname = "Button1Mask")]
    public const uint BUTTON1_MASK;
}

[CCode (cheader_filename = "sys/file.h")]
namespace FileLock {
    [CCode (cname = "flock")]
    public int flock(int fd, int operation);
    [CCode (cname = "LOCK_EX")]
    public const int EXCLUSIVE;
    [CCode (cname = "LOCK_NB")]
    public const int NON_BLOCKING;
}
