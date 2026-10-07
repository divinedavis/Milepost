#!/usr/bin/env python3
"""App Store creative assets (Asset Library, fall 2026) for Milepost.

Apple's three canvases:

    header    3840x1646  product page header (21:9) — also each custom
                         product page's header
    search    3840x2560  search results asset (3:2)
    universal 5244x2950  16:9 master Apple can crop into either

Same look as make_asc_header.py (navy field, white runner wordmark, small
floating pieces of the product, no phone), re-laid in fractions of the
canvas. Apple crops the edges per device, so the wordmark and tagline sit in
the centre ~60% width / ~70% height and every floating piece is decoration:
losing any of them to a crop costs nothing that has to be read. The App
Store draws the icon, name and subtitle BELOW the header, so text is one
wordmark and one short line.

Content rules (Apple): no prices, no URLs, no (c), no awards or claims that
cannot be checked, no other platforms or stores, 4+. Every number on a chip
is a sample stat of the kind the app shows, not a claim.

One set per page: "default" (all three canvases) and one header per custom
product page in cpp-<slug>/. plan.json beside them is written by hand.

    ~/.venvs/spendcap/bin/python scripts/make_creative_assets.py [OUT_DIR]
    # default OUT_DIR: marketing/asc-creative/
"""
from __future__ import annotations

import pathlib
import subprocess
import sys
import tempfile

from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from asc_make_screenshots import NAVY, WHITE, font  # noqa: E402
from make_asc_header import (BLUE, CARD, GREEN, RED, SOFT, chip,  # noqa: E402
                             rounded, route_circle, shadow, split_tile,
                             start_pill, tilt)

ROOT = pathlib.Path(__file__).resolve().parent.parent
WORDMARK_SVG = ROOT / "marketing" / "logo" / "runner-wordmark-dark-transparent.svg"
CANVASES = {"header": (3840, 1646), "search": (3840, 2560), "universal": (5244, 2950)}
TOP = (78, 124, 236)
BOTTOM = (40, 80, 196)
TOE = (255, 255, 255)         # the navy toe vanishes on the navy field; white keeps the runner whole
TAG_INK = (226, 234, 255)
HEART = (255, 69, 88)

PAGES = {
    "default": {
        "tagline": "Press Start. Every mile, mapped.",
        "pieces": ["pace", "clock", "route", "splits", "start"],
    },
    "cpp-ride": {
        "tagline": "Every ride, mapped. Speed, splits, climbs.",
        "pieces": ["speed", "climb", "route-ride", "ride-splits", "ride-start"],
    },
    "cpp-watch": {
        "tagline": "Start a run from your wrist.",
        "pieces": ["pace", "heart", "route", None, "start"],
        "hero": "watch",
    },
}


# ---------------------------------------------------------------- pieces

def wordmark(width: int) -> Image.Image:
    """The runner wordmark rendered from its SVG at the exact width, with the
    toe recoloured so it does not vanish into the navy field."""
    svg = WORDMARK_SVG.read_text().replace("#3D6BE0", "#%02X%02X%02X" % TOE)
    with tempfile.TemporaryDirectory() as t:
        src, dst = pathlib.Path(t) / "wm.svg", pathlib.Path(t) / "wm.png"
        src.write_text(svg)
        subprocess.run(["rsvg-convert", "-w", str(width), str(src), "-o", str(dst)], check=True)
        return Image.open(dst).convert("RGBA").copy()


def gradient(w: int, h: int) -> Image.Image:
    col = Image.new("RGB", (1, h))
    px = col.load()
    for y in range(h):
        t = y / (h - 1)
        px[0, y] = tuple(int(a + (b - a) * t) for a, b in zip(TOP, BOTTOM))
    base = col.resize((w, h))
    # A soft lighter pool behind the wordmark so the centre reads first.
    glow = Image.new("L", (w, h), 0)
    ImageDraw.Draw(glow).ellipse((w * 0.22, h * 0.18, w * 0.78, h * 0.82), fill=70)
    glow = glow.filter(ImageFilter.GaussianBlur(int(min(w, h) * 0.12)))
    return Image.composite(Image.new("RGB", (w, h), (120, 160, 250)), base, glow)


def bike_glyph(size: int, ink: tuple) -> Image.Image:
    """A road bike in strokes: two wheels, diamond frame, bars and saddle."""
    s = size
    im = Image.new("RGBA", (s, int(s * 0.62)), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    lw = max(4, int(s * 0.05))
    r = s * 0.20
    rear, front = (s * 0.22, s * 0.40), (s * 0.78, s * 0.40)
    for cx, cy in (rear, front):
        d.ellipse((cx - r, cy - r, cx + r, cy + r), outline=ink, width=lw)
    bb = (s * 0.45, s * 0.40)          # bottom bracket
    seat = (s * 0.38, s * 0.12)
    head = (s * 0.70, s * 0.14)
    for a, b in ((rear, bb), (bb, seat), (seat, rear), (seat, head), (head, bb), (head, front)):
        d.line((a, b), fill=ink, width=lw)
    d.line(((seat[0] - s * 0.07, seat[1] - s * 0.02), (seat[0] + s * 0.05, seat[1] - s * 0.02)),
           fill=ink, width=lw)
    d.line((head, (head[0] + s * 0.07, head[1] - s * 0.05)), fill=ink, width=lw)
    for x, y in (*(rear, front), bb, seat, head):
        rr = lw / 2
        d.ellipse((x - rr, y - rr, x + rr, y + rr), fill=ink)
    return im


def speed_splits(size: tuple[int, int]) -> Image.Image:
    """The splits bar as a ride shows it: each mile's speed, the fastest lit."""
    im, d = rounded(size, int(size[1] * 0.14), CARD)
    w, h = size
    d.text((int(w * 0.09), int(h * 0.07)), "Splits (mph)", fill=SOFT, font=font(int(h * 0.10), bold=False))
    base, col_w, gap, x = int(h * 0.86), int(w * 0.22), int(w * 0.06), int(w * 0.09)
    for i, (hh, label) in enumerate(((0.34, None), (0.48, "17.2"), (0.28, None))):
        top = base - int(h * hh)
        d.rounded_rectangle((x, top, x + col_w, base), radius=int(col_w * 0.12),
                            fill=BLUE if i == 1 else (58, 58, 58))
        if label:
            f = font(int(h * 0.11))
            d.text((x + (col_w - d.textlength(label, font=f)) / 2, top - int(h * 0.15)), label, fill=WHITE, font=f)
            d.rectangle((x, base + int(h * 0.02), x + col_w, base + int(h * 0.045)), fill=NAVY)
        x += col_w + gap
    return im


BLUE_LIGHT = (158, 189, 255)   # Theme.splitBlue


def heart(d: ImageDraw.ImageDraw, cx: float, cy: float, r: float, fill: tuple) -> None:
    d.ellipse((cx - 2 * r, cy - r * 1.6, cx, cy + r * 0.4), fill=fill)
    d.ellipse((cx, cy - r * 1.6, cx + 2 * r, cy + r * 0.4), fill=fill)
    d.polygon([(cx - 1.93 * r, cy - 0.3 * r), (cx + 1.93 * r, cy - 0.3 * r), (cx, cy + 1.9 * r)], fill=fill)


def heart_chip(h: int) -> Image.Image:
    f = font(int(h * 0.42))
    fs = font(int(h * 0.2), bold=False)
    probe = ImageDraw.Draw(Image.new("RGB", (1, 1)))
    tw = probe.textlength("148", font=f)
    w = int(h * 0.35 + h * 0.42 + h * 0.16 + max(tw, probe.textlength("heart rate", font=fs)) + h * 0.4)
    im, d = rounded((w, h), int(h * 0.28), CARD)
    heart(d, h * 0.35 + h * 0.21, h * 0.34, h * 0.105, HEART)
    x = h * 0.35 + h * 0.42 + h * 0.16
    d.text((x, h * 0.12), "148", fill=WHITE, font=f)
    d.text((h * 0.35, h * 0.64), "heart rate", fill=SOFT, font=fs)
    return im


def watch(height: int) -> Image.Image:
    """An Apple Watch face-on: band stubs, case, crown, and the metrics page
    (distance big, pace and heart rate under it, the Pause button)."""
    H = height
    cw, ch = int(H * 0.56), int(H * 0.66)       # case
    W = int(cw * 1.14)
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    cx0 = (W - cw) // 2 - int(cw * 0.04)
    cy0 = (H - ch) // 2
    band = (28, 28, 30)
    bw = int(cw * 0.78)
    bx = cx0 + (cw - bw) // 2
    d.rounded_rectangle((bx, 0, bx + bw, cy0 + ch // 2), radius=int(bw * 0.18), fill=band)
    d.rounded_rectangle((bx, cy0 + ch // 2, bx + bw, H - 1), radius=int(bw * 0.18), fill=band)
    # crown + side button
    d.rounded_rectangle((cx0 + cw - 8, cy0 + int(ch * 0.22), cx0 + cw + int(cw * 0.07), cy0 + int(ch * 0.36)),
                        radius=int(cw * 0.03), fill=(150, 150, 156))
    d.rounded_rectangle((cx0 + cw - 8, cy0 + int(ch * 0.48), cx0 + cw + int(cw * 0.035), cy0 + int(ch * 0.66)),
                        radius=int(cw * 0.02), fill=(120, 120, 126))
    d.rounded_rectangle((cx0, cy0, cx0 + cw, cy0 + ch), radius=int(cw * 0.26), fill=(70, 70, 76))
    inset = int(cw * 0.045)
    d.rounded_rectangle((cx0 + inset, cy0 + inset, cx0 + cw - inset, cy0 + ch - inset),
                        radius=int(cw * 0.22), fill=(0, 0, 0))
    # screen content
    sx, sy = cx0 + int(cw * 0.15), cy0 + int(ch * 0.13)
    d.text((sx, sy), "Run", fill=BLUE_LIGHT, font=font(int(ch * 0.075)))
    d.text((cx0 + cw - int(cw * 0.15) - d.textlength("09:18", font=font(int(ch * 0.075))), sy),
           "09:18", fill=(255, 214, 10), font=font(int(ch * 0.075)))
    d.text((sx, sy + int(ch * 0.10)), "1.21", fill=WHITE, font=font(int(ch * 0.22)))
    d.text((sx + int(cw * 0.02), sy + int(ch * 0.34)), "mi", fill=SOFT, font=font(int(ch * 0.065), bold=False))
    row = sy + int(ch * 0.44)
    d.text((sx, row), "7:41", fill=WHITE, font=font(int(ch * 0.095)))
    d.text((sx, row + int(ch * 0.11)), "/mi", fill=SOFT, font=font(int(ch * 0.055), bold=False))
    hx = cx0 + int(cw * 0.56)
    heart(d, hx + ch * 0.026, row + ch * 0.05, ch * 0.022, HEART)
    d.text((hx + int(ch * 0.075), row), "148", fill=WHITE, font=font(int(ch * 0.095)))
    d.text((hx, row + int(ch * 0.11)), "bpm", fill=SOFT, font=font(int(ch * 0.055), bold=False))
    by = cy0 + int(ch * 0.75)
    d.rounded_rectangle((sx, by, cx0 + cw - int(cw * 0.15), by + int(ch * 0.11)),
                        radius=int(ch * 0.055), fill=NAVY)
    pf = font(int(ch * 0.06))
    label = "Pause"
    tw = d.textlength(label, font=pf)
    mid = cx0 + cw // 2
    bar_w, gap = int(ch * 0.012), int(ch * 0.012)
    icon_w = bar_w * 2 + gap
    x0 = mid - (icon_w + int(ch * 0.025) + tw) / 2
    for i in range(2):
        bxx = x0 + i * (bar_w + gap)
        d.rectangle((bxx, by + ch * 0.033, bxx + bar_w, by + ch * 0.077), fill=WHITE)
    d.text((x0 + icon_w + ch * 0.025, by + ch * 0.022), label, fill=WHITE, font=pf)
    return im


def ride_route(diameter: int) -> Image.Image:
    """The route disc with a longer, loopier line: a ride covers more map."""
    im = Image.new("RGBA", (diameter, diameter), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    s = diameter
    d.ellipse((0, 0, s - 1, s - 1), fill=CARD)
    d.ellipse((0, 0, s - 1, s - 1), outline=WHITE, width=int(s * 0.03))
    pts = [(0.24, 0.62), (0.28, 0.38), (0.44, 0.24), (0.62, 0.26), (0.74, 0.40),
           (0.68, 0.56), (0.52, 0.58), (0.50, 0.74), (0.70, 0.78)]
    pts = [(int(x * s), int(y * s)) for x, y in pts]
    d.line(pts, fill=NAVY, width=int(s * 0.05), joint="curve")
    r = int(s * 0.05)
    for (x, y), c in ((pts[0], GREEN), (pts[-1], RED)):
        d.ellipse((x - r, y - r, x + r, y + r), fill=c, outline=WHITE, width=int(r * 0.35))
    return im


def piece(name: str, s: float) -> Image.Image:
    """Each floating piece at its natural size for scale s (1.0 = 1646 tall)."""
    if name == "pace":
        return tilt(chip("7:40", "avg. pace /mi", int(300 * s), CARD, WHITE, SOFT), 7)
    if name == "speed":
        return tilt(chip("16.4", "avg. speed mph", int(300 * s), CARD, WHITE, SOFT), 7)
    if name == "clock":
        return tilt(chip("00:09:23", None, int(230 * s), CARD, WHITE, SOFT), -6)
    if name == "climb":
        return tilt(chip("+420 ft", "elevation gain", int(260 * s), CARD, WHITE, SOFT), -6)
    if name == "heart":
        return tilt(heart_chip(int(260 * s)), -6)
    if name in ("route", "route-ride"):
        d = int(470 * s)
        disc = route_circle(d) if name == "route" else ride_route(d)
        label = "1 mi" if name == "route" else "12 mi"
        badge = chip(label, None, int(130 * s), WHITE, NAVY, NAVY)
        im = Image.new("RGBA", (d + badge.width // 2, d + badge.height // 3), (0, 0, 0, 0))
        im.paste(disc, (0, badge.height // 3), disc)
        im.paste(badge, (im.width - badge.width, 0), badge)
        return im
    if name == "splits":
        return tilt(split_tile((int(560 * s), int(470 * s))), -8)
    if name == "ride-splits":
        return tilt(speed_splits((int(560 * s), int(470 * s))), -8)
    if name == "watch":
        return tilt(watch(int(760 * s)), -6)
    if name == "start":
        return start_pill(int(210 * s))
    if name == "ride-start":
        # The Record tab's bottom row: the sport chip beside Start.
        h = int(210 * s)
        sport = ride_chip(h)
        pill = start_pill(h)
        gap = int(40 * s)
        im = Image.new("RGBA", (sport.width + gap + pill.width, h), (0, 0, 0, 0))
        im.paste(sport, (0, 0), sport)
        im.paste(pill, (sport.width + gap, 0), pill)
        return im
    raise KeyError(name)


def ride_chip(h: int) -> Image.Image:
    """Dark capsule: bike glyph + "Ride", the sport chosen before Start."""
    f = font(int(h * 0.40))
    g = bike_glyph(int(h * 0.92), WHITE)
    tw = int(ImageDraw.Draw(Image.new("RGB", (1, 1))).textlength("Ride", font=f))
    w = int(h * 0.36) + g.width + int(h * 0.16) + tw + int(h * 0.42)
    im, d = rounded((w, h), h // 2, CARD)
    im.paste(g, (int(h * 0.36), (h - g.height) // 2), g)
    d.text((int(h * 0.36) + g.width + int(h * 0.16), int(h * 0.24)), "Ride", fill=WHITE, font=f)
    return im


# Centre of each slot as a fraction of the canvas, per canvas shape. Slots
# outside the centre safe area are decoration and allowed to be cropped.
SLOTS = {
    #           top-left       top-right      left           right          bottom
    "header":    [(0.215, 0.22), (0.785, 0.20), (0.105, 0.66), (0.885, 0.62), (0.50, 0.77)],
    "search":    [(0.20, 0.21), (0.80, 0.20), (0.12, 0.73), (0.88, 0.70), (0.50, 0.76)],
    "universal": [(0.205, 0.19), (0.795, 0.18), (0.11, 0.68), (0.89, 0.65), (0.50, 0.75)],
}


def render(w: int, h: int, kind: str, page: dict) -> Image.Image:
    s = min(w / 3840, h / 1646)
    canvas = gradient(w, h).convert("RGBA")
    hero = page.get("hero")
    # With a hero object the text block moves left of centre and the hero
    # takes the right of the safe area; both stay inside it.
    cx = 0.40 if hero else 0.50

    # Wordmark + tagline, the only things that must be read. Both sit inside
    # the centre 60% x 70% of every canvas.
    # The taller canvases get a bigger wordmark and bigger pieces, or the
    # header's layout floats in the middle of them with an empty bottom.
    wm_frac = {"header": 0.40, "search": 0.46, "universal": 0.44}[kind]
    ps = s * {"header": 1.0, "search": 1.22, "universal": 1.12}[kind]
    if hero:
        wm_frac = 0.34
    wm = wordmark(int(w * wm_frac))
    tag = page["tagline"]
    size = int(104 * ps)
    tf = font(size, bold=False)
    probe = ImageDraw.Draw(canvas)
    while probe.textlength(tag, font=tf) > w * (0.40 if hero else 0.56):
        size -= 2
        tf = font(size, bold=False)
    gap = int(56 * ps)
    block_h = wm.height + gap + size
    top = int(h * (0.48 if kind == "search" else 0.45) - block_h / 2)
    shadow(canvas, wm, (int(cx * w - wm.width / 2), top), blur=int(50 * s))
    d = ImageDraw.Draw(canvas)
    tw = d.textlength(tag, font=tf)
    d.text((cx * w - tw / 2, top + wm.height + gap), tag, fill=TAG_INK, font=tf)

    if hero == "watch":
        im = piece("watch", s * (1.15 if kind == "header" else 1.4))
        shadow(canvas, im, (int(0.70 * w - im.width / 2), int(0.50 * h - im.height / 2)),
               blur=int(36 * s))

    for name, (fx, fy) in zip(page["pieces"], SLOTS[kind]):
        if name is None:
            continue
        im = piece(name, ps)
        if name in ("start", "ride-start"):
            fx = cx
        if hero and name == "pace":
            fx -= 0.04
        if hero and name == "heart":
            fx, fy = 0.90, fy + 0.02
        x = int(fx * w - im.width / 2)
        y = int(fy * h - im.height / 2)
        # Keep every piece clear of the canvas edge by at least 3%.
        x = max(int(w * 0.03), min(x, w - im.width - int(w * 0.03)))
        y = max(int(h * 0.04), min(y, h - im.height - int(h * 0.04)))
        shadow(canvas, im, (x, y), blur=int(36 * s))
    return canvas.convert("RGB")


def main() -> int:
    out = pathlib.Path(sys.argv[1]).expanduser() if len(sys.argv) > 1 else ROOT / "marketing" / "asc-creative"
    for name, page in PAGES.items():
        kinds = CANVASES if name == "default" else {"header": CANVASES["header"]}
        for kind, (w, h) in kinds.items():
            img = render(w, h, kind, page)
            assert img.mode == "RGB" and img.size == (w, h)
            p = out / name / f"{kind}-{w}x{h}.png"
            p.parent.mkdir(parents=True, exist_ok=True)
            img.save(p, optimize=True)
            print("wrote", p)
            if kind == "header":
                lockup(img).save(p.parent / "preview-product-page.png", optimize=True)
    return 0


ICON = ROOT / "Milepost" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset" / "icon-1024.png"
NAME, SUBTITLE = "Milepost: Run, Walk & Ride", "GPS run, walk & ride tracker"   # asc_metadata.py


def lockup(header: Image.Image) -> Image.Image:
    """Not an upload: the header at phone width with the icon, name and
    subtitle the App Store draws under it, to judge the page as a whole."""
    W = 1290
    hh = int(header.height * W / header.width)
    out = Image.new("RGB", (W, hh + 520), (0, 0, 0))
    out.paste(header.resize((W, hh), Image.LANCZOS), (0, 0))
    icon = Image.open(ICON).convert("RGB").resize((260, 260), Image.LANCZOS)
    mask = Image.new("L", icon.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, 259, 259), radius=58, fill=255)
    out.paste(icon, (60, hh + 70), mask)
    d = ImageDraw.Draw(out)
    d.text((360, hh + 105), NAME, fill=WHITE, font=font(64))
    d.text((360, hh + 195), SUBTITLE, fill=(150, 150, 156), font=font(46, bold=False))
    return out


if __name__ == "__main__":
    sys.exit(main())
