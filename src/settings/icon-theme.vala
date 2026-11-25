/* Icon theme of GTK programs, notifications and rofi. */
namespace IconTheme {
    string config_path(string directory, string file_name) {
        return Path.build_filename(Environment.get_user_config_dir(), directory, file_name);
    }

    string xsettings_path() {
        return config_path("xsettingsd", "xsettingsd.conf");
    }

    /* Directory names of the themes of the user. */
    public GenericArray<string> installed() {
        var names = new GenericArray<string>();
        string directory = Path.build_filename(Environment.get_user_data_dir(), "icons");
        try {
            var items = Dir.open(directory);
            unowned string? name;
            while ((name = items.read_name()) != null) {
                if (is_icon_theme(directory, name)) {
                    names.add(name);
                }
            }
        } catch (FileError error) {
            return names;       // no themes
        }
        names.sort((first, second) => {
            return strcmp(readable_name(first).casefold(), readable_name(second).casefold());
        });
        return names;
    }

    public string readable_name(string name) {
        return name.replace("-", " ");
    }

    bool is_icon_theme(string directory, string name) {
        if (name == "hicolor" || !Regex.match_simple("^[A-Za-z0-9][A-Za-z0-9 ._+-]*$", name)) {
            return false;
        }
        var index = new KeyFile();
        try {
            string path = Path.build_filename(directory, name, "index.theme");
            index.load_from_file(path, KeyFileFlags.NONE);
            string directories = index.get_string("Icon Theme", "Directories");
            return "places" in directories || "apps" in directories;
        } catch (Error error) {
            return false;       // only cursors, or not a theme
        }
    }

    public string current() throws Error {
        var pattern = new Regex(
            "^Net/IconThemeName \"([^\"]*)\"",
            RegexCompileFlags.MULTILINE
        );
        MatchInfo match;
        pattern.match(Files.read(xsettings_path()), 0, out match);
        return match.matches() ? match.fetch(1) : "";
    }

    public void apply(string name) throws Error {
        set_in_xsettings(name);
        // notifications read theirs after the next login
        set_in_file(
            config_path("dunst", "dunstrc"),
            "^(\\s*icon_theme = ).*$",
            "\\g<1>\"%s, Yaru, hicolor\"".printf(name)
        );
        set_in_file(
            config_path("rofi", "config.rasi"),
            "^(\\s*icon-theme: ).*$",
            "\\g<1>\"%s\";".printf(name)
        );
        LocalConf.write("ICON_THEME", name);
        Command.run({ "pkill", "-HUP", "-x", "xsettingsd" });
    }

    void set_in_xsettings(string name) throws Error {
        var pattern = new Regex("^Net/IconThemeName .*$", RegexCompileFlags.MULTILINE);
        string text = Files.read(xsettings_path());
        if (!pattern.match(text)) {
            throw new SettingsError.UNKNOWN_FORMAT("xsettingsd.conf has no Net/IconThemeName line");
        }
        string line = "Net/IconThemeName \"%s\"".printf(name);
        Files.replace(xsettings_path(), pattern.replace_literal(text, -1, 0, line));
    }

    void set_in_file(string path, string pattern, string replacement) throws Error {
        if (!FileUtils.test(path, FileTest.EXISTS)) {
            return;
        }
        var line = new Regex(pattern, RegexCompileFlags.MULTILINE);
        Files.replace(path, line.replace(Files.read(path), -1, 0, replacement));
    }
}
