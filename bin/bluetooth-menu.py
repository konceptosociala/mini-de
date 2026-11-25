#!/usr/bin/python3
"""Connect, pair and forget Bluetooth devices in rofi (talks to BlueZ over D-Bus)."""
import re, shutil, subprocess, sys
from gi.repository import Gio, GLib

SCAN, FORGET, OFF, ON = "Search for new devices", "Forget a device…", "Turn Bluetooth off", "Turn Bluetooth on"
SCAN_SECONDS = 8
BLUEZ, ADAPTER, DEVICE = "org.bluez", "org.bluez.Adapter1", "org.bluez.Device1"
AGENT_PATH = "/local/minide/agent"
AGENT = """<node><interface name="org.bluez.Agent1">
  <method name="Release"/>
  <method name="Cancel"/>
  <method name="RequestPinCode"><arg type="o" direction="in"/><arg type="s" direction="out"/></method>
  <method name="DisplayPinCode"><arg type="o" direction="in"/><arg type="s" direction="in"/></method>
  <method name="RequestPasskey"><arg type="o" direction="in"/><arg type="u" direction="out"/></method>
  <method name="DisplayPasskey"><arg type="o" direction="in"/><arg type="u" direction="in"/><arg type="q" direction="in"/></method>
  <method name="RequestConfirmation"><arg type="o" direction="in"/><arg type="u" direction="in"/></method>
  <method name="RequestAuthorization"><arg type="o" direction="in"/></method>
  <method name="AuthorizeService"><arg type="o" direction="in"/><arg type="s" direction="in"/></method>
</interface></node>"""
ICONS = {"audio": "󰋋", "input-keyboard": "󰌌", "input-mouse": "󰍽", "input-gaming": "󰊗", "phone": "󰄜", "computer": "󰌢"}

try:
    bus = Gio.bus_get_sync(Gio.BusType.SYSTEM)
except GLib.Error as e:
    sys.exit(e.message)


class Failed(Exception):
    pass


def call(path, iface, method, args=None, timeout=30):
    """Call a method while the main loop runs, so that BlueZ can ask the agent meanwhile."""
    loop, out = GLib.MainLoop(), {}

    def done(conn, result):
        try:
            out["value"] = conn.call_finish(result).unpack()
        except GLib.Error as e:
            out["error"] = re.sub(r"^GDBus\.Error:\S+: ", "", e.message)
        loop.quit()
    bus.call(BLUEZ, path, iface, method, args, None, Gio.DBusCallFlags.NONE, timeout * 1000, None, done)
    loop.run()
    if "error" in out:
        raise Failed(out["error"])
    return out["value"]


def set_prop(path, iface, name, value):
    call(path, "org.freedesktop.DBus.Properties", "Set", GLib.Variant("(ssv)", (iface, name, GLib.Variant("b", value))))


def notify(title, text="", urgent=False):
    subprocess.run(["notify-send", "-u", "critical" if urgent else "normal",
                    "-h", "string:x-dunst-stack-tag:bluetooth", title, text])


def rofi(prompt, items, *extra):
    r = subprocess.run(["rofi", "-dmenu", "-i", "-p", prompt, "-format", "i", *extra],
                       input="\n".join(items), capture_output=True, text=True)
    return int(r.stdout) if r.returncode == 0 and r.stdout.strip().lstrip("-").isdigit() else None


def ask(prompt):
    r = subprocess.run(["rofi", "-dmenu", "-p", prompt, "-l", "0"], input="", capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else ""


class Device:
    def __init__(self, path, props, battery):
        self.path, self.battery = path, battery
        self.name = " ".join(props.get("Alias", "").split()) or props.get("Address", "?")
        self.named = "Name" in props
        self.paired, self.connected = props.get("Paired", False), props.get("Connected", False)
        self.trusted = props.get("Trusted", False)
        self.rssi = props.get("RSSI", -999)
        icon = props.get("Icon", "")
        self.icon = next((g for k, g in ICONS.items() if icon.startswith(k)), "󰂯")

    def row(self):
        state = "   ✓ connected" if self.connected else "" if self.paired else "   new"
        return f"{self.icon}  {self.name}" + (f"  {self.battery} %" if self.battery is not None else "") + state


def state():
    """Path and properties of the first adapter, and its devices: connected, paired, then new ones by signal."""
    objects = call("/", "org.freedesktop.DBus.ObjectManager", "GetManagedObjects")[0]
    adapters = sorted(p for p, i in objects.items() if ADAPTER in i)
    if not adapters:
        raise Failed("No Bluetooth adapter")
    path = adapters[0]
    devices = [Device(p, i[DEVICE], i.get("org.bluez.Battery1", {}).get("Percentage"))
               for p, i in objects.items() if DEVICE in i and i[DEVICE].get("Adapter") == path]
    devices = [d for d in devices if d.paired or d.connected or d.named]      # others only have an address
    devices.sort(key=lambda d: (not d.connected, not d.paired, 0 if d.paired else -d.rssi, d.name.casefold()))
    return path, objects[path][ADAPTER], devices


def scan(adapter):
    notify("Bluetooth", "Searching for devices…")
    call(adapter, ADAPTER, "StartDiscovery")
    loop = GLib.MainLoop()
    GLib.timeout_add_seconds(SCAN_SECONDS, loop.quit)
    loop.run()
    try:
        call(adapter, ADAPTER, "StopDiscovery")
    except Failed:
        pass


# ── pairing ──────────────────────────────────────────────────
def agent_call(_conn, _sender, _path, _iface, method, args, inv):
    args = args.unpack()

    def reject():
        inv.return_dbus_error("org.bluez.Error.Rejected", "Rejected")
    if method == "RequestConfirmation":
        if rofi(f"Does the device show {args[1]:06d}?", ["Yes", "No"], "-l", "2") == 0:
            inv.return_value(None)
        else:
            reject()
    elif method == "RequestAuthorization":
        if rofi("Pair with this device?", ["Yes", "No"], "-l", "2") == 0:
            inv.return_value(None)
        else:
            reject()
    elif method == "RequestPinCode":
        pin = ask("PIN code")
        if 1 <= len(pin) <= 16:
            inv.return_value(GLib.Variant("(s)", (pin,)))
        else:
            reject()
    elif method == "RequestPasskey":
        key = ask("Code shown by the device")
        if key.isascii() and key.isdigit() and int(key) <= 999999:
            inv.return_value(GLib.Variant("(u)", (int(key),)))
        else:
            reject()
    elif method in ("DisplayPinCode", "DisplayPasskey"):
        code = args[1] if method == "DisplayPinCode" else f"{args[1]:06d}"
        notify("Bluetooth", f"Type {code} on the device and press Enter", True)
        inv.return_value(None)
    else:
        inv.return_value(None)


def pair(adapter, pairable, device):
    info = Gio.DBusNodeInfo.new_for_xml(AGENT).interfaces[0]
    reg = bus.register_object(AGENT_PATH, info, agent_call, None, None)
    call("/org/bluez", "org.bluez.AgentManager1", "RegisterAgent", GLib.Variant("(os)", (AGENT_PATH, "KeyboardDisplay")))
    try:
        if not pairable:             # otherwise the keys of the device are not kept
            set_prop(adapter, ADAPTER, "Pairable", True)
        call(device.path, DEVICE, "Pair", timeout=90)
    finally:
        try:
            call("/org/bluez", "org.bluez.AgentManager1", "UnregisterAgent", GLib.Variant("(o)", (AGENT_PATH,)))
            if not pairable:
                set_prop(adapter, ADAPTER, "Pairable", False)
        except Failed:
            pass
        bus.unregister_object(reg)


def choose(adapter, pairable, device):
    try:
        if device.connected:
            call(device.path, DEVICE, "Disconnect")
            return notify("Bluetooth", f"Disconnected from {device.name}")
        notify("Bluetooth", f"Connecting to {device.name}…")
        if not device.paired:
            pair(adapter, pairable, device)
        if not device.trusted:       # so that it may connect by itself later
            set_prop(device.path, DEVICE, "Trusted", True)
        call(device.path, DEVICE, "Connect", timeout=60)
        notify("Bluetooth", f"Connected to {device.name}")
    except Failed as e:
        notify(f"Could not {'disconnect from' if device.connected else 'connect to'} {device.name}", str(e), True)


def forget(adapter, devices):
    i = rofi("Forget", [d.row() for d in devices])
    if i is not None and 0 <= i < len(devices):
        call(adapter, ADAPTER, "RemoveDevice", GLib.Variant("(o)", (devices[i].path,)))
        notify("Bluetooth", f"{devices[i].name} was forgotten")


def main():
    while True:
        adapter, props, devices = state()
        if not props.get("Powered"):
            if rofi("Bluetooth", [ON], "-l", "1") == 0:
                if shutil.which("rfkill"):
                    subprocess.run(["rfkill", "unblock", "bluetooth"], capture_output=True)
                set_prop(adapter, ADAPTER, "Powered", True)
                notify("Bluetooth", "Turned on")
            return
        paired = [d for d in devices if d.paired]
        actions = [SCAN] + ([FORGET] if paired else []) + [OFF]
        active = [str(i) for i, d in enumerate(devices) if d.connected]
        i = rofi("Bluetooth", [d.row() for d in devices] + actions, *(["-a", ",".join(active)] if active else []))
        if i is None or i < 0:
            return
        if i < len(devices):
            return choose(adapter, props.get("Pairable", False), devices[i])
        action = actions[i - len(devices)]
        if action == SCAN:
            scan(adapter)
            continue
        if action == FORGET:
            forget(adapter, paired)
        elif action == OFF:
            set_prop(adapter, ADAPTER, "Powered", False)
            notify("Bluetooth", "Turned off")
        return


try:
    main()
except Failed as e:
    notify("Bluetooth", str(e), True)
    sys.exit(1)
