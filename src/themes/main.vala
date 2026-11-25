/* Recolors themes of other programs; used by install.sh. */
const string USAGE = """usage:
  mini-de-theme qt <KvLibadwaita directory> <output directory> KEY=#rrggbb ...
  mini-de-theme telegram <colors of the night theme> <output directory> KEY=#rrggbb ...
""";

int main(string[] args) {
    if (args.length < 4) {
        stderr.printf("%s", USAGE);
        return 2;
    }
    try {
        var palette = new Palette(args[4:args.length]);
        switch (args[1]) {
            case "qt":
                new QtTheme(palette).build(args[2], args[3]);
                return 0;
            case "telegram":
                new TelegramTheme(palette).build(args[2], args[3]);
                return 0;
            default:
                stderr.printf("%s", USAGE);
                return 2;
        }
    } catch (Error error) {
        stderr.printf("mini-de-theme: %s\n", error.message);
        return 1;
    }
}
