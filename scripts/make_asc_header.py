#!/usr/bin/env python3
"""App Store "Header and Search Results" creative assets → marketing/asc-header/.

Produces the large 5244x2950 banner (Apple's big size; downscales cleanly to
1280x720) plus a 1280x720 copy. Dark field, the runner wordmark, a one-line
promise, and the live recorder inside a device frame on the right. Uploading
is browser-only (Distribution → Product Page Information → Header and Search
Results); these files are for that.

    ~/.venvs/spendcap/bin/python scripts/make_asc_header.py
"""
from __future__ import annotations

import pathlib
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from asc_make_screenshots import INK, ORANGE, RAW_DIR, WHITE, WORDMARK, font  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "marketing" / "asc-header"
SIZE = (5244, 2950)


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    canvas = Image.new("RGB", SIZE, INK)
    draw = ImageDraw.Draw(canvas)
    # Orange band up the right edge behind the phone.
    draw.rectangle((SIZE[0] - 1900, 0, SIZE[0], SIZE[1]), fill=ORANGE)

    wm = Image.open(WORDMARK).convert("RGBA")
    wm_w = 1500
    wm = wm.resize((wm_w, int(wm.height * wm_w / wm.width)), Image.LANCZOS)
    canvas.paste(wm, (300, 420), wm)

    y = 420 + wm.height + 160
    for line in ("press start.", "that's it."):
        draw.text((300, y), line, fill=WHITE, font=font(360))
        y = draw.textbbox((300, y), line, font=font(360))[3] + 20
    y += 90
    draw.text((300, y), "GPS runs and walks. Time, pace, splits, route.", fill=(200, 200, 200), font=font(110, bold=False))
    y += 150
    draw.text((300, y), "Nothing leaves your phone.", fill=ORANGE, font=font(110, bold=False))

    # Phone on the right, running off the bottom.
    raw_path = RAW_DIR / "route-recording.png"
    if raw_path.exists():
        raw = Image.open(raw_path).convert("RGBA")
        screen_w = 1300
        screen_h = int(raw.height * screen_w / raw.width)
        bezel = 34
        frame = Image.new("RGBA", (screen_w + 2 * bezel, screen_h + 2 * bezel), (0, 0, 0, 0))
        ImageDraw.Draw(frame).rounded_rectangle((0, 0, frame.width, frame.height), radius=230, fill=(30, 30, 30))
        screen = raw.resize((screen_w, screen_h), Image.LANCZOS)
        mask = Image.new("L", screen.size, 0)
        ImageDraw.Draw(mask).rounded_rectangle((0, 0, screen_w, screen_h), radius=200, fill=255)
        screen.putalpha(mask)
        frame.paste(screen, (bezel, bezel), screen)
        canvas.paste(frame, (SIZE[0] - 1900 + (1900 - frame.width) // 2, 330), frame)
    else:
        print("  ! no route-recording capture; banner has no phone")

    canvas.save(OUT / "header-5244x2950.png", optimize=True)
    canvas.resize((1280, 720), Image.LANCZOS).save(OUT / "header-1280x720.png", optimize=True)
    print(f"wrote {OUT}/header-5244x2950.png and header-1280x720.png")
    return 0


if __name__ == "__main__":
    sys.exit(main())
