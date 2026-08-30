#!/usr/bin/env python3
"""Render the App Store set. Usage: render_set.py <exports-dir> <out-dir>"""
import json, os, sys
from PIL import Image
from compositor import compose

FRAMES = [
    ("m-listening", "01-follows", "On Cue · Listening", "Talk.\nIt follows.",
     "On-device speech keeps your place while you read.", 0.085),
    ("m-recording", "02-record",  "On Cue · Recording", "Read. Record.\nDone.",
     "Front camera and script on one screen.", 0.085),
    ("m-leader",    "03-lens",    "On Cue · Pre-roll",  "Find\nthe lens.",
     "A countdown to settle into, not just a number.", 0.085),
    ("m-mirroring", "04-rigs",    "On Cue · Mirror",    "Built\nfor rigs.",
     "Flips for teleprompter glass. Controls stay put.", 0.085),
    ("m-editor",    "05-write",   "On Cue · Your script", "Write it.\nOr open it.",
     "Type a script, or open one from Files or iCloud.", 0.20),
]

def main(src, dest):
    man = json.load(open(os.path.join(src, "manifest.json")))
    by = {a["suggestedHumanReadableName"].split("_")[0]: a["exportedFileName"]
          for e in man for a in e.get("attachments", [])}
    os.makedirs(dest, exist_ok=True)
    for cap, name, eyebrow, head, sub, keep in FRAMES:
        if cap not in by:
            raise SystemExit(f"missing capture {cap}")
        shot = Image.open(os.path.join(src, by[cap])).convert("RGB")
        img = compose(shot, eyebrow, head, sub, keep_fraction=keep)
        p = os.path.join(dest, name + ".png")
        img.save(p)
        print(f"{p}  {img.size[0]}x{img.size[1]}")

if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
