"""Outer Blocks ground tiles (VISUAL_PLAN V5.1/V5.5, P4 style sample).
Writes art/map/outer_tiles.png + outer_tiles.json ({"regions": {id: [x,y,w,h]}})
for scripts/art_atlas.gd. 64 px tiles, 4 variants each, seeded (same output
every run). Colours come from tuning.gd via palette.tuning_color.

  python3 tools/art/tiles.py
"""
import json, os, random
import numpy as np
from PIL import Image
from palette import tuning_color, PALETTE

T = 64
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "art", "map")
# Lawn kept a step darker than COL_OB_GRASS so zombies (COL_ZOMBIE_DARK) stay readable on it.
GRASS = np.array(tuning_color("COL_OB_GRASS"), float) * 0.84
PAVE = np.array(tuning_color("COL_OB_PAVE"), float)
ROAD = np.array(tuning_color("COL_ROAD"), float)
LINE = np.array(tuning_color("COL_ROAD_LINE"), float)
DIRT = np.array((74, 62, 46), float) * 0 + np.array(PALETTE["rust"], float) * 0.55 + GRASS * 0.25


def clamp(a):
    return np.clip(a, 0, 255).astype(np.uint8)


def noise(rng, h, w, amp):
    return (np.array([[rng.random() for _ in range(w)] for _ in range(h)]) - 0.5) * 2 * amp


def blocky(rng, h, w, cell, amp):
    small = noise(rng, h // cell + 1, w // cell + 1, amp)
    return np.kron(small, np.ones((cell, cell)))[:h, :w]


def rgba(rgb, alpha=None):
    a = np.full(rgb.shape[:2] + (1,), 255, np.uint8) if alpha is None else alpha[..., None].astype(np.uint8)
    return np.concatenate([clamp(rgb), a], axis=2)


def grass(rng):
    base = np.tile(GRASS, (T, T, 1))
    base += (blocky(rng, T, T, 8, 10) + noise(rng, T, T, 6))[..., None]
    for _ in range(70):  # blade tufts: lighter and darker 1x2 px strokes
        x, y = rng.randrange(T), rng.randrange(T - 2)
        base[y:y + 2, x] += 22 if rng.random() < 0.5 else -24
    for _ in range(rng.randint(0, 3)):  # dry patch
        x, y, r = rng.randrange(T), rng.randrange(T), rng.randint(3, 7)
        yy, xx = np.ogrid[:T, :T]
        m = ((xx - x) % T - 0) ** 2 + ((yy - y) % T) ** 2 < r * r
        base[m] = base[m] * 0.6 + DIRT * 0.4
    return rgba(base)


def pavement(rng):
    base = np.tile(PAVE, (T, T, 1)) + noise(rng, T, T, 5)[..., None]
    base[::32, :] *= 0.62  # slab joints every 32 px
    base[:, ::32] *= 0.62
    for _ in range(rng.randint(1, 3)):  # crack with grass in it
        x, y = rng.randrange(4, T - 4), rng.randrange(4, T - 4)
        for _ in range(rng.randint(8, 18)):
            base[y, x] = base[y, x] * 0.45
            if rng.random() < 0.35:
                base[y, x] = GRASS * 1.1
            x = min(T - 1, max(0, x + rng.choice((-1, 0, 1))))
            y = min(T - 1, max(0, y + rng.choice((0, 1))))
    return rgba(base)


def asphalt(rng):
    base = np.tile(ROAD * 1.15, (T, T, 1)) + noise(rng, T, T, 7)[..., None]
    for _ in range(40):  # aggregate specks
        x, y = rng.randrange(T), rng.randrange(T)
        base[y, x] += 18
    if rng.random() < 0.2:  # pothole / patch
        x, y, r = rng.randrange(10, 54), rng.randrange(10, 54), rng.randint(4, 8)
        yy, xx = np.ogrid[:T, :T]
        base[(xx - x) ** 2 + (yy - y) ** 2 < r * r] *= 0.55
    return rgba(base)


def dirt(rng):
    base = np.tile(DIRT, (T, T, 1)) + (blocky(rng, T, T, 4, 9) + noise(rng, T, T, 6))[..., None]
    return rgba(base)


def blob(rng, size, colour, lobes, dark=0.55):
    """Top-down canopy: overlapping discs, lit from the upper left, 1 px outline."""
    img = np.zeros((size, size, 3)); a = np.zeros((size, size))
    yy, xx = np.ogrid[:size, :size]
    c = size / 2
    for _ in range(lobes):
        cx, cy = c + rng.uniform(-size * .18, size * .18), c + rng.uniform(-size * .18, size * .18)
        r = rng.uniform(size * .2, size * .3)
        m = (xx - cx) ** 2 + (yy - cy) ** 2 < r * r
        lit = 1.0 - ((xx - cx + r * .4) ** 2 + (yy - cy + r * .4) ** 2) ** .5 / (r * 2.2)
        shade = np.clip(lit, dark, 1.15)
        img[m] = (colour[None, :] * shade[..., None])[m] if np.ndim(shade) else colour * shade
        a[m] = 255
    img += noise(rng, size, size, 8)[..., None]
    # outline
    edge = (a > 0) & ~(np.roll(a, 1, 0) > 0) | (a > 0) & ~(np.roll(a, -1, 0) > 0) | (a > 0) & ~(np.roll(a, 1, 1) > 0) | (a > 0) & ~(np.roll(a, -1, 1) > 0)
    img[edge] = (12, 11, 13)
    return rgba(img, a)


def lane_dash():
    t = np.zeros((6, 46, 4), np.uint8); t[..., :3] = clamp(LINE); t[..., 3] = 170
    return t


def worn_bar(rng, h, w):
    """Crosswalk stripe / stop line: faded paint with worn-off patches."""
    t = np.zeros((h, w, 4), np.uint8)
    t[..., :3] = clamp(PAVE * 1.45)
    a = np.full((h, w), 150.0) + noise(rng, h, w, 25)
    for _ in range(w // 6):
        x, y = rng.randrange(w), rng.randrange(h)
        a[max(0, y - 1):y + 2, max(0, x - 2):x + 3] *= 0.35
    t[..., 3] = clamp(a)
    return t


def main():
    rng = random.Random(4207)
    tiles = {}
    for i in range(4):
        tiles["grass_%d" % i] = grass(rng)
        tiles["pave_%d" % i] = pavement(rng)
        tiles["asphalt_%d" % i] = asphalt(rng)
        tiles["dirt_%d" % i] = dirt(rng)
    for i in range(3):
        tiles["bush_%d" % i] = blob(rng, 40, GRASS * 0.8, 4)
    for i in range(2):
        tiles["tree_%d" % i] = blob(rng, 88, GRASS * np.array([0.85, 0.95, 0.8]), 7, 0.45)
    tiles["lane_dash"] = lane_dash()
    tiles["zebra"] = worn_bar(rng, 10, 44)
    tiles["stop_bar"] = worn_bar(rng, 8, 100)
    # Shelf-pack into one atlas, 1 px gutter.
    W = 512
    x = y = row = 0
    regions = {}
    sheet = np.zeros((512, W, 4), np.uint8)
    for k, t in tiles.items():
        h, w = t.shape[:2]
        if x + w > W:
            x, y, row = 0, y + row + 1, 0
        sheet[y:y + h, x:x + w] = t
        regions[k] = [x, y, w, h]
        x += w + 1; row = max(row, h)
    sheet = sheet[:y + row + 1]
    os.makedirs(OUT, exist_ok=True)
    Image.fromarray(sheet, "RGBA").save(os.path.join(OUT, "outer_tiles.png"))
    json.dump({"regions": regions, "tile": T}, open(os.path.join(OUT, "outer_tiles.json"), "w"), indent=1)
    print("outer_tiles:", sheet.shape, len(regions), "regions")


if __name__ == "__main__":
    main()
