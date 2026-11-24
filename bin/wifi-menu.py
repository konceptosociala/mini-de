#!/usr/bin/python3
"""Choose a Wi-Fi network in rofi (uses nmcli)."""
import re, subprocess, sys

RESCAN, EDIT, OFF, ON = "Rescan", "Edit connections…", "Turn Wi-Fi off", "Turn Wi-Fi on"


def nmcli(*a, timeout=60):
    try:
        return subprocess.run(["nmcli", *a], capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return subprocess.CompletedProcess(a, 1, "", "Timed out")


def rows(*a):
    """Terse nmcli output as lists of fields; ':' inside a field is escaped as '\\:'."""
    for line in nmcli("-t", *a).stdout.splitlines():
        yield [re.sub(r"\\(.)", r"\1", f) for f in re.split(r"(?<!\\):", line)]


def notify(title, text="", urgent=False):
    subprocess.run(["notify-send", "-u", "critical" if urgent else "normal",
                    "-h", "string:x-dunst-stack-tag:wifi", title, text])


def rofi(prompt, items, *extra):
    r = subprocess.run(["rofi", "-dmenu", "-i", "-p", prompt, "-format", "i", *extra],
                       input="\n".join(items), capture_output=True, text=True)
    return int(r.stdout) if r.returncode == 0 and r.stdout.strip().lstrip("-").isdigit() else None


def ask_password(ssid):
    r = subprocess.run(["rofi", "-dmenu", "-password", "-p", f"Password for {ssid}", "-l", "0"],
                       input="", capture_output=True, text=True)
    return r.stdout.rstrip("\n") if r.returncode == 0 else None


def networks():
    """Strongest access point of every visible network, connected one first."""
    best = {}
    for f in rows("-f", "IN-USE,SSID,SIGNAL,SECURITY", "device", "wifi", "list", "--rescan", "no"):
        if len(f) != 4 or not f[1]:
            continue
        used, ssid, signal, sec = f[0] == "*", f[1], int(f[2] or 0), f[3] not in ("", "--")
        old = best.get(ssid)
        best[ssid] = (used or bool(old and old[0]), ssid, max(signal, old[2] if old else 0), sec or bool(old and old[3]))
    return sorted(best.values(), key=lambda n: (not n[0], -n[2]))


def saved():
    """SSID -> UUID of saved Wi-Fi connections."""
    out = {}
    for f in rows("-f", "UUID,TYPE", "connection", "show"):
        if f[-1] == "802-11-wireless":
            ssid = nmcli("-g", "802-11-wireless.ssid", "connection", "show", f[0]).stdout.rstrip("\n")
            out.setdefault(re.sub(r"\\(.)", r"\1", ssid), f[0])
    return out


def scan():
    notify("Wi-Fi", "Scanning…")
    nmcli("device", "wifi", "list", "--rescan", "yes")


def bars(signal):
    return "▂▄▆█"[:max(1, min(4, (signal + 24) // 25))].ljust(4)


def connect(ssid, secured):
    uuid = saved().get(ssid)
    if uuid:
        notify("Wi-Fi", f"Connecting to {ssid}…")
        r = nmcli("connection", "up", "uuid", uuid)
        if r.returncode == 0:
            return notify("Wi-Fi", f"Connected to {ssid}")
        return notify(f"Could not connect to {ssid}", r.stderr.strip(), True)
    args = ["device", "wifi", "connect", ssid]
    if secured:
        password = ask_password(ssid)
        if not password:
            return
        args += ["password", password]
    notify("Wi-Fi", f"Connecting to {ssid}…")
    r = nmcli(*args)
    if r.returncode == 0:
        return notify("Wi-Fi", f"Connected to {ssid}")
    new = saved().get(ssid)            # do not keep a connection with a wrong password
    if new:
        nmcli("connection", "delete", "uuid", new)
    notify(f"Could not connect to {ssid}", r.stderr.strip(), True)


def main():
    scanned = False
    while True:
        if nmcli("radio", "wifi").stdout.strip() != "enabled":
            if rofi("Wi-Fi", [ON]) == 0:
                nmcli("radio", "wifi", "on")
                notify("Wi-Fi", "Turned on")
            return
        nets = networks()
        if len(nets) < 2 and not scanned:      # NetworkManager forgets old scan results
            scan()
            nets, scanned = networks(), True
        items = [f"{bars(s)}  {name}" + ("  🔒" if sec else "") + ("   ✓ connected" if used else "")
                 for used, name, s, sec in nets]
        actions = [RESCAN, EDIT, OFF]
        i = rofi("Wi-Fi", items + actions, *(["-a", "0"] if nets and nets[0][0] else []))
        if i is None or i < 0:
            return
        if i < len(nets):
            used, ssid, _, sec = nets[i]
            return None if used else connect(ssid, sec)
        action = actions[i - len(nets)]
        if action == RESCAN:
            scan()
            continue
        if action == EDIT:
            subprocess.Popen(["nm-connection-editor"], start_new_session=True)
        elif action == OFF:
            nmcli("radio", "wifi", "off")
            notify("Wi-Fi", "Turned off")
        return


sys.exit(main())
