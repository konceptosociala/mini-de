/* CSS of a component, followed by the colors of the theme variant that install.sh writes. */
namespace Styles {
    const uint COMPONENT_PRIORITY = 800;
    const uint COLORS_PRIORITY = 801;

    Gtk.CssProvider? colors = null;
    int64 colors_time = 0;

    public void add(string css) {
        var provider = new Gtk.CssProvider();
        try {
            provider.load_from_data(css);
        } catch (Error error) {
            warning("invalid CSS: %s", error.message);
        }
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(),
            provider,
            COMPONENT_PRIORITY
        );
    }

    /* Reads the colors again if install.sh has changed them. */
    public void refresh_colors() {
        string path = Path.build_filename(Environment.get_user_config_dir(), "mini-de", "colors.css");
        Posix.Stat status;
        if (Posix.stat(path, out status) != 0) {
            return;
        }
        int64 time = status.st_mtim.tv_sec * 1000000000 + status.st_mtim.tv_nsec;
        if (time == colors_time) {
            return;
        }
        colors_time = time;
        if (colors == null) {
            colors = new Gtk.CssProvider();
            Gtk.StyleContext.add_provider_for_screen(
                Gdk.Screen.get_default(),
                colors,
                COLORS_PRIORITY
            );
        }
        try {
            colors.load_from_path(path);
        } catch (Error error) {
            warning("%s: %s", path, error.message);
        }
    }
}
