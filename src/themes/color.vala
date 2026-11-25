/* A color with components from 0 to 255. */
struct Color {
    public double red;
    public double green;
    public double blue;

    /* From "#rrggbb". */
    public Color.parse(string text) {
        red = component(text, 1);
        green = component(text, 3);
        blue = component(text, 5);
    }

    static double component(string text, int start) {
        return (double) uint64.parse(text.substring(start, 2), 16);
    }

    public string to_hex() {
        return "#%02x%02x%02x".printf(
            (uint) Math.rint(red),
            (uint) Math.rint(green),
            (uint) Math.rint(blue)
        );
    }

    /* 0 is this color, 1 is the other one. */
    public Color mix(Color other, double share) {
        return Color() {
            red = red + (other.red - red) * share,
            green = green + (other.green - green) * share,
            blue = blue + (other.blue - blue) * share
        };
    }

    public double max() {
        return double.max(red, double.max(green, blue));
    }

    public double min() {
        return double.min(red, double.min(green, blue));
    }

    public Hls to_hls() {
        double r = red / 255;
        double g = green / 255;
        double b = blue / 255;
        double highest = max() / 255;
        double lowest = min() / 255;
        double sum = highest + lowest;
        double range = highest - lowest;
        Hls hls = { 0, sum / 2, 0 };
        if (range == 0) {
            return hls;
        }
        hls.saturation = hls.lightness <= 0.5 ? range / sum : range / (2 - highest - lowest);
        double from_red = (highest - r) / range;
        double from_green = (highest - g) / range;
        double from_blue = (highest - b) / range;
        double hue;
        if (r == highest) {
            hue = from_blue - from_green;
        } else if (g == highest) {
            hue = 2 + from_red - from_blue;
        } else {
            hue = 4 + from_green - from_red;
        }
        hue /= 6;
        hls.hue = hue - Math.floor(hue);
        return hls;
    }
}

/* Hue, lightness and saturation from 0 to 1. */
struct Hls {
    public double hue;
    public double lightness;
    public double saturation;
}

errordomain PaletteError {
    INVALID_COLOR,
    MISSING_COLOR
}

/* Colors of a theme variant by name. */
class Palette {
    HashTable<string, string> colors = new HashTable<string, string>(str_hash, str_equal);

    /* From arguments such as "ACCENT=#3574f0". */
    public Palette(string[] assignments) throws Error {
        var pattern = new Regex("^(\\w+)=(#[0-9a-fA-F]{6})$");
        foreach (unowned string assignment in assignments) {
            MatchInfo match;
            if (!pattern.match(assignment, 0, out match)) {
                throw new PaletteError.INVALID_COLOR("%s is not KEY=#rrggbb".printf(assignment));
            }
            colors[match.fetch(1)] = match.fetch(2);
        }
    }

    public void set_color(string name, Color color) {
        colors[name] = color.to_hex();
    }

    public string hex(string name) throws PaletteError {
        unowned string? color = colors[name];
        if (color == null) {
            throw new PaletteError.MISSING_COLOR("the color %s is missing".printf(name));
        }
        return color;
    }

    public Color color(string name) throws PaletteError {
        return Color.parse(hex(name));
    }
}

/* Maps the lightness of a gray in the base theme to a color of the variant. */
class GrayRamp {
    double[] lightness = {};
    Color[] colors = {};

    /* From the darkest to the lightest. */
    public void add(double lightness, Color color) {
        this.lightness += lightness;
        colors += color;
    }

    /* Null if it is lighter than the last step. */
    public Color? at(double wanted) {
        for (int index = 1; index < lightness.length; index++) {
            if (wanted <= lightness[index]) {
                double start = lightness[index - 1];
                double share = (wanted - start) / (lightness[index] - start);
                return colors[index - 1].mix(colors[index], share);
            }
        }
        return null;
    }
}
