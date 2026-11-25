/* Builds a Kvantum (Qt) theme in the colors of a variant. The base is KvLibadwaitaDark: its grays
   become the grays of the variant and its blues the accent; shapes, sizes and shadows stay. */
class QtTheme {
    struct Assignment {
        string key;
        string color;
    }

    const Assignment[] GENERAL_COLORS = {
        { "window.color", "BG" },
        { "base.color", "SURFACE" },
        { "alt.base.color", "ALT" },
        { "button.color", "RAISED" },
        { "light.color", "BORDER" },
        { "mid.light.color", "RAISED" },
        { "dark.color", "SURFACE" },
        { "mid.color", "BG" },
        { "highlight.color", "ACCENT" },
        { "inactive.highlight.color", "HILITE" },
        { "text.color", "FG" },
        { "window.text.color", "FG" },
        { "button.text.color", "FG" },
        { "disabled.text.color", "OFF" },
        { "tooltip.base.color", "RAISED" },
        { "tooltip.text.color", "FG" },
        { "highlight.text.color", "ON_ACCENT" },
        { "inactive.highlight.text.color", "HILITE_FG" },
        { "link.color", "ACCENT_TEXT" },
        { "link.visited.color", "DIM" },
        { "placeholder.text.color", "DIM" }
    };
    const string GENERAL_SECTION = "[GeneralColors]";

    Palette palette;
    GrayRamp grays = new GrayRamp();

    public QtTheme(Palette palette) throws PaletteError {
        this.palette = palette;
        Color background = palette.color("BG");
        Color surface = palette.color("SURFACE");
        palette.set_color("ALT", surface.mix(background, 0.45));
        palette.set_color("OFF", background.mix(palette.color("DIM"), 0.6));

        grays.add(0.00, Color.parse("#000000"));
        grays.add(0.12, surface);
        grays.add(0.17, background);
        grays.add(0.20, background);
        grays.add(0.27, palette.color("RAISED"));
        grays.add(0.40, palette.color("BORDER"));
        grays.add(0.60, palette.color("DIM"));
        grays.add(0.875, palette.color("FG"));
        grays.add(1.00, Color.parse("#ffffff"));
    }

    public void build(string source_directory, string output_directory) throws Error {
        string base_path = Path.build_filename(
            source_directory,
            "src",
            "KvLibadwaita",
            "KvLibadwaitaDark"
        );
        string shapes, config;
        FileUtils.get_contents(base_path + ".svg", out shapes);
        FileUtils.get_contents(base_path + ".kvconfig", out config);

        DirUtils.create_with_parents(output_directory, 0755);
        string name = Path.get_basename(output_directory);
        string output_path = Path.build_filename(output_directory, name);
        FileUtils.set_contents(output_path + ".svg", recolor_text(shapes));
        FileUtils.set_contents(output_path + ".kvconfig", convert_config(recolor_text(config)));
    }

    string recolor_text(string text) throws Error {
        var color_pattern = new Regex("#[0-9a-fA-F]{6}\\b");
        var result = new StringBuilder();
        int copied = 0;
        MatchInfo match;
        for (color_pattern.match(text, 0, out match); match.matches(); match.next()) {
            int start, end;
            match.fetch_pos(0, out start, out end);
            result.append_len(text.offset(copied), start - copied);
            result.append(recolor(match.fetch(0).down()));
            copied = end;
        }
        result.append(text.offset(copied));
        return result.str;
    }

    string recolor(string original) throws PaletteError {
        Color color = Color.parse(original);
        bool is_shadow_or_overlay = color.max() < 8 || color.min() > 240;
        if (is_shadow_or_overlay) {
            return original;
        }
        Hls hls = color.to_hls();
        bool is_gray = hls.saturation <= 0.2 || color.max() - color.min() <= 30;
        if (is_gray) {
            Color? gray = grays.at(hls.lightness);
            return gray != null ? gray.to_hex() : original;
        }
        bool is_blue = hls.hue > 0.50 && hls.hue < 0.70;
        if (!is_blue) {
            return original;        // red of destructive actions and the like
        }
        return palette.hex(hls.lightness < 0.62 ? "ACCENT" : "ACCENT_TEXT");
    }

    string convert_config(string config) throws Error {
        var comment = new Regex("^comment=.*$", RegexCompileFlags.MULTILINE);
        string text = comment.replace_literal(
            config,
            -1,
            0,
            "comment=KvLibadwaita in the colors of mini-de"
        );
        int start = text.index_of(GENERAL_SECTION);
        if (start < 0) {
            return text;
        }
        start += GENERAL_SECTION.length;
        int end = text.index_of("\n[", start);
        if (end < 0) {
            end = text.length;
        }
        string section = set_general_colors(text.substring(start, end - start));
        return text.substring(0, start) + section + "\n" + text.substring(end);
    }

    string set_general_colors(string section) throws Error {
        string result = section;
        foreach (var assignment in GENERAL_COLORS) {
            string line = "%s=%s".printf(assignment.key, palette.hex(assignment.color));
            var existing = new Regex(
                "^%s=.*$".printf(Regex.escape_string(assignment.key)),
                RegexCompileFlags.MULTILINE
            );
            if (existing.match(result)) {
                result = existing.replace_literal(result, -1, 0, line);
            } else {
                result += "\n" + line;
            }
        }
        while (result.has_suffix("\n")) {
            result = result.substring(0, result.length - 1);
        }
        return result;
    }
}
