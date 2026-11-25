/* Icon of an app or tile of a folder, with a smooth zoom. */
class ItemArt : Gtk.DrawingArea {
    public const int ICON_SIZE = 84;            // px
    public const double HOVER_SCALE = 1.16;
    public const double PRESSED_SCALE = 0.92;
    const int MINI_ICON_SIZE = 28;              // in the tile of a folder, px
    const int MINI_ICON_GAP = 3;                // px
    const int TILE_COLUMNS = 3;
    const int TILE_SIZE = ICON_SIZE + 16;
    const int TILE_RADIUS = 18;
    const int AREA_SIZE = (int) (TILE_SIZE * HOVER_SCALE) + 4;
    const int64 DURATION = 160 * TimeSpan.MILLISECOND;

    LauncherItem item;
    AppIcons icons;

    double scale = 1;
    double start_scale = 1;
    double target_scale = 1;
    int64 start_time = 0;           // 0 until the first frame of the animation
    uint animation = 0;

    public ItemArt(LauncherItem item, AppIcons icons) {
        this.item = item;
        this.icons = icons;
        halign = Gtk.Align.CENTER;
        set_size_request(AREA_SIZE, AREA_SIZE);
    }

    // ── animation ───────────────────────────────────────────

    public void zoom_to(double target) {
        if (target == target_scale) {
            return;
        }
        target_scale = target;
        if (!get_mapped() || !Gtk.Settings.get_default().gtk_enable_animations) {
            stop_animation();
            scale = target;
            queue_draw();
            return;
        }
        start_scale = scale;
        start_time = 0;
        if (animation == 0) {
            animation = add_tick_callback(on_frame);
        }
    }

    void stop_animation() {
        if (animation != 0) {
            remove_tick_callback(animation);
            animation = 0;
        }
    }

    bool on_frame(Gtk.Widget widget, Gdk.FrameClock clock) {
        int64 now = clock.get_frame_time();
        if (start_time == 0) {
            start_time = now;
        }
        double progress = double.min(1, (now - start_time) / (double) DURATION);
        double eased = 1 - Math.pow(1 - progress, 3);
        scale = start_scale + (target_scale - start_scale) * eased;
        queue_draw();
        if (progress < 1) {
            return Source.CONTINUE;
        }
        animation = 0;
        return Source.REMOVE;
    }

    // ── drawing ─────────────────────────────────────────────

    public override bool draw(Cairo.Context context) {
        context.translate(AREA_SIZE / 2.0, AREA_SIZE / 2.0);
        context.scale(scale, scale);
        var folder = item as Folder;
        if (folder != null) {
            draw_tile(context);
            draw_mini_icons(context, folder);
        } else {
            draw_icon(context, (App) item, -ICON_SIZE / 2.0, -ICON_SIZE / 2.0, ICON_SIZE);
        }
        return false;
    }

    void draw_tile(Cairo.Context context) {
        double center = TILE_SIZE / 2.0 - TILE_RADIUS;     // of a rounded corner
        context.new_sub_path();
        context.arc(center, -center, TILE_RADIUS, -Math.PI / 2, 0);
        context.arc(center, center, TILE_RADIUS, 0, Math.PI / 2);
        context.arc(-center, center, TILE_RADIUS, Math.PI / 2, Math.PI);
        context.arc(-center, -center, TILE_RADIUS, Math.PI, Math.PI * 3 / 2);
        context.close_path();

        Gdk.RGBA color = {};
        get_style_context().lookup_color("md_tile", out color);
        double glow = double.max(0, (scale - 1) / (HOVER_SCALE - 1));
        context.set_source_rgba(
            color.red + 0.10 * glow,
            color.green + 0.09 * glow,
            color.blue + 0.08 * glow,
            0.75 + 0.15 * glow
        );
        context.fill();
    }

    void draw_mini_icons(Cairo.Context context, Folder folder) {
        int step = MINI_ICON_SIZE + MINI_ICON_GAP;
        int icons_size = TILE_COLUMNS * step - MINI_ICON_GAP;
        double start = Math.round(-icons_size / 2.0);
        int count = int.min(folder.apps.length, TILE_COLUMNS * TILE_COLUMNS);
        for (int index = 0; index < count; index++) {
            draw_icon(
                context,
                folder.apps[index],
                start + index % TILE_COLUMNS * step,
                start + index / TILE_COLUMNS * step,
                MINI_ICON_SIZE
            );
        }
    }

    void draw_icon(Cairo.Context context, App app, double x, double y, int size) {
        // crisp at rest, drawn from a larger image while animating
        var icon = icons.find_or_default(app.info, scale == 1 ? size : size * 2);
        if (icon == null) {
            return;
        }
        double ratio = size / (double) int.max(icon.width, icon.height);
        context.save();
        context.translate(
            x + (size - icon.width * ratio) / 2,
            y + (size - icon.height * ratio) / 2
        );
        context.scale(ratio, ratio);
        Gdk.cairo_set_source_pixbuf(context, icon, 0, 0);
        context.get_source().set_filter(Cairo.Filter.GOOD);
        context.paint();
        context.restore();
    }
}
