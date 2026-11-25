/* Chooses a Wi-Fi network. */
class WifiMenu {
    const string RESCAN = "Rescan";
    const string EDIT = "Edit connections…";
    const string TURN_OFF = "Turn Wi-Fi off";
    const string TURN_ON = "Turn Wi-Fi on";

    NetworkManager manager = new NetworkManager();

    public async void run() throws Error {
        bool scanned = false;
        while (true) {
            bool enabled = yield manager.is_wifi_enabled();
            if (!enabled) {
                yield offer_to_turn_on();
                return;
            }
            var networks = yield manager.visible_networks();
            if (networks.length < 2 && !scanned) {
                // NetworkManager forgets old results
                yield scan();
                networks = yield manager.visible_networks();
                scanned = true;
            }
            bool again = yield show(networks);
            if (!again) {
                return;
            }
        }
    }

    async void offer_to_turn_on() throws Error {
        int choice = yield Rofi.choose("Wi-Fi", { TURN_ON });
        if (choice == 0) {
            yield manager.set_wifi_enabled(true);
            yield notify("Turned on");
        }
    }

    /* True if the menu should be shown again. */
    async bool show(GenericArray<WifiNetwork> networks) throws Error {
        string[] items = {};
        foreach (var network in networks) {
            items += describe(network);
        }
        string[] actions = { RESCAN, EDIT, TURN_OFF };
        foreach (unowned string action in actions) {
            items += action;
        }
        bool first_connected = networks.length > 0 && networks[0].connected;
        int[] connected = first_connected ? new int[] { 0 } : new int[] {};

        int choice = yield Rofi.choose("Wi-Fi", items, Rofi.highlight(connected));
        if (choice < 0) {
            return false;
        }
        if (choice < networks.length) {
            if (!networks[choice].connected) {
                yield connect_to(networks[choice]);
            }
            return false;
        }
        switch (actions[choice - networks.length]) {
            case RESCAN:
                yield scan();
                return true;
            case EDIT:
                new Subprocess.newv({ "nm-connection-editor" }, SubprocessFlags.NONE);
                return false;
            default:
                yield manager.set_wifi_enabled(false);
                yield notify("Turned off");
                return false;
        }
    }

    static string describe(WifiNetwork network) {
        return "%s  %s%s%s".printf(
            signal_bars(network.signal_strength),
            network.name,
            network.secured ? "  🔒" : "",
            network.connected ? "   ✓ connected" : ""
        );
    }

    /* One to four bars, always four characters wide. */
    static string signal_bars(int strength) {
        const string[] BARS = { "▂   ", "▂▄  ", "▂▄▆ ", "▂▄▆█" };
        return BARS[((strength + 24) / 25).clamp(1, BARS.length) - 1];
    }

    async void scan() {
        yield notify("Scanning…");
        yield manager.scan();
    }

    // ── connecting ──────────────────────────────────────────

    async void connect_to(WifiNetwork network) {
        string? saved = yield manager.saved_connection(network.name);
        if (saved != null) {
            yield connect_saved(network, saved);
            return;
        }
        string? password = null;
        if (network.secured) {
            password = yield Rofi.ask_password("Password for %s".printf(network.name));
            if (password == null || password == "") {
                return;
            }
        }
        yield connect_new(network, password);
    }

    async void connect_saved(WifiNetwork network, string connection_id) {
        yield notify("Connecting to %s…".printf(network.name));
        try {
            yield manager.connect_saved(connection_id);
            yield notify("Connected to %s".printf(network.name));
        } catch (Error error) {
            yield notify_failure(network, error);
        }
    }

    async void connect_new(WifiNetwork network, string? password) {
        yield notify("Connecting to %s…".printf(network.name));
        try {
            yield manager.connect_new(network.name, password);
            yield notify("Connected to %s".printf(network.name));
        } catch (Error error) {
            yield forget_failed(network);
            yield notify_failure(network, error);
        }
    }

    /* A connection with a wrong password is not kept. */
    async void forget_failed(WifiNetwork network) {
        string? saved = yield manager.saved_connection(network.name);
        if (saved == null) {
            return;
        }
        try {
            yield manager.forget(saved);
        } catch (Error error) {
            warning("%s", error.message);
        }
    }

    static async void notify(string text) {
        yield Notifications.show("Wi-Fi", text, "wifi");
    }

    static async void notify_failure(WifiNetwork network, Error error) {
        string title = "Could not connect to %s".printf(network.name);
        yield Notifications.show(title, error.message, "wifi", true);
    }
}
