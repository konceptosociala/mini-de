/* Icons of applications, kept in memory. */
class AppIcons {
    const string DEFAULT_ICON = "application-x-executable";

    // by size and desktop id
    HashTable<string, Gdk.Pixbuf> icons = new HashTable<string, Gdk.Pixbuf>(str_hash, str_equal);

    AppInfoMonitor monitor = AppInfoMonitor.get();

    public AppIcons() {
        Gtk.IconTheme.get_default().changed.connect(() => icons.remove_all());
        monitor.changed.connect(() => icons.remove_all());
    }

    /* Null if the application has no icon of its own. */
    public Gdk.Pixbuf? find(DesktopAppInfo app, int size) {
        string key = "%d:%s".printf(size, app.get_id());
        var icon = icons[key];
        if (icon == null) {
            icon = load(app.get_icon(), size);
            if (icon != null) {
                icons[key] = icon;
            }
        }
        return icon;
    }

    public Gdk.Pixbuf? find_or_default(DesktopAppInfo app, int size) {
        var icon = find(app, size);
        return icon != null ? icon : default_icon(size);
    }

    public Gdk.Pixbuf? default_icon(int size) {
        string key = "%d:".printf(size);
        var icon = icons[key];
        if (icon == null) {
            icon = find_in_theme(DEFAULT_ICON, size);
            if (icon != null) {
                icons[key] = icon;
            }
        }
        return icon;
    }

    /* Frees the memory of icons that are only needed while something is animated. */
    public void forget_larger_than(int size) {
        icons.foreach_remove((key, icon) => int.parse(key) > size);
    }

    static Gdk.Pixbuf? load(Icon? icon, int size) {
        if (icon == null) {
            return null;
        }
        var found = Gtk.IconTheme.get_default().lookup_by_gicon(
            icon,
            size,
            Gtk.IconLookupFlags.FORCE_SIZE
        );
        try {
            return found != null ? found.load_icon() : null;
        } catch (Error error) {
            return null;
        }
    }

    public static Gdk.Pixbuf? find_in_theme(string name, int size) {
        if (name == "") {
            return null;
        }
        try {
            return Gtk.IconTheme.get_default().load_icon(
                name,
                size,
                Gtk.IconLookupFlags.FORCE_SIZE
            );
        } catch (Error error) {
            return null;
        }
    }
}
