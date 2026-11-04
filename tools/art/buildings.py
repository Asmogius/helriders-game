"""Outer Blocks low houses (VISUAL_PLAN V5.2/V5.5, P4 style sample).
Modular pieces so any building rect from layouts.gd can be assembled by
scripts/map_art.gd: shingle roof tiles (north slope lit, south slope dark),
a south wall strip (siding, windows, a door, a few lit windows) seen at the
30 degree tilt, and a chimney. Writes art/map/outer_house.png + .json.

  python3 tools/art/buildings.py
"""
import json, os, random
import numpy as np
from PIL import Image
from palette import tuning_color, PALETTE, OUTLINE

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "art", "map")
ROOF = np.array(tuning_color("COL_OB_ROOF"), float)
SIDING = np.array(tuning_color("COL_OB_SIDING"), float)
ORANGE = np.array(PALETTE["orange"], float)
GLASS = np.array(PALETTE["glass"], float)
RT, WH, WW = 32, 30, 32   # roof tile, wall height, wall piece width

ROOFS = [ROOF, ROOF * np.array([0.8, 0.9, 1.05]), ROOF * np.array([0.85, 1.05, 0.85])]  # brown, slate, moss
SIDINGS = [SIDING, SIDING * np.array([0.85, 0.95, 1.08]), SIDING * np.array([0.95, 1.02, 0.85])]


def clamp(a):
    return np.clip(a, 0, 255).astype(np.uint8)


def rgba(rgb):
    return np.concatenate([clamp(rgb), np.full(rgb.shape[:2] + (1,), 255, np.uint8)], axis=2)


def shingles(rng, col, lit):
    t = np.tile(col * (1.12 if lit else 0.7), (RT, RT, 1))
    for row in range(0, RT, 6):  # courses with staggered tabs
        t[row, :] *= 0.62
        off = 0 if (row // 6) % 2 == 0 else 5
        for x in range(off, RT, 10):
            t[row:row + 6, x] *= 0.75
    for _ in range(26):
        x, y = rng.randrange(RT), rng.randrange(RT)
        t[y, x] *= rng.uniform(0.8, 1.2)
    if rng.random() < 0.4:  # moss / missing shingle
        x, y = rng.randrange(RT - 6), rng.randrange(RT - 4)
        t[y:y + 4, x:x + 6] = t[y:y + 4, x:x + 6] * 0.5 + np.array(tuning_color("COL_OB_GRASS")) * 0.4
    return rgba(t)


def wall(rng, col, kind):
    t = np.tile(col * 0.78, (WH, WW, 1))
    t[::3, :] *= 0.88               # horizontal siding boards
    t[:3, :] = col * 0.45            # eave shadow
    t[-3:, :] = col * 0.4            # foundation
    if kind in ("window", "lit"):
        g = ORANGE * 0.85 if kind == "lit" else GLASS
        t[9:21, 9:23] = np.array(OUTLINE[:3])
        t[10:20, 10:22] = g
        t[10:20, 15:16] = col * 0.5  # mullion
        t[14:15, 10:22] = col * 0.5
        if kind != "lit":
            t[10:13, 10:14] += 25        # glint
    elif kind == "door":
        t[8:27, 11:21] = np.array(OUTLINE[:3])
        t[9:27, 12:20] = np.array(PALETTE["rust"]) * 0.8
        t[17, 18] = (200, 190, 150)
    return rgba(t)


def chimney(rng):
    t = np.tile(np.array(PALETTE["rust"]) * 0.75, (18, 14, 1))
    t[::4, :] *= 0.8
    t[:3, :] = np.array(OUTLINE[:3]) + 20
    t[:, -4:] *= 0.65
    return rgba(t)


def main():
    rng = random.Random(9172)
    pieces = {}
    for i, c in enumerate(ROOFS):
        for v in range(2):
            pieces["roof%d_lit_%d" % (i, v)] = shingles(rng, c, True)
            pieces["roof%d_dark_%d" % (i, v)] = shingles(rng, c, False)
    for i, c in enumerate(SIDINGS):
        for k in ("plain", "window", "lit", "door"):
            pieces["wall%d_%s" % (i, k)] = wall(rng, c, k)
    pieces["chimney"] = chimney(rng)
    W = 256
    x = y = row = 0
    regions = {}
    sheet = np.zeros((256, W, 4), np.uint8)
    for k, t in pieces.items():
        h, w = t.shape[:2]
        if x + w > W:
            x, y, row = 0, y + row + 1, 0
        sheet[y:y + h, x:x + w] = t
        regions[k] = [x, y, w, h]
        x += w + 1; row = max(row, h)
    sheet = sheet[:y + row + 1]
    os.makedirs(OUT, exist_ok=True)
    Image.fromarray(sheet, "RGBA").save(os.path.join(OUT, "outer_house.png"))
    json.dump({"regions": regions, "roofs": len(ROOFS), "sidings": len(SIDINGS), "wall_h": WH},
              open(os.path.join(OUT, "outer_house.json"), "w"), indent=1)
    print("outer_house:", sheet.shape, len(regions), "regions")


if __name__ == "__main__":
    main()
