/* Connects, pairs and forgets Bluetooth devices. */
class BluetoothMenu {
    const string SEARCH = "Search for new devices";
    const string FORGET = "Forget a device…";
    const string TURN_OFF = "Turn Bluetooth off";
    const string TURN_ON = "Turn Bluetooth on";

    public async void run() throws Error {
        var adapter = yield new BluetoothAdapter();
        while (true) {
            if (!adapter.powered) {
                yield offer_to_turn_on(adapter);
                return;
            }
            bool again = yield show(adapter);
            if (!again) {
                return;
            }
            yield adapter.read();
        }
    }

    async void offer_to_turn_on(BluetoothAdapter adapter) throws Error {
        int choice = yield Rofi.choose("Bluetooth", { TURN_ON }, { "-l", "1" });
        if (choice == 0) {
            yield adapter.set_powered(true);
            yield notify("Turned on");
        }
    }

    /* True if the menu should be shown again. */
    async bool show(BluetoothAdapter adapter) throws Error {
        var devices = adapter.devices;
        string[] items = {};
        int[] connected = {};
        bool any_paired = false;
        for (int index = 0; index < devices.length; index++) {
            items += describe(devices[index]);
            any_paired = any_paired || devices[index].paired;
            if (devices[index].connected) {
                connected += index;
            }
        }
        string[] actions = { SEARCH };
        if (any_paired) {
            actions += FORGET;
        }
        actions += TURN_OFF;
        foreach (unowned string action in actions) {
            items += action;
        }

        int choice = yield Rofi.choose("Bluetooth", items, Rofi.highlight(connected));
        if (choice < 0) {
            return false;
        }
        if (choice < devices.length) {
            yield toggle(adapter, devices[choice]);
            return false;
        }
        switch (actions[choice - devices.length]) {
            case SEARCH:
                yield notify("Searching for devices…");
                yield adapter.scan();
                return true;
            case FORGET:
                yield forget(adapter);
                return false;
            default:
                yield adapter.set_powered(false);
                yield notify("Turned off");
                return false;
        }
    }

    static string describe(BluetoothDevice device) {
        string state = device.paired ? "" : "   new";
        if (device.connected) {
            state = "   ✓ connected";
        }
        return "%s  %s%s%s".printf(
            icon_for(device),
            device.name,
            device.battery >= 0 ? "  %d %%".printf(device.battery) : "",
            state
        );
    }

    /* Characters of Symbols Nerd Font. */
    static string icon_for(BluetoothDevice device) {
        if (device.icon.has_prefix("audio")) {
            return "󰋋";
        }
        if (device.icon.has_prefix("input-keyboard")) {
            return "󰌌";
        }
        if (device.icon.has_prefix("input-mouse")) {
            return "󰍽";
        }
        if (device.icon.has_prefix("input-gaming")) {
            return "󰊗";
        }
        if (device.icon.has_prefix("phone")) {
            return "󰄜";
        }
        if (device.icon.has_prefix("computer")) {
            return "󰌢";
        }
        return "󰂯";
    }

    async void toggle(BluetoothAdapter adapter, BluetoothDevice device) {
        string failure = device.connected ? "Could not disconnect from" : "Could not connect to";
        try {
            if (device.connected) {
                yield adapter.disconnect_from(device);
                yield notify("Disconnected from %s".printf(device.name));
            } else {
                yield notify("Connecting to %s…".printf(device.name));
                yield adapter.connect_to(device);
                yield notify("Connected to %s".printf(device.name));
            }
        } catch (Error error) {
            DBusError.strip_remote_error(error);
            string title = "%s %s".printf(failure, device.name);
            yield Notifications.show(title, error.message, "bluetooth", true);
        }
    }

    async void forget(BluetoothAdapter adapter) throws Error {
        BluetoothDevice[] paired = {};
        string[] items = {};
        foreach (var device in adapter.devices) {
            if (device.paired) {
                paired += device;
                items += describe(device);
            }
        }
        int choice = yield Rofi.choose("Forget", items);
        if (choice >= 0 && choice < paired.length) {
            yield adapter.forget(paired[choice]);
            yield notify("%s was forgotten".printf(paired[choice].name));
        }
    }

    static async void notify(string text) {
        yield Notifications.show("Bluetooth", text, "bluetooth");
    }
}
