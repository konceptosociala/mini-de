/* Lets other programs open the launcher over D-Bus. */
[DBus (name = "local.minide.Shell")]
class ShellService : Object {
    const string NAME = "local.minide.Shell";
    const string PATH = "/local/minide/Shell";
    const int TIMEOUT = 3000;       // ms

    [DBus (visible = false)]
    public signal void launcher_requested();

    public void toggle_launcher() throws DBusError, IOError {
        launcher_requested();
    }

    [DBus (visible = false)]
    public void start() {
        Bus.own_name(
            BusType.SESSION,
            NAME,
            BusNameOwnerFlags.NONE,
            (connection) => {
                try {
                    connection.register_object(PATH, this);
                } catch (IOError error) {
                    warning("%s: %s", NAME, error.message);
                }
            },
            null,
            () => warning("%s is no longer on the bus", NAME)
        );
    }

    /* Asks the running shell. */
    [DBus (visible = false)]
    public static void call_toggle_launcher() throws Error {
        Bus.get_sync(BusType.SESSION).call_sync(
            NAME,
            PATH,
            NAME,
            "ToggleLauncher",
            null,
            null,
            DBusCallFlags.NO_AUTO_START,
            TIMEOUT
        );
    }
}
