#!/usr/bin/env python3
"""Renders the Cue app icon.

The mark is the app itself in miniature: lines of script with one amber
reading line across the middle. Lines above it are dimmed like spoken text,
lines below sit brighter like text still to read.

    python3 Tools/make_icon.py

Writes Cue/Assets.xcassets/AppIcon.appiconset/icon-1024.png.
"""

from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
AMBER = (255, 176, 58)
OUT = Path(__file__).resolve().parent.parent / "Cue/Assets.xcassets/AppIcon.appiconset/icon-1024.png"

# (y centre, width, colour, alpha) — the amber row is the reading line.
ROWS = [
    (250, 560, (150, 165, 185), 60),
    (372, 690, (150, 165, 185), 90),
    (494, 744, AMBER, 255),
    (616, 700, (226, 234, 245), 170),
    (738, 520, (226, 234, 245), 120),
]
BAR_H = 54
MARGIN = 140


def background() -> Image.Image:
    """Dark tile with a faint warm lift behind the reading line."""
    img = Image.new("RGB", (SIZE, SIZE), (10, 14, 20))
    top, bottom = (22, 29, 40), (7, 10, 15)
    draw = ImageDraw.Draw(img)
    for y in range(SIZE):
        t = y / SIZE
        draw.line(
            [(0, y), (SIZE, y)],
            fill=tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(3)),
        )

    glow = Image.new("RGB", (SIZE, SIZE), (0, 0, 0))
    ImageDraw.Draw(glow).ellipse([-140, 300, SIZE + 140, 690], fill=(70, 44, 12))
    glow = glow.filter(ImageFilter.GaussianBlur(110))
    return Image.blend(img, Image.blend(img, glow, 0.55), 0.85)


def main() -> None:
    img = background().convert("RGBA")

    # Amber halo under the reading line, so it reads as lit rather than painted.
    halo = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    ImageDraw.Draw(halo).rounded_rectangle(
        [MARGIN - 30, 494 - 46, SIZE - MARGIN + 30, 494 + 46],
        radius=46,
        fill=AMBER + (130,),
    )
    img.alpha_composite(halo.filter(ImageFilter.GaussianBlur(38)))

    layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    for y, width, colour, alpha in ROWS:
        x0 = (SIZE - width) / 2 if colour == AMBER else MARGIN
        draw.rounded_rectangle(
            [x0, y - BAR_H / 2, x0 + width, y + BAR_H / 2],
            radius=BAR_H / 2,
            fill=colour + (alpha,),
        )

    # Cue ticks at both edges, mirroring the marker in the prompter.
    for x0, x1 in [(52, 116), (SIZE - 116, SIZE - 52)]:
        draw.rounded_rectangle([x0, 494 - 9, x1, 494 + 9], radius=9, fill=AMBER + (255,))

    img.alpha_composite(layer)

    OUT.parent.mkdir(parents=True, exist_ok=True)
    img.convert("RGB").save(OUT)
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
