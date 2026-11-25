/* Popups of the desktop. */
const string USAGE = """usage:
  mini-de-shell             launcher on Super, windows on Alt+Tab, keyboard layouts on Super+Space
  mini-de-shell launcher    shows or hides the launcher
""";

class Shell {
    const uint LAUNCHER_DELAY = 2;      // s: first let the session start

    AppIcons icons = new AppIcons();
    LayoutSwitcher? layout_switcher = null;
    WindowSwitcher? window_switcher = null;
    X11.SuperTap? super_tap = null;
    Launcher? launcher = null;
    ShellService service = new ShellService();

    public void start() {
        // each of them works without the others, such as when another program has taken its keys
        try {
            layout_switcher = new LayoutSwitcher();
        } catch (X11.Error error) {
            warning("Super+Space: %s", error.message);
        }
        try {
            window_switcher = new WindowSwitcher(icons);
        } catch (X11.Error error) {
            warning("Alt+Tab: %s", error.message);
        }
        try {
            super_tap = new X11.SuperTap();
            super_tap.tapped.connect(on_super_tapped);
        } catch (X11.Error error) {
            warning("Super: %s", error.message);
        }
        service.launcher_requested.connect(() => get_launcher().toggle());
        service.start();
        Timeout.add_seconds(LAUNCHER_DELAY, () => {
            get_launcher();
            return Source.REMOVE;
        });
    }

    void on_super_tapped() {
        // an open launcher has the keyboard itself
        if (get_launcher().visible || super_tap.keyboard_is_free()) {
            get_launcher().toggle();
        }
    }

    Launcher get_launcher() {
        if (launcher == null) {
            launcher = new Launcher(icons);
        }
        return launcher;
    }
}

int main(string[] args) {
    Environment.set_prgname("mini-de-shell");
    if (args.length > 1) {
        return run_command(args[1]);
    }
    if (!SingleInstance.acquire("mini-de-shell")) {
        return 0;
    }
    if (!Gtk.init_check(ref args)) {
        stderr.printf("mini-de-shell: cannot open the display\n");
        return 1;
    }
    var shell = new Shell();
    shell.start();
    Gtk.main();
    return 0;
}

int run_command(string command) {
    if (command != "launcher") {
        stderr.printf("%s", USAGE);
        return 2;
    }
    try {
        ShellService.call_toggle_launcher();
        return 0;
    } catch (Error error) {
        stderr.printf("mini-de-shell: %s\n", error.message);
        return 1;
    }
}
