/* Menus of the panel. */
const string USAGE = """usage:
  mini-de-menu wifi         choose a Wi-Fi network
  mini-de-menu bluetooth    connect, pair and forget Bluetooth devices
""";

int exit_code = 0;

async void run_menu(string menu) {
    string title = menu == "wifi" ? "Wi-Fi" : "Bluetooth";
    try {
        if (menu == "wifi") {
            yield new WifiMenu().run();
        } else {
            yield new BluetoothMenu().run();
        }
    } catch (Error error) {
        DBusError.strip_remote_error(error);
        yield Notifications.show(title, error.message, menu, true);
        exit_code = 1;
    }
}

int main(string[] args) {
    if (args.length != 2 || (args[1] != "wifi" && args[1] != "bluetooth")) {
        stderr.printf("%s", USAGE);
        return 2;
    }
    var loop = new MainLoop();
    run_menu.begin(args[1], (source, result) => {
        run_menu.end(result);
        loop.quit();
    });
    loop.run();
    return exit_code;
}
