/* Finds the application and icon of a window. */
class AppCatalog {
    public const int ICON_SIZE = 84;        // px
    const int MAX_ICON_SIDE = 1024;         // of an icon set by a window itself, px
    const long MAX_ICON_DATA = 400000;      // numbers

    // by window class
    HashTable<string, string> desktop_ids = new HashTable<string, string>(str_hash, str_equal);
    // of windows without an application, by window
    HashTable<string, Gdk.Pixbuf> window_icons = new HashTable<string, Gdk.Pixbuf>(str_hash, str_equal);
    AppIcons icons;
    AppInfoMonitor monitor = AppInfoMonitor.get();

    public AppCatalog(AppIcons icons) {
        this.icons = icons;
        read_apps();
        monitor.changed.connect(read_apps);
        Gtk.IconTheme.get_default().changed.connect(() => window_icons.remove_all());
    }

    void read_apps() {
        desktop_ids.remove_all();
        var apps = AppInfo.get_all();
        // visible entries win over hidden ones, such as the URL handler of VS Code
        foreach (bool visible in new bool[] { true, false }) {
            foreach (var app in apps) {
                var desktop_app = app as DesktopAppInfo;
                if (desktop_app != null && desktop_app.should_show() == visible) {
                    add_app(desktop_app);
                }
            }
        }
    }

    void add_app(DesktopAppInfo app) {
        string? id = app.get_id();
        if (id == null) {
            return;
        }
        string name = id.has_suffix(".desktop") ? id.substring(0, id.length - ".desktop".length) : id;
        string last_part = name.substring(name.last_index_of_char('.') + 1);
        string?[] window_classes = {
            app.get_startup_wm_class(),
            name,
            last_part,
            Path.get_basename(app.get_executable() ?? "")
        };
        foreach (unowned string? window_class in window_classes) {
            if (window_class == null || window_class == "" || window_class == ".") {
                continue;
            }
            string key = window_class.down();
            if (!(key in desktop_ids)) {
                desktop_ids[key] = id;
            }
        }
    }

    /* Describes the window; app is null if no application is known for it. */
    public void identify(X11.Window window, out DesktopAppInfo? app, out string window_class) {
        app = null;
        window_class = "";
        string[] classes = {};
        foreach (unowned string part in window.read_strings("WM_CLASS")) {
            if (part != "") {
                classes += part;
            }
        }
        for (int index = classes.length - 1; index >= 0; index--) {
            unowned string? id = desktop_ids[classes[index].down()];
            if (id != null) {
                app = new DesktopAppInfo(id);
                window_class = classes[index];
                return;
            }
        }
        if (classes.length > 0) {
            window_class = classes[classes.length - 1];
        }
    }

    public Gdk.Pixbuf? icon_for(X11.Window window, DesktopAppInfo? app, string window_class) {
        var icon = app != null ? icons.find(app, ICON_SIZE) : null;
        if (icon != null) {
            return icon;
        }
        string key = window_key(window.id);
        icon = window_icons[key];
        if (icon == null) {
            icon = AppIcons.find_in_theme(window_class.down(), ICON_SIZE);
        }
        if (icon == null) {
            icon = load_window_icon(window);
        }
        if (icon == null) {
            icon = icons.default_icon(ICON_SIZE);
        }
        if (icon != null) {
            window_icons[key] = icon;
        }
        return icon;
    }

    /* Forgets icons of windows that are gone. */
    public void forget_closed_windows(ulong[] open_ids) {
        var open_keys = new GenericSet<string>(str_hash, str_equal);
        foreach (ulong id in open_ids) {
            open_keys.add(window_key(id));
        }
        window_icons.foreach_remove((key, icon) => !(key in open_keys));
    }

    static string window_key(ulong id) {
        return "%lu".printf(id);
    }

    /* The icon set by the window itself, of the most suitable size. */
    static Gdk.Pixbuf? load_window_icon(X11.Window window) {
        // width, height and pixels of every icon, one after another
        var data = window.read_numbers("_NET_WM_ICON", MAX_ICON_DATA);
        int best_start = -1;
        int best_width = 0;
        int best_height = 0;
        for (int start = 0; start + 2 < data.length;) {
            ulong width = data[start];
            ulong height = data[start + 1];
            if (width < 1 || width > MAX_ICON_SIDE || height < 1 || height > MAX_ICON_SIDE) {
                break;
            }
            int pixels = (int) (width * height);
            if (start + 2 + pixels > data.length) {
                break;
            }
            if (best_start < 0 || distance_from_ideal((int) width) < distance_from_ideal(best_width)) {
                best_start = start + 2;
                best_width = (int) width;
                best_height = (int) height;
            }
            start += 2 + pixels;
        }
        if (best_start < 0) {
            return null;
        }
        var pixels = data[best_start:best_start + best_width * best_height];
        return scale_to_icon(pixbuf_from_argb(pixels, best_width, best_height));
    }

    static int distance_from_ideal(int width) {
        return (width - ICON_SIZE * 3 / 2).abs();
    }

    static Gdk.Pixbuf pixbuf_from_argb(ulong[] pixels, int width, int height) {
        const int CHANNELS = 4;
        var bytes = new uint8[pixels.length * CHANNELS];
        for (int index = 0; index < pixels.length; index++) {
            ulong pixel = pixels[index];
            bytes[index * CHANNELS] = (uint8) (pixel >> 16);
            bytes[index * CHANNELS + 1] = (uint8) (pixel >> 8);
            bytes[index * CHANNELS + 2] = (uint8) pixel;
            bytes[index * CHANNELS + 3] = (uint8) (pixel >> 24);
        }
        return new Gdk.Pixbuf.from_bytes(
            new Bytes.take((owned) bytes),
            Gdk.Colorspace.RGB,
            true,
            8,
            width,
            height,
            width * CHANNELS
        );
    }

    static Gdk.Pixbuf? scale_to_icon(Gdk.Pixbuf icon) {
        const double MAX_SCALE = 2;     // a tiny icon would be a blur
        double scale = double.min(ICON_SIZE / (double) int.max(icon.width, icon.height), MAX_SCALE);
        return icon.scale_simple(
            int.max(1, (int) Math.round(icon.width * scale)),
            int.max(1, (int) Math.round(icon.height * scale)),
            Gdk.InterpType.BILINEAR
        );
    }
}
