/* Apps that the user does not want to see, one desktop id per line of a file. */
class HiddenApps {
    string path = Path.build_filename(Environment.get_user_config_dir(), "mini-de", "hidden-apps");
    string[] ids = {};

    public HiddenApps() {
        read();
    }

    public void read() {
        ids = {};
        string text;
        try {
            FileUtils.get_contents(path, out text);
        } catch (Error error) {
            return;         // nothing has been hidden yet
        }
        foreach (unowned string line in text.split("\n")) {
            string id = line.strip();
            if (id != "") {
                ids += id;
            }
        }
    }

    public bool contains(App app) {
        return app.id in ids;
    }

    /* Folders of hidden apps are remembered by GNOME's settings. */
    public void set_hidden(App app, bool hidden) throws Error {
        read();
        ids = hidden ? StringLists.with(ids, app.id) : StringLists.without(ids, app.id);
        write();
    }

    void write() throws Error {
        var sorted = new GenericArray<string>();
        foreach (unowned string id in ids) {
            sorted.add(id);
        }
        sorted.sort(strcmp);
        var text = new StringBuilder();
        foreach (unowned string id in sorted) {
            text.append(id);
            text.append_c('\n');
        }
        DirUtils.create_with_parents(Path.get_dirname(path), 0755);
        FileUtils.set_contents(path, text.str);
    }
}
