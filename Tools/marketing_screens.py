#!/usr/bin/env python3
"""Composite App Store screenshots: a headline band over a real screen capture.

Captures come from the `CueUITests/MarketingCaptures` harness, which shoots the
actual app rather than a mockup. This adds the marketing band on top and writes
the result at exactly the dimensions App Store Connect expects for that device
class, which is whatever the simulator already produced.

    xcodebuild test -project Cue.xcodeproj -scheme Cue \
      -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
      -only-testing:CueUITests/MarketingCaptures -resultBundlePath /tmp/mkt
    xcrun xcresulttool export attachments --path /tmp/mkt --output-path /tmp/shots
    Tools/marketing_screens.py /tmp/shots Marketing/AppStoreScreenshots

The band is designed at 1320pt wide (iPhone 17 Pro Max) and scaled by width for
everything else, which is how the iPad set was built and why the two look like
one family. Lives here rather than in a scratch directory because it was written
from scratch twice: the copy below IS the marketing copy, and recovering it
meant reading pixels back out of the previous PNGs.
"""
import json
import os
import sys
from PIL import Image, ImageDraw, ImageFont

BAND_TOP = (29, 19, 36)
BAND_BOTTOM = (18, 12, 24)
ACCENT = (253, 176, 36)
WHITE = (245, 243, 247)
GREY = (168, 162, 176)

BOLD = "/System/Library/Fonts/HelveticaNeue.ttc"
BOLD_INDEX = 1          # Helvetica Neue Bold
REGULAR_INDEX = 0       # Helvetica Neue

# (capture name, output name, headline runs, subline). A run is (text, accent?)
SCREENS = [
    ("m-listening", "01-listens",
     [("It", True), (" listens.", False)],
     "Speak at your pace. Pause, skip a line, paraphrase — it stays with you."),
    ("m-recording", "02-records",
     [("Prop up your phone ", False), ("and hit record.", True)],
     "Front camera and script on one screen — no extra gear, no separate operator."),
    ("m-mirroring", "03-mirrors",
     [("Built for ", False), ("teleprompter", True), (" rigs.", False)],
     "Flips the script so it reads correctly through the glass — confirmed on a real rig."),
    ("m-editor", "04-editor",
     [("Write", True), (" it. Or open any script.", False)],
     "Import from Files or iCloud Drive — edits save back automatically."),
]


def font(index, size):
    return ImageFont.truetype(BOLD, size=size, index=index)


def wrap(runs, draw, f, max_width):
    """Greedy-wrap accent-tagged runs into lines of (text, accent) pieces."""
    words = [(w, accent) for text, accent in runs for w in text.split(" ") if w != ""]
    lines, line, width = [], [], 0
    for word, accent in words:
        piece = word + " "
        w = draw.textlength(piece, font=f)
        if line and width + w > max_width:
            lines.append(line)
            line, width = [], 0
        line.append((piece, accent))
        width += w
    if line:
        lines.append(line)
    return lines


def compose(shot, runs, subline):
    W, H = shot.size
    s = W / 1320
    margin = int(64 * s)
    head_f = font(BOLD_INDEX, int(66 * s))
    logo_f = font(BOLD_INDEX, int(26 * s))
    sub_f = font(REGULAR_INDEX, int(28 * s))
    line_h = int(76 * s)

    out = Image.new("RGB", (W, H), BAND_BOTTOM)
    draw = ImageDraw.Draw(out)

    lines = wrap(runs, draw, head_f, W - margin * 2)
    head_top = int(150 * s)
    sub_top = head_top + line_h * (len(lines) - 1) + int(100 * s)
    band_h = sub_top + int(28 * s) + int(48 * s)
    rule = max(2, int(4 * s))

    for y in range(band_h):
        t = y / max(1, band_h - 1)
        draw.line(
            [(0, y), (W, y)],
            fill=tuple(int(a + (b - a) * t) for a, b in zip(BAND_TOP, BAND_BOTTOM)),
        )

    sq = int(20 * s)
    sq_y = int(68 * s)
    draw.rectangle([margin, sq_y, margin + sq, sq_y + sq], fill=ACCENT)
    draw.text((margin + sq + int(16 * s), sq_y - int(4 * s)), "ON CUE", font=logo_f, fill=WHITE)

    y = head_top
    for line in lines:
        x = margin
        for piece, accent in line:
            draw.text((x, y), piece, font=head_f, fill=ACCENT if accent else WHITE)
            x += draw.textlength(piece, font=head_f)
        y += line_h

    draw.text((margin, sub_top), subline, font=sub_f, fill=GREY)
    draw.rectangle([0, band_h, W, band_h + rule], fill=ACCENT)

    # Bottom-aligned: the chrome at the foot of the screen is the point of the
    # shot, so the band eats into the top of the capture rather than squashing it.
    top = band_h + rule
    out.paste(shot.crop((0, H - (H - top), W, H)), (0, top))
    return out


def main(shots_dir, out_dir):
    manifest = json.load(open(os.path.join(shots_dir, "manifest.json")))
    by_name = {
        a["suggestedHumanReadableName"].split("_")[0]: a["exportedFileName"]
        for e in manifest for a in e.get("attachments", [])
    }
    os.makedirs(out_dir, exist_ok=True)
    for capture, out_name, runs, subline in SCREENS:
        src = by_name.get(capture)
        if src is None:
            raise SystemExit(f"missing capture {capture} in {shots_dir}")
        shot = Image.open(os.path.join(shots_dir, src)).convert("RGB")
        dest = os.path.join(out_dir, out_name + ".png")
        compose(shot, runs, subline).save(dest)
        print(f"{dest}  {shot.size[0]}x{shot.size[1]}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    main(sys.argv[1], sys.argv[2])
