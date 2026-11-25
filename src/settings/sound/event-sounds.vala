/* A group of sounds that event-sounds.sh plays. */
struct EventSound {
    string setting;             // variable in local.conf
    bool enabled_by_default;
    string title;
    string details;
    string example;             // event to play

    public static EventSound[] all() {
        return {
            {
                "SOUND_POWER",
                true,
                "Charger",
                "connected and disconnected",
                "plug"
            },
            {
                "SOUND_BATTERY",
                true,
                "Low battery",
                "20, 10 and 5 % left",
                "battery-20"
            },
            {
                "SOUND_BLUETOOTH",
                true,
                "Bluetooth",
                "device connected and disconnected",
                "connected"
            },
            {
                "SOUND_LOGIN",
                true,
                "Login",
                "",
                "login"
            },
            {
                "SOUND_LOGOUT",
                false,
                "Logout and shutdown",
                "the computer waits two seconds for it",
                "logout"
            }
        };
    }
}

class EventSoundRow : Gtk.Box {
    public signal void failed(string message);
    public signal void saved();

    EventSound event;
    Gtk.Switch enabled_switch = new Gtk.Switch();

    public EventSoundRow(EventSound event) {
        Object(orientation: Gtk.Orientation.HORIZONTAL, spacing: 10);
        this.event = event;

        var title = new Gtk.Label(event.title);
        var details = new Gtk.Label(event.details);
        details.xalign = 0;
        details.ellipsize = Pango.EllipsizeMode.END;
        details.get_style_context().add_class("dim-label");
        var play_button = new Gtk.Button.from_icon_name("media-playback-start-symbolic");
        play_button.relief = Gtk.ReliefStyle.NONE;
        play_button.tooltip_text = "Play";
        play_button.clicked.connect(play);
        enabled_switch.valign = Gtk.Align.CENTER;
        enabled_switch.active = is_enabled();
        enabled_switch.notify["active"].connect(save);

        pack_start(title, false, false);
        pack_start(details, true, true);
        pack_start(play_button, false, false);
        pack_start(enabled_switch, false, false);
    }

    bool is_enabled() {
        return LocalConf.read(event.setting, event.enabled_by_default ? "1" : "0") == "1";
    }

    void save() {
        try {
            LocalConf.write(event.setting, enabled_switch.active ? "1" : "0");
            saved();
        } catch (Error error) {
            failed("Could not be saved: %s".printf(error.message));
        }
    }

    void play() {
        string player = Path.build_filename(
            Environment.get_user_config_dir(),
            "openbox",
            "event-sounds.sh"
        );
        try {
            new Subprocess.newv({ player, "preview", event.example }, SubprocessFlags.NONE);
        } catch (Error error) {
            failed(error.message);
        }
    }
}
