/* Context menu of an app or folder. */
class ItemMenu : Gtk.Menu {
    delegate void Action();

    unowned Launcher launcher;
    unowned LauncherModel model;

    public ItemMenu(Launcher launcher, LauncherModel model, LauncherItem item) {
        this.launcher = launcher;
        this.model = model;
        var folder = item as Folder;
        if (folder == null) {
            add_app_actions((App) item);
        } else if (folder.id == LauncherModel.HIDDEN_FOLDER) {
            add_action(this, "Show all apps again", () => model.unhide_all());
        } else {
            add_action(this, "Rename…", () => launcher.ask_to_rename(folder));
            add_action(this, "Remove folder", () => model.remove_folder(folder));
        }
        attach_to_widget(launcher, null);
        show_all();
    }

    void add_app_actions(App app) {
        if (model.is_pinned(app)) {
            add_action(this, "Unpin from dock", () => model.dock.unpin(app));
        } else {
            add_action(this, "Pin to dock", () => model.dock.pin(app));
        }
        append(new Gtk.SeparatorMenuItem());

        var current_folder = model.folder_of(app);
        add_folders(app, current_folder);
        if (current_folder != null) {
            add_action(this, "Remove from folder", () => model.move_app(app, null));
        }
        append(new Gtk.SeparatorMenuItem());

        if (model.hidden_apps.contains(app)) {
            add_action(this, "Unhide", () => model.set_hidden(app, false));
        } else {
            add_action(this, "Hide", () => model.set_hidden(app, true));
        }
    }

    void add_folders(App app, Folder? current_folder) {
        var submenu = new Gtk.Menu();
        foreach (var folder in model.folders) {
            if (folder != current_folder) {
                string id = folder.id;
                add_action(submenu, folder.name, () => model.move_app(app, id));
            }
        }
        if (submenu.get_children() != null) {
            submenu.append(new Gtk.SeparatorMenuItem());
        }
        add_action(submenu, "New folder…", () => launcher.ask_to_create_folder({ app }));

        var parent = new Gtk.MenuItem.with_label("Move to folder");
        parent.submenu = submenu;
        append(parent);
    }

    static void add_action(Gtk.Menu menu, string label, owned Action action) {
        var menu_item = new Gtk.MenuItem.with_label(label);
        menu_item.activate.connect(() => action());
        menu.append(menu_item);
    }
}
