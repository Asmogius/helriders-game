"""Previews in art/previews/:
  <model>_x3.png        every heading, 3x nearest, on road grey
  <model>_chunks_x4.png chunks pulled apart along their offsets (wreck check), heading 1/8 turn
  ingame_x2.png         both rigs at true in-game size (zoom 1.3 ~ x1) beside each other, 2x"""
import json, os
from PIL import Image
HERE = os.path.dirname(os.path.abspath(__file__))
SPR = os.path.join(HERE, "..", "..", "art", "sprites")
OUT = os.path.join(HERE, "..", "..", "art", "previews")
os.makedirs(OUT, exist_ok=True)
BG = (27, 27, 29, 255)  # COL_ROAD


def on_bg(im):
    bg = Image.new("RGBA", im.size, BG); bg.alpha_composite(im); return bg


def frame(sheet, meta, i):
    fw, fh, c = meta["frame_w"], meta["frame_h"], meta["columns"]
    return sheet.crop(((i % c) * fw, (i // c) * fh, (i % c + 1) * fw, (i // c + 1) * fh))


for f in sorted(os.listdir(SPR)):
    if not f.endswith(".json"):
        continue
    name = f[:-5]
    meta = json.load(open(os.path.join(SPR, f)))
    sheet = Image.open(os.path.join(SPR, meta["sheet"]))
    on_bg(sheet).resize((sheet.width * 3, sheet.height * 3), Image.NEAREST).save(os.path.join(OUT, f"{name}_x3.png"))
    i = meta["directions"] // 8 * 7          # nose up-right
    fw = meta["frame_w"]
    canvas = Image.new("RGBA", (fw * 2, fw * 2), BG)
    for cn, cd in meta["chunks"].items():
        ch = frame(Image.open(os.path.join(SPR, cd["sheet"])), meta, i)
        ox, oy = cd["offsets"][i]
        d = max(1.0, (ox * ox + oy * oy) ** 0.5)
        push = 10.0 / d + 0.5   # every piece moves out ~10 px plus half its offset
        canvas.alpha_composite(ch, (int(fw / 2 + ox * push), int(fw / 2 + oy * push)))
    canvas.resize((fw * 8, fw * 8), Image.NEAREST).save(os.path.join(OUT, f"{name}_chunks_x4.png"))
    print(name)
