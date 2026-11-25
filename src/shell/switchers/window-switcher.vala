/* Windows on Alt+Tab with large icons, most recently used first. Tab, Shift+Tab and arrows
   move, releasing Alt or a click switches, Esc cancels. */
class WindowSwitcher {
    const uint SHOW_DELAY = 110;            // ms: a quick Alt+Tab switches without showing anything
    const uint WATCHDOG_INTERVAL = 400;     // ms
    const int SPACING = 4;                  // px
    const int SCREEN_MARGIN = 160;          // px
    const string[] SKIPPED_TYPES = {
        X11.WindowType.DOCK,
        X11.WindowType.DESKTOP,
        X11.WindowType.SPLASH,
        X11.WindowType.NOTIFICATION
    };
    const string CSS = """
        @define-color md_panel #282828;
        @define-color md_border #504945;
        @define-color md_fg #ebdbb2;
        @define-color md_dim #928374;
        @define-color md_accent #fabd2f;
        #alttab {
            background: transparent;
        }
        #alttab #frame {
            background: alpha(@md_panel, 0.97);
            border: 1px solid @md_border;
            border-radius: 16px;
            padding: 14px;
        }
        #alttab label {
            color: @md_fg;
            font: 14px "Inter";
        }
        #alttab #title {
            color: @md_dim;
            font: 13px "Inter";
            padding: 6px 10px 2px 10px;
        }
        #alttab .cell {
            border-radius: 12px;
            padding: 12px 8px;
            border: 2px solid transparent;
        }
        #alttab .cell.selected {
            background: alpha(@md_accent, 0.22);
            border-color: @md_accent;
        }
        #alttab .cell.minimized image {
            opacity: 0.45;
        }
    """;

    X11.Connection connection;
    uint tab_key;
    uint escape_key;
    uint enter_key;
    uint left_key;
    uint right_key;
    uint up_key;
    uint down_key;

    AppCatalog catalog;
    RecentOrder recent = new RecentOrder();
    bool active = false;
    X11.Window[] windows = {};
    int selected = 0;

    Popup popup = new Popup("alttab");
    Gtk.Grid grid = new Gtk.Grid();
    Gtk.Label title = new Gtk.Label("");
    WindowCell[] cells = {};
    int columns = 1;
    uint show_timer = 0;

    public WindowSwitcher(AppIcons icons) throws X11.Error {
        connection = new X11.Connection();
        tab_key = connection.keycode(X11.Keysym.TAB);
        escape_key = connection.keycode(X11.Keysym.ESCAPE);
        enter_key = connection.keycode(X11.Keysym.ENTER);
        left_key = connection.keycode(X11.Keysym.LEFT);
        right_key = connection.keycode(X11.Keysym.RIGHT);
        up_key = connection.keycode(X11.Keysym.UP);
        down_key = connection.keycode(X11.Keysym.DOWN);
        connection.merge_key_repeats();
        connection.grab_key(tab_key, Xl.MOD1_MASK);
        connection.root.select_events(Xl.PROPERTY_MASK);
        connection.listen(on_event);

        catalog = new AppCatalog(icons);
        Styles.add(CSS);
        build_popup();
        update_recent();
    }

    void build_popup() {
        popup.make_translucent();
        grid.row_spacing = SPACING;
        grid.column_spacing = SPACING;
        grid.halign = Gtk.Align.CENTER;
        title.name = "title";
        title.ellipsize = Pango.EllipsizeMode.END;
        title.max_width_chars = 60;

        var frame = new Gtk.Box(Gtk.Orientation.VERTICAL, 6);
        frame.name = "frame";
        frame.pack_start(grid, false, false);
        frame.pack_start(title, false, false);
        popup.add(frame);
    }

    // ── events ──────────────────────────────────────────────

    void on_event(Xl.Event event) {
        switch (event.type) {
            case Xl.KEY_PRESS:
                bool shift = (event.key_modifiers & Xl.SHIFT_MASK) != 0;
                if (active) {
                    on_key(event.keycode, shift);
                } else if (event.keycode == tab_key) {
                    start(shift);
                }
                break;
            case Xl.KEY_RELEASE:
                if (active && !alt_held()) {
                    finish();
                }
                break;
            case Xl.PROPERTY:
                if (!active && event.property == connection.atom("_NET_ACTIVE_WINDOW")) {
                    update_recent();
                }
                break;
        }
    }

    void on_key(uint keycode, bool shift) {
        if (keycode == tab_key) {
            select(selected + (shift ? -1 : 1));
        } else if (keycode == right_key) {
            select(selected + 1);
        } else if (keycode == left_key) {
            select(selected - 1);
        } else if (keycode == down_key && selected + columns < windows.length) {
            select(selected + columns);
        } else if (keycode == up_key && selected >= columns) {
            select(selected - columns);
        } else if (keycode == enter_key) {
            finish();
        } else if (keycode == escape_key) {
            close();
        }
    }

    /* Never leaves the keyboard grabbed, even if a release of the key got lost. */
    bool watch_alt() {
        if (active && !alt_held()) {
            finish();
        }
        return active ? Source.CONTINUE : Source.REMOVE;
    }

    bool alt_held() {
        return connection.pointer().alt_key;
    }

    // ── switching ───────────────────────────────────────────

    void start(bool backwards) {
        ulong current_id = update_recent();
        windows = list_windows();
        if (windows.length == 0) {
            return;
        }
        active = true;
        connection.grab_keyboard();

        // to the previous window, or to the first one when none is active
        selected = 0;
        if (windows.length > 1 && windows[0].id == current_id) {
            selected = backwards ? windows.length - 1 : 1;
        }
        show_timer = Timeout.add(SHOW_DELAY, () => {
            show_timer = 0;
            show_popup();
            return Source.REMOVE;
        });
        Timeout.add(WATCHDOG_INTERVAL, watch_alt);
        if (!alt_held()) {
            finish();       // released before the keyboard was grabbed
        }
    }

    void select(int index) {
        selected = (index + windows.length) % windows.length;
        if (popup.visible) {
            update_selection();
        }
    }

    void finish() {
        if (!active) {
            return;
        }
        var chosen = windows[selected];
        close();
        chosen.activate();
    }

    void close() {
        active = false;
        if (show_timer != 0) {
            Source.remove(show_timer);
            show_timer = 0;
        }
        connection.release_keyboard();
        popup.hide();
        cells = {};
        windows = {};
    }

    // ── windows ─────────────────────────────────────────────

    /* Puts the active window first and new windows last; returns the active one. */
    ulong update_recent() {
        var stacked_ids = connection.stacked_client_ids();
        for (int index = stacked_ids.length - 1; index >= 0; index--) {
            recent.append(stacked_ids[index]);
        }
        ulong active_id = connection.active_id();
        recent.move_to_front(active_id);
        return active_id;
    }

    X11.Window[] list_windows() {
        var open_ids = connection.client_ids();
        recent.keep_only(open_ids);
        catalog.forget_closed_windows(open_ids);

        ulong desktop = connection.current_desktop();
        X11.Window[] listed = {};
        for (int index = 0; index < recent.length; index++) {
            var window = connection.window(recent[index]);
            bool skipped = window.has_type(SKIPPED_TYPES)
                || window.has_state({ X11.WindowState.SKIP_TASKBAR });
            if (!skipped && window.is_on_desktop(desktop)) {
                listed += window;
            }
        }
        return listed;
    }

    // ── popup ───────────────────────────────────────────────

    void show_popup() {
        foreach (var cell in grid.get_children()) {
            cell.destroy();
        }
        int fitting = (Popup.monitor_with_pointer().width - SCREEN_MARGIN) / (WindowCell.WIDTH + SPACING);
        columns = int.max(1, int.min(windows.length, fitting));
        cells = {};
        for (int index = 0; index < windows.length; index++) {
            var cell = create_cell(index);
            grid.attach(cell, index % columns, index / columns);
            cells += cell;
        }
        update_selection();
        popup.show_centered();
    }

    WindowCell create_cell(int index) {
        var window = windows[index];
        DesktopAppInfo? app;
        string window_class;
        catalog.identify(window, out app, out window_class);

        string caption = window_class != "" ? window_class : window.title();
        if (app != null) {
            caption = app.get_display_name();
        }
        var cell = new WindowCell(
            caption,
            catalog.icon_for(window, app, window_class),
            window.has_state({ X11.WindowState.HIDDEN })
        );
        cell.hovered.connect(() => {
            if (active && index != selected) {
                select(index);
            }
        });
        cell.clicked.connect(() => {
            if (active) {
                select(index);
                finish();
            }
        });
        return cell;
    }

    void update_selection() {
        for (int index = 0; index < cells.length; index++) {
            cells[index].set_selected(index == selected);
        }
        title.label = windows[selected].title();
    }
}
