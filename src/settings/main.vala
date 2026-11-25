/* Settings of the desktop: mini-de-settings [page] */
class SettingsApplication : Gtk.Application {
    const string CSS = """
        .wallpaper {
            border-radius: 10px;
            padding: 5px;
            border: 3px solid transparent;
            outline: none;
        }
        .wallpaper:hover {
            background: alpha(currentColor, 0.08);
        }
        .wallpaper.current {
            border-color: @theme_selected_bg_color;
        }
        .page-title {
            font-size: 20px;
            font-weight: 700;
        }
        .section-title {
            font-size: 15px;
            font-weight: 600;
        }
    """;

    public SettingsApplication() {
        Object(
            application_id: "local.minide.Settings",
            flags: ApplicationFlags.HANDLES_COMMAND_LINE
        );
    }

    public override void startup() {
        base.startup();
        var provider = new Gtk.CssProvider();
        try {
            provider.load_from_data(CSS);
        } catch (Error error) {
            warning("invalid CSS: %s", error.message);
        }
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(),
            provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        );
    }

    public override int command_line(ApplicationCommandLine command_line) {
        var window = active_window as SettingsWindow;
        if (window == null) {
            window = new SettingsWindow(this);
        }
        var arguments = command_line.get_arguments();
        if (arguments.length > 1) {
            window.show_page(arguments[1]);
        }
        window.present();
        return 0;
    }
}

int main(string[] args) {
    Environment.set_prgname("mini-de-settings");
    Gdk.set_program_class("mini-de-settings");
    return new SettingsApplication().run(args);
}
