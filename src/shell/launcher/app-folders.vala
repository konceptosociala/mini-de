/* Folders of applications: the same settings that GNOME uses, so both see every change. */
class AppFolders {
    const string ROOT_SCHEMA = "org.gnome.desktop.app-folders";
    const string FOLDER_SCHEMA = "org.gnome.desktop.app-folders.folder";
    const string FOLDER_PATH = "/org/gnome/desktop/app-folders/folders/%s/";
    const string[] FOLDER_KEYS = {
        "name",
        "translate",
        "apps",
        "excluded-apps",
        "categories"
    };

    public signal void changed();

    Settings? root = null;          // null if the schemas are not installed
    Settings[] watched = {};

    public AppFolders() {
        var schemas = SettingsSchemaSource.get_default();
        if (schemas.lookup(ROOT_SCHEMA, true) == null || schemas.lookup(FOLDER_SCHEMA, true) == null) {
            return;
        }
        root = new Settings(ROOT_SCHEMA);
        root.changed.connect(() => {
            watch_folders();
            changed();
        });
        watch_folders();
    }

    /* Follows every folder, including ones that were just created. */
    void watch_folders() {
        watched = {};
        foreach (unowned string id in folder_ids()) {
            var folder = folder_settings(id);
            folder.changed.connect(() => changed());
            watched += folder;
        }
    }

    string[] folder_ids() {
        return root != null ? root.get_strv("folder-children") : new string[] {};
    }

    static Settings folder_settings(string id) {
        return new Settings.with_path(FOLDER_SCHEMA, FOLDER_PATH.printf(id));
    }

    // ── reading ─────────────────────────────────────────────

    /* Folders by name, and the apps that are in none of them. */
    public void sort_out(
        GenericArray<App> apps,
        out GenericArray<Folder> folders,
        out GenericArray<App> loose_apps
    ) {
        folders = new GenericArray<Folder>();
        var taken = new GenericSet<string>(str_hash, str_equal);
        foreach (unowned string id in folder_ids()) {
            var settings = folder_settings(id);
            var members = find_members(settings, apps, taken);
            if (members.length == 0) {
                continue;
            }
            foreach (var app in members) {
                taken.add(app.id);
            }
            folders.add(new Folder(id, read_name(settings), members));
        }
        folders.sort(LauncherItem.compare);

        loose_apps = new GenericArray<App>();
        foreach (var app in apps) {
            if (!(app.id in taken)) {
                loose_apps.add(app);
            }
        }
    }

    /* First the listed apps in their order, then those of the categories. */
    static GenericArray<App> find_members(
        Settings settings,
        GenericArray<App> apps,
        GenericSet<string> taken
    ) {
        var members = new GenericArray<App>();
        var excluded = settings.get_strv("excluded-apps");
        foreach (unowned string id in settings.get_strv("apps")) {
            if (id in excluded || id in taken) {
                continue;
            }
            foreach (var app in apps) {
                if (app.id == id && !members.find(app)) {
                    members.add(app);
                }
            }
        }
        var categories = settings.get_strv("categories");
        foreach (var app in apps) {
            bool fits = app.has_any_category(categories)
                && !(app.id in excluded)
                && !(app.id in taken);
            if (fits && !members.find(app)) {
                members.add(app);
            }
        }
        return members;
    }

    static string read_name(Settings settings) {
        string name = settings.get_string("name");
        if (!settings.get_boolean("translate")) {
            return name;
        }
        var file = new KeyFile();
        try {
            string full_path;
            file.load_from_data_dirs("desktop-directories/" + name, out full_path, KeyFileFlags.NONE);
            return file.get_locale_string("Desktop Entry", "Name");
        } catch (Error error) {
            // such as "X-GNOME-Utilities.directory"
            return name.replace(".directory", "").replace("X-", "").replace("GNOME-", "");
        }
    }

    // ── changing ────────────────────────────────────────────

    /* Puts the app into this folder, or into none. */
    public void move_app(App app, string? target_id) {
        foreach (unowned string id in folder_ids()) {
            var settings = folder_settings(id);
            var apps = settings.get_strv("apps");
            var excluded = settings.get_strv("excluded-apps");
            var categories = settings.get_strv("categories");
            if (id == target_id) {
                settings.set_strv("apps", StringLists.with(apps, app.id));
                settings.set_strv("excluded-apps", StringLists.without(excluded, app.id));
                continue;
            }
            var remaining = StringLists.without(apps, app.id);
            if (remaining.length != apps.length) {
                settings.set_strv("apps", remaining);
            }
            if (app.has_any_category(categories) && !(app.id in excluded)) {
                settings.set_strv("excluded-apps", StringLists.with(excluded, app.id));
            }
            bool became_empty = apps.length > 0 && remaining.length == 0 && categories.length == 0;
            if (became_empty) {
                remove(id);         // like in GNOME
            }
        }
        Settings.sync();
    }

    /* Removes the folder; its apps return to the grid. */
    public void remove(string id) {
        if (root == null) {
            return;
        }
        root.set_strv("folder-children", StringLists.without(folder_ids(), id));
        var settings = folder_settings(id);
        foreach (unowned string key in FOLDER_KEYS) {
            settings.reset(key);
        }
        Settings.sync();
    }

    public void create(string name, App[] apps) {
        if (root == null) {
            Notifications.show.begin("The folder was not created", "The settings of GNOME are not installed");
            return;
        }
        string id = Uuid.string_random();
        rename(id, name);
        root.set_strv("folder-children", StringLists.with(folder_ids(), id));
        foreach (var app in apps) {
            move_app(app, id);
        }
    }

    public void rename(string id, string name) {
        var settings = folder_settings(id);
        settings.set_string("name", name);
        settings.set_boolean("translate", false);
        Settings.sync();
    }
}
