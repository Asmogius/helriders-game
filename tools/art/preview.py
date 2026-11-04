"""Preview: each sheet upscaled 4x (nearest) on road-grey, plus a 1x in-game-scale strip."""
import os, sys
from PIL import Image
HERE = os.path.dirname(os.path.abspath(__file__))
SPR = os.path.join(HERE, "..", "..", "art", "sprites")
OUT = os.path.join(HERE, "..", "..", "art", "previews")
os.makedirs(OUT, exist_ok=True)
BG = (27, 27, 29, 255)  # COL_ROAD
for f in sorted(os.listdir(SPR)):
    if not f.endswith(".png"):
        continue
    im = Image.open(os.path.join(SPR, f))
    bg = Image.new("RGBA", im.size, BG); bg.alpha_composite(im)
    bg.resize((im.width * 4, im.height * 4), Image.NEAREST).save(os.path.join(OUT, f.replace(".png", "_x4.png")))
    print(f)
