class IconsPage : Page {
    Gtk.ListBox list = new Gtk.ListBox();
    Queue<IconThemeRow> without_preview = new Queue<IconThemeRow>();

    public IconsPage() {
        base("icons", "Icons", "preferences-desktop-theme");
        list.selection_mode = Gtk.SelectionMode.NONE;
        list.row_activated.connect((row) => choose((IconThemeRow) row));
        add_scrolled(list);

        string current;
        try {
            current = IconTheme.current();
        } catch (Error error) {
            show_error("The icon theme cannot be read: %s".printf(error.message));
            return;
        }
        foreach (unowned string name in IconTheme.installed()) {
            var row = new IconThemeRow(name);
            row.set_current(name == current);
            list.add(row);
            without_preview.push_tail(row);
        }
        Idle.add(load_next_preview);
    }

    /* One by one, so that the window opens at once. */
    bool load_next_preview() {
        var row = without_preview.pop_head();
        if (row == null) {
            return Source.REMOVE;
        }
        row.load_preview();
        return Source.CONTINUE;
    }

    void choose(IconThemeRow chosen) {
        try {
            IconTheme.apply(chosen.theme_name);
            clear_error();
        } catch (Error error) {
            show_error("Not changed: %s".printf(error.message));
            return;
        }
        foreach (var row in list.get_children()) {
            ((IconThemeRow) row).set_current(row == chosen);
        }
    }
}

class IconThemeRow : Gtk.ListBoxRow {
    const int PREVIEW_SIZE = 40;        // px
    const int NAME_WIDTH = 190;         // px
    const string[] PREVIEW_ICONS = {
        "folder",
        "user-home",
        "folder-download",
        "firefox",
        "telegram",
        "discord",
        "gimp",
        "utilities-terminal",
        "preferences-system"
    };

    public string theme_name;
    Gtk.Image check = new Gtk.Image.from_icon_name("object-select-symbolic", Gtk.IconSize.BUTTON);
    Gtk.Box preview = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12);

    public IconThemeRow(string theme_name) {
        this.theme_name = theme_name;
        var label = new Gtk.Label(IconTheme.readable_name(theme_name));
        label.xalign = 0;
        label.set_size_request(NAME_WIDTH, -1);
        preview.set_size_request(-1, PREVIEW_SIZE);

        var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 16);
        box.margin = 10;
        box.pack_start(check, false, false);
        box.pack_start(label, false, false);
        box.pack_start(preview, false, false);
        add(box);
    }

    public void set_current(bool current) {
        check.opacity = current ? 1 : 0;
    }

    public void load_preview() {
        var theme = new Gtk.IconTheme();
        theme.set_custom_theme(theme_name);
        foreach (unowned string name in PREVIEW_ICONS) {
            preview.pack_start(load_icon(theme, name), false, false);
        }
        preview.show_all();
    }

    /* Empty if the theme has no such icon. */
    static Gtk.Image load_icon(Gtk.IconTheme theme, string name) {
        var image = new Gtk.Image();
        image.set_size_request(PREVIEW_SIZE, PREVIEW_SIZE);
        try {
            image.pixbuf = theme.load_icon(name, PREVIEW_SIZE, Gtk.IconLookupFlags.FORCE_SIZE);
        } catch (Error error) {
            image.clear();
        }
        return image;
    }
}
