#!/usr/bin/python3
"""Builds a Kvantum (Qt) theme in the colors of a mini-de variant.
   build.py <KvLibadwaita directory> <output directory> KEY=#rrggbb ...
The base is KvLibadwaitaDark: its grays become the grays of the variant and its blues the accent;
shapes, sizes and shadows stay."""
import colorsys, os, re, sys

src, out = sys.argv[1:3]
P = dict(a.split("=", 1) for a in sys.argv[3:])
rgb = lambda h: tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))
hexa = lambda c: "#%02x%02x%02x" % tuple(round(x) for x in c)
mix = lambda a, b, t: tuple(x + (y - x) * t for x, y in zip(a, b))

# lightness of the base theme -> color of the variant
RAMP = [(0.00, (0, 0, 0)), (0.12, rgb(P["SURFACE"])), (0.17, rgb(P["BG"])), (0.20, rgb(P["BG"])), (0.27, rgb(P["RAISED"])),
        (0.40, rgb(P["BORDER"])), (0.60, rgb(P["DIM"])), (0.875, rgb(P["FG"])), (1.00, (255, 255, 255))]
GENERAL = {
    "window.color": "BG", "base.color": "SURFACE", "alt.base.color": "ALT", "button.color": "RAISED", "light.color": "BORDER",
    "mid.light.color": "RAISED", "dark.color": "SURFACE", "mid.color": "BG", "highlight.color": "ACCENT",
    "inactive.highlight.color": "HILITE", "text.color": "FG", "window.text.color": "FG", "button.text.color": "FG",
    "disabled.text.color": "OFF", "tooltip.base.color": "RAISED", "tooltip.text.color": "FG", "highlight.text.color": "ON_ACCENT",
    "inactive.highlight.text.color": "HILITE_FG", "link.color": "ACCENT_TEXT", "link.visited.color": "DIM",
    "placeholder.text.color": "DIM",
}
P["ALT"] = hexa(mix(rgb(P["SURFACE"]), rgb(P["BG"]), 0.45))
P["OFF"] = hexa(mix(rgb(P["BG"]), rgb(P["DIM"]), 0.6))


def recolor(value):
    value = value.lower()
    r, g, b = rgb(value)
    if max(r, g, b) < 8 or min(r, g, b) > 240:      # shadows and white overlays
        return value
    h, l, s = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
    if s > 0.2 and max(r, g, b) - min(r, g, b) > 30:
        if 0.50 < h < 0.70:                         # blues
            return P["ACCENT"] if l < 0.62 else P["ACCENT_TEXT"]
        return value                                # red of destructive actions and the like
    for (l0, c0), (l1, c1) in zip(RAMP, RAMP[1:]):
        if l <= l1:
            return hexa(mix(c0, c1, (l - l0) / (l1 - l0)))
    return value


def convert(text):
    return re.sub(r"#[0-9a-fA-F]{6}\b", lambda m: recolor(m[0]), text)


os.makedirs(out, exist_ok=True)
name = os.path.basename(os.path.normpath(out))
base = os.path.join(src, "src", "KvLibadwaita", "KvLibadwaitaDark")
with open(base + ".svg") as f:
    svg = convert(f.read())
with open(base + ".kvconfig") as f:
    conf = convert(f.read())
conf = re.sub(r"(?m)^comment=.*$", "comment=KvLibadwaita in the colors of mini-de", conf)
head, sep, rest = conf.partition("[GeneralColors]")
body, sep2, tail = rest.partition("\n[")
for key, token in GENERAL.items():
    line = f"{key}={P[token]}"
    body, n = re.subn(rf"(?m)^{re.escape(key)}=.*$", line, body)
    if not n:
        body += "\n" + line
conf = head + sep + body.rstrip("\n") + "\n" + sep2 + tail
for ext, text in ((".svg", svg), (".kvconfig", conf)):
    with open(os.path.join(out, name + ext), "w") as f:
        f.write(text)
