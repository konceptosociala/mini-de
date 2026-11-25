class BluetoothDevice {
    public ObjectPath path;
    public string name;
    public string icon;
    public bool has_name;
    public bool paired;
    public bool connected;
    public bool trusted;
    public int signal_strength = int16.MIN;
    public int battery = -1;            // percent, -1 if unknown

    public BluetoothDevice(ObjectPath path, HashTable<string, Variant> properties) {
        this.path = path;
        name = read_string(properties, "Alias");
        if (name == "") {
            name = read_string(properties, "Address");
        }
        icon = read_string(properties, "Icon");
        has_name = "Name" in properties;
        paired = read_flag(properties, "Paired");
        connected = read_flag(properties, "Connected");
        trusted = read_flag(properties, "Trusted");
        Variant? rssi = properties["RSSI"];
        if (rssi != null) {
            signal_strength = rssi.get_int16();
        }
    }

    static string read_string(HashTable<string, Variant> properties, string key) {
        Variant? value = properties[key];
        if (value == null) {
            return "";
        }
        return value.get_string().replace("\n", " ").strip();
    }

    public static bool read_flag(HashTable<string, Variant> properties, string key) {
        Variant? value = properties[key];
        return value != null && value.get_boolean();
    }

    /* Connected, then paired, then new ones by signal. */
    public static int compare(BluetoothDevice first, BluetoothDevice second) {
        if (first.connected != second.connected) {
            return first.connected ? -1 : 1;
        }
        if (first.paired != second.paired) {
            return first.paired ? -1 : 1;
        }
        if (!first.paired && first.signal_strength != second.signal_strength) {
            return second.signal_strength - first.signal_strength;
        }
        return strcmp(first.name.casefold(), second.name.casefold());
    }
}

/* The first Bluetooth adapter and its devices. */
class BluetoothAdapter {
    const string AGENT_PATH = "/local/minide/agent";
    const uint SCAN_TIME = 8;           // s

    public ObjectPath path;
    public bool powered;
    bool pairable;
    public GenericArray<BluetoothDevice> devices = new GenericArray<BluetoothDevice>();

    public async BluetoothAdapter() throws Error {
        yield read();
    }

    /* Learns the current state. */
    public async void read() throws Error {
        Bluez.ObjectManager manager = yield Bus.get_proxy(BusType.SYSTEM, Bluez.NAME, "/");
        var objects = yield manager.get_managed_objects();

        ObjectPath? first = null;
        objects.foreach((object_path, interfaces) => {
            if (Bluez.ADAPTER_INTERFACE in interfaces && (first == null || strcmp(object_path, first) < 0)) {
                first = object_path;
            }
        });
        if (first == null) {
            throw new IOError.NOT_FOUND("No Bluetooth adapter");
        }
        path = first;
        powered = BluetoothDevice.read_flag(objects[path][Bluez.ADAPTER_INTERFACE], "Powered");
        pairable = BluetoothDevice.read_flag(objects[path][Bluez.ADAPTER_INTERFACE], "Pairable");

        devices = new GenericArray<BluetoothDevice>();
        objects.foreach((object_path, interfaces) => {
            if (Bluez.DEVICE_INTERFACE in interfaces) {
                add_device(object_path, interfaces);
            }
        });
        devices.sort(BluetoothDevice.compare);
    }

    void add_device(
        ObjectPath device_path,
        HashTable<string, HashTable<string, Variant>> interfaces
    ) {
        var properties = interfaces[Bluez.DEVICE_INTERFACE];
        Variant? owner = properties["Adapter"];
        if (owner == null || owner.get_string() != path) {
            return;
        }
        var device = new BluetoothDevice(device_path, properties);
        // others only have an address
        if (!device.paired && !device.connected && !device.has_name) {
            return;
        }
        var battery = interfaces[Bluez.BATTERY_INTERFACE];
        Variant? percentage = battery != null ? battery["Percentage"] : null;
        if (percentage != null) {
            device.battery = percentage.get_byte();
        }
        devices.add(device);
    }

    public async void set_powered(bool powered) throws Error {
        if (powered && Environment.find_program_in_path("rfkill") != null) {
            try {
                yield Command.run_async({ "rfkill", "unblock", "bluetooth" });
            } catch (Error error) {
                warning("%s", error.message);
            }
        }
        yield Bluez.set_flag(path, Bluez.ADAPTER_INTERFACE, "Powered", powered);
    }

    public async void scan() throws Error {
        Bluez.Adapter adapter = yield Bus.get_proxy(BusType.SYSTEM, Bluez.NAME, path);
        yield adapter.start_discovery();
        Timeout.add_seconds(SCAN_TIME, scan.callback);
        yield;
        try {
            yield adapter.stop_discovery();
        } catch (Error error) {
            warning("%s", error.message);
        }
    }

    public async void forget(BluetoothDevice device) throws Error {
        Bluez.Adapter adapter = yield Bus.get_proxy(BusType.SYSTEM, Bluez.NAME, path);
        yield adapter.remove_device(device.path);
    }

    // ── connecting ──────────────────────────────────────────

    public async void disconnect_from(BluetoothDevice device) throws Error {
        Bluez.Device proxy = yield Bus.get_proxy(BusType.SYSTEM, Bluez.NAME, device.path);
        yield proxy.disconnect_device();
    }

    public async void connect_to(BluetoothDevice device) throws Error {
        Bluez.Device proxy = yield Bus.get_proxy(BusType.SYSTEM, Bluez.NAME, device.path);
        if (!device.paired) {
            yield pair(proxy);
        }
        if (!device.trusted) {
            // so that it may connect by itself later
            yield Bluez.set_flag(device.path, Bluez.DEVICE_INTERFACE, "Trusted", true);
        }
        yield proxy.connect_device();
    }

    async void pair(Bluez.Device device) throws Error {
        var bus = yield Bus.get(BusType.SYSTEM);
        uint registration = bus.register_object(AGENT_PATH, new PairingAgent());
        Bluez.AgentManager agents = yield Bus.get_proxy(BusType.SYSTEM, Bluez.NAME, "/org/bluez");
        var agent_path = new ObjectPath(AGENT_PATH);
        yield agents.register_agent(agent_path, "KeyboardDisplay");
        try {
            if (!pairable) {
                // otherwise the keys of the device are not kept
                yield Bluez.set_flag(path, Bluez.ADAPTER_INTERFACE, "Pairable", true);
            }
            yield device.pair();
        } finally {
            yield clean_up_pairing(agents, agent_path);
            bus.unregister_object(registration);
        }
    }

    async void clean_up_pairing(Bluez.AgentManager agents, ObjectPath agent_path) {
        try {
            yield agents.unregister_agent(agent_path);
            if (!pairable) {
                yield Bluez.set_flag(path, Bluez.ADAPTER_INTERFACE, "Pairable", false);
            }
        } catch (Error error) {
            warning("%s", error.message);
        }
    }
}
