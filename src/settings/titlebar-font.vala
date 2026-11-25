errordomain SettingsError {
    UNKNOWN_FORMAT
}

/* Font of titlebars, which is set in rc.xml and the window theme at once. */
class TitlebarFont {
    const string FONT_PATTERN =
        "(<font place=\"(?:Active|Inactive)Window\">\\s*<name>[^<]*</name>\\s*<size>)(\\d+)"
        + "(</size>.*?<weight>)(\\w+)";
    const int FONT_PLACES = 2;          // active and inactive windows

    string openbox_path = Path.build_filename(
        Environment.get_user_config_dir(),
        "openbox",
        "rc.xml"
    );
    string theme_path = Path.build_filename(
        Environment.get_home_dir(),
        ".themes",
        "Gruvbox-Round",
        "openbox-3",
        "themerc"
    );
    string sizes_path = Path.build_filename(
        Environment.get_user_config_dir(),
        "mini-de",
        "title-fonts"
    );

    public int size;
    public bool bold;
    public int[] sizes = {};            // supported ones, from the smallest
    HashTable<int, int> horizontal_paddings = new HashTable<int, int>(direct_hash, direct_equal);
    HashTable<int, int> vertical_paddings = new HashTable<int, int>(direct_hash, direct_equal);
    Regex font_pattern;

    public TitlebarFont() throws Error {
        font_pattern = new Regex(FONT_PATTERN, RegexCompileFlags.DOTALL);
        read_sizes();
        read_current();
    }

    void read_sizes() throws Error {
        foreach (unowned string line in Files.read(sizes_path).split("\n")) {
            int size, horizontal, vertical;
            if (line.scanf("%d %d %d", out size, out horizontal, out vertical) != 3) {
                continue;       // a comment
            }
            sizes += size;
            horizontal_paddings[size] = horizontal;
            vertical_paddings[size] = vertical;
        }
        if (sizes.length == 0) {
            throw new SettingsError.UNKNOWN_FORMAT("%s has no sizes", sizes_path);
        }
    }

    void read_current() throws Error {
        MatchInfo match;
        if (!font_pattern.match(Files.read(openbox_path), 0, out match)) {
            throw new SettingsError.UNKNOWN_FORMAT("%s has no font of titlebars", openbox_path);
        }
        size = int.parse(match.fetch(2));
        bold = match.fetch(4).down() == "bold";
    }

    /* Nothing is written unless both files can be changed. */
    public void apply(int new_size, bool new_bold) throws Error {
        string weight = new_bold ? "bold" : "normal";
        string old_theme = Files.read(theme_path);
        string openbox = with_font(Files.read(openbox_path), new_size, weight);
        string theme = with_padding(old_theme, "width", horizontal_paddings[new_size]);
        theme = with_padding(theme, "height", vertical_paddings[new_size]);
        check_xml(openbox);

        Files.replace(theme_path, theme);
        try {
            Files.replace(openbox_path, openbox);
        } catch (Error error) {
            Files.replace(theme_path, old_theme);
            throw error;
        }
        LocalConf.write("TITLE_FONT_SIZE", new_size.to_string());
        LocalConf.write("TITLE_FONT_WEIGHT", weight);
        size = new_size;
        bold = new_bold;
        Command.run({ "openbox", "--reconfigure" });
    }

    string with_font(string openbox, int new_size, string weight) throws Error {
        check_count(font_pattern, openbox, FONT_PLACES);
        string replacement = "\\g<1>%d\\g<3>%s".printf(new_size, weight);
        return font_pattern.replace(openbox, -1, 0, replacement);
    }

    static string with_padding(string theme, string dimension, int padding) throws Error {
        var pattern = new Regex(
            "^padding\\.%s:.*$".printf(dimension),
            RegexCompileFlags.MULTILINE
        );
        check_count(pattern, theme, 1);
        return pattern.replace_literal(theme, -1, 0, "padding.%s: %d".printf(dimension, padding));
    }

    static void check_count(Regex pattern, string text, int expected) throws Error {
        int count = 0;
        MatchInfo match;
        for (pattern.match(text, 0, out match); match.matches(); match.next()) {
            count++;
        }
        if (count != expected) {
            throw new SettingsError.UNKNOWN_FORMAT(
                "rc.xml or the window theme was edited in a way this page does not understand"
            );
        }
    }

    static void check_xml(string text) throws MarkupError {
        MarkupParser parser = {};
        var context = new MarkupParseContext(parser, 0, null, null);
        context.parse(text, -1);
        context.end_parse();
    }
}
