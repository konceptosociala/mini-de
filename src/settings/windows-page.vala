class WindowsPage : Page {
    const uint APPLY_DELAY = 350;       // ms: wait for the slider to settle
    const int SLIDER_WIDTH = 320;       // px

    TitlebarFont font;
    Gtk.Scale size_scale;
    Gtk.Switch bold_switch = new Gtk.Switch();
    uint apply_timer = 0;

    public WindowsPage() {
        base("windows", "Windows", "preferences-system-windows");
        spacing = 18;
        try {
            font = new TitlebarFont();
        } catch (Error error) {
            show_error("The titlebar settings cannot be read: %s".printf(error.message));
            return;
        }
        build();
        size_scale.value_changed.connect(schedule_apply);
        bold_switch.notify["active"].connect(schedule_apply);
    }

    void build() {
        int smallest = font.sizes[0];
        int largest = font.sizes[font.sizes.length - 1];
        size_scale = new Gtk.Scale.with_range(Gtk.Orientation.HORIZONTAL, smallest, largest, 1);
        size_scale.draw_value = false;
        size_scale.set_size_request(SLIDER_WIDTH, -1);
        foreach (int size in font.sizes) {
            size_scale.add_mark(size, Gtk.PositionType.BOTTOM, size.to_string());
        }
        size_scale.set_value(font.size.clamp(smallest, largest));
        bold_switch.active = font.bold;
        bold_switch.halign = Gtk.Align.START;

        var grid = new Gtk.Grid();
        grid.row_spacing = 18;
        grid.column_spacing = 30;
        grid.attach(left_label("Titlebar font size"), 0, 0);
        grid.attach(size_scale, 1, 0);
        grid.attach(left_label("Bold titles"), 0, 1);
        grid.attach(bold_switch, 1, 1);
        add_content(grid);

        var hint = left_label(
            "The change is applied to all windows at once. The height of titlebars stays the same."
        );
        hint.wrap = true;
        hint.get_style_context().add_class("dim-label");
        add_content(hint);
    }

    void schedule_apply() {
        if (apply_timer != 0) {
            Source.remove(apply_timer);
        }
        apply_timer = Timeout.add(APPLY_DELAY, () => {
            apply_timer = 0;
            apply();
            return Source.REMOVE;
        });
    }

    void apply() {
        int size = (int) Math.rint(size_scale.get_value());
        if (size == font.size && bold_switch.active == font.bold) {
            return;
        }
        try {
            font.apply(size, bold_switch.active);
            clear_error();
        } catch (Error error) {
            show_error("Not changed: %s".printf(error.message));
        }
    }
}
