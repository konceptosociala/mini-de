/* A page of the settings with its title and a place for error messages. */
abstract class Page : Gtk.Box {
    const int MARGIN = 20;      // px

    public string page_id;
    public string page_title;
    public string page_icon;

    protected Gtk.Box header = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
    Gtk.Label error_label = new Gtk.Label("");

    protected Page(string id, string title, string icon) {
        Object(orientation: Gtk.Orientation.VERTICAL, spacing: 14);
        page_id = id;
        page_title = title;
        page_icon = icon;
        margin_top = MARGIN;

        var title_label = new Gtk.Label(title);
        title_label.xalign = 0;
        title_label.get_style_context().add_class("page-title");
        header.pack_start(title_label, true, true);
        add_content(header);

        error_label.xalign = 0;
        error_label.wrap = true;
        error_label.no_show_all = true;
        error_label.get_style_context().add_class("error");
        add_content(error_label);
    }

    protected void add_content(Gtk.Widget widget) {
        widget.margin_start = MARGIN;
        widget.margin_end = MARGIN;
        pack_start(widget, false, false);
    }

    /* Takes the rest of the page. */
    protected void add_scrolled(Gtk.Widget widget) {
        var window = scrolled(widget);
        window.margin_start = MARGIN;
        window.margin_end = MARGIN;
        window.margin_bottom = MARGIN;
        pack_start(window, true, true);
    }

    /* The same, but the scrollbar is at the edge of the page, away from switches and buttons. */
    protected void add_scrolled_to_edge(Gtk.Widget widget) {
        widget.margin_start = MARGIN;
        widget.margin_end = MARGIN;
        widget.margin_bottom = MARGIN;
        pack_start(scrolled(widget), true, true);
    }

    protected void show_error(string message) {
        error_label.label = message;
        error_label.show();
    }

    protected void clear_error() {
        error_label.hide();
    }

    static Gtk.ScrolledWindow scrolled(Gtk.Widget child) {
        var window = new Gtk.ScrolledWindow(null, null);
        window.hscrollbar_policy = Gtk.PolicyType.NEVER;
        window.add(child);
        return window;
    }

    protected static Gtk.Label left_label(string text) {
        var label = new Gtk.Label(text);
        label.xalign = 0;
        return label;
    }
}
