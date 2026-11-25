/* Everything that the launcher shows. */
class LauncherModel {
    public const string HIDDEN_FOLDER = ".hidden";      // id and name
    const uint REGROUP_DELAY = 150;     // ms
    const uint RELOAD_DELAY = 800;      // ms

    public signal void changed();

    public AppFolders app_folders = new AppFolders();
    public HiddenApps hidden_apps = new HiddenApps();
    public Dock dock = new Dock();

    public GenericArray<App> apps = new GenericArray<App>();
    public GenericArray<Folder> folders = new GenericArray<Folder>();
    public GenericArray<App> loose_apps = new GenericArray<App>();
    public Folder hidden_folder;
    GenericSet<string> pinned_paths = new GenericSet<string>(str_hash, str_equal);

    AppInfoMonitor monitor = AppInfoMonitor.get();
    uint reload_timer = 0;
    uint regroup_timer = 0;

    public LauncherModel() {
        load_apps();
        group_apps();
        monitor.changed.connect(schedule_reload);
        Gtk.IconTheme.get_default().changed.connect(schedule_reload);
        dock.changed.connect(schedule_regroup);
        app_folders.changed.connect(schedule_regroup);
    }

    void load_apps() {
        apps = new GenericArray<App>();
        foreach (var info in AppInfo.get_all()) {
            var desktop_info = info as DesktopAppInfo;
            if (desktop_info != null && desktop_info.get_id() != null && desktop_info.should_show()) {
                apps.add(new App(desktop_info));
            }
        }
        apps.sort(LauncherItem.compare);
    }

    /* Hidden apps and apps pinned to the dock are left out of the grid. */
    void group_apps() {
        pinned_paths = dock.pinned_paths();
        hidden_apps.read();
        var shown = new GenericArray<App>();
        var hidden = new GenericArray<App>();
        foreach (var app in apps) {
            if (hidden_apps.contains(app)) {
                hidden.add(app);
            } else if (!is_pinned(app)) {
                shown.add(app);
            }
        }
        app_folders.sort_out(shown, out folders, out loose_apps);
        hidden_folder = new Folder(HIDDEN_FOLDER, HIDDEN_FOLDER, hidden);
    }

    /* After a change of the dock or folders. */
    public void regroup() {
        group_apps();
        changed();
    }

    void schedule_regroup() {
        if (regroup_timer != 0) {
            return;
        }
        regroup_timer = Timeout.add(REGROUP_DELAY, () => {
            regroup_timer = 0;
            regroup();
            return Source.REMOVE;
        });
    }

    /* After a change of the installed apps or icons. */
    void schedule_reload() {
        if (reload_timer != 0) {
            return;
        }
        reload_timer = Timeout.add(RELOAD_DELAY, () => {
            reload_timer = 0;
            load_apps();
            regroup();
            return Source.REMOVE;
        });
    }

    // ── queries ─────────────────────────────────────────────

    public bool is_pinned(App app) {
        return app.path in pinned_paths;
    }

    public Folder? folder_of(App app) {
        foreach (var folder in folders) {
            if (folder.contains(app)) {
                return folder;
            }
        }
        return null;
    }

    /* Null if it is gone or empty. */
    public Folder? find_folder(string id) {
        if (id == HIDDEN_FOLDER) {
            return hidden_folder.apps.length > 0 ? hidden_folder : null;
        }
        foreach (var folder in folders) {
            if (folder.id == id) {
                return folder;
            }
        }
        return null;
    }

    /* Folders first, then apps, the best matches of the name at the beginning. */
    public GenericArray<LauncherItem> search(string query, bool with_hidden) {
        var found = new GenericArray<LauncherItem>();
        bool hidden_folder_matches = query.length > 1 && HIDDEN_FOLDER.has_prefix(query);
        if (hidden_folder_matches && hidden_folder.apps.length > 0) {
            found.add(hidden_folder);
        }
        foreach (var folder in folders) {
            if (query in folder.sort_key) {
                found.add(folder);
            }
        }
        string[] words = {};
        foreach (unowned string word in query.split_set(" \t")) {
            if (word != "") {
                words += word;
            }
        }
        const int RANKS = 4;
        for (int rank = 0; rank < RANKS; rank++) {
            foreach (var app in apps) {
                bool visible = with_hidden || !hidden_apps.contains(app);
                if (visible && app.matches(words) && app.rank(query) == rank) {
                    found.add(app);
                }
            }
        }
        return found;
    }

    // ── changes ─────────────────────────────────────────────

    /* Into this folder, or into none. */
    public void move_app(App app, string? folder_id) {
        if (hidden_apps.contains(app)) {
            write_hidden(app, false);
        }
        app_folders.move_app(app, folder_id);
        regroup();
    }

    public void create_folder(string name, App[] apps) {
        foreach (var app in apps) {
            if (hidden_apps.contains(app)) {
                write_hidden(app, false);
            }
        }
        app_folders.create(name, apps);
        regroup();
    }

    public void remove_folder(Folder folder) {
        app_folders.remove(folder.id);
        regroup();
    }

    public void rename_folder(Folder folder, string name) {
        app_folders.rename(folder.id, name);
        regroup();
    }

    public void set_hidden(App app, bool hidden) {
        write_hidden(app, hidden);
        regroup();
    }

    public void unhide_all() {
        foreach (var app in hidden_folder.apps) {
            write_hidden(app, false);
        }
        regroup();
    }

    void write_hidden(App app, bool hidden) {
        try {
            hidden_apps.set_hidden(app, hidden);
        } catch (Error error) {
            Notifications.show.begin("The list of hidden apps was not changed", error.message);
        }
    }
}
