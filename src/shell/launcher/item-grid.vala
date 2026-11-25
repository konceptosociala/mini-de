/* Scrollable grid of items; the keyboard selection is moved by the launcher. */
class ItemGrid : Gtk.ScrolledWindow {
    const int SPACING = 10;                             // px
    const int COLUMN_WIDTH = ItemCell.WIDTH + 26;       // px, with some air
    const int MARGIN = 120;                             // px
    const int MAX_COLUMNS = 9;

    public signal void picked(LauncherItem item);

    AppIcons icons;
    unowned DragHandler? drag_handler;
    Gtk.FlowBox flow = new Gtk.FlowBox();
    int columns = 1;

    public ItemGrid(AppIcons icons, DragHandler? drag_handler) {
        this.icons = icons;
        this.drag_handler = drag_handler;
        hscrollbar_policy = Gtk.PolicyType.NEVER;
        flow.homogeneous = true;
        flow.halign = Gtk.Align.CENTER;
        flow.valign = Gtk.Align.START;
        flow.row_spacing = SPACING;
        flow.column_spacing = SPACING;
        flow.can_focus = false;
        flow.child_activated.connect((child) => picked(((ItemCell) child).item));
        add(flow);
    }

    /* How many columns a screen has room for. */
    public static int columns_for_width(int width) {
        return ((width - MARGIN) / COLUMN_WIDTH).clamp(1, MAX_COLUMNS);
    }

    public void fill(GenericArray<LauncherItem> items, int columns) {
        foreach (var cell in flow.get_children()) {
            cell.destroy();
        }
        this.columns = int.max(1, columns);
        // the lower limit may not exceed the upper one at any moment
        flow.min_children_per_line = 1;
        flow.max_children_per_line = this.columns;
        flow.min_children_per_line = this.columns;
        foreach (var item in items) {
            flow.add(new ItemCell(item, icons, drag_handler));
        }
        flow.show_all();
        scroll_to(0);
    }

    public void reset() {
        flow.unselect_all();
        foreach (var cell in flow.get_children()) {
            ((ItemCell) cell).reset_look();
        }
    }

    // ── selection ───────────────────────────────────────────

    public LauncherItem? selected_item() {
        var cell = selected_cell();
        return cell != null ? cell.item : null;
    }

    ItemCell? selected_cell() {
        var selected = flow.get_selected_children();
        return selected != null ? (ItemCell) selected.data : null;
    }

    public void select(int index) {
        var cell = flow.get_child_at_index(index);
        if (cell == null) {
            return;
        }
        flow.select_child(cell);
        Gtk.Allocation area;
        cell.get_allocation(out area);
        vadjustment.clamp_page(area.y, area.y + area.height);
    }

    public void move_selection(int right, int down) {
        int count = (int) flow.get_children().length();
        var cell = selected_cell();
        if (count == 0) {
            return;
        }
        if (cell == null) {
            select(0);
            return;
        }
        int current = cell.get_index();
        int next = current + right + down * columns;
        bool has_row_below = current / columns < (count - 1) / columns;
        if (down > 0 && next >= count && has_row_below) {
            next = count - 1;           // the last row is shorter
        }
        if (next >= 0 && next < count) {
            select(next);
        }
    }

    // ── scrolling ───────────────────────────────────────────

    public double scroll_position() {
        return vadjustment.value;
    }

    public void scroll_to(double position) {
        vadjustment.value = position;
    }

    /* When the new contents have got their sizes. */
    public void scroll_later(double position) {
        Idle.add(() => {
            scroll_to(position);
            return Source.REMOVE;
        });
    }

    public void scroll_pages(int pages) {
        vadjustment.value += pages * vadjustment.page_size;
    }

    // ── position of clicks ──────────────────────────────────

    /* Whether the widget is the area with the cells or something in it. */
    public bool holds(Gtk.Widget widget) {
        return widget == flow || widget.is_ancestor(flow);
    }

    /* Coordinates of the launcher window. */
    public bool has_cell_at(int window_x, int window_y) {
        int x, y;
        get_toplevel().translate_coordinates(flow, window_x, window_y, out x, out y);
        foreach (var cell in flow.get_children()) {
            Gtk.Allocation area;
            cell.get_allocation(out area);
            bool inside = x >= area.x
                && x < area.x + area.width
                && y >= area.y
                && y < area.y + area.height;
            if (inside) {
                return true;
            }
        }
        return false;
    }
}
