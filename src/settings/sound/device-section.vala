/* Outputs or inputs: choice of the default device, its volume and port. */
class DeviceSection : Gtk.Box {
    const uint VOLUME_DELAY = 40;       // ms: collects the steps of a moving slider
    const int64 ECHO_TIME = 300 * TimeSpan.MILLISECOND;

    public signal void failed(string message);
    public signal void device_changed();

    delegate void Change() throws Error;

    unowned SoundServer server;
    SoundDirection direction;
    string icon_name;
    string muted_icon_name;

    SoundDevice? device = null;
    string shown_devices = "";
    bool updating = false;              // changes are not made by the user
    uint volume_timer = 0;
    int64 echo_until = 0;

    Gtk.Box volume_bar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
    Gtk.ToggleButton mute_button = new Gtk.ToggleButton();
    Gtk.Image mute_image = new Gtk.Image();
    Gtk.Scale volume_scale = new Gtk.Scale.with_range(Gtk.Orientation.HORIZONTAL, 0, 100, 1);
    Gtk.Box device_list = new Gtk.Box(Gtk.Orientation.VERTICAL, 4);
    Gtk.RadioButton none = new Gtk.RadioButton(null);       // never shown: all others may be off
    Gtk.Box port_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
    Gtk.ComboBoxText port_list = new Gtk.ComboBoxText();

    public DeviceSection(SoundServer server, SoundDirection direction) {
        Object(orientation: Gtk.Orientation.VERTICAL, spacing: 8);
        this.server = server;
        this.direction = direction;
        bool is_output = direction == SoundDirection.OUTPUT;
        icon_name = is_output ? "audio-volume-high-symbolic" : "audio-input-microphone-symbolic";
        muted_icon_name = is_output
            ? "audio-volume-muted-symbolic"
            : "microphone-sensitivity-muted-symbolic";
        build(is_output ? "Output" : "Input");
        connect_events();
    }

    void build(string title) {
        var label = new Gtk.Label(title);
        label.xalign = 0;
        label.get_style_context().add_class("section-title");
        pack_start(label, false, false);

        mute_button.relief = Gtk.ReliefStyle.NONE;
        mute_button.tooltip_text = "Mute";
        mute_button.add(mute_image);
        volume_scale.value_pos = Gtk.PositionType.RIGHT;
        volume_scale.format_value.connect((value) => "%.0f %%".printf(value));
        volume_bar.pack_start(mute_button, false, false);
        volume_bar.pack_start(volume_scale, true, true);
        pack_start(volume_bar, false, false);

        pack_start(device_list, false, false);

        port_row.pack_start(new Gtk.Label("Port"), false, false);
        port_row.pack_start(port_list, false, false);
        port_row.show_all();
        port_row.hide();
        port_row.no_show_all = true;
        pack_start(port_row, false, false);
    }

    void connect_events() {
        mute_button.toggled.connect(() => {
            change(() => server.set_muted(direction, device.name, mute_button.active));
        });
        volume_scale.value_changed.connect(schedule_volume);
        port_list.changed.connect(() => {
            string? port = port_list.active_id;
            if (port != null) {
                change(() => server.set_port(direction, device.name, port));
            }
        });
        destroy.connect(() => {
            if (volume_timer != 0) {
                Source.remove(volume_timer);
            }
        });
    }

    // ── showing the state ───────────────────────────────────

    public void update(GenericArray<SoundDevice> all_devices, string default_name) {
        updating = true;
        device = null;
        var devices = new GenericArray<SoundDevice>();
        foreach (var candidate in all_devices) {
            bool is_default = candidate.name == default_name;
            if (candidate.is_monitor() || (!candidate.is_connected && !is_default)) {
                continue;
            }
            devices.add(candidate);
            if (is_default) {
                device = candidate;
            }
        }
        update_devices(devices, default_name);
        update_volume();
        update_ports();
        updating = false;
    }

    void update_devices(GenericArray<SoundDevice> devices, string default_name) {
        var description = new StringBuilder("devices");
        foreach (var item in devices) {
            description.append("\n%s\n%s".printf(item.name, item.title));
        }
        if (description.str != shown_devices) {
            shown_devices = description.str;
            fill_device_list(devices);
        }
        none.active = true;
        foreach (var child in device_list.get_children()) {
            var button = child as DeviceButton;
            if (button != null && button.device_name == default_name) {
                button.active = true;
            }
        }
    }

    void fill_device_list(GenericArray<SoundDevice> devices) {
        foreach (var child in device_list.get_children()) {
            child.destroy();
        }
        foreach (var item in devices) {
            var button = new DeviceButton(none, item);
            button.toggled.connect(() => {
                if (button.active) {
                    change(() => server.set_default(direction, button.device_name));
                }
            });
            device_list.pack_start(button, false, false);
        }
        if (devices.length == 0) {
            var label = new Gtk.Label("Nothing is connected");
            label.xalign = 0;
            device_list.pack_start(label, false, false);
        }
        device_list.show_all();
    }

    void update_volume() {
        volume_bar.sensitive = device != null;
        bool muted = device != null && device.muted;
        mute_button.active = muted;
        mute_image.set_from_icon_name(muted ? muted_icon_name : icon_name, Gtk.IconSize.BUTTON);
        // a slider that is being moved must not be moved back by its own changes
        bool moving = volume_timer != 0 || get_monotonic_time() < echo_until;
        if (device != null && !moving) {
            volume_scale.set_value(device.volume());
        }
    }

    void update_ports() {
        port_list.remove_all();
        if (device == null) {
            port_row.hide();
            return;
        }
        foreach (var port in device.ports) {
            port_list.append(port.name, port.description);
        }
        port_list.active_id = device.active_port;
        port_row.visible = device.ports.length > 1;
    }

    // ── changes by the user ─────────────────────────────────

    void schedule_volume() {
        if (updating || device == null || volume_timer != 0) {
            return;
        }
        volume_timer = Timeout.add(VOLUME_DELAY, () => {
            volume_timer = 0;
            echo_until = get_monotonic_time() + ECHO_TIME;
            int volume = (int) Math.rint(volume_scale.get_value());
            change(() => server.set_volume(direction, device, volume));
            return Source.REMOVE;
        });
    }

    void change(Change change) {
        if (updating || device == null) {
            return;
        }
        try {
            change();
        } catch (Error error) {
            failed(error.message);
        }
        device_changed();
    }
}

class DeviceButton : Gtk.RadioButton {
    public string device_name;

    public DeviceButton(Gtk.RadioButton group, SoundDevice device) {
        Object(group: group, label: device.title);
        device_name = device.name;
        ((Gtk.Label) get_child()).ellipsize = Pango.EllipsizeMode.END;
    }
}
