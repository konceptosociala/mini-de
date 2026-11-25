/* Name of the symbols of a keymap, such as "pc+us+ua:2+ru(phonetic):3+inet(evdev)":
   parts without a number belong to the first layout. */
namespace X11.KeymapSymbols {
    const int MAX_LAYOUTS = 4;
    // parts that add keys to layouts instead of being one
    const string[] NOT_LAYOUTS = {
        "altwin",
        "capslock",
        "compose",
        "ctrl",
        "eurosign",
        "group",
        "inet",
        "keypad",
        "kpdl",
        "level3",
        "level5",
        "nbsp",
        "pc",
        "rupeesign",
        "shift",
        "srvr_ctrl",
        "terminate"
    };

    /* Layouts in their order, without variants. */
    public string[] layouts(string symbols) {
        var found = new string?[MAX_LAYOUTS];
        foreach (unowned string part in symbols.split("+")) {
            string name;
            int number;
            parse(part, out name, out number);
            bool valid = name != ""
                && number >= 1
                && number <= MAX_LAYOUTS
                && !(name in NOT_LAYOUTS);
            if (valid && found[number - 1] == null) {
                found[number - 1] = name;
            }
        }
        string[] layouts = {};
        foreach (unowned string? name in found) {
            if (name == null) {
                break;
            }
            layouts += name;
        }
        return layouts;
    }

    /* "ru(phonetic):3" is ru, 3. */
    void parse(string part, out string name, out int number) {
        int number_start = part.index_of_char(':');
        number = number_start >= 0 ? int.parse(part.substring(number_start + 1)) : 1;

        int name_length = part.length;
        foreach (char delimiter in new char[] { '(', ':' }) {
            int position = part.index_of_char(delimiter);
            if (position >= 0) {
                name_length = int.min(name_length, position);
            }
        }
        name = part.substring(0, name_length);
    }
}
