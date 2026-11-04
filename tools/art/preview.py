"""Previews in art/previews/:
  <model>_x3.png        every heading of the composite (core + stock parts), 3x
  <model>_chunks_x4.png wreck pieces pulled apart (core chunks + stock part pieces)
  <model>_parts_x3.png  every part layer on the core at one heading (chassis models)"""
import json, os
from PIL import Image
HERE = os.path.dirname(os.path.abspath(__file__))
SPR = os.path.join(HERE, "..", "..", "art", "sprites")
OUT = os.path.join(HERE, "..", "..", "art", "previews")
os.makedirs(OUT, exist_ok=True)
for f in os.listdir(OUT):
    if f.endswith(".png") and not f.endswith("_capture.png"):
        os.remove(os.path.join(OUT, f))
BG = (27, 27, 29, 255)  # COL_ROAD


def frame(path, meta, i):
    sheet = Image.open(os.path.join(SPR, path))
    fw, c = meta["frame_w"], meta["columns"]
    return sheet.crop(((i % c) * fw, (i // c) * fw, (i % c + 1) * fw, (i // c + 1) * fw))


for f in sorted(os.listdir(SPR)):
    if not f.endswith(".json"):
        continue
    name = f[:-5]
    meta = json.load(open(os.path.join(SPR, f)))
    sheet = Image.open(os.path.join(SPR, meta["composite"]))
    bg = Image.new("RGBA", sheet.size, BG); bg.alpha_composite(sheet)
    bg.resize((sheet.width * 3, sheet.height * 3), Image.NEAREST).save(os.path.join(OUT, f"{name}_x3.png"))
    i, fw = meta["directions"] // 8 * 7, meta["frame_w"]
    pieces = [(c["sheet"], c["offsets"]) for c in meta["chunks"].values()]
    for d in meta.get("defaults", []):
        pieces += [(p["sheet"], p["offsets"]) for p in meta["layers"][d]["pieces"].values()]
    canvas = Image.new("RGBA", (fw * 2, fw * 2), BG)
    for sh, offs in pieces:
        ox, oy = offs[i]
        d = max(1.0, (ox * ox + oy * oy) ** 0.5)
        push = 10.0 / d + 0.5
        canvas.alpha_composite(frame(sh, meta, i), (int(fw / 2 + ox * push), int(fw / 2 + oy * push)))
    canvas.resize((fw * 8, fw * 8), Image.NEAREST).save(os.path.join(OUT, f"{name}_chunks_x4.png"))
    if meta.get("layers"):
        ids = [l for l in meta["layers"] if l not in meta["defaults"]]
        cols = 5
        rows = (len(ids) + cols - 1) // cols
        grid = Image.new("RGBA", (fw * cols, fw * rows), BG)
        h = meta["directions"] // 8 * 7
        for k, lid in enumerate(ids):
            cell = frame(meta["sheet"], meta, h)
            slot = meta["layers"][lid]["slot"]
            for d in meta["defaults"]:
                if meta["layers"][d]["slot"] != slot:
                    cell.alpha_composite(frame(meta["layers"][d]["sheet"], meta, h))
            cell.alpha_composite(frame(meta["layers"][lid]["sheet"], meta, h))
            grid.alpha_composite(cell, ((k % cols) * fw, (k // cols) * fw))
        grid.resize((grid.width * 3, grid.height * 3), Image.NEAREST).save(os.path.join(OUT, f"{name}_parts_x3.png"))
    print(name)
