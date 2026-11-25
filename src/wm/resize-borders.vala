/* Invisible resize borders around windows, like in GNOME: Openbox itself only reacts
   on the 1 px frame. */
class ResizeBorders {
    const string[] SKIPPED_TYPES = {
        X11.WindowType.DOCK,
        X11.WindowType.DESKTOP,
        X11.WindowType.SPLASH,
        X11.WindowType.NOTIFICATION
    };
    const string[] SKIPPED_STATES = {
        X11.WindowState.FULLSCREEN,
        X11.WindowState.HIDDEN,
        X11.WindowState.SHADED,
        X11.WindowState.MAXIMIZED_VERTICALLY,
        X11.WindowState.MAXIMIZED_HORIZONTALLY
    };

    unowned X11.Connection connection;
    // by window of the program
    HashTable<void*, ResizeBorder> borders =
        new HashTable<void*, ResizeBorder>(direct_hash, direct_equal);

    public ResizeBorders(X11.Connection connection) {
        this.connection = connection;
    }

    public ResizeBorder? find_by_ring(ulong ring_id) {
        return borders.find((client_id, border) => border.ring_id == ring_id);
    }

    public void update() {
        var client_ids = connection.client_ids();
        remove_all_except(client_ids);

        ulong parent;
        ulong[] stacking;
        if (!connection.root.query_tree(out parent, out stacking)) {
            return;
        }
        ulong desktop = connection.current_desktop();
        foreach (ulong id in client_ids) {
            update_window(connection.window(id), desktop, stacking);
        }
        connection.flush();
    }

    void update_window(X11.Window client, ulong desktop, ulong[] stacking) {
        ResizeBorder? border = borders[(void*) client.id];
        var frame = is_resizable(client, desktop) ? client.frame() : null;
        Rect? bounds = frame != null ? frame.bounds() : null;
        if (bounds == null) {
            if (border != null) {
                border.hide();
            }
            return;
        }
        if (border == null) {
            border = new ResizeBorder(connection, client);
            borders[(void*) client.id] = border;
            client.select_events(Xl.PROPERTY_MASK);     // to learn about changes of its state
        }
        border.surround(frame, bounds, stacking);
    }

    void remove_all_except(ulong[] client_ids) {
        borders.foreach_remove((id, border) => {
            if ((ulong) id in client_ids) {
                return false;
            }
            border.destroy();
            return true;
        });
    }

    static bool is_resizable(X11.Window window, ulong desktop) {
        return window.allows(X11.WindowAction.RESIZE)
            && !window.has_type(SKIPPED_TYPES)
            && !window.has_state(SKIPPED_STATES)
            && window.is_on_desktop(desktop);
    }
}
