/* A short lone tap of Super. Only listens (XInput2 raw events), grabs no keys. */
public class X11.SuperTap {
    const ulong MAX_DURATION = 600;         // ms: a longer press is not a tap

    public signal void tapped();

    enum State {
        RELEASED,
        PRESSED_ALONE,
        COMBINED        // something else was pressed too
    }

    Connection connection;
    int input_extension;
    uint[] super_keys = {};
    State state = State.RELEASED;
    uint pressed_key = 0;
    ulong pressed_at = 0;

    public SuperTap() throws X11.Error {
        connection = new Connection();
        foreach (ulong keysym in new ulong[] { Keysym.SUPER_LEFT, Keysym.SUPER_RIGHT }) {
            uint keycode = connection.keycode(keysym);
            if (keycode != 0) {
                super_keys += keycode;
            }
        }
        select_raw_events();
        connection.listen(on_event);
    }

    void select_raw_events() throws X11.Error {
        int first_event, first_error;
        bool found = Xl.query_extension(
            connection.display,
            "XInputExtension",
            out input_extension,
            out first_event,
            out first_error
        );
        int major = 2;
        int minor = 2;
        if (!found || Xl.query_input_version(connection.display, ref major, ref minor) != 0) {
            throw new X11.Error.NO_RAW_INPUT("the X server has no XInput 2.2");
        }
        uint8 bits[4] = { 0, 0, 0, 0 };
        foreach (int type in new int[] {
            Xl.RAW_KEY_PRESS,
            Xl.RAW_KEY_RELEASE,
            Xl.RAW_BUTTON_PRESS
        }) {
            bits[type >> 3] |= (uint8) (1 << (type & 7));
        }
        Xl.InputMask mask = {};
        mask.deviceid = Xl.ALL_MASTER_DEVICES;
        mask.mask_len = bits.length;
        mask.bits = bits;
        Xl.select_input_events(connection.display, connection.root.id, &mask, 1);
        connection.sync();
    }

    /* Nobody has grabbed the keyboard, such as the lock screen, a menu or a virtual machine. */
    public bool keyboard_is_free() {
        bool is_free = connection.grab_keyboard();
        if (is_free) {
            connection.release_keyboard();
        }
        return is_free;
    }

    void on_event(Xl.Event event) {
        if (event.type != Xl.GENERIC_EVENT || event.cookie_extension != input_extension) {
            return;
        }
        Xl.Event cookie = event;
        if (!Xl.get_event_data(connection.display, &cookie)) {
            return;
        }
        Xl.RawInput input = *((Xl.RawInput*) cookie.cookie_data);
        Xl.free_event_data(connection.display, &cookie);
        on_input(input);
    }

    void on_input(Xl.RawInput input) {
        uint keycode = input.detail;
        switch (input.evtype) {
            case Xl.RAW_KEY_PRESS:
                on_key_pressed(keycode, input.time);
                break;
            case Xl.RAW_BUTTON_PRESS:
                if (state != State.RELEASED) {
                    state = State.COMBINED;
                }
                break;
            case Xl.RAW_KEY_RELEASE:
                on_key_released(keycode, input.time);
                break;
        }
    }

    void on_key_pressed(uint keycode, ulong time) {
        if (state == State.RELEASED) {
            if (keycode in super_keys) {
                state = State.PRESSED_ALONE;
                pressed_key = keycode;
                pressed_at = time;
            }
        } else if (state == State.COMBINED || keycode != pressed_key) {
            state = State.COMBINED;
        }
    }

    void on_key_released(uint keycode, ulong time) {
        if (keycode in super_keys) {
            bool is_tap = state == State.PRESSED_ALONE
                && keycode == pressed_key
                && time - pressed_at <= MAX_DURATION;
            state = State.RELEASED;
            if (is_tap) {
                tapped();
            }
        } else if (state == State.COMBINED && !connection.any_key_down(super_keys)) {
            state = State.RELEASED;
        }
    }
}
