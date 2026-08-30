#!/usr/bin/env python3
"""App Store screenshot compositor for On Cue 1.5 — direction D, "amber block".

A solid accent panel carrying black type, with the capture below it. Chosen
from five drafted directions; it is the one that stops a thumb in a search
result, which is the only job the first frame has.

Note the deliberate inversion: in the app, amber is a mark and never a field —
it means "this is the live thing". Here it is the field. That is a marketing
context, not a reading one, and the app's own amber marks still read against it
because they sit on black below the panel.
"""
from PIL import Image, ImageDraw, ImageFont

AMBER = (255, 184, 59)
GROUND = (7, 9, 12)
INK = (7, 9, 12)

CONDENSED = "/System/Library/Fonts/Supplemental/Arial Narrow Bold.ttf"
BODY = "/System/Library/Fonts/Helvetica.ttc"


def _tracked(draw, xy, text, font, fill, tracking):
    x, y = xy
    for ch in text:
        draw.text((x, y), ch, font=font, fill=fill)
        x += draw.textlength(ch, font=font) + tracking
    return x


def compose(shot, eyebrow, headline, subline, keep_fraction=0.085):
    """`headline` may contain newlines; each becomes its own line."""
    W, H = shot.size
    s = W / 1320
    m = int(78 * s)

    eye_f = ImageFont.truetype(CONDENSED, size=int(34 * s))
    head_f = ImageFont.truetype(CONDENSED, size=int(168 * s))
    sub_f = ImageFont.truetype(BODY, size=int(40 * s))

    lines = headline.split("\n")
    line_h = int(158 * s)
    # Fixed, not derived from this frame's line count. A panel that grows with
    # its headline makes a row of five look accidental; every frame gets the
    # same block and a two-line headline simply sits in more air.
    panel_h = int(96 * s) + int(70 * s) + line_h * 2 + int(150 * s)

    out = Image.new("RGB", (W, H), GROUND)
    d = ImageDraw.Draw(out)
    d.rectangle([0, 0, W, panel_h], fill=AMBER)

    y = int(96 * s)
    _tracked(d, (m, y), eyebrow.upper(), eye_f, (INK[0], INK[1], INK[2]), 34 * s * 0.13)

    y += int(70 * s)
    for ln in lines:
        _tracked(d, (m, y), ln.upper(), head_f, INK, 168 * s * 0.02)
        y += line_h

    # Sit the subline off the panel's bottom edge rather than letting it grow
    # down into it — it was touching the boundary at every length.
    y = panel_h - int(78 * s)
    d.text((m, y), subline, font=sub_f, fill=(64, 48, 12))

    # The capture starts above the reading line so the amber active word and
    # the line itself are in frame — a bottom slice would discard exactly the
    # evidence the caption is claiming.
    panel = shot.crop((0, int(H * keep_fraction), W, H))
    panel = panel.resize((W, H - panel_h), Image.LANCZOS)
    out.paste(panel, (0, panel_h))
    return out
