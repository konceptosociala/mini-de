/* Dragging a maximized window: restores its normal size with the titlebar under
   the pointer, then hands the move over to Openbox. Called from rc.xml. */
class Unmaximize {
    const string[] MAXIMIZED = {
        X11.WindowState.MAXIMIZED_HORIZONTALLY,
        X11.WindowState.MAXIMIZED_VERTICALLY
    };
    const int64 RESIZE_TIMEOUT = 400 * TimeSpan.MILLISECOND;
    const int64 MOVE_TIMEOUT = 200 * TimeSpan.MILLISECOND;
    const ulong POLL_INTERVAL = 5 * (ulong) TimeSpan.MILLISECOND;
    const int BUTTONS_WIDTH = 110;      // buttons at the right end of the titlebar, px
    const int MIN_OFFSET = 40;          // from the left end, px

    delegate bool Condition();

    unowned X11.Connection connection;
    X11.Window window;

    public Unmaximize(X11.Connection connection) {
        this.connection = connection;
        window = connection.window(connection.active_id());
    }

    public void run(bool held_by_titlebar) {
        var grabbed_at = connection.pointer();
        if (window.id == 0 || !grabbed_at.left_button || !window.has_state(MAXIMIZED)) {
            return;
        }
        Rect? maximized = window.frame_bounds();
        if (maximized == null) {
            return;
        }
        restore_size();

        Rect? restored = window.frame_bounds();
        var pointer = connection.pointer();
        if (restored == null || !pointer.left_button) {
            return;
        }
        double grabbed_share = (grabbed_at.x - maximized.x) / (double) int.max(maximized.width, 1);
        int offset_x = (int) titlebar_offset(grabbed_share, restored.width);
        int offset_y = grabbed_at.y - maximized.y;
        int titlebar_height = window.frame_extents().top;
        if (held_by_titlebar && titlebar_height != 0) {
            offset_y = titlebar_height / 2;
        }
        offset_y = int.min(offset_y, restored.height - 10);

        move_to(pointer.x - offset_x, pointer.y - offset_y);
        if (connection.pointer().left_button) {
            window.start_drag(pointer.x, pointer.y, X11.DragKind.MOVE);
        }
    }

    void restore_size() {
        Rect? old_size = window.screen_bounds();
        if (old_size == null) {
            return;
        }
        window.unmaximize();
        // the frame is not enough: Openbox changes its extents before the size
        wait_until(RESIZE_TIMEOUT, () => {
            Rect? size = window.screen_bounds();
            return size == null || (!window.has_state(MAXIMIZED) && !size.same_size(old_size));
        });
    }

    void move_to(int x, int y) {
        window.move_frame(x, y);
        wait_until(MOVE_TIMEOUT, () => {
            Rect? frame = window.frame_bounds();
            return frame == null || (frame.x - x).abs() <= 2;
        });
    }

    /* Where to hold the titlebar, staying clear of its buttons. */
    static double titlebar_offset(double share, int width) {
        double wanted = double.max(share * width, MIN_OFFSET);
        return double.min(wanted, int.max(width - BUTTONS_WIDTH, MIN_OFFSET));
    }

    static void wait_until(int64 timeout, Condition condition) {
        int64 end = get_monotonic_time() + timeout;
        while (get_monotonic_time() < end && !condition()) {
            Thread.usleep(POLL_INTERVAL);
        }
    }
}
