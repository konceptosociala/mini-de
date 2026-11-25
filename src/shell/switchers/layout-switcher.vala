/* Keyboard layouts on Super+Space in most recently used order, like in GNOME.
   Shift goes back, Esc cancels. */
class LayoutSwitcher {
    const uint HIDE_DELAY = 400;        // ms
    const uint WATCHDOG_INTERVAL = 500; // ms
    const string CSS = """
        @define-color md_surface #1d2021;
        @define-color md_border #504945;
        @define-color md_fg #ebdbb2;
        @define-color md_accent #fabd2f;
        @define-color md_on_accent #1d2021;
        #kbosd {
            background: @md_surface;
            border: 2px solid @md_border;
        }
        #kbosd label {
            color: @md_fg;
            font: 600 22px "Inter";
            padding: 14px 22px;
            margin: 8px;
        }
        #kbosd label.selected {
            color: @md_on_accent;
            background: @md_accent;
            border-radius: 8px;
        }
    """;

    X11.Connection connection;
    uint space_key;
    uint escape_key;
    uint[] super_keys = {};

    string[] names = {};
    RecentOrder recent = new RecentOrder();
    bool active = false;
    int selected = 0;
    uint layout_before = 0;

    Popup popup = new Popup("kbosd");
    Gtk.Box box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
    uint hide_timer = 0;

    public LayoutSwitcher() throws X11.Error {
        connection = new X11.Connection();
        space_key = connection.keycode(X11.Keysym.SPACE);
        escape_key = connection.keycode(X11.Keysym.ESCAPE);
        foreach (ulong keysym in new ulong[] { X11.Keysym.SUPER_LEFT, X11.Keysym.SUPER_RIGHT }) {
            uint keycode = connection.keycode(keysym);
            if (keycode != 0) {
                super_keys += keycode;
            }
        }
        connection.merge_key_repeats();
        connection.grab_key(space_key, Xl.MOD4_MASK);
        connection.listen(on_event);

        Styles.add(CSS);
        popup.add(box);
        read_layouts();
    }

    /* Takes over the configured layouts; the order is kept as long as they are the same. */
    void read_layouts() {
        var current_names = connection.layout_names();
        if (string.joinv(",", current_names) == string.joinv(",", names)) {
            return;
        }
        names = current_names;
        recent = new RecentOrder();
        for (int layout = 0; layout < names.length; layout++) {
            recent.append(layout);
        }
    }

    void on_event(Xl.Event event) {
        switch (event.type) {
            case Xl.KEY_PRESS:
                if (event.keycode == space_key) {
                    step((event.key_modifiers & Xl.SHIFT_MASK) != 0);
                } else if (active && event.keycode == escape_key) {
                    cancel();
                }
                break;
            case Xl.KEY_RELEASE:
                if (active && event.keycode in super_keys) {
                    finish();
                }
                break;
        }
    }

    void step(bool backwards) {
        if (!active) {
            start();
        }
        if (recent.length == 0) {
            finish();
            return;
        }
        selected = (selected + (backwards ? recent.length - 1 : 1)) % recent.length;
        connection.set_layout((uint) recent[selected]);
        show_popup();
        if (!super_held()) {
            finish();       // released before the keyboard was grabbed
        }
    }

    void start() {
        active = true;
        read_layouts();
        layout_before = connection.current_layout();
        recent.move_to_front(layout_before);
        selected = 0;
        connection.grab_keyboard();
        cancel_hiding();
        Timeout.add(WATCHDOG_INTERVAL, watch_super);
    }

    void finish() {
        if (selected < recent.length) {
            recent.move_to_front(recent[selected]);
        }
        close();
    }

    void cancel() {
        connection.set_layout(layout_before);
        close();
    }

    void close() {
        active = false;
        connection.release_keyboard();
        hide_timer = Timeout.add(HIDE_DELAY, () => {
            hide_timer = 0;
            popup.hide();
            return Source.REMOVE;
        });
    }

    void cancel_hiding() {
        if (hide_timer != 0) {
            Source.remove(hide_timer);
            hide_timer = 0;
        }
    }

    /* Never leaves the keyboard grabbed, even if a release of the key got lost. */
    bool watch_super() {
        if (active && !super_held()) {
            finish();
        }
        return active ? Source.CONTINUE : Source.REMOVE;
    }

    bool super_held() {
        return connection.any_key_down(super_keys);
    }

    void show_popup() {
        foreach (var label in box.get_children()) {
            label.destroy();
        }
        for (int index = 0; index < recent.length; index++) {
            var label = new Gtk.Label(names[recent[index]]);
            set_css_class(label, "selected", index == selected);
            box.add(label);
        }
        popup.show_centered();
    }
}
