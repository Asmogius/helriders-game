"""V6.3 interface icon set: 16x16 pixel glyphs on one atlas.
Writes art/ui/icons.png + art/ui/icons.json ({"regions": {id: [x, y, w, h]}}),
read by scripts/art_atlas.gd. White glyphs with a dark outline, so code tints
them (modulate) with stat, status, category or class colours.

    python3 tools/art/icons.py
"""
import json, os
from PIL import Image, ImageDraw

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "art", "ui")
S = 16
COLS = 8
W = (255, 255, 255, 255)


def g_hp(d):        # a cross (health)
    d.rectangle([6, 2, 9, 13], fill=W); d.rectangle([2, 6, 13, 9], fill=W)
def g_armor(d):     # a plate with bolts
    d.polygon([(2, 3), (13, 3), (13, 9), (8, 14), (2, 9)], fill=W)
def g_shield(d):    # a bubble arc
    d.arc([1, 1, 14, 14], 200, 340, fill=W, width=3); d.arc([1, 1, 14, 14], 20, 160, fill=W, width=2)
def g_speed(d):     # two chevrons
    for x in (2, 8):
        d.line([(x, 3), (x + 5, 8), (x, 13)], fill=W, width=2)
def g_accel(d):     # an up arrow
    d.polygon([(8, 1), (14, 8), (10, 8), (10, 14), (6, 14), (6, 8), (2, 8)], fill=W)
def g_power(d):     # a bolt
    d.polygon([(9, 1), (3, 9), (7, 9), (6, 15), (13, 6), (9, 6)], fill=W)
def g_weight(d):    # a kettlebell
    d.ellipse([3, 6, 12, 14], fill=W); d.arc([5, 1, 10, 8], 180, 360, fill=W, width=2)
def g_dps(d):       # crosshair
    d.ellipse([3, 3, 12, 12], outline=W, width=2); d.line([(8, 0), (8, 15)], fill=W); d.line([(0, 8), (15, 8)], fill=W)
def g_lock(d):      # brackets
    for (x, y, sx, sy) in [(2, 2, 1, 1), (13, 2, -1, 1), (2, 13, 1, -1), (13, 13, -1, -1)]:
        d.line([(x, y), (x + 4 * sx, y)], fill=W, width=2); d.line([(x, y), (x, y + 4 * sy)], fill=W, width=2)
# Statuses
def g_shock(d):
    d.line([(9, 1), (5, 8), (10, 8), (6, 15)], fill=W, width=2)
def g_fire(d):
    d.polygon([(8, 1), (13, 9), (11, 14), (5, 14), (3, 9), (6, 6), (7, 9)], fill=W)
def g_acid(d):
    d.polygon([(8, 2), (12, 9), (8, 14), (4, 9)], fill=W); d.point([(12, 3), (13, 4)], fill=W)
def g_toxic(d):
    d.ellipse([5, 2, 11, 8], fill=W); d.rectangle([6, 8, 10, 10], fill=W); d.line([(3, 12), (13, 15)], fill=W, width=2); d.line([(3, 15), (13, 12)], fill=W, width=2)
def g_slime(d):
    d.ellipse([2, 8, 14, 14], fill=W); d.ellipse([6, 3, 10, 9], fill=W)
def g_goop(d):
    d.ellipse([2, 4, 9, 11], fill=W); d.ellipse([7, 7, 14, 14], fill=W)
# Part categories
def g_chassis(d):
    d.rectangle([3, 2, 12, 13], outline=W, width=2); d.line([(3, 7), (12, 7)], fill=W)
def g_engine(d):
    d.rectangle([2, 5, 13, 12], fill=W); d.rectangle([5, 2, 10, 5], fill=W)
def g_drive(d):
    d.ellipse([2, 2, 13, 13], outline=W, width=3); d.ellipse([6, 6, 9, 9], fill=W)
def g_weapon(d):
    d.rectangle([2, 7, 14, 9], fill=W); d.rectangle([2, 5, 7, 12], fill=W)
def g_internal(d):
    d.rectangle([4, 4, 11, 11], fill=W)
    for i in (5, 8, 10):
        d.point([(i, 2), (i, 13), (2, i), (13, i)], fill=W)
def g_utility(d):
    d.line([(3, 13), (11, 5)], fill=W, width=3); d.ellipse([9, 1, 14, 6], outline=W, width=2)
# Crew classes
def g_driver(d):
    d.ellipse([2, 2, 13, 13], outline=W, width=2); d.line([(3, 8), (12, 8)], fill=W, width=2); d.line([(8, 8), (8, 13)], fill=W, width=2)
def g_gunner(d):
    g_dps(d)
def g_mechanic(d):
    d.line([(3, 13), (10, 6)], fill=W, width=3); d.arc([8, 1, 15, 8], 90, 360, fill=W, width=2)
def g_spotter(d):
    d.ellipse([1, 5, 15, 11], outline=W, width=2); d.ellipse([6, 6, 10, 10], fill=W)
def g_engineer(d):
    d.ellipse([3, 3, 12, 12], outline=W, width=3)
    for (x, y) in [(8, 1), (8, 14), (1, 8), (14, 8)]:
        d.rectangle([x - 1, y - 1, x + 1, y + 1], fill=W)
def g_medic(d):
    d.rectangle([2, 4, 13, 13], outline=W, width=2); d.rectangle([7, 6, 8, 11], fill=W); d.rectangle([5, 8, 10, 9], fill=W)
def g_scavenger(d):
    d.polygon([(2, 6), (14, 6), (12, 14), (4, 14)], fill=W); d.arc([5, 1, 11, 9], 180, 360, fill=W, width=2)
def g_bruiser(d):
    d.rectangle([3, 5, 12, 12], fill=W); d.rectangle([3, 3, 12, 5], fill=W)

ICONS = [
    ("hp", g_hp), ("armor", g_armor), ("shield", g_shield), ("speed", g_speed), ("accel", g_accel),
    ("power", g_power), ("weight", g_weight), ("dps", g_dps), ("lock", g_lock),
    ("shock", g_shock), ("fire", g_fire), ("acid", g_acid), ("toxic", g_toxic), ("slime", g_slime), ("goop", g_goop),
    ("chassis", g_chassis), ("engine", g_engine), ("drive", g_drive), ("cat_armor", g_armor), ("weapon", g_weapon),
    ("internal", g_internal), ("utility", g_utility),
    ("driver", g_driver), ("gunner", g_gunner), ("mechanic", g_mechanic), ("spotter", g_spotter),
    ("engineer", g_engineer), ("medic", g_medic), ("scavenger", g_scavenger), ("bruiser", g_bruiser),
]


def outline(im):
    """1 px dark outline round the white glyph, for contrast on any ground."""
    src = im.copy().load()
    px = im.load()
    for y in range(S):
        for x in range(S):
            if src[x, y][3] == 0 and any(0 <= x + dx < S and 0 <= y + dy < S and src[x + dx, y + dy][3] > 0
                                         for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                px[x, y] = (10, 10, 12, 200)
    return im


def main():
    os.makedirs(OUT, exist_ok=True)
    rows = (len(ICONS) + COLS - 1) // COLS
    atlas = Image.new("RGBA", (COLS * S, rows * S), (0, 0, 0, 0))
    regions = {}
    for i, (name, fn) in enumerate(ICONS):
        tile = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        fn(ImageDraw.Draw(tile))
        outline(tile)
        x, y = (i % COLS) * S, (i // COLS) * S
        atlas.paste(tile, (x, y))
        regions[name] = [x, y, S, S]
    atlas.save(os.path.join(OUT, "icons.png"))
    with open(os.path.join(OUT, "icons.json"), "w") as f:
        json.dump({"regions": regions}, f, indent=1, sort_keys=True)
    print("wrote art/ui/icons.png (%d icons)" % len(ICONS))


if __name__ == "__main__":
    main()
