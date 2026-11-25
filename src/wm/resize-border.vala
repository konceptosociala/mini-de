/* A transparent window, a little larger than the frame of a program's window and stacked right
   below it, so only the ring around the frame receives the pointer. */
class ResizeBorder {
    const int THICKNESS = 7;            // px
    const int CORNER_LENGTH = 18;       // px

    unowned X11.Connection connection;
    X11.Window client;
    X11.Window ring;
    Rect? frame_bounds = null;
    X11.DragKind? cursor = null;
    bool visible = false;

    public ResizeBorder(X11.Connection connection, X11.Window client) {
        this.connection = connection;
        this.client = client;
        ring = connection.create_input_window(Xl.BUTTON_PRESS_MASK | Xl.POINTER_MOTION_MASK);
    }

    public bool is_placed {
        get { return frame_bounds != null; }
    }

    public ulong ring_id {
        get { return ring.id; }
    }

    /* Puts the ring around the frame; stacking is all windows of the screen, bottom to top. */
    public void surround(X11.Window frame, Rect bounds, ulong[] stacking) {
        int frame_index = -1;
        for (int index = 0; index < stacking.length && frame_index < 0; index++) {
            if (stacking[index] == frame.id) {
                frame_index = index;
            }
        }
        if (frame_index < 0) {
            return;
        }
        if (frame_bounds == null || !bounds.equals(frame_bounds)) {
            ring.set_bounds({
                bounds.x - THICKNESS,
                bounds.y - THICKNESS,
                bounds.width + 2 * THICKNESS,
                bounds.height + 2 * THICKNESS
            });
            frame_bounds = bounds;
        }
        if (frame_index == 0 || stacking[frame_index - 1] != ring.id) {
            ring.stack_below(frame);
        }
        if (!visible) {
            ring.map();
            visible = true;
        }
    }

    public void hide() {
        if (visible) {
            ring.unmap();
            visible = false;
        }
    }

    public void destroy() {
        ring.destroy();
    }

    public void on_pointer_moved(int x, int y) {
        var kind = drag_kind_at(x, y);
        if (kind != cursor) {
            ring.set_cursor(cursor_shape(kind));
            cursor = kind;
        }
    }

    public void on_pressed(int x, int y) {
        connection.release_pointer();       // the window manager grabs it
        client.activate();
        client.start_drag(x, y, drag_kind_at(x, y));
    }

    X11.DragKind drag_kind_at(int x, int y) {
        Rect frame = frame_bounds;
        bool on_left = x < frame.x;
        bool on_right = x >= frame.right;
        bool on_top = y < frame.y;
        bool on_bottom = y >= frame.bottom;

        int corner_width = int.min(CORNER_LENGTH, frame.width / 3);
        int corner_height = int.min(CORNER_LENGTH, frame.height / 3);
        bool near_left = x < frame.x + corner_width;
        bool near_right = x >= frame.right - corner_width;
        bool near_top = y < frame.y + corner_height;
        bool near_bottom = y >= frame.bottom - corner_height;

        if ((on_top && near_left) || (on_left && near_top)) {
            return X11.DragKind.TOP_LEFT;
        }
        if ((on_top && near_right) || (on_right && near_top)) {
            return X11.DragKind.TOP_RIGHT;
        }
        if ((on_bottom && near_right) || (on_right && near_bottom)) {
            return X11.DragKind.BOTTOM_RIGHT;
        }
        if ((on_bottom && near_left) || (on_left && near_bottom)) {
            return X11.DragKind.BOTTOM_LEFT;
        }
        if (on_top) {
            return X11.DragKind.TOP;
        }
        if (on_right) {
            return X11.DragKind.RIGHT;
        }
        return on_bottom ? X11.DragKind.BOTTOM : X11.DragKind.LEFT;
    }

    /* Shapes of the X cursor font. */
    static uint cursor_shape(X11.DragKind kind) {
        switch (kind) {
            case X11.DragKind.TOP_LEFT:
                return 134;
            case X11.DragKind.TOP:
                return 138;
            case X11.DragKind.TOP_RIGHT:
                return 136;
            case X11.DragKind.RIGHT:
                return 96;
            case X11.DragKind.BOTTOM_RIGHT:
                return 14;
            case X11.DragKind.BOTTOM:
                return 16;
            case X11.DragKind.BOTTOM_LEFT:
                return 12;
            default:
                return 70;
        }
    }
}
