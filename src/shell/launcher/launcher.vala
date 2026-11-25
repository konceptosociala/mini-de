/* Full-screen launcher with the app folders of GNOME and a .hidden folder (Ctrl+H). */
class Launcher : Gtk.Window, DragHandler {
    const int SEARCH_WIDTH = 460;           // px
    const int FOLDER_COLUMNS = 6;
    const double FOLDER_HEIGHT = 0.65;      // of the screen
    const double THE_END = 1000000;         // scroll position
    const string CSS = """
        @define-color md_surface #1d2021;
        @define-color md_panel #282828;
        @define-color md_border #504945;
        @define-color md_raised #3c3836;
        @define-color md_fg #ebdbb2;
        @define-color md_dim #928374;
        @define-color md_accent #fabd2f;
        @define-color md_accent_text #fabd2f;
        @define-color md_on_accent #1d2021;
        @define-color md_tile #504945;
        #launcher {
            background: alpha(@md_surface, 0.90);
        }
        #launcher.opaque {
            background: @md_surface;
        }
        #launcher scrolledwindow,
        #launcher viewport,
        #launcher flowbox {
            background: transparent;
            border: none;
        }
        #search {
            font: 18px "Inter";
            color: @md_fg;
            background: @md_raised;
            caret-color: @md_accent;
            border: 2px solid @md_border;
            border-radius: 24px;
            padding: 8px 18px;
            box-shadow: none;
        }
        #search:focus {
            border-color: @md_accent;
        }
        #launcher flowboxchild {
            border-radius: 14px;
            padding: 0;
            background: transparent;
            outline: none;
            transition: background 160ms ease-out;
        }
        #launcher flowboxchild.hover {
            background: alpha(@md_fg, 0.10);
        }
        #launcher flowboxchild:selected {
            background: alpha(@md_accent, 0.22);
        }
        #launcher label {
            color: @md_fg;
            font: 14px "Inter";
        }
        #eye {
            color: @md_dim;
            background: transparent;
            border: none;
            box-shadow: none;
            border-radius: 24px;
            padding: 10px;
        }
        #eye:hover {
            color: @md_fg;
            background: alpha(@md_fg, 0.10);
        }
        #dim {
            background: rgba(0, 0, 0, 0.55);
        }
        #launcher menu {
            background: @md_panel;
            border: 1px solid @md_border;
            padding: 4px;
        }
        #launcher menuitem {
            padding: 6px 12px;
        }
        #launcher menuitem:hover {
            background: alpha(@md_accent, 0.35);
        }
        #panel {
            background: @md_panel;
            border: 2px solid @md_border;
            border-radius: 20px;
        }
        #launcher #title {
            font: 700 22px "Inter";
            color: @md_accent_text;
        }
        #launcher #empty {
            font: 18px "Inter";
            color: @md_dim;
        }
    """;

    /* Where a click landed. */
    enum Place {
        SOMETHING,          // an item, the search, a button
        EMPTY_PAGE,
        AROUND_FOLDER
    }

    AppIcons icons;
    LauncherModel model = new LauncherModel();

    Gtk.Entry search = new Gtk.Entry();
    Gtk.Stack stack = new Gtk.Stack();
    ItemGrid all_items;
    ItemGrid found_items;
    Gtk.Label nothing_found = new Gtk.Label("Nothing found");
    Gtk.Image eye_image = new Gtk.Image();
    Gtk.EventBox dim = new Gtk.EventBox();      // around an open folder
    Gtk.EventBox folder_panel = new Gtk.EventBox();
    Gtk.Label folder_title = new Gtk.Label("");
    ItemGrid folder_items;

    Gdk.Rectangle monitor = { 0, 0, 1920, 1080 };
    bool show_hidden = false;
    string open_folder_id = "";
    Place pressed_place = Place.SOMETHING;
    App? dragged_app = null;
    Gtk.Dialog? dialog = null;
    ItemMenu? menu = null;
    bool had_focus = false;
    uint h_keycode = 0;

    public Launcher(AppIcons icons) {
        this.icons = icons;
        name = "launcher";
        title = "Applications";
        decorated = false;
        skip_taskbar_hint = true;
        skip_pager_hint = true;
        set_keep_above(true);
        set_wmclass("launcher", "Launcher");
        var visual = get_screen().get_rgba_visual();
        if (visual != null) {
            set_visual(visual);
        }
        Styles.add(CSS);

        all_items = create_grid(this);
        found_items = create_grid(null);
        folder_items = create_grid(this);
        build();
        connect_events();

        warm_up_icons();
        refill();
        model.changed.connect(on_model_changed);
    }

    ItemGrid create_grid(DragHandler? drag_handler) {
        var grid = new ItemGrid(icons, drag_handler);
        grid.picked.connect(pick);
        return grid;
    }

    void warm_up_icons() {
        foreach (var app in model.apps) {
            icons.find_or_default(app.info, ItemArt.ICON_SIZE);
        }
    }

    // ── building ────────────────────────────────────────────

    void build() {
        var overlay = new Gtk.Overlay();
        overlay.add(build_page());
        overlay.add_overlay(build_eye());
        overlay.add_overlay(build_folder());
        add(overlay);
        overlay.show_all();
        dim.hide();
    }

    Gtk.Widget build_page() {
        search.name = "search";
        search.placeholder_text = "Search…";
        search.halign = Gtk.Align.CENTER;
        search.set_size_request(SEARCH_WIDTH, -1);
        search.set_icon_from_icon_name(Gtk.EntryIconPosition.PRIMARY, "edit-find-symbolic");

        nothing_found.name = "empty";
        stack.add(all_items);
        stack.add(found_items);
        stack.add(nothing_found);

        var page = new Gtk.Box(Gtk.Orientation.VERTICAL, 36);
        page.margin_top = 56;
        page.margin_bottom = 40;
        page.margin_start = 40;
        page.margin_end = 40;
        page.pack_start(search, false, false);
        page.pack_start(stack, true, true);
        return page;
    }

    Gtk.Widget build_eye() {
        var eye = new Gtk.Button();
        eye.name = "eye";
        eye.relief = Gtk.ReliefStyle.NONE;
        eye.can_focus = false;
        eye.halign = Gtk.Align.END;
        eye.valign = Gtk.Align.START;
        eye.margin = 56;
        eye.tooltip_text = "Show or hide the .hidden folder (Ctrl+H)";
        eye.add(eye_image);
        eye.clicked.connect(toggle_hidden);
        return eye;
    }

    Gtk.Widget build_folder() {
        folder_title.name = "title";
        folder_items.propagate_natural_height = true;
        folder_items.propagate_natural_width = true;
        var column = new Gtk.Box(Gtk.Orientation.VERTICAL, 18);
        column.margin = 26;
        column.pack_start(folder_title, false, false);
        column.pack_start(folder_items, true, true);

        folder_panel.name = "panel";
        folder_panel.halign = Gtk.Align.CENTER;
        folder_panel.valign = Gtk.Align.CENTER;
        folder_panel.add(column);
        dim.name = "dim";
        dim.add(folder_panel);

        // dropping an app outside the open folder takes it out; the panel itself accepts nothing
        set_up_dropping(dim, true);
        set_up_dropping(folder_panel, false);
        return dim;
    }

    void set_up_dropping(Gtk.Widget widget, bool outside) {
        AppDrag.allow_dropping_on(widget);
        widget.drag_motion.connect((context, x, y, time) => {
            AppDrag.show_status(context, outside && dragged_app != null, time);
            return true;
        });
        widget.drag_drop.connect((context, x, y, time) => {
            bool allowed = outside && dragged_app != null;
            Gtk.drag_finish(context, allowed, false, time);
            if (allowed) {
                take_out_of_folder(dragged_app);
            }
            return true;
        });
    }

    void connect_events() {
        add_events(Gdk.EventMask.BUTTON_PRESS_MASK | Gdk.EventMask.BUTTON_RELEASE_MASK);
        button_press_event.connect(on_button_pressed);
        button_release_event.connect(on_button_released);
        key_press_event.connect(on_key_pressed);
        focus_in_event.connect(() => {
            had_focus = true;
            return false;
        });
        focus_out_event.connect(() => {
            on_focus_lost();
            return false;
        });
        delete_event.connect(() => {
            close_launcher();
            return true;
        });
        search.changed.connect(update_search);

        Gdk.KeymapKey[] keys;
        var keymap = Gdk.Keymap.get_for_display(Gdk.Display.get_default());
        if (keymap.get_entries_for_keyval(Gdk.Key.h, out keys) && keys.length > 0) {
            h_keycode = keys[0].keycode;
        }
    }

    // ── contents ────────────────────────────────────────────

    void on_model_changed() {
        double position = all_items.scroll_position();
        string reopened_id = dim.visible ? open_folder_id : "";
        warm_up_icons();
        refill();
        all_items.scroll_later(position);
        var folder = reopened_id != "" ? model.find_folder(reopened_id) : null;
        if (folder != null) {
            open_folder(folder);
        }
    }

    void refill() {
        var items = new GenericArray<LauncherItem>();
        foreach (var folder in model.folders) {
            items.add(folder);
        }
        foreach (var app in model.loose_apps) {
            items.add(app);
        }
        if (show_hidden) {
            items.add(model.hidden_folder);
        }
        all_items.fill(items, columns());
        eye_image.set_from_icon_name(
            show_hidden ? "view-reveal-symbolic" : "view-conceal-symbolic",
            Gtk.IconSize.LARGE_TOOLBAR
        );
        close_folder();
        update_search();
    }

    int columns() {
        return ItemGrid.columns_for_width(monitor.width);
    }

    void toggle_hidden() {
        show_hidden = !show_hidden;
        refill();
        if (show_hidden) {
            all_items.scroll_later(THE_END);        // the tile is the last one
        }
    }

    void update_search() {
        string query = search.text.strip().casefold();
        if (query == "") {
            stack.visible_child = all_items;
            return;
        }
        close_folder();
        var found = model.search(query, show_hidden);
        found_items.fill(found, columns());
        if (found.length == 0) {
            stack.visible_child = nothing_found;
            return;
        }
        stack.visible_child = found_items;
        int first_app = 0;
        while (first_app < found.length && !(found[first_app] is App)) {
            first_app++;
        }
        found_items.select(first_app < found.length ? first_app : 0);
    }

    ItemGrid current_grid() {
        if (dim.visible) {
            return folder_items;
        }
        return stack.visible_child == found_items ? found_items : all_items;
    }

    // ── showing ─────────────────────────────────────────────

    public void toggle() {
        if (visible) {
            close_launcher();
        } else {
            open();
        }
    }

    void open() {
        Styles.refresh_colors();
        set_css_class(this, "opaque", !get_screen().is_composited());

        var new_monitor = Popup.monitor_with_pointer();
        bool width_changed = new_monitor.width != monitor.width;
        monitor = new_monitor;
        if (width_changed || show_hidden) {
            show_hidden = false;        // hidden apps are hidden again every time
            refill();
        }
        search.text = "";
        all_items.reset();
        all_items.scroll_to(0);
        had_focus = false;
        fullscreen_on_monitor(get_screen(), monitor_number());
        show();
        take_focus();
        search.grab_focus();
    }

    int monitor_number() {
        var display = Gdk.Display.get_default();
        for (int number = 0; number < display.get_n_monitors(); number++) {
            if (display.get_monitor(number).geometry.equal(monitor)) {
                return number;
            }
        }
        return 0;
    }

    void take_focus() {
        present_with_time(Gdk.X11.get_server_time((Gdk.X11.Window) get_window()));
    }

    void close_launcher() {
        close_folder();
        hide();
        icons.forget_larger_than(ItemArt.ICON_SIZE);
    }

    void on_focus_lost() {
        bool menu_open = menu != null && menu.visible;
        bool busy = dialog != null || dragged_app != null || menu_open;
        if (had_focus && visible && !busy) {
            close_launcher();
        }
    }

    void open_folder(Folder folder) {
        open_folder_id = folder.id;
        folder_title.label = folder.name;
        var items = new GenericArray<LauncherItem>();
        foreach (var app in folder.apps) {
            items.add(app);
        }
        int wanted_columns = int.min(items.length, FOLDER_COLUMNS);
        folder_items.fill(items, int.min(wanted_columns, columns()));
        folder_items.max_content_height = (int) (monitor.height * FOLDER_HEIGHT);
        dim.show();
    }

    void close_folder() {
        dim.hide();
    }

    // ── actions ─────────────────────────────────────────────

    void pick(LauncherItem item) {
        var folder = item as Folder;
        if (folder == null) {
            launch((App) item);
        } else if (folder.apps.length > 0) {
            open_folder(folder);
        }
    }

    void launch(App app) {
        close_launcher();
        var context = Gdk.Display.get_default().get_app_launch_context();
        context.set_timestamp(Gtk.get_current_event_time());
        try {
            app.info.launch(null, context);
        } catch (Error error) {
            Notifications.show.begin("Could not launch " + app.name, error.message);
        }
    }

    public void ask_to_create_folder(App[] apps) {
        string? folder_name = ask_name("New folder", "New folder");
        if (folder_name != null) {
            model.create_folder(folder_name, apps);
        }
    }

    public void ask_to_rename(Folder folder) {
        string? folder_name = ask_name("Rename folder", folder.name);
        if (folder_name != null && folder_name != folder.name) {
            model.rename_folder(folder, folder_name);
        }
    }

    /* Null if it was cancelled. */
    string? ask_name(string dialog_title, string suggestion) {
        dialog = new Gtk.Dialog.with_buttons(
            dialog_title,
            this,
            Gtk.DialogFlags.MODAL,
            "Cancel",
            Gtk.ResponseType.CANCEL,
            "OK",
            Gtk.ResponseType.OK
        );
        dialog.resizable = false;
        dialog.set_default_response(Gtk.ResponseType.OK);
        var entry = new Gtk.Entry();
        entry.text = suggestion;
        entry.activates_default = true;
        entry.width_chars = 28;
        entry.margin = 16;
        dialog.get_content_area().add(entry);
        dialog.show_all();
        entry.grab_focus();

        bool accepted = dialog.run() == Gtk.ResponseType.OK;
        string answer = entry.text.strip();
        dialog.destroy();
        dialog = null;
        take_focus();
        return accepted && answer != "" ? answer : null;
    }

    void show_menu(LauncherItem item) {
        var folder = item as Folder;
        if (folder == model.hidden_folder && folder != null && folder.apps.length == 0) {
            return;
        }
        if (menu != null) {
            menu.destroy();
        }
        menu = new ItemMenu(this, model, item);
        menu.popup_at_pointer();
    }

    // ── dragging ────────────────────────────────────────────

    public void on_drag_started(App app) {
        dragged_app = app;
    }

    public void on_drag_ended() {
        dragged_app = null;
    }

    public bool can_drop_on(LauncherItem item) {
        return dragged_app != null && item != dragged_app && !dim.visible;
    }

    public void on_dropped_on(LauncherItem item) {
        var app = dragged_app;
        var folder = item as Folder;
        after_drag(() => {
            if (folder == null) {
                ask_to_create_folder({ (App) item, app });
            } else if (folder.id == LauncherModel.HIDDEN_FOLDER) {
                model.set_hidden(app, true);
            } else {
                model.move_app(app, folder.id);
            }
        });
    }

    void take_out_of_folder(App app) {
        bool was_hidden = open_folder_id == LauncherModel.HIDDEN_FOLDER;
        after_drag(() => {
            if (was_hidden) {
                model.set_hidden(app, false);
            } else {
                model.move_app(app, null);
            }
        });
    }

    delegate void Change();

    /* A change recreates the cells, so it has to wait until GTK has finished with them. */
    void after_drag(owned Change change) {
        Idle.add(() => {
            dragged_app = null;
            change();
            return Source.REMOVE;
        });
    }

    // ── keyboard ────────────────────────────────────────────

    bool on_key_pressed(Gdk.EventKey event) {
        var grid = current_grid();
        bool control = (event.state & Gdk.ModifierType.CONTROL_MASK) != 0;
        if (control && event.hardware_keycode == h_keycode) {       // in any layout
            toggle_hidden();
            return true;
        }
        switch (event.keyval) {
            case Gdk.Key.Escape:
                go_back();
                return true;
            case Gdk.Key.Left:
            case Gdk.Key.ISO_Left_Tab:
                grid.move_selection(-1, 0);
                return true;
            case Gdk.Key.Right:
            case Gdk.Key.Tab:
                grid.move_selection(1, 0);
                return true;
            case Gdk.Key.Up:
                grid.move_selection(0, -1);
                return true;
            case Gdk.Key.Down:
                grid.move_selection(0, 1);
                return true;
            case Gdk.Key.Page_Up:
                grid.scroll_pages(-1);
                return true;
            case Gdk.Key.Page_Down:
                grid.scroll_pages(1);
                return true;
            case Gdk.Key.Return:
            case Gdk.Key.KP_Enter:
                var item = grid.selected_item();
                if (item != null) {
                    pick(item);
                }
                return true;
        }
        if (!search.has_focus) {
            search.grab_focus_without_selecting();
        }
        return false;
    }

    void go_back() {
        if (dim.visible) {
            close_folder();
        } else if (search.text != "") {
            search.text = "";
        } else {
            close_launcher();
        }
    }

    // ── mouse ───────────────────────────────────────────────

    bool on_button_pressed(Gdk.EventButton event) {
        var widget = Gtk.get_event_widget(Gtk.get_current_event());
        var cell = find_cell(widget);
        pressed_place = Place.SOMETHING;
        if (event.button == Gdk.BUTTON_SECONDARY && cell != null) {
            show_menu(cell.item);
            return true;
        }
        if (event.button == Gdk.BUTTON_PRIMARY && cell == null) {
            pressed_place = find_place(widget, (int) event.x_root, (int) event.y_root);
        }
        return false;
    }

    bool on_button_released(Gdk.EventButton event) {
        var place = pressed_place;
        pressed_place = Place.SOMETHING;
        switch (place) {
            case Place.AROUND_FOLDER:
                close_folder();
                return true;
            case Place.EMPTY_PAGE:
                close_launcher();
                return true;
            default:
                return false;
        }
    }

    static ItemCell? find_cell(Gtk.Widget? widget) {
        var current = widget;
        while (current != null && !(current is ItemCell)) {
            current = current.get_parent();
        }
        return current as ItemCell;
    }

    Place find_place(Gtk.Widget? widget, int root_x, int root_y) {
        if (widget == null) {
            return Place.EMPTY_PAGE;
        }
        int origin_x, origin_y;
        get_window().get_origin(out origin_x, out origin_y);
        foreach (var grid in new ItemGrid[] { all_items, found_items, folder_items }) {
            if (!grid.holds(widget)) {
                continue;
            }
            bool empty = !grid.has_cell_at(root_x - origin_x, root_y - origin_y);
            return empty && grid != folder_items ? Place.EMPTY_PAGE : Place.SOMETHING;
        }
        for (var current = widget; current != null; current = current.get_parent()) {
            bool useful = current is Gtk.Entry
                || current is Gtk.Scrollbar
                || current is Gtk.Button
                || current == folder_panel;
            if (useful) {
                return Place.SOMETHING;
            }
            if (current == dim) {
                return Place.AROUND_FOLDER;
            }
        }
        return Place.EMPTY_PAGE;
    }
}
