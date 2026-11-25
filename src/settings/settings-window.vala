class SettingsWindow : Gtk.ApplicationWindow {
    const int SIDEBAR_WIDTH = 190;      // px

    Gtk.Stack stack = new Gtk.Stack();
    Gtk.ListBox sidebar = new Gtk.ListBox();

    public SettingsWindow(Gtk.Application application) {
        Object(application: application);
        title = "Mini DE Settings";
        icon_name = "preferences-desktop";
        set_default_size(1040, 640);

        stack.transition_type = Gtk.StackTransitionType.CROSSFADE;
        sidebar.selection_mode = Gtk.SelectionMode.BROWSE;
        sidebar.set_size_request(SIDEBAR_WIDTH, -1);
        sidebar.row_selected.connect((row) => {
            if (row != null) {
                stack.visible_child = ((PageRow) row).page;
            }
        });

        add_page(new WallpaperPage(this));
        add_page(new IconsPage());
        add_page(new WindowsPage());
        add_page(new SoundPage());

        var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
        box.pack_start(sidebar, false, false);
        box.pack_start(new Gtk.Separator(Gtk.Orientation.VERTICAL), false, false);
        box.pack_start(stack, true, true);
        add(box);
        show_all();
        sidebar.select_row(sidebar.get_row_at_index(0));
    }

    void add_page(Page page) {
        stack.add(page);
        sidebar.add(new PageRow(page));
    }

    /* Does nothing if there is no such page. */
    public void show_page(string id) {
        foreach (var row in sidebar.get_children()) {
            if (((PageRow) row).page.page_id == id) {
                sidebar.select_row((PageRow) row);
            }
        }
    }
}

class PageRow : Gtk.ListBoxRow {
    public Page page;

    public PageRow(Page page) {
        this.page = page;
        var label = new Gtk.Label(page.page_title);
        label.xalign = 0;
        var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 10);
        box.margin = 10;
        box.pack_start(
            new Gtk.Image.from_icon_name(page.page_icon, Gtk.IconSize.LARGE_TOOLBAR),
            false,
            false
        );
        box.pack_start(label, true, true);
        add(box);
    }
}
