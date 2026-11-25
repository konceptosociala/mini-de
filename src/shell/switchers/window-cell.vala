/* One window in the popup of the window switcher. */
class WindowCell : Gtk.EventBox {
    public const int WIDTH = 160;       // px

    public signal void hovered();
    public signal void clicked();

    Gtk.Box box = new Gtk.Box(Gtk.Orientation.VERTICAL, 8);

    public WindowCell(string caption, Gdk.Pixbuf? icon, bool minimized) {
        var image = new Gtk.Image.from_pixbuf(icon);
        image.set_size_request(AppCatalog.ICON_SIZE, AppCatalog.ICON_SIZE);
        var label = new Gtk.Label(caption);
        label.ellipsize = Pango.EllipsizeMode.END;
        box.pack_start(image, false, false);
        box.pack_start(label, false, false);
        set_css_class(box, "cell", true);       // an event box ignores padding
        set_css_class(box, "minimized", minimized);
        add(box);

        add_events(Gdk.EventMask.BUTTON_RELEASE_MASK | Gdk.EventMask.POINTER_MOTION_MASK);
        motion_notify_event.connect((event) => {
            hovered();
            return false;
        });
        button_release_event.connect((event) => {
            clicked();
            return false;
        });
    }

    public void set_selected(bool selected) {
        set_css_class(box, "selected", selected);
    }

    // Always the same width, so that a long name is cut instead of widening the cell.
    public override void get_preferred_width(out int minimum, out int natural) {
        minimum = natural = WIDTH;
    }

    public override void get_preferred_width_for_height(int height, out int minimum, out int natural) {
        minimum = natural = WIDTH;
    }
}
