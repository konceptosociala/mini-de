class WifiNetwork {
    public string name;
    public int signal_strength = 0;     // percent
    public bool secured = false;
    public bool connected = false;

    public WifiNetwork(string name) {
        this.name = name;
    }

    /* The connected one first, then by signal. */
    public static int compare(WifiNetwork first, WifiNetwork second) {
        if (first.connected != second.connected) {
            return first.connected ? -1 : 1;
        }
        return second.signal_strength - first.signal_strength;
    }
}

/* Wi-Fi through nmcli. */
class NetworkManager {
    const string TIMEOUT = "60";        // s

    public async bool is_wifi_enabled() {
        try {
            string state = yield nmcli({ "radio", "wifi" });
            return state.strip() == "enabled";
        } catch (Error error) {
            return false;
        }
    }

    public async void set_wifi_enabled(bool enabled) throws Error {
        yield nmcli({ "radio", "wifi", enabled ? "on" : "off" });
    }

    public async void scan() {
        try {
            yield nmcli({ "device", "wifi", "list", "--rescan", "yes" });
        } catch (Error error) {
            return;         // the old results stay
        }
    }

    /* One entry for all access points of a network. */
    public async GenericArray<WifiNetwork> visible_networks() {
        var networks = new GenericArray<WifiNetwork>();
        string list;
        try {
            list = yield nmcli({
                "-t",
                "-f",
                "IN-USE,SSID,SIGNAL,SECURITY",
                "device",
                "wifi",
                "list",
                "--rescan",
                "no"
            });
        } catch (Error error) {
            return networks;
        }
        foreach (unowned string line in list.split("\n")) {
            var fields = split_fields(line);
            if (fields.length != 4 || fields[1] == "") {
                continue;
            }
            var network = find_or_add(networks, fields[1]);
            network.connected = network.connected || fields[0] == "*";
            network.signal_strength = int.max(network.signal_strength, int.parse(fields[2]));
            network.secured = network.secured || (fields[3] != "" && fields[3] != "--");
        }
        networks.sort(WifiNetwork.compare);
        return networks;
    }

    static WifiNetwork find_or_add(GenericArray<WifiNetwork> networks, string name) {
        foreach (var network in networks) {
            if (network.name == name) {
                return network;
            }
        }
        var added = new WifiNetwork(name);
        networks.add(added);
        return added;
    }

    /* Id of the saved connection, null if there is none. */
    public async string? saved_connection(string network_name) {
        try {
            string list = yield nmcli({ "-t", "-f", "UUID,TYPE", "connection", "show" });
            foreach (unowned string line in list.split("\n")) {
                var fields = split_fields(line);
                if (fields[fields.length - 1] != "802-11-wireless") {
                    continue;
                }
                string name = yield nmcli({
                    "-g",
                    "802-11-wireless.ssid",
                    "connection",
                    "show",
                    fields[0]
                });
                if (unescape(name.strip()) == network_name) {
                    return fields[0];
                }
            }
        } catch (Error error) {
            warning("%s", error.message);
        }
        return null;
    }

    public async void connect_saved(string connection_id) throws Error {
        yield nmcli({ "connection", "up", "uuid", connection_id });
    }

    public async void connect_new(string network_name, string? password) throws Error {
        string[] arguments = { "device", "wifi", "connect", network_name };
        if (password != null) {
            arguments += "password";
            arguments += password;
        }
        yield nmcli(arguments);
    }

    public async void forget(string connection_id) throws Error {
        yield nmcli({ "connection", "delete", "uuid", connection_id });
    }

    // ── nmcli ───────────────────────────────────────────────

    async string nmcli(string[] arguments) throws Error {
        string[] command = { "timeout", TIMEOUT, "nmcli" };
        foreach (unowned string argument in arguments) {
            command += argument;
        }
        return yield Command.run_async(command);
    }

    /* Fields are separated by ':', which is written as '\:' inside of them. */
    static string[] split_fields(string line) {
        string[] fields = {};
        var field = new StringBuilder();
        bool escaped = false;
        for (int index = 0; index < line.length; index++) {
            char character = line[index];
            if (escaped) {
                field.append_c(character);
                escaped = false;
            } else if (character == '\\') {
                escaped = true;
            } else if (character == ':') {
                fields += field.str;
                field.truncate();
            } else {
                field.append_c(character);
            }
        }
        fields += field.str;
        return fields;
    }

    static string unescape(string text) {
        return string.joinv(":", split_fields(text));
    }
}
