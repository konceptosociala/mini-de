namespace X11 {
    public errordomain Error {
        NO_DISPLAY,
        NO_RAW_INPUT,
        KEY_TAKEN
    }

    public delegate void EventHandler(Xl.Event event);

    /* A connection to the X server. Failed requests are ignored: windows may close at any moment. */
    public class Connection {
        static int failed_requests = 0;

        internal Xl.Display display;
        HashTable<string, ulong?> atoms = new HashTable<string, ulong?>(str_hash, str_equal);
        HashTable<uint, ulong?> cursors = new HashTable<uint, ulong?>(direct_hash, direct_equal);
        EventSource? event_source = null;

        public Window root;

        public Connection() throws Error {
            display = new Xl.Display();
            if (display == null) {
                throw new Error.NO_DISPLAY("cannot open the display");
            }
            Xl.set_error_handler((display, error) => {
                failed_requests++;
                return 0;
            });
            root = new Window(this, Xl.default_root_window(display));
        }

        internal int file_descriptor {
            get { return Xl.connection_number(display); }
        }

        /* Waits until the server has done everything asked so far. */
        public void sync() {
            Xl.sync(display, false);
        }

        public void flush() {
            Xl.flush(display);
        }

        public ulong atom(string name) {
            ulong? known = atoms[name];
            if (known == null) {
                known = Xl.intern_atom(display, name, false);
                atoms[name] = known;
            }
            return known;
        }

        // ── events ──────────────────────────────────────────

        /* Calls the handler from the main loop for every event. */
        public void listen(owned EventHandler handler) {
            event_source = new EventSource(this, (owned) handler);
            event_source.attach(null);
        }

        internal bool has_events() {
            return Xl.pending(display) > 0;
        }

        internal Xl.Event next_event() {
            Xl.Event event;
            Xl.next_event(display, out event);
            return event;
        }

        // ── desktop ─────────────────────────────────────────

        public Window window(ulong id) {
            return new Window(this, id);
        }

        /* Ids of all windows of programs, oldest first. */
        public ulong[] client_ids() {
            return root.read_numbers("_NET_CLIENT_LIST");
        }

        /* The same windows, bottom to top. */
        public ulong[] stacked_client_ids() {
            return root.read_numbers("_NET_CLIENT_LIST_STACKING");
        }

        /* 0 if no window is active. */
        public ulong active_id() {
            return root.read_number("_NET_ACTIVE_WINDOW");
        }

        public ulong current_desktop() {
            return root.read_number("_NET_CURRENT_DESKTOP");
        }

        public Rect[] monitors() {
            Rect[] monitors = {};
            int count;
            Xl.ScreenInfo* screens = Xl.query_screens(display, out count);
            if (screens == null) {
                return monitors;
            }
            for (int index = 0; index < count; index++) {
                Rect monitor = {
                    screens[index].x_org,
                    screens[index].y_org,
                    screens[index].width,
                    screens[index].height
                };
                monitors += monitor;
            }
            Xl.free(screens);
            return monitors;
        }

        public ulong cursor(uint shape) {
            ulong? known = cursors[shape];
            if (known == null) {
                known = Xl.create_font_cursor(display, shape);
                cursors[shape] = known;
            }
            return known;
        }

        /* An invisible window that only receives events of the pointer. */
        public Window create_input_window(long events) {
            Xl.SetWindowAttributes attributes = {};
            attributes.override_redirect = 1;
            attributes.event_mask = events;
            ulong id = Xl.create_window(
                display,
                root.id,
                -100,
                -100,
                1,
                1,
                0,
                0,
                Xl.INPUT_ONLY,
                null,
                Xl.CW_OVERRIDE_REDIRECT | Xl.CW_EVENT_MASK,
                &attributes
            );
            return window(id);
        }

        // ── pointer ─────────────────────────────────────────

        public Pointer pointer() {
            Pointer pointer = {};
            ulong root_id, child;
            int window_x, window_y;
            Xl.query_pointer(
                display,
                root.id,
                out root_id,
                out child,
                out pointer.x,
                out pointer.y,
                out window_x,
                out window_y,
                out pointer.mask
            );
            return pointer;
        }

        public void release_pointer() {
            Xl.ungrab_pointer(display, 0);
        }

        // ── keyboard ────────────────────────────────────────

        /* 0 if the keyboard has no such key. */
        public uint keycode(ulong keysym) {
            return Xl.keysym_to_keycode(display, keysym);
        }

        public bool any_key_down(uint[] keycodes) {
            uint8 keys[32];
            Xl.query_keymap(display, keys);
            foreach (uint keycode in keycodes) {
                if ((keys[keycode >> 3] & (1 << (keycode & 7))) != 0) {
                    return true;
                }
            }
            return false;
        }

        /* Holding a key sends only presses, without releases in between. */
        public void merge_key_repeats() {
            bool supported;
            Xl.set_detectable_auto_repeat(display, true, out supported);
        }

        /* Receive this key with the modifiers, also with Shift, whatever Caps Lock and Num Lock are. */
        public void grab_key(uint keycode, uint modifiers) throws Error {
            sync();
            int failed_before = failed_requests;
            foreach (uint locks in new uint[] {
                0,
                Xl.LOCK_MASK,
                Xl.MOD2_MASK,
                Xl.LOCK_MASK | Xl.MOD2_MASK
            }) {
                foreach (uint shift in new uint[] { 0, Xl.SHIFT_MASK }) {
                    Xl.grab_key(
                        display,
                        (int) keycode,
                        modifiers | shift | locks,
                        root.id,
                        false,
                        Xl.GRAB_ASYNC,
                        Xl.GRAB_ASYNC
                    );
                }
            }
            sync();
            if (failed_requests != failed_before) {
                throw new Error.KEY_TAKEN("the key is already taken by another program");
            }
        }

        /* Receive the whole keyboard until release_keyboard(); false if another program has it. */
        public bool grab_keyboard() {
            int result = Xl.grab_keyboard(
                display,
                root.id,
                false,
                Xl.GRAB_ASYNC,
                Xl.GRAB_ASYNC,
                0
            );
            sync();
            return result == Xl.GRAB_SUCCESS;
        }

        public void release_keyboard() {
            Xl.ungrab_keyboard(display, 0);
            sync();
        }

        // ── keyboard layouts ────────────────────────────────

        public uint current_layout() {
            Xl.KeyboardState state;
            Xl.get_keyboard_state(display, Xl.CORE_KEYBOARD, out state);
            return state.group;
        }

        public void set_layout(uint layout) {
            Xl.lock_group(display, Xl.CORE_KEYBOARD, layout);
            sync();
        }

        /* Names of the layouts, such as "us" and "ua". They are taken from the keymap in use:
           the property _XKB_RULES_NAMES is overwritten whenever a device with any keys is
           connected, even headphones. */
        public string[] layout_names() {
            return KeymapSymbols.layouts(keymap_symbols());
        }

        string keymap_symbols() {
            var description = Xl.get_keyboard_map(display, 0, Xl.CORE_KEYBOARD);
            if (description == null) {
                return "";
            }
            string symbols = "";
            if (Xl.get_keyboard_names(display, Xl.SYMBOLS_NAME, description) == 0) {
                symbols = atom_name(description->symbols);
            }
            Xl.free_keyboard(description, 0, true);
            return symbols;
        }

        string atom_name(ulong atom) {
            char* text = atom != 0 ? Xl.get_atom_name(display, atom) : null;
            if (text == null) {
                return "";
            }
            string name = (string) text;
            Xl.free(text);
            return name;
        }
    }

    /* Wakes the main loop also for events that Xlib has already read from the connection. */
    class EventSource : Source {
        public unowned Connection connection;
        public EventHandler handler;

        public EventSource(Connection connection, owned EventHandler handler) {
            this.connection = connection;
            this.handler = (owned) handler;
            add_unix_fd(connection.file_descriptor, IOCondition.IN | IOCondition.HUP);
        }

        protected override bool prepare(out int timeout) {
            timeout = -1;
            return connection.has_events();
        }

        protected override bool check() {
            return connection.has_events();
        }

        protected override bool dispatch(SourceFunc? callback) {
            while (connection.has_events()) {
                handler(connection.next_event());
            }
            return Source.CONTINUE;
        }
    }
}
