/* Builds a Telegram Desktop theme in the colors of a variant. The base is Telegram's own night theme:
   its blue-grays become the grays of the variant, its blues become the accent, everything else
   (names, files, errors) stays. */
class TelegramTheme {
    struct Assignment {
        string key;
        string color;
    }

    // surfaces that define the look; other keys refer to these or are recolored by the rules below
    const Assignment[] FIXED_COLORS = {
        { "windowBg", "BG" },
        { "windowFg", "FG" },
        { "windowBoldFg", "FG" },
        { "windowBoldFgOver", "FG" },
        { "windowFgOver", "FG" },
        { "windowBgOver", "RAISED" },
        { "windowBgRipple", "BORDER" },
        { "windowSubTextFg", "DIM" },
        { "windowSubTextFgOver", "DIM" },
        { "windowBgActive", "ACCENT" },
        { "windowFgActive", "ON_ACCENT" },
        { "windowActiveTextFg", "ACCENT_TEXT" },
        { "activeButtonBg", "ACCENT" },
        { "activeButtonBgOver", "ACCENT" },
        { "activeButtonBgRipple", "ACCENT_TEXT" },
        { "activeButtonFg", "ON_ACCENT" },
        { "activeButtonFgOver", "ON_ACCENT" },
        { "activeButtonSecondaryFg", "ON_ACCENT" },
        { "activeLineFg", "ACCENT" },
        { "lightButtonFg", "ACCENT_TEXT" },
        { "menuIconFg", "DIM" },
        { "titleBg", "BG" },
        { "titleBgActive", "BG" },
        { "topBarBg", "BG" },
        { "boxBg", "BG" },
        { "menuBg", "BG" },
        { "filterInputInactiveBg", "SURFACE" },
        { "filterInputActiveBg", "SURFACE" },
        { "dialogsBgOver", "RAISED" },
        { "dialogsBgActive", "HILITE" },
        { "dialogsNameFg", "FG" },
        { "dialogsTextFg", "DIM" },
        { "dialogsDateFg", "DIM" },
        { "dialogsNameFgActive", "HILITE_FG" },
        { "dialogsTextFgActive", "HILITE_FG" },
        { "dialogsDateFgActive", "HILITE_FG" },
        { "dialogsUnreadBg", "ACCENT" },
        { "dialogsUnreadFg", "ON_ACCENT" },
        { "dialogsUnreadFgActive", "HILITE" },
        { "sideBarBg", "SURFACE" },
        { "sideBarBgActive", "HILITE" },
        { "sideBarTextFg", "DIM" },
        { "sideBarIconFg", "DIM" },
        { "sideBarTextFgActive", "HILITE_FG" },
        { "sideBarIconFgActive", "ACCENT_TEXT" },
        { "sideBarBadgeBg", "ACCENT" },
        { "sideBarBadgeFg", "ON_ACCENT" },
        { "msgInBg", "BG" },
        { "msgOutBg", "HILITE" },
        { "msgInBgSelected", "ACCENT" },
        { "msgOutBgSelected", "ACCENT" },
        { "msgInDateFg", "DIM" },
        { "msgOutDateFg", "FG" },
        { "historyTextOutFg", "FG" },
        { "msgInServiceFg", "ACCENT_TEXT" },
        { "msgOutServiceFg", "LINK_OUT" },
        { "historyLinkInFg", "ACCENT_TEXT" },
        { "historyLinkOutFg", "LINK_OUT" },
        { "historyComposeAreaBg", "BG" },
        { "historyPinnedBg", "BG" },
        { "historySendIconFg", "ACCENT_TEXT" },
        { "mainMenuCoverBg", "HILITE" },
        { "mainMenuCloudBg", "SURFACE" },
        { "mainMenuCoverFg", "HILITE_FG" },
        { "mainMenuCloudFg", "FG" },
        { "tooltipBg", "RAISED" }
    };
    const string SERVICE_KEY = "msgServiceBg";
    const string SERVICE_ALPHA = "d5";
    const int TILE_SIZE = 16;       // px

    Palette palette;
    GrayRamp grays = new GrayRamp();
    HashTable<string, string> fixed_colors = new HashTable<string, string>(str_hash, str_equal);

    public TelegramTheme(Palette palette) throws PaletteError {
        this.palette = palette;
        // readable on own messages
        Color link = palette.color("ACCENT_TEXT").mix(Color.parse("#ffffff"), 0.45);
        palette.set_color("LINK_OUT", link);
        foreach (var assignment in FIXED_COLORS) {
            fixed_colors[assignment.key] = palette.hex(assignment.color);
        }
        fixed_colors[SERVICE_KEY] = palette.hex("SURFACE") + SERVICE_ALPHA;

        grays.add(0.00, Color.parse("#000000"));
        grays.add(0.09, palette.color("SURFACE"));
        grays.add(0.128, palette.color("BG"));
        grays.add(0.20, palette.color("RAISED"));
        grays.add(0.31, palette.color("BORDER"));
        grays.add(0.55, palette.color("DIM"));
        grays.add(0.94, palette.color("FG"));
        grays.add(1.00, Color.parse("#ffffff"));
    }

    /* Writes the files that the archive of the theme consists of. */
    public void build(string base_path, string output_directory) throws Error {
        string base_colors;
        FileUtils.get_contents(base_path, out base_colors);
        FileUtils.set_contents(
            Path.build_filename(output_directory, "colors.tdesktop-theme"),
            convert(base_colors)
        );
        write_tile(Path.build_filename(output_directory, "tiled.png"));
    }

    string convert(string base_colors) throws Error {
        var assignment = new Regex("^([A-Za-z0-9]+)\\s*:\\s*([^;]+);");
        var plain_color = new Regex("^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$");
        var result = new StringBuilder();
        foreach (unowned string line in base_colors.split("\n")) {
            MatchInfo match;
            if (!assignment.match(line, 0, out match)) {
                continue;
            }
            string key = match.fetch(1);
            string value = match.fetch(2).strip();
            unowned string? fixed_color = fixed_colors[key];
            if (fixed_color != null) {
                value = fixed_color;
            } else if (plain_color.match(value)) {
                value = recolor(value.substring(0, 7).down()) + value.substring(7);
            }
            result.append("%s: %s;\n".printf(key, value));
        }
        return result.str;
    }

    string recolor(string original) throws PaletteError {
        Hls hls = Color.parse(original).to_hls();
        bool is_bluish = hls.hue > 0.52 && hls.hue < 0.66;
        if (!is_bluish) {
            return original;        // reds, greens, yellows and plain grays
        }
        bool is_blue = hls.saturation >= 0.42 && hls.lightness >= 0.24;
        if (!is_blue) {
            Color? gray = grays.at(hls.lightness);
            return gray != null ? gray.to_hex() : original;
        }
        if (hls.lightness < 0.34) {
            return palette.hex("HILITE");
        }
        return palette.hex(hls.lightness < 0.54 ? "ACCENT" : "ACCENT_TEXT");
    }

    /* Background of chats. */
    void write_tile(string path) throws Error {
        Color color = palette.color("SURFACE");
        var tile = new Gdk.Pixbuf(Gdk.Colorspace.RGB, false, 8, TILE_SIZE, TILE_SIZE);
        tile.fill(
            (uint32) color.red << 24
            | (uint32) color.green << 16
            | (uint32) color.blue << 8
            | 0xff
        );
        tile.save(path, "png");
    }
}
