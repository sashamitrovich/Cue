#!/usr/bin/env python3
"""English-store language hero: the house amber band over a list of languages
set like the prompter itself — read lines grey, the live line amber on the
reading line, the rest white. Usage: marketing_hero_languages.py <out.png>"""
import os, subprocess, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from PIL import Image, ImageDraw, ImageFont
import marketing_compositor as mc

W, H = 1320, 2868
LANGS = [("🇬🇧", "English"), ("🇧🇷", "Português"), ("🇪🇸", "Español"), ("🇮🇹", "Italiano"),
         ("🇫🇷", "Français"), ("🇩🇪", "Deutsch"), ("🇳🇱", "Nederlands"), ("🇵🇱", "Polski"),
         ("🇨🇿", "Čeština"), ("🇭🇷", "Hrvatski"), ("🇺🇦", "Українська"), ("🇷🇺", "Русский")]
LIVE = 1                       # the line "being read"
READ, UNREAD = (128, 128, 128), (255, 255, 255)

def main(out):
    img = mc.compose(Image.new("RGB", (W, H), mc.GROUND), "On Cue · Languages",
                     "Speak your\nlanguage.",
                     "Detects your script's language and listens in it.")
    panel_h = 96 + 70 + 158 * 2 + 150
    d = ImageDraw.Draw(img)
    name_f = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", 92)
    name_f.set_variation_by_name("Bold")
    flag_dir = os.path.join(os.path.dirname(os.path.abspath(out)), "flags")
    subprocess.run(["swift", os.path.join(os.path.dirname(os.path.abspath(__file__)), "render_emoji.swift"),
                    flag_dir] + [f for f, _ in LANGS], check=True)
    foot_f = ImageFont.truetype(mc.BODY, 40)

    m, top, foot_h = 78, panel_h + 80, 230
    pitch = (H - top - foot_h) // len(LANGS)
    flag_h = 96
    for i, (flag, name) in enumerate(LANGS):
        y = top + i * pitch
        tile = Image.open(os.path.join(flag_dir, f"{i}.png")).convert("RGBA")
        tile = tile.crop(tile.getbbox())
        tile = tile.resize((int(tile.width * flag_h / tile.height), flag_h), Image.LANCZOS)
        if i < LIVE:            # already read: dimmed like spoken words
            tile.putalpha(tile.getchannel("A").point(lambda a: a * 45 // 100))
        img.paste(tile, (m, y + (pitch - flag_h) // 2), tile)
        colour = READ if i < LIVE else mc.AMBER if i == LIVE else UNREAD
        tx = m + tile.width + 44
        bb = d.textbbox((0, 0), name, font=name_f)
        d.text((tx, y + (pitch - (bb[3] - bb[1])) // 2 - bb[1]), name, font=name_f, fill=colour)
        if i == LIVE:           # the prompter's reading line
            ly = y + pitch // 2
            d.line([(tx + d.textlength(name, font=name_f) + 30, ly), (W - m, ly)],
                   fill=(70, 70, 70), width=3)
    d.text((m, H - foot_h + 70), "And every other language your iPhone can recognise.",
           font=foot_f, fill=(150, 150, 150))
    img.save(out)
    print(out, img.size)

if __name__ == "__main__":
    main(sys.argv[1])
