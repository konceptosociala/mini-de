enum SoundDirection {
    OUTPUT,
    INPUT;

    /* As PulseAudio calls it. */
    public string pulse_name() {
        return this == OUTPUT ? "sink" : "source";
    }
}

class SoundPort {
    public string name;
    public string description;

    public SoundPort(string name, string description) {
        this.name = name;
        this.description = description;
    }
}

class SoundDevice {
    public string name;
    public string title;
    public bool muted;
    public int[] volumes = {};          // of the channels, percent
    public GenericArray<SoundPort> ports = new GenericArray<SoundPort>();       // usable ones
    public string active_port = "";
    public bool is_connected;           // has something to play on or record from

    public SoundDevice.from_json(Json.Object json) {
        name = json.get_string_member("name");
        muted = json.get_boolean_member("mute");
        title = read_title(json);
        active_port = read_string(json, "active_port");
        json.get_object_member("volume").foreach_member((object, channel, node) => {
            string percent = node.get_object().get_string_member("value_percent");
            volumes += int.parse(percent.strip());
        });
        read_ports(json.get_array_member("ports"));
    }

    void read_ports(Json.Array list) {
        is_connected = list.get_length() == 0;
        list.foreach_element((array, index, node) => {
            var port = node.get_object();
            if (read_string(port, "availability") == "not available") {
                return;
            }
            is_connected = true;
            ports.add(new SoundPort(read_string(port, "name"), read_string(port, "description")));
        });
    }

    /* Built-in cards are called by what they drive, everything else by its own name. */
    static string read_title(Json.Object json) {
        if (json.has_member("properties")) {
            var properties = json.get_object_member("properties");
            string profile = read_string(properties, "device.profile.description");
            if (read_string(properties, "device.bus") == "pci" && profile != "") {
                return profile;
            }
        }
        string description = read_string(json, "description");
        return description != "" ? description : json.get_string_member("name");
    }

    /* Empty if there is none. */
    static string read_string(Json.Object json, string member) {
        var node = json.get_member(member);
        if (node == null || node.get_node_type() != Json.NodeType.VALUE) {
            return "";
        }
        unowned string? text = node.get_string();
        return text != null ? text : "";
    }

    /* Records what another device plays. */
    public bool is_monitor() {
        return name.has_suffix(".monitor");
    }

    /* Of the loudest channel. */
    public int volume() {
        int loudest = 0;
        foreach (int channel in volumes) {
            loudest = int.max(loudest, channel);
        }
        return loudest;
    }
}

/* PulseAudio or PipeWire through pactl. */
class SoundServer {
    const string TIMEOUT = "5";         // s
    const uint RESTART_DELAY = 2;       // s

    public signal void changed();

    Regex relevant_event;
    Subprocess? watcher = null;
    bool closed = false;

    public SoundServer() {
        try {
            relevant_event = new Regex(" on (sink|source|card|server)( #|$)");
        } catch (RegexError error) {
            GLib.error("%s", error.message);
        }
    }

    public string default_device(SoundDirection direction) throws Error {
        return pactl({ "get-default-" + direction.pulse_name() }).strip();
    }

    public GenericArray<SoundDevice> devices(SoundDirection direction) throws Error {
        var parser = new Json.Parser();
        parser.load_from_data(pactl({ "-f", "json", "list", direction.pulse_name() + "s" }));
        var devices = new GenericArray<SoundDevice>();
        parser.get_root().get_array().foreach_element((array, index, node) => {
            devices.add(new SoundDevice.from_json(node.get_object()));
        });
        return devices;
    }

    public void set_default(SoundDirection direction, string device) throws Error {
        pactl({ "set-default-" + direction.pulse_name(), device });
    }

    public void set_muted(SoundDirection direction, string device, bool muted) throws Error {
        pactl({ "set-%s-mute".printf(direction.pulse_name()), device, muted ? "1" : "0" });
    }

    public void set_port(SoundDirection direction, string device, string port) throws Error {
        pactl({ "set-%s-port".printf(direction.pulse_name()), device, port });
    }

    /* Keeps the balance. */
    public void set_volume(SoundDirection direction, SoundDevice device, int volume) throws Error {
        string[] arguments = { "set-%s-volume".printf(direction.pulse_name()), device.name };
        int old_volume = device.volume();
        foreach (int channel in device.volumes) {
            int scaled = volume;
            if (old_volume > 0) {
                scaled = (int) Math.rint(channel * volume / (double) old_volume);
            }
            arguments += "%d%%".printf(scaled);
        }
        pactl(arguments);
    }

    static string pactl(string[] arguments) throws Error {
        string[] command = { "timeout", TIMEOUT, "pactl" };
        foreach (unowned string argument in arguments) {
            command += argument;
        }
        return Command.run(command);
    }

    // ── changes made elsewhere ──────────────────────────────

    public void watch() {
        watch_events.begin();
    }

    public void stop_watching() {
        closed = true;
        if (watcher != null) {
            watcher.force_exit();
        }
    }

    async void watch_events() {
        while (!closed) {
            try {
                yield read_events();
            } catch (Error error) {
                warning("pactl: %s", error.message);
            }
            if (closed) {
                return;
            }
            // pactl exits when the sound server restarts
            changed();
            Timeout.add_seconds(RESTART_DELAY, watch_events.callback);
            yield;
        }
    }

    async void read_events() throws Error {
        var launcher = new SubprocessLauncher(
            SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_SILENCE
        );
        launcher.setenv("LC_ALL", "C", true);
        watcher = launcher.spawnv({ "pactl", "subscribe" });
        var events = new DataInputStream(watcher.get_stdout_pipe());
        string? line;
        while ((line = yield events.read_line_utf8_async()) != null) {
            if (relevant_event.match(line)) {
                changed();
            }
        }
    }
}
