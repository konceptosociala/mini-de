/* Asks the user with rofi. */
namespace Rofi {
    public const int CANCELLED = -1;

    /* Index of the chosen item. */
    public async int choose(string prompt, string[] items, string[] options = {}) {
        string[] arguments = { "rofi", "-dmenu", "-i", "-p", prompt, "-format", "i" };
        foreach (unowned string option in options) {
            arguments += option;
        }
        string answer;
        try {
            answer = yield Command.run_async(arguments, string.joinv("\n", items));
        } catch (Error error) {
            return CANCELLED;
        }
        int index;
        return int.try_parse(answer.strip(), out index, null, 10) ? index : CANCELLED;
    }

    /* Null if it was cancelled. */
    public async string? ask(string prompt) {
        return yield ask_with(prompt, {});
    }

    public async string? ask_password(string prompt) {
        return yield ask_with(prompt, { "-password" });
    }

    async string? ask_with(string prompt, string[] options) {
        string[] arguments = { "rofi", "-dmenu", "-p", prompt, "-l", "0" };
        foreach (unowned string option in options) {
            arguments += option;
        }
        try {
            string answer = yield Command.run_async(arguments, "");
            return answer.has_suffix("\n") ? answer.substring(0, answer.length - 1) : answer;
        } catch (Error error) {
            return null;
        }
    }

    /* Options that highlight these items. */
    public string[] highlight(int[] indexes) {
        if (indexes.length == 0) {
            return {};
        }
        var list = new StringBuilder();
        foreach (int index in indexes) {
            list.append("%s%d".printf(list.len > 0 ? "," : "", index));
        }
        return { "-a", list.str };
    }
}
