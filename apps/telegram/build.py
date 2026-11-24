#!/usr/bin/python3
"""Builds a Telegram Desktop theme in the colors of a mini-de variant.
   build.py <night.tdesktop-theme> <output> KEY=#rrggbb ...
The base is Telegram's own night theme: its blue-grays become the grays of the variant,
its blues become the accent, everything else (names, files, errors) stays."""
import colorsys, io, re, struct, sys, zipfile, zlib

base, output = sys.argv[1:3]
P = dict(a.split("=", 1) for a in sys.argv[3:])
rgb = lambda h: tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))
hexa = lambda c: "#%02x%02x%02x" % tuple(round(x) for x in c)
mix = lambda a, b, t: tuple(x + (y - x) * t for x, y in zip(a, b))

P["LINK_OUT"] = hexa(mix(rgb(P["ACCENT_TEXT"]), (255, 255, 255), 0.45))      # readable on own messages

# lightness of the night theme -> color of the variant
RAMP = [(0.00, (0, 0, 0)), (0.09, rgb(P["SURFACE"])), (0.128, rgb(P["BG"])), (0.20, rgb(P["RAISED"])),
        (0.31, rgb(P["BORDER"])), (0.55, rgb(P["DIM"])), (0.94, rgb(P["FG"])), (1.00, (255, 255, 255))]

# surfaces that define the look; other keys refer to these or are recolored by the rules below
FIXED = {
    "windowBg": "BG", "windowFg": "FG", "windowBoldFg": "FG", "windowBoldFgOver": "FG", "windowFgOver": "FG",
    "windowBgOver": "RAISED", "windowBgRipple": "BORDER", "windowSubTextFg": "DIM", "windowSubTextFgOver": "DIM",
    "windowBgActive": "ACCENT", "windowFgActive": "ON_ACCENT", "windowActiveTextFg": "ACCENT_TEXT",
    "activeButtonBg": "ACCENT", "activeButtonBgOver": "ACCENT", "activeButtonBgRipple": "ACCENT_TEXT",
    "activeButtonFg": "ON_ACCENT", "activeButtonFgOver": "ON_ACCENT", "activeButtonSecondaryFg": "ON_ACCENT",
    "activeLineFg": "ACCENT", "lightButtonFg": "ACCENT_TEXT", "menuIconFg": "DIM",
    "titleBg": "BG", "titleBgActive": "BG", "topBarBg": "BG", "boxBg": "BG", "menuBg": "BG",
    "filterInputInactiveBg": "SURFACE", "filterInputActiveBg": "SURFACE",
    "dialogsBgOver": "RAISED", "dialogsBgActive": "HILITE", "dialogsNameFg": "FG", "dialogsTextFg": "DIM", "dialogsDateFg": "DIM",
    "dialogsNameFgActive": "HILITE_FG", "dialogsTextFgActive": "HILITE_FG", "dialogsDateFgActive": "HILITE_FG",
    "dialogsUnreadBg": "ACCENT", "dialogsUnreadFg": "ON_ACCENT", "dialogsUnreadFgActive": "HILITE",
    "sideBarBg": "SURFACE", "sideBarBgActive": "HILITE", "sideBarTextFg": "DIM", "sideBarIconFg": "DIM",
    "sideBarTextFgActive": "HILITE_FG", "sideBarIconFgActive": "ACCENT_TEXT", "sideBarBadgeBg": "ACCENT", "sideBarBadgeFg": "ON_ACCENT",
    "msgInBg": "BG", "msgOutBg": "HILITE", "msgInBgSelected": "ACCENT", "msgOutBgSelected": "ACCENT",
    "msgInDateFg": "DIM", "msgOutDateFg": "FG", "historyTextOutFg": "FG",
    "msgInServiceFg": "ACCENT_TEXT", "msgOutServiceFg": "LINK_OUT",
    "historyLinkInFg": "ACCENT_TEXT", "historyLinkOutFg": "LINK_OUT",
    "historyComposeAreaBg": "BG", "historyPinnedBg": "BG", "historySendIconFg": "ACCENT_TEXT",
    "mainMenuCoverBg": "HILITE", "mainMenuCloudBg": "SURFACE", "mainMenuCoverFg": "HILITE_FG", "mainMenuCloudFg": "FG",
    "tooltipBg": "RAISED",
}
WITH_ALPHA = {"msgServiceBg": ("SURFACE", "d5")}


def recolor(value):
    h, l, s = colorsys.rgb_to_hls(*(x / 255 for x in rgb(value)))
    if not 0.52 < h < 0.66:                       # not blue: keep reds, greens, yellows and plain grays
        return value
    if s >= 0.42 and l >= 0.24:                   # real blues
        return P["HILITE"] if l < 0.34 else P["ACCENT"] if l < 0.54 else P["ACCENT_TEXT"]
    for (l0, c0), (l1, c1) in zip(RAMP, RAMP[1:]):
        if l <= l1:
            return hexa(mix(c0, c1, (l - l0) / (l1 - l0)))
    return value


lines = []
for line in zipfile.ZipFile(base).read("colors.tdesktop-theme").decode().splitlines():
    m = re.match(r"([A-Za-z0-9]+)\s*:\s*([^;]+);", line)
    if not m:
        continue
    key, value = m.group(1), m.group(2).strip()
    if key in FIXED:
        value = P[FIXED[key]]
    elif key in WITH_ALPHA:
        value = P[WITH_ALPHA[key][0]] + WITH_ALPHA[key][1]
    elif re.fullmatch(r"#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?", value):
        value = recolor(value[:7].lower()) + value[7:]
    lines.append(f"{key}: {value};")


def png(color, size=16):
    chunk = lambda t, d: struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d))
    rows = (b"\0" + bytes(color) * size) * size
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b""))


with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as z:
    z.writestr("colors.tdesktop-theme", "\n".join(lines) + "\n")
    z.writestr("tiled.png", png(rgb(P["SURFACE"])))        # chat background
