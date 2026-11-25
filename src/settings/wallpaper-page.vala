class WallpaperPage : Page {
    const string DEFAULT_WALLPAPER = "/usr/share/backgrounds/warty-final-ubuntu.png";
    const string SETTING = "WALLPAPER";
    const uint RELOAD_DELAY = 400;      // ms

    unowned Gtk.Window window;
    string directory = Path.build_filename(Environment.get_user_data_dir(), "mini-de", "wallpapers");
    string current = "";
    Gtk.FlowBox flow = new Gtk.FlowBox();
    Queue<WallpaperTile> without_thumbnail = new Queue<WallpaperTile>();
    FileMonitor? monitor = null;
    uint reload_timer = 0;

    public WallpaperPage(Gtk.Window window) {
        base("wallpaper", "Wallpaper", "preferences-desktop-wallpaper");
        this.window = window;
        DirUtils.create_with_parents(directory, 0755);

        add_button("Open folder", "folder-open-symbolic").clicked.connect(open_folder);
        add_button("Add image…", "list-add-symbolic").clicked.connect(add_images);

        flow.homogeneous = true;
        flow.valign = Gtk.Align.START;
        flow.row_spacing = 8;
        flow.column_spacing = 8;
        flow.min_children_per_line = 2;
        flow.max_children_per_line = 8;
        flow.selection_mode = Gtk.SelectionMode.NONE;
        add_scrolled(flow);

        watch_directory();
        reload();
    }

    Gtk.Button add_button(string label, string icon) {
        var button = new Gtk.Button.with_label(label);
        button.image = new Gtk.Image.from_icon_name(icon, Gtk.IconSize.BUTTON);
        button.always_show_image = true;
        header.pack_start(button, false, false);
        return button;
    }

    void watch_directory() {
        try {
            monitor = File.new_for_path(directory).monitor_directory(FileMonitorFlags.NONE);
            monitor.changed.connect(schedule_reload);
        } catch (Error error) {
            show_error(error.message);
        }
    }

    void schedule_reload() {
        if (reload_timer != 0) {
            return;
        }
        reload_timer = Timeout.add(RELOAD_DELAY, () => {
            reload_timer = 0;
            reload();
            return Source.REMOVE;
        });
    }

    // ── tiles ───────────────────────────────────────────────

    void reload() {
        current = resolve(LocalConf.read(SETTING, DEFAULT_WALLPAPER));
        foreach (var child in flow.get_children()) {
            child.destroy();
        }
        without_thumbnail.clear();
        foreach (unowned string path in find_wallpapers()) {
            add_tile(path);
        }
        flow.show_all();
        Idle.add(load_next_thumbnail);
    }

    GenericArray<string> find_wallpapers() {
        var paths = new GenericArray<string>();
        bool has_current = false;
        try {
            var items = Dir.open(directory);
            unowned string? file_name;
            while ((file_name = items.read_name()) != null) {
                if (!WallpaperTile.is_image(file_name)) {
                    continue;
                }
                string path = Path.build_filename(directory, file_name);
                paths.add(path);
                has_current = has_current || resolve(path) == current;
            }
        } catch (Error error) {
            show_error(error.message);
        }
        paths.sort((first, second) => {
            return strcmp(
                Path.get_basename(first).casefold(),
                Path.get_basename(second).casefold()
            );
        });
        // one that was chosen outside the directory
        if (!has_current && FileUtils.test(current, FileTest.EXISTS)) {
            paths.insert(0, current);
        }
        return paths;
    }

    void add_tile(string path) {
        var tile = new WallpaperTile(path);
        tile.set_current(resolve(path) == current);
        tile.clicked.connect(() => choose(tile));
        flow.add(tile);
        tile.get_parent().can_focus = false;
        without_thumbnail.push_tail(tile);
    }

    /* One by one, so that the window opens at once. */
    bool load_next_thumbnail() {
        var tile = without_thumbnail.pop_head();
        if (tile == null) {
            return Source.REMOVE;
        }
        tile.load_thumbnail();
        return Source.CONTINUE;
    }

    static string resolve(string path) {
        string? resolved = Posix.realpath(path);
        return resolved != null ? resolved : path;
    }

    // ── actions ─────────────────────────────────────────────

    void choose(WallpaperTile chosen) {
        try {
            Command.run({ "feh", "--no-fehbg", "--bg-fill", chosen.path });
        } catch (Error error) {
            show_error(error.message);
            return;
        }
        try {
            LocalConf.write(SETTING, chosen.path);
            clear_error();
        } catch (Error error) {
            show_error("The wallpaper is set, but could not be saved: %s".printf(error.message));
            return;
        }
        current = resolve(chosen.path);
        foreach (var child in flow.get_children()) {
            var tile = (WallpaperTile) ((Gtk.Bin) child).get_child();
            tile.set_current(resolve(tile.path) == current);
        }
    }

    void open_folder() {
        try {
            AppInfo.launch_default_for_uri(Filename.to_uri(directory), null);
        } catch (Error error) {
            show_error(error.message);
        }
    }

    void add_images() {
        var dialog = new Gtk.FileChooserDialog(
            "Add images",
            window,
            Gtk.FileChooserAction.OPEN,
            "Cancel",
            Gtk.ResponseType.CANCEL,
            "Add",
            Gtk.ResponseType.ACCEPT
        );
        dialog.select_multiple = true;
        dialog.add_filter(WallpaperTile.image_filter());
        SList<string> chosen = new SList<string>();
        if (dialog.run() == Gtk.ResponseType.ACCEPT) {
            chosen = dialog.get_filenames();
        }
        dialog.destroy();
        foreach (unowned string path in chosen) {
            try {
                copy_into_directory(path);
            } catch (Error error) {
                show_error(error.message);
            }
        }
    }

    /* Never overwrites an existing image. */
    void copy_into_directory(string path) throws Error {
        string file_name = Path.get_basename(path);
        int dot = file_name.last_index_of_char('.');
        string stem = dot > 0 ? file_name.substring(0, dot) : file_name;
        string extension = dot > 0 ? file_name.substring(dot) : "";

        string target = Path.build_filename(directory, file_name);
        if (resolve(path) == resolve(target)) {
            return;
        }
        for (int number = 2; FileUtils.test(target, FileTest.EXISTS); number++) {
            target = Path.build_filename(directory, "%s-%d%s".printf(stem, number, extension));
        }
        File.new_for_path(path).copy(File.new_for_path(target), FileCopyFlags.NONE);
    }
}

class WallpaperTile : Gtk.Button {
    const string[] EXTENSIONS = { ".png", ".jpg", ".jpeg", ".webp", ".bmp" };
    const int THUMBNAIL_WIDTH = 240;    // px
    const int THUMBNAIL_HEIGHT = 150;   // px

    public string path;
    Gtk.Image thumbnail = new Gtk.Image();

    public WallpaperTile(string path) {
        this.path = path;
        relief = Gtk.ReliefStyle.NONE;
        tooltip_text = path;
        get_style_context().add_class("wallpaper");

        thumbnail.set_size_request(THUMBNAIL_WIDTH, THUMBNAIL_HEIGHT);
        var label = new Gtk.Label(readable_name(path));
        label.ellipsize = Pango.EllipsizeMode.END;
        label.max_width_chars = 24;
        var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 4);
        box.pack_start(thumbnail, false, false);
        box.pack_start(label, false, false);
        add(box);
    }

    public static bool is_image(string file_name) {
        string lower = file_name.down();
        foreach (unowned string extension in EXTENSIONS) {
            if (lower.has_suffix(extension)) {
                return true;
            }
        }
        return false;
    }

    public static Gtk.FileFilter image_filter() {
        var filter = new Gtk.FileFilter();
        filter.set_filter_name("Images");
        foreach (unowned string extension in EXTENSIONS) {
            filter.add_pattern("*" + extension);
            filter.add_pattern("*" + extension.up());
        }
        return filter;
    }

    /* "foggy-forest.png" is "Foggy forest". */
    static string readable_name(string path) {
        string file_name = Path.get_basename(path);
        int dot = file_name.last_index_of_char('.');
        string stem = dot > 0 ? file_name.substring(0, dot) : file_name;
        string[] words = {};
        foreach (unowned string word in stem.split_set("-_")) {
            if (word != "") {
                words += word;
            }
        }
        string name = string.joinv(" ", words).strip().down();
        if (name == "") {
            return name;
        }
        int first_end = name.index_of_nth_char(1);
        return name.substring(0, first_end).up() + name.substring(first_end);
    }

    public void set_current(bool current) {
        if (current) {
            get_style_context().add_class("current");
        } else {
            get_style_context().remove_class("current");
        }
    }

    /* Covers the whole area, the rest is cut off. */
    public void load_thumbnail() {
        int width, height;
        if (Gdk.Pixbuf.get_file_info(path, out width, out height) == null) {
            show_missing();
            return;
        }
        double scale = double.max(
            THUMBNAIL_WIDTH / (double) width,
            THUMBNAIL_HEIGHT / (double) height
        );
        int scaled_width = int.max(THUMBNAIL_WIDTH, (int) Math.rint(width * scale));
        int scaled_height = int.max(THUMBNAIL_HEIGHT, (int) Math.rint(height * scale));
        try {
            var image = new Gdk.Pixbuf.from_file_at_scale(path, scaled_width, scaled_height, false);
            thumbnail.pixbuf = new Gdk.Pixbuf.subpixbuf(
                image,
                (scaled_width - THUMBNAIL_WIDTH) / 2,
                (scaled_height - THUMBNAIL_HEIGHT) / 2,
                THUMBNAIL_WIDTH,
                THUMBNAIL_HEIGHT
            );
        } catch (Error error) {
            show_missing();
        }
    }

    void show_missing() {
        thumbnail.set_from_icon_name("image-missing", Gtk.IconSize.DIALOG);
    }
}
