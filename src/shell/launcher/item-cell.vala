/* What happens when apps are dragged onto each other. */
interface DragHandler : Object {
    public abstract void on_drag_started(App app);
    public abstract void on_drag_ended();
    public abstract bool can_drop_on(LauncherItem item);
    public abstract void on_dropped_on(LauncherItem item);
}

namespace AppDrag {
    public const Gtk.TargetEntry[] TARGETS = {
        { "application/x-mini-de-app", Gtk.TargetFlags.SAME_APP, 0 }
    };

    public void allow_dropping_on(Gtk.Widget widget) {
        Gtk.drag_dest_set(widget, 0, TARGETS, Gdk.DragAction.MOVE);
    }

    public void show_status(Gdk.DragContext context, bool allowed, uint time) {
        Gdk.drag_status(context, allowed ? Gdk.DragAction.MOVE : 0, time);
    }
}

/* An app or folder in the grid. */
class ItemCell : Gtk.FlowBoxChild {
    public const int WIDTH = 172;   // px
    const int HEIGHT = 180;         // px

    public LauncherItem item;
    DragHandler? drag_handler;      // null if nothing can be dragged here
    AppIcons icons;
    ItemArt art;
    Gtk.EventBox event_box = new Gtk.EventBox();
    bool hovered = false;
    bool pressed = false;

    public ItemCell(LauncherItem item, AppIcons icons, DragHandler? drag_handler) {
        this.item = item;
        this.icons = icons;
        this.drag_handler = drag_handler;
        can_focus = false;
        set_size_request(WIDTH, HEIGHT);

        art = new ItemArt(item, icons);
        var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 2);
        box.margin = 6;
        box.pack_start(art, false, false);
        box.pack_start(create_label(), false, false);
        event_box.visible_window = false;
        event_box.above_child = true;
        event_box.add(box);
        add(event_box);

        follow_pointer();
        state_flags_changed.connect(() => update_look());
        if (drag_handler != null) {
            set_up_dragging();
        }
    }

    Gtk.Label create_label() {
        var label = new Gtk.Label(item.name);
        label.justify = Gtk.Justification.CENTER;
        label.wrap = true;
        label.wrap_mode = Pango.WrapMode.WORD_CHAR;
        label.lines = 2;
        label.ellipsize = Pango.EllipsizeMode.END;
        label.max_width_chars = 14;
        label.valign = Gtk.Align.START;
        return label;
    }

    // ── look ────────────────────────────────────────────────

    void follow_pointer() {
        event_box.add_events(
            Gdk.EventMask.ENTER_NOTIFY_MASK
            | Gdk.EventMask.LEAVE_NOTIFY_MASK
            | Gdk.EventMask.BUTTON_PRESS_MASK
            | Gdk.EventMask.BUTTON_RELEASE_MASK
        );
        event_box.enter_notify_event.connect((event) => on_crossing(event, true));
        event_box.leave_notify_event.connect((event) => on_crossing(event, false));
        event_box.button_press_event.connect((event) => on_button(event, true));
        event_box.button_release_event.connect((event) => on_button(event, false));
    }

    bool on_crossing(Gdk.EventCrossing event, bool inside) {
        if (event.detail != Gdk.NotifyType.INFERIOR) {
            hovered = inside;
            pressed = pressed && inside;
            update_look();
        }
        return false;
    }

    bool on_button(Gdk.EventButton event, bool down) {
        if (event.button == Gdk.BUTTON_PRIMARY) {
            pressed = down;
            update_look();
        }
        return false;
    }

    void update_look() {
        set_css_class(this, "hover", hovered);
        if (pressed) {
            art.zoom_to(ItemArt.PRESSED_SCALE);
        } else if (hovered || is_selected()) {
            art.zoom_to(ItemArt.HOVER_SCALE);
        } else {
            art.zoom_to(1);
        }
    }

    public void reset_look() {
        hovered = false;
        pressed = false;
        update_look();
    }

    // ── dragging ────────────────────────────────────────────

    void set_up_dragging() {
        var app = item as App;
        if (app != null) {
            Gtk.drag_source_set(
                event_box,
                Gdk.ModifierType.BUTTON1_MASK,
                AppDrag.TARGETS,
                Gdk.DragAction.MOVE
            );
            event_box.drag_begin.connect((context) => {
                reset_look();
                var icon = icons.find_or_default(app.info, ItemArt.ICON_SIZE);
                if (icon != null) {
                    Gtk.drag_set_icon_pixbuf(context, icon, icon.width / 2, icon.height / 2);
                }
                drag_handler.on_drag_started(app);
            });
            event_box.drag_data_get.connect((context, data, info, time) => {
                data.set(data.get_target(), 8, "app".data);
            });
            event_box.drag_end.connect((context) => drag_handler.on_drag_ended());
        }
        AppDrag.allow_dropping_on(event_box);
        event_box.drag_motion.connect((context, x, y, time) => {
            hovered = drag_handler.can_drop_on(item);
            update_look();
            AppDrag.show_status(context, hovered, time);
            return true;            // nothing behind this cell gets the drop
        });
        event_box.drag_leave.connect((context, time) => reset_look());
        event_box.drag_drop.connect((context, x, y, time) => {
            bool allowed = drag_handler.can_drop_on(item);
            Gtk.drag_finish(context, allowed, false, time);
            reset_look();
            if (allowed) {
                drag_handler.on_dropped_on(item);
            }
            return true;
        });
    }
}
