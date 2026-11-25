/* Window handling that Openbox lacks. */
const string USAGE = """usage:
  mini-de-wm                       keeps titlebars reachable and widens the resize borders
  mini-de-wm unmaximize [title]    starts dragging the active maximized window
""";

class WindowWatcher {
    const uint BORDERS_DELAY = 60;      // ms
    const uint TITLEBARS_DELAY = 150;   // ms

    X11.Connection connection;
    ResizeBorders borders;
    TitlebarKeeper titlebars;
    DeferredTask update_borders;
    DeferredTask check_titlebars;

    public WindowWatcher(X11.Connection connection) {
        this.connection = connection;
        borders = new ResizeBorders(connection);
        titlebars = new TitlebarKeeper(connection);
        update_borders = new DeferredTask(connection, () => borders.update());
        check_titlebars = new DeferredTask(connection, () => titlebars.check());
    }

    public void start() {
        connection.root.select_events(Xl.SUBSTRUCTURE_MASK | Xl.STRUCTURE_MASK | Xl.PROPERTY_MASK);
        connection.listen(on_event);
        update_borders.run_within(0);
        check_titlebars.run_after(0);
    }

    void on_event(Xl.Event event) {
        switch (event.type) {
            case Xl.MOTION:
                var hovered = borders.find_by_ring(event.window);
                if (hovered != null && hovered.is_placed) {
                    hovered.on_pointer_moved(event.x_root, event.y_root);
                }
                break;
            case Xl.BUTTON_PRESS:
                var pressed = borders.find_by_ring(event.window);
                if (pressed != null && pressed.is_placed && event.button == 1) {
                    pressed.on_pressed(event.x_root, event.y_root);
                }
                break;
            case Xl.PROPERTY:
                update_borders.run_within(BORDERS_DELAY);
                if (event.window == connection.root.id) {
                    check_titlebars.run_after(TITLEBARS_DELAY);
                }
                break;
            case Xl.MAP:
            case Xl.CONFIGURE:
                if (borders.find_by_ring(event.subject) == null) {
                    update_borders.run_within(BORDERS_DELAY);
                    check_titlebars.run_after(TITLEBARS_DELAY);
                }
                break;
            case Xl.UNMAP:
            case Xl.DESTROY:
            case Xl.REPARENT:
                if (borders.find_by_ring(event.subject) == null) {
                    update_borders.run_within(BORDERS_DELAY);
                }
                break;
        }
    }
}

int main(string[] args) {
    bool unmaximize = args.length > 1 && args[1] == "unmaximize";
    if (args.length > 1 && !unmaximize) {
        stderr.printf("%s", USAGE);
        return 2;
    }
    if (!unmaximize && !SingleInstance.acquire("mini-de-wm")) {
        return 0;
    }
    X11.Connection connection;
    try {
        connection = new X11.Connection();
    } catch (X11.Error error) {
        stderr.printf("mini-de-wm: %s\n", error.message);
        return 1;
    }
    if (unmaximize) {
        new Unmaximize(connection).run("title" in args);
        return 0;
    }
    var watcher = new WindowWatcher(connection);
    watcher.start();
    new MainLoop().run();
    return 0;
}
