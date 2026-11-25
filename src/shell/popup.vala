/* A window without decorations in the middle of the monitor with the pointer. */
class Popup : Gtk.Window {
    public Popup(string css_name) {
        Object(type: Gtk.WindowType.POPUP);
        name = css_name;
    }

    /* Lets picom blend the window, and tells it not to draw a rectangular shadow. */
    public void make_translucent() {
        app_paintable = true;
        type_hint = Gdk.WindowTypeHint.NOTIFICATION;
        var visual = get_screen().get_rgba_visual();
        if (visual != null) {
            set_visual(visual);
        }
    }

    public void show_centered() {
        Styles.refresh_colors();
        get_child().show_all();

        Gtk.Requisition size;
        get_preferred_size(null, out size);
        var monitor = monitor_with_pointer();
        resize(size.width, size.height);
        move(
            monitor.x + (monitor.width - size.width) / 2,
            monitor.y + (monitor.height - size.height) / 2
        );
        show();
    }

    public static Gdk.Rectangle monitor_with_pointer() {
        var display = Gdk.Display.get_default();
        int x, y;
        display.get_default_seat().get_pointer().get_position(null, out x, out y);
        return display.get_monitor_at_point(x, y).get_geometry();
    }
}

/* Adds or removes a CSS class. */
void set_css_class(Gtk.Widget widget, string css_class, bool enabled) {
    var context = widget.get_style_context();
    if (enabled) {
        context.add_class(css_class);
    } else {
        context.remove_class(css_class);
    }
}
