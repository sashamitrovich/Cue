#!/usr/bin/env python3
"""Localized App Store sets (pt-BR, it) for On Cue, using the repo's own
compositor so the amber band matches the English set exactly.
Usage: render_localized.py <captures-dir> <out-root>"""
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from PIL import Image, ImageDraw, ImageFont
import marketing_compositor as mc

SETS = {
    "pt-BR": [
        ("m-editor",    "01-idioma",  "On Cue · Idioma",   "Seu roteiro.\nSeu idioma.",
         "Detecta o idioma do roteiro e ouve nele.", 0.120),
        ("m-listening", "02-segue",   "On Cue · Escuta",   "Fale.\nEle segue.",
         "A fala no aparelho guarda seu lugar enquanto você lê.", 0.085),
        ("m-recording", "03-grava",   "On Cue · Gravação", "Leia. Grave.\nPronto.",
         "Câmera frontal e roteiro na mesma tela.", 0.085),
        ("m-leader",    "04-lente",   "On Cue · Contagem", "Olhe para\na lente.",
         "Uma contagem para se preparar, não só um número.", 0.085),
        ("m-mirroring", "05-vidro",   "On Cue · Espelho",  "Feito para\no vidro.",
         "Espelha o texto para o vidro. Os controles ficam no lugar.", 0.085),
    ],
    "it": [
        ("m-editor",    "01-lingua",  "On Cue · Lingua",   "Il tuo testo.\nLa tua lingua.",
         "Riconosce la lingua del copione e ascolta in quella.", 0.120),
        ("m-listening", "02-segue",   "On Cue · Ascolto",  "Parla.\nTi segue.",
         "Il riconoscimento sul dispositivo tiene il segno mentre leggi.", 0.085),
        ("m-recording", "03-registra", "On Cue · Registrazione", "Leggi. Gira.\nFatto.",
         "Fotocamera frontale e copione nella stessa schermata.", 0.085),
        ("m-leader",    "04-obiettivo", "On Cue · Conto alla rovescia", "Guarda\nl'obiettivo.",
         "Un conto alla rovescia per concentrarti, non solo un numero.", 0.085),
        ("m-mirroring", "05-vetro",   "On Cue · Specchio", "Fatto per\nil vetro.",
         "Rovescia il testo per il vetro. I comandi restano al loro posto.", 0.085),
    ],
}

def widths(head, sub, W=1320):
    s = W / 1320; avail = W - 2 * int(78 * s)
    d = ImageDraw.Draw(Image.new("RGB", (1, 1)))
    hf = ImageFont.truetype(mc.CONDENSED, int(168 * s)); sf = ImageFont.truetype(mc.BODY, int(40 * s))
    hw = max(sum(d.textlength(c, font=hf) + 168 * s * 0.02 for c in ln.upper()) for ln in head.split("\n"))
    return hw, d.textlength(sub, font=sf), avail

def main(src, out_root):
    bad = []
    for loc, frames in SETS.items():
        man = json.load(open(os.path.join(src, f"{loc}-raw", "manifest.json")))
        by = {a["suggestedHumanReadableName"].split("_")[0]: a["exportedFileName"]
              for e in man for a in e["attachments"]}
        dest = os.path.join(out_root, loc); os.makedirs(dest, exist_ok=True)
        for cap, name, eye, head, sub, keep in frames:
            hw, sw, avail = widths(head, sub)
            flag = "" if hw <= avail and sw <= avail else "  <-- OVERFLOW"
            if flag: bad.append(f"{loc}/{name}")
            shot = Image.open(os.path.join(src, f"{loc}-raw", by[cap])).convert("RGB")
            img = mc.compose(shot, eye, head, sub, keep_fraction=keep)
            p = os.path.join(dest, name + ".png"); img.save(p)
            print(f"{loc}/{name}  {img.size[0]}x{img.size[1]}  head {hw:.0f} sub {sw:.0f} / {avail}{flag}")
    if bad: sys.exit("overflow: " + ", ".join(bad))

if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
