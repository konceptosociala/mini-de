/* Answers of the user to the questions of BlueZ while a device is being paired. */
[DBus (name = "org.bluez.Error")]
errordomain AgentError {
    REJECTED
}

[DBus (name = "org.bluez.Agent1")]
class PairingAgent : Object {
    const int MAX_PIN_LENGTH = 16;
    const int64 MAX_PASSKEY = 999999;
    const uint DECIMAL = 10;            // otherwise 0042 would be octal

    public async string request_pin_code(ObjectPath device) throws DBusError, IOError, AgentError {
        string? pin = yield Rofi.ask("PIN code");
        string code = pin != null ? pin.strip() : "";
        if (code == "" || code.length > MAX_PIN_LENGTH) {
            throw new AgentError.REJECTED("Rejected");
        }
        return code;
    }

    public async uint32 request_passkey(ObjectPath device) throws DBusError, IOError, AgentError {
        string? answer = yield Rofi.ask("Code shown by the device");
        int64 passkey = -1;
        bool valid = answer != null
            && int64.try_parse(answer.strip(), out passkey, null, DECIMAL)
            && passkey >= 0
            && passkey <= MAX_PASSKEY;
        if (!valid) {
            throw new AgentError.REJECTED("Rejected");
        }
        return (uint32) passkey;
    }

    public async void request_confirmation(
        ObjectPath device,
        uint32 passkey
    ) throws DBusError, IOError, AgentError {
        yield confirm("Does the device show %06u?".printf(passkey));
    }

    public async void request_authorization(
        ObjectPath device
    ) throws DBusError, IOError, AgentError {
        yield confirm("Pair with this device?");
    }

    public async void display_pin_code(
        ObjectPath device,
        string pin_code
    ) throws DBusError, IOError {
        yield show_code(pin_code);
    }

    public async void display_passkey(
        ObjectPath device,
        uint32 passkey,
        uint16 entered
    ) throws DBusError, IOError {
        yield show_code("%06u".printf(passkey));
    }

    public void authorize_service(ObjectPath device, string uuid) throws DBusError, IOError {
    }

    public void cancel() throws DBusError, IOError {
    }

    public void release() throws DBusError, IOError {
    }

    async void confirm(string question) throws AgentError {
        int choice = yield Rofi.choose(question, { "Yes", "No" }, { "-l", "2" });
        if (choice != 0) {
            throw new AgentError.REJECTED("Rejected");
        }
    }

    async void show_code(string code) {
        string text = "Type %s on the device and press Enter".printf(code);
        yield Notifications.show("Bluetooth", text, "bluetooth", true);
    }
}
