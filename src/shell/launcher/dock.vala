/* Apps pinned to Plank. */
class Dock {
    const string GROUP = "PlankDockItemPreferences";
    const int TIMEOUT = 3000;       // ms

    public signal void changed();

    string directory = Path.build_filename(
        Environment.get_user_config_dir(),
        "plank",
        "dock1",
        "launchers"
    );
    FileMonitor? monitor = null;

    public Dock() {
        DirUtils.create_with_parents(directory, 0755);
        try {
            monitor = File.new_for_path(directory).monitor_directory(FileMonitorFlags.NONE);
            monitor.changed.connect(() => changed());
        } catch (Error error) {
            warning("%s: %s", directory, error.message);
        }
    }

    /* .desktop files, with links resolved. */
    public GenericSet<string> pinned_paths() {
        var paths = new GenericSet<string>(str_hash, str_equal);
        Dir items;
        try {
            items = Dir.open(directory);
        } catch (Error error) {
            return paths;
        }
        unowned string? file_name;
        while ((file_name = items.read_name()) != null) {
            var item = new KeyFile();
            try {
                item.load_from_file(Path.build_filename(directory, file_name), KeyFileFlags.NONE);
                string path = Filename.from_uri(item.get_string(GROUP, "Launcher"));
                paths.add(App.resolve_links(path));
            } catch (Error error) {
                continue;       // not an application
            }
        }
        return paths;
    }

    public void pin(App app) {
        call.begin("Add", app);
    }

    public void unpin(App app) {
        call.begin("Remove", app);
    }

    /* Plank writes the file itself, then the monitor reports it. */
    async void call(string method, App app) {
        try {
            string uri = Filename.to_uri(app.info.get_filename());
            var bus = yield Bus.get(BusType.SESSION);
            yield bus.call(
                "net.launchpad.plank",
                "/net/launchpad/plank/dock1",
                "net.launchpad.plank.Items",
                method,
                new Variant("(s)", uri),
                null,
                DBusCallFlags.NO_AUTO_START,
                TIMEOUT
            );
        } catch (Error error) {
            Notifications.show.begin("Plank did not respond", error.message);
        }
    }
}
