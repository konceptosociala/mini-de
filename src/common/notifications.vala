/* Messages shown by the notification daemon. */
namespace Notifications {
    const string NAME = "org.freedesktop.Notifications";
    const string PATH = "/org/freedesktop/Notifications";
    const int TIMEOUT = 2000;       // ms

    /* A message with the same tag replaces the previous one. */
    public async void show(string title, string body = "", string tag = "", bool urgent = false) {
        const uint8 NORMAL = 1;
        const uint8 CRITICAL = 2;
        var actions = new VariantBuilder(new VariantType("as"));
        var hints = new VariantBuilder(new VariantType("a{sv}"));
        hints.add("{sv}", "urgency", new Variant.byte(urgent ? CRITICAL : NORMAL));
        if (tag != "") {
            hints.add("{sv}", "x-dunst-stack-tag", new Variant.string(tag));
        }
        var parameters = new Variant(
            "(susssasa{sv}i)",
            "Mini DE",
            0,
            "",
            title,
            body,
            actions,
            hints,
            -1
        );
        try {
            var bus = yield Bus.get(BusType.SESSION);
            yield bus.call(
                NAME,
                PATH,
                NAME,
                "Notify",
                parameters,
                null,
                DBusCallFlags.NONE,
                TIMEOUT
            );
        } catch (Error error) {
            warning("%s: %s (%s)", title, body, error.message);
        }
    }
}
