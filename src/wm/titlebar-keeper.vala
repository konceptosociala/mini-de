/* Keeps titlebars reachable: a window whose top ended up under the panel
   or above the screen is moved below it. */
class TitlebarKeeper {
    const string[] SKIPPED_TYPES = {
        X11.WindowType.DOCK,
        X11.WindowType.DESKTOP,
        X11.WindowType.SPLASH,
        X11.WindowType.NOTIFICATION
    };
    const string[] SKIPPED_STATES = {
        X11.WindowState.FULLSCREEN,
        X11.WindowState.HIDDEN,
        X11.WindowState.MAXIMIZED_VERTICALLY
    };
    const int PANEL_GAP = 8;        // a panel may hang this far below the top of the screen, px

    unowned X11.Connection connection;
    CorrectionLimit limit = new CorrectionLimit();

    public TitlebarKeeper(X11.Connection connection) {
        this.connection = connection;
    }

    public void check() {
        var monitors = connection.monitors();
        if (monitors.length == 0) {
            return;
        }
        var client_ids = connection.client_ids();
        var tops = usable_tops(monitors, client_ids);
        foreach (ulong id in client_ids) {
            correct(connection.window(id), monitors, tops);
        }
        limit.forget_all_except(client_ids);
    }

    /* The topmost line of every monitor that is not covered by a panel. */
    int[] usable_tops(Rect[] monitors, ulong[] client_ids) {
        int[] tops = {};
        foreach (Rect monitor in monitors) {
            tops += monitor.y;
        }
        foreach (ulong id in client_ids) {
            var window = connection.window(id);
            if (!window.has_type({ X11.WindowType.DOCK }) || window.reserved_top() == 0) {
                continue;
            }
            Rect? panel = window.screen_bounds();
            if (panel == null) {
                continue;
            }
            int index = monitor_with_most_of(panel, monitors);
            if (panel.y <= monitors[index].y + PANEL_GAP) {
                tops[index] = int.max(tops[index], panel.bottom);
            }
        }
        return tops;
    }

    void correct(X11.Window window, Rect[] monitors, int[] tops) {
        if (window.has_type(SKIPPED_TYPES) || window.has_state(SKIPPED_STATES)) {
            return;
        }
        Rect? frame = window.frame_bounds();
        if (frame == null) {
            return;
        }
        int shadow = window.shadow_extents().top;
        Rect visible = {
            frame.x,
            frame.y + shadow,
            frame.width,
            frame.height - shadow
        };
        int index = monitor_with_most_of(visible, monitors);
        if (monitors[index].shared_area(visible) == 0) {
            index = nearest_monitor(visible, monitors);
        }
        if (visible.y < tops[index] && limit.allows(window.id)) {
            window.move_frame(frame.x, tops[index] - shadow);
        }
    }

    static int monitor_with_most_of(Rect rect, Rect[] monitors) {
        int best = 0;
        for (int index = 1; index < monitors.length; index++) {
            if (monitors[index].shared_area(rect) > monitors[best].shared_area(rect)) {
                best = index;
            }
        }
        return best;
    }

    static int nearest_monitor(Rect rect, Rect[] monitors) {
        int best = 0;
        int best_distance = int.MAX;
        for (int index = 0; index < monitors.length; index++) {
            Rect monitor = monitors[index];
            int horizontal = (monitor.x + monitor.width / 2 - rect.x - rect.width / 2).abs();
            int vertical = (monitor.y - rect.y).abs();
            if (horizontal + vertical < best_distance) {
                best = index;
                best_distance = horizontal + vertical;
            }
        }
        return best;
    }
}

/* Never fight with a program that moves its window back. */
class CorrectionLimit {
    const int MAX_CORRECTIONS = 3;
    const int64 PERIOD = 5 * TimeSpan.SECOND;

    [Compact]
    class History {
        public int64[] times = {};
    }

    HashTable<void*, History> histories = new HashTable<void*, History>(direct_hash, direct_equal);

    /* Whether the window may be corrected now; counts this correction. */
    public bool allows(ulong window_id) {
        int64 now = get_monotonic_time();
        var recent = new History();
        unowned History? known = histories[(void*) window_id];
        if (known != null) {
            foreach (int64 time in known.times) {
                if (now - time < PERIOD) {
                    recent.times += time;
                }
            }
        }
        if (recent.times.length >= MAX_CORRECTIONS) {
            return false;
        }
        recent.times += now;
        histories[(void*) window_id] = (owned) recent;
        return true;
    }

    public void forget_all_except(ulong[] window_ids) {
        histories.foreach_remove((id, history) => !((ulong) id in window_ids));
    }
}
