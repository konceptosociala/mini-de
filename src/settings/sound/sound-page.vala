class SoundPage : Page {
    const uint UPDATE_DELAY = 80;       // ms

    SoundServer server = new SoundServer();
    DeviceSection output;
    DeviceSection input;
    uint update_timer = 0;

    public SoundPage() {
        base("sound", "Sound", "preferences-desktop-sound");
        spacing = 18;
        output = create_section(SoundDirection.OUTPUT);
        input = create_section(SoundDirection.INPUT);

        var contents = new Gtk.Box(Gtk.Orientation.VERTICAL, 18);
        contents.pack_start(output, false, false);
        contents.pack_start(new Gtk.Separator(Gtk.Orientation.HORIZONTAL), false, false);
        contents.pack_start(input, false, false);
        contents.pack_start(new Gtk.Separator(Gtk.Orientation.HORIZONTAL), false, false);
        contents.pack_start(create_events(), false, false);
        add_scrolled_to_edge(contents);

        update();
        server.changed.connect(schedule_update);
        server.watch();
        destroy.connect(() => {
            server.stop_watching();
            if (update_timer != 0) {
                Source.remove(update_timer);
            }
        });
    }

    DeviceSection create_section(SoundDirection direction) {
        var section = new DeviceSection(server, direction);
        section.failed.connect((message) => show_error(message));
        section.device_changed.connect(schedule_update);
        return section;
    }

    Gtk.Widget create_events() {
        var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 8);
        var title = left_label("Event sounds");
        title.get_style_context().add_class("section-title");
        box.pack_start(title, false, false);
        foreach (var event in EventSound.all()) {
            var row = new EventSoundRow(event);
            row.failed.connect((message) => show_error(message));
            row.saved.connect(() => clear_error());
            box.pack_start(row, false, false);
        }
        return box;
    }

    void schedule_update() {
        if (update_timer != 0) {
            return;
        }
        update_timer = Timeout.add(UPDATE_DELAY, () => {
            update_timer = 0;
            update();
            return Source.REMOVE;
        });
    }

    void update() {
        try {
            update_section(output, SoundDirection.OUTPUT);
            update_section(input, SoundDirection.INPUT);
        } catch (Error error) {
            show_error("No connection to the sound server: %s".printf(error.message));
        }
    }

    void update_section(DeviceSection section, SoundDirection direction) throws Error {
        section.update(server.devices(direction), server.default_device(direction));
    }
}
