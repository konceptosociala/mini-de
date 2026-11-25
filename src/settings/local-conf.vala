/* Settings of this machine in local.conf, which is a shell script. */
namespace LocalConf {
    string path() {
        return Path.build_filename(Environment.get_user_config_dir(), "mini-de", "local.conf");
    }

    /* Value of a variable, evaluated by the shell just like autostart does. */
    public string read(string name, string default_value) {
        string script = ". \"$1\" >/dev/null 2>&1; printf %s \"${" + name + "}\"";
        if (!FileUtils.test(path(), FileTest.EXISTS)) {
            return default_value;
        }
        try {
            string value = Command.run({ "sh", "-c", script, "sh", path() });
            return value != "" ? value : default_value;
        } catch (Error error) {
            return default_value;
        }
    }

    /* Replaces the variable and keeps everything else as it is. */
    public void write(string name, string value) throws Error {
        string text = "";
        if (FileUtils.test(path(), FileTest.EXISTS)) {
            FileUtils.get_contents(path(), out text);
        } else {
            DirUtils.create_with_parents(Path.get_dirname(path()), 0755);
        }
        string assignment = "%s=%s".printf(name, quote(value));
        Files.replace(path(), with_assignment(text, name, assignment));
    }

    /* The last assignment is the one that counts. */
    string with_assignment(string text, string name, string assignment) throws RegexError {
        var pattern = new Regex("^\\s*(export\\s+)?%s=".printf(name));
        var lines = new GenericArray<string>();
        int found = -1;
        foreach (unowned string line in text.split("\n")) {
            if (pattern.match(line)) {
                found = lines.length;
            }
            lines.add(line);
        }
        // the part after the final newline
        if (lines.length > 0 && lines[lines.length - 1] == "") {
            lines.remove_index(lines.length - 1);
        }
        if (found >= 0) {
            lines[found] = assignment;
        } else {
            lines.add(assignment);
        }
        var result = new StringBuilder();
        foreach (unowned string line in lines) {
            result.append(line);
            result.append_c('\n');
        }
        return result.str;
    }

    string quote(string value) {
        try {
            var safe = new Regex("^[\\w@%+=:,./-]+$", RegexCompileFlags.RAW);
            if (safe.match(value)) {
                return value;
            }
        } catch (RegexError error) {
            warning("%s", error.message);
        }
        return Shell.quote(value);
    }
}
