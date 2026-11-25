/* Something in the grid of the launcher. */
abstract class LauncherItem {
    public string name;
    string? sort_key_cache = null;

    /* For comparing without regard to case. */
    public string sort_key {
        get {
            if (sort_key_cache == null) {
                sort_key_cache = name.casefold();
            }
            return sort_key_cache;
        }
    }

    public static int compare(LauncherItem first, LauncherItem second) {
        return strcmp(first.sort_key, second.sort_key);
    }
}

class App : LauncherItem {
    public DesktopAppInfo info;
    public string id;
    public string path;                 // of the .desktop file, with links resolved
    string[] categories = {};
    string search_text;

    public App(DesktopAppInfo info) {
        this.info = info;
        name = info.get_display_name();
        id = info.get_id();
        path = resolve_links(info.get_filename());
        string? category_list = info.get_categories();
        if (category_list != null) {
            foreach (unowned string category in category_list.split(";")) {
                if (category != "") {
                    categories += category;
                }
            }
        }
        search_text = collect_search_text(info);
    }

    static string collect_search_text(DesktopAppInfo info) {
        var text = new StringBuilder(info.get_display_name());
        string?[] parts = {
            info.get_generic_name(),
            info.get_executable()
        };
        foreach (unowned string? part in parts) {
            if (part != null) {
                text.append_c(' ');
                text.append(part);
            }
        }
        foreach (unowned string keyword in info.get_keywords()) {
            text.append_c(' ');
            text.append(keyword);
        }
        return text.str.casefold();
    }

    public bool has_any_category(string[] wanted) {
        foreach (unowned string category in categories) {
            if (category in wanted) {
                return true;
            }
        }
        return false;
    }

    /* Whether all of the words, in lower case, occur somewhere. */
    public bool matches(string[] words) {
        foreach (unowned string word in words) {
            if (!(word in search_text)) {
                return false;
            }
        }
        return true;
    }

    /* 0 is the best match of the name. */
    public int rank(string query) {
        if (sort_key.has_prefix(query)) {
            return 0;
        }
        foreach (unowned string word in sort_key.split(" ")) {
            if (word.has_prefix(query)) {
                return 1;
            }
        }
        return query in sort_key ? 2 : 3;
    }

    public static string resolve_links(string? path) {
        if (path == null) {
            return "";
        }
        string? resolved = Posix.realpath(path);
        return resolved != null ? resolved : path;
    }
}

class Folder : LauncherItem {
    public string id;
    public GenericArray<App> apps;

    public Folder(string id, string name, GenericArray<App> apps) {
        this.id = id;
        this.name = name;
        this.apps = apps;
    }

    public bool contains(App app) {
        return apps.find(app);
    }
}
