namespace X11 {
    public class Window {
        const ulong ON_ALL_DESKTOPS = 0xFFFFFFFFU;
        public const long PROPERTY_LENGTH = 1024;

        unowned Connection connection;
        public ulong id;

        public Window(Connection connection, ulong id) {
            this.connection = connection;
            this.id = id;
        }

        // ── properties ──────────────────────────────────────

        /* Data of a property to be freed with Xl.free(), null if there is none of this format. */
        uint8* read_property(string name, int wanted_format, long length, out ulong count) {
            ulong type, bytes_left;
            int format;
            uint8* data;
            int failed = Xl.get_window_property(
                connection.display,
                id,
                connection.atom(name),
                0,
                length,
                false,
                0,
                out type,
                out format,
                out count,
                out bytes_left,
                out data
            );
            if (failed != 0 || data == null) {
                return null;
            }
            if (format != wanted_format) {
                Xl.free(data);
                return null;
            }
            return data;
        }

        /* Empty if there is no such property. */
        public ulong[] read_numbers(string name, long length = PROPERTY_LENGTH) {
            ulong count;
            uint8* data = read_property(name, 32, length, out count);
            if (data == null) {
                return {};
            }
            var numbers = new ulong[count];
            for (ulong index = 0; index < count; index++) {
                numbers[index] = ((ulong*) data)[index];
            }
            Xl.free(data);
            return numbers;
        }

        /* 0 if there is no such number. */
        public ulong read_number(string name, int index = 0) {
            var numbers = read_numbers(name);
            return index < numbers.length ? numbers[index] : 0;
        }

        /* Strings separated by zero bytes. */
        public string[] read_strings(string name) {
            ulong count;
            uint8* data = read_property(name, 8, PROPERTY_LENGTH, out count);
            if (data == null) {
                return {};
            }
            string[] strings = {};
            for (ulong start = 0; start < count;) {
                // Xlib always adds a zero byte after the data
                unowned string text = (string) (data + start);
                strings += text.make_valid();
                start += text.length + 1;
            }
            Xl.free(data);
            return strings;
        }

        /* Whether a list of atoms has any of these names. */
        public bool list_has_any(string property, string[] names) {
            foreach (ulong atom in read_numbers(property)) {
                foreach (unowned string name in names) {
                    if (atom == connection.atom(name)) {
                        return true;
                    }
                }
            }
            return false;
        }

        // ── what the window is ──────────────────────────────

        public bool has_type(string[] types) {
            return list_has_any("_NET_WM_WINDOW_TYPE", types);
        }

        public bool has_state(string[] states) {
            return list_has_any("_NET_WM_STATE", states);
        }

        public bool allows(string action) {
            return list_has_any("_NET_WM_ALLOWED_ACTIONS", { action });
        }

        public bool is_on_desktop(ulong desktop) {
            var own = read_numbers("_NET_WM_DESKTOP");
            return own.length == 0
                || own[0] == desktop
                || own[0] == ON_ALL_DESKTOPS
                || own[0] == ulong.MAX;
        }

        public string title() {
            foreach (unowned string property in new string[] { "_NET_WM_NAME", "WM_NAME" }) {
                var strings = read_strings(property);
                if (strings.length > 0 && strings[0] != "") {
                    return strings[0];
                }
            }
            return "";
        }

        /* Height that a panel reserves at the top of the screen. */
        public int reserved_top() {
            foreach (unowned string property in new string[] { "_NET_WM_STRUT_PARTIAL", "_NET_WM_STRUT" }) {
                var strut = read_numbers(property);
                if (strut.length >= 4) {
                    return (int) strut[2];
                }
            }
            return 0;
        }

        // ── geometry ────────────────────────────────────────

        /* Position in the parent, with the border; null if the window is gone. */
        public Rect? bounds() {
            ulong root_id;
            int x, y;
            uint width, height, border, depth;
            int found = Xl.get_geometry(
                connection.display,
                id,
                out root_id,
                out x,
                out y,
                out width,
                out height,
                out border,
                out depth
            );
            if (found == 0) {
                return null;
            }
            return Rect() {
                x = x,
                y = y,
                width = (int) (width + 2 * border),
                height = (int) (height + 2 * border)
            };
        }

        /* Position of the contents on the screen; null if the window is gone. */
        public Rect? screen_bounds() {
            Rect? bounds = this.bounds();
            if (bounds == null) {
                return null;
            }
            int x, y;
            ulong child;
            int found = Xl.translate_coordinates(
                connection.display,
                id,
                connection.root.id,
                0,
                0,
                out x,
                out y,
                out child
            );
            if (found == 0) {
                return null;
            }
            return Rect() {
                x = x,
                y = y,
                width = bounds.width,
                height = bounds.height
            };
        }

        /* Position on the screen with the titlebar and borders; null if the window is gone. */
        public Rect? frame_bounds() {
            Rect? contents = screen_bounds();
            if (contents == null) {
                return null;
            }
            var frame = frame_extents();
            return Rect() {
                x = contents.x - frame.left,
                y = contents.y - frame.top,
                width = contents.width + frame.left + frame.right,
                height = contents.height + frame.top + frame.bottom
            };
        }

        public FrameExtents frame_extents() {
            return read_extents("_NET_FRAME_EXTENTS");
        }

        /* Invisible margin around a window that draws its own decorations. */
        public FrameExtents shadow_extents() {
            return read_extents("_GTK_FRAME_EXTENTS");
        }

        FrameExtents read_extents(string property) {
            var numbers = read_numbers(property);
            if (numbers.length < 4) {
                return {};
            }
            return FrameExtents() {
                left = (int) numbers[0],
                right = (int) numbers[1],
                top = (int) numbers[2],
                bottom = (int) numbers[3]
            };
        }

        // ── window tree ─────────────────────────────────────

        /* Children bottom to top; false if the window is gone. */
        public bool query_tree(out ulong parent, out ulong[] children) {
            ulong root_id;
            ulong* list;
            uint count;
            children = {};
            if (Xl.query_tree(connection.display, id, out root_id, out parent, out list, out count) == 0) {
                return false;
            }
            if (list == null) {
                return true;
            }
            children = new ulong[count];
            for (uint index = 0; index < count; index++) {
                children[index] = list[index];
            }
            Xl.free(list);
            return true;
        }

        /* The frame that the window manager put this window into; null if there is none. */
        public Window? frame() {
            const int MAX_DEPTH = 8;
            ulong current = id;
            for (int depth = 0; depth < MAX_DEPTH; depth++) {
                ulong parent;
                ulong[] children;
                bool found = connection.window(current).query_tree(out parent, out children);
                if (!found || parent == 0) {
                    return null;
                }
                if (parent == connection.root.id) {
                    return connection.window(current);
                }
                current = parent;
            }
            return null;
        }

        // ── changing windows of this program ────────────────

        public void select_events(long events) {
            Xl.select_input(connection.display, id, events);
        }

        public void set_bounds(Rect bounds) {
            Xl.WindowChanges changes = {};
            changes.x = bounds.x;
            changes.y = bounds.y;
            changes.width = bounds.width;
            changes.height = bounds.height;
            uint mask = Xl.CW_X | Xl.CW_Y | Xl.CW_WIDTH | Xl.CW_HEIGHT;
            Xl.configure_window(connection.display, id, mask, &changes);
        }

        public void stack_below(Window sibling) {
            Xl.WindowChanges changes = {};
            changes.sibling = sibling.id;
            changes.stack_mode = Xl.BELOW;
            Xl.configure_window(connection.display, id, Xl.CW_SIBLING | Xl.CW_STACK_MODE, &changes);
        }

        public void set_cursor(uint shape) {
            Xl.define_cursor(connection.display, id, connection.cursor(shape));
        }

        public void map() {
            Xl.map_window(connection.display, id);
        }

        public void unmap() {
            Xl.unmap_window(connection.display, id);
        }

        public void destroy() {
            Xl.destroy_window(connection.display, id);
        }

        // ── requests to the window manager ──────────────────

        void request(string message, long[] data) {
            Xl.Event event = {};
            event.type = Xl.CLIENT_MESSAGE;
            event.client_window = id;
            event.client_type = connection.atom(message);
            event.client_format = 32;
            for (int index = 0; index < data.length; index++) {
                event.client_data[index] = data[index];
            }
            long mask = Xl.SUBSTRUCTURE_MASK | Xl.REDIRECT_MASK;
            Xl.send_event(connection.display, connection.root.id, false, mask, &event);
            connection.sync();
        }

        const long FROM_PAGER = 2;

        public void activate() {
            request("_NET_ACTIVE_WINDOW", { FROM_PAGER });
        }

        public void unmaximize() {
            const long REMOVE = 0;
            request("_NET_WM_STATE", {
                REMOVE,
                (long) connection.atom(WindowState.MAXIMIZED_HORIZONTALLY),
                (long) connection.atom(WindowState.MAXIMIZED_VERTICALLY),
                FROM_PAGER
            });
        }

        /* Moves the top left corner of the frame there. */
        public void move_frame(int x, int y) {
            const long NORTH_WEST = 1;
            const long HAS_X = 1 << 8;
            const long HAS_Y = 1 << 9;
            request("_NET_MOVERESIZE_WINDOW", {
                NORTH_WEST | HAS_X | HAS_Y | FROM_PAGER << 12,
                x,
                y
            });
        }

        /* Lets the window manager move or resize the window while the left button is held. */
        public void start_drag(int x, int y, DragKind kind) {
            const ulong REACTION_TIME = 20000;      // microseconds
            request_drag(x, y, kind);
            Thread.usleep(REACTION_TIME);
            if (!connection.pointer().left_button) {
                request_drag(x, y, DragKind.CANCEL);        // released meanwhile
            }
        }

        void request_drag(int x, int y, DragKind kind) {
            const long LEFT_BUTTON = 1;
            request("_NET_WM_MOVERESIZE", { x, y, kind, LEFT_BUTTON, FROM_PAGER });
        }
    }
}
