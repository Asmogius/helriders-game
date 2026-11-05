"""Outer Blocks street decor (VISUAL_PLAN V5.3/V5.5, P4 style sample).
Voxel props rendered with voxel_render.render_frame at the same 45 degree tilt
as the rigs (top plus the visible south face), plus a cast shadow from
render_shadow (team sun, opaque SHADOW_RGB, alpha 0.5) aligned to the sprite's
ground centre. Flat decals (cracks, potholes, puddles, oil, blood, trash,
weeds, graffiti, scorch) have no shadow. Everything is baked by
scripts/map_art.gd into the map chunks: decor only, never collision. Colours
derive from tuning.gd COL_* / palette.PALETTE and are kept muted and away from
the zombie greens (see check_readability()).
Writes art/map/outer_props.png + .json.

  python3 tools/art/props.py
"""
import json, os, random
import numpy as np
from PIL import Image
from palette import tuning_color, PALETTE, OUTLINE
from voxel_render import render_frame, render_shadow, canvas_for, shadow_canvas, SHADOW_ALPHA

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "art", "map")
f = lambda c, m=1.0: tuple(int(min(255, v * m)) for v in c[:3])
PAVE, SIDING, ROOF = tuning_color("COL_OB_PAVE"), tuning_color("COL_OB_SIDING"), tuning_color("COL_OB_ROOF")
ROAD, GRASS = tuning_color("COL_ROAD"), tuning_color("COL_OB_GRASS")
ZOMBIE, ZOMBIE_DARK = tuning_color("COL_ZOMBIE"), tuning_color("COL_ZOMBIE_DARK")
STEEL, STEEL_D, RUST, TYRE, GLASS = (PALETTE[k] for k in ("steel", "steel_dark", "rust", "tyre", "glass"))

# Prop palette (index 0 empty). Muted: nothing as bright as a rig light.
COLS = {
    "steel": f(STEEL, 1.25), "steel_d": f(STEEL_D, 0.85), "rust": f(RUST, 0.85), "tyre": TYRE, "glass": f(GLASS, 0.9),
    "paint0": f(PALETTE["bone"], 0.55), "paint1": f(RUST, 0.7), "paint2": f(GLASS, 1.2),
    "concrete": f(PAVE, 1.18), "sand": f(PALETTE["goop"], 0.52), "wood": f(RUST, 0.62),
    "sign": f(PALETTE["enemy_red"], 0.42), "signw": f(PAVE, 1.45), "lamp": f(PALETTE["white_hot"], 0.72),
    "stripe": f(PALETTE["orange"], 0.5), "tank": f(STEEL, 1.15), "roofgrey": f(ROOF, 0.8),
}
NAMES = ["_"] + list(COLS)
I = {n: i for i, n in enumerate(NAMES)}
COLORS = [(0, 0, 0, 0)] + [COLS[n] + (255,) for n in NAMES[1:]]
BURNT = [(0, 0, 0, 0)] + [f(COLS[n], 0.33 if n not in ("lamp",) else 0.12) + (255,) for n in NAMES[1:]]


def grid(x, y, z):
    return np.zeros((x, y, z), np.int16)


def box(g, x0, x1, y0, y1, z0, z1, c):
    g[max(0, x0):x1, max(0, y0):y1, max(0, z0):z1] = I[c]


def car(paint, rng, dent=True):
    g = grid(40, 20, 13)
    for wx in (6, 29):  # wheels
        box(g, wx, wx + 6, 0, 3, 0, 6, "tyre"); box(g, wx, wx + 6, 17, 20, 0, 6, "tyre")
    box(g, 1, 39, 1, 19, 3, 8, paint)                 # body
    box(g, 0, 2, 2, 18, 3, 6, "steel_d"); box(g, 38, 40, 2, 18, 3, 6, "steel_d")  # bumpers
    box(g, 11, 30, 2, 18, 8, 12, "glass")             # cabin
    box(g, 13, 28, 3, 17, 12, 13, paint)              # roof
    if dent:
        for _ in range(14):
            x, y = rng.randrange(1, 39), rng.randrange(1, 19)
            g[x, y, 7] = I["rust"]
        g[33:39, 1:19, 7] = 0                          # crumpled hood
        g[34:38, 3:17, 6] = I["rust"]
    return g


def jersey():
    g = grid(30, 6, 7)
    box(g, 0, 30, 0, 6, 0, 3, "concrete"); box(g, 0, 30, 1, 5, 3, 7, "concrete")
    for x in range(0, 30, 10):
        box(g, x, x + 5, 1, 2, 4, 6, "stripe")
    return g


def sandbags(n=5):
    g = grid(n * 6 + 1, 7, 7)
    for row, z in enumerate((0, 2, 4)):
        off = 3 if row % 2 else 0
        for i in range(n - (row == 2)):
            box(g, off + i * 6, off + i * 6 + 6, 1 if row else 0, 7 if not row else 6, z, z + 2, "sand")
            g[off + i * 6, :, z:z + 2] = 0  # seam between bags
    return g


def fence(length=48, wood=False):
    g = grid(length, 2, 12)
    for x in range(0, length, 8 if wood else 12):
        box(g, x, x + 1 + wood, 0, 2, 0, 12, "wood" if wood else "steel")
    if wood:
        box(g, 0, length, 0, 1, 2, 11, "wood")
        for x in range(0, length, 3):
            g[x, 0, 2:11] = I["rust"] if x % 9 == 0 else g[x, 0, 2:11]
        g[length // 3:length // 3 + 4, 0, 4:11] = 0   # broken boards
    else:
        box(g, 0, length, 0, 1, 11, 12, "steel")
        for x in range(length):
            for z in range(1, 11):
                if (x + z) % 4 == 0 or (x - z) % 4 == 0:
                    g[x, 0, z] = I["steel_d"]
    return g


def streetlight():
    g = grid(14, 4, 30)
    box(g, 1, 3, 1, 3, 0, 30, "steel_d"); box(g, 0, 4, 0, 4, 0, 2, "steel_d")
    box(g, 3, 12, 1, 3, 28, 30, "steel_d"); box(g, 9, 13, 0, 4, 26, 28, "lamp")
    return g


def stop_sign():
    g = grid(9, 2, 22)
    box(g, 4, 5, 0, 1, 0, 14, "steel")
    box(g, 1, 8, 1, 2, 14, 21, "sign"); box(g, 2, 7, 1, 2, 13, 22, "sign")
    box(g, 2, 7, 1, 2, 17, 18, "signw")
    return g


def ac_unit():
    g = grid(14, 10, 7)
    box(g, 0, 14, 0, 10, 0, 7, "tank")
    for x in range(2, 12, 2):
        box(g, x, x + 1, 9, 10, 1, 6, "steel_d")
    box(g, 4, 10, 2, 8, 7, 7, "steel_d")
    g[4:10, 2:8, 6] = I["steel_d"]
    return g


def vent():
    g = grid(6, 6, 8)
    box(g, 1, 5, 1, 5, 0, 6, "steel"); box(g, 0, 6, 0, 6, 6, 8, "steel_d")
    return g


def water_tank():
    g = grid(22, 22, 26)
    for x, y in ((3, 3), (17, 3), (3, 17), (17, 17)):
        box(g, x, x + 2, y, y + 2, 0, 10, "wood")
    yy, xx = np.ogrid[:22, :22]
    disc = (xx - 10.5) ** 2 + (yy - 10.5) ** 2 < 10 ** 2
    for z in range(10, 23):
        g[:, :, z][disc] = I["wood"] if z % 4 else I["rust"]
    cone = (xx - 10.5) ** 2 + (yy - 10.5) ** 2 < 6 ** 2
    g[:, :, 23][disc] = I["roofgrey"]; g[:, :, 24][cone] = I["roofgrey"]; g[9:12, 9:12, 25] = I["roofgrey"]
    return g


def debris(rng):
    g = grid(20, 14, 5)
    for _ in range(26):
        x, y = rng.randrange(1, 18), rng.randrange(1, 12)
        c = rng.choice(["concrete", "rust", "steel_d", "wood", "concrete"])
        h = rng.randrange(1, 4)
        box(g, x, x + rng.randrange(1, 4), y, y + rng.randrange(1, 3), 0, h, c)
    return g


def tyres():
    g = grid(9, 9, 8)
    yy, xx = np.ogrid[:9, :9]
    ring = ((xx - 4) ** 2 + (yy - 4) ** 2 < 17) & ((xx - 4) ** 2 + (yy - 4) ** 2 > 3)
    for z in range(0, 8):
        if z % 3 != 2:
            g[:, :, z][ring] = I["tyre"]
    return g


def dumpster():
    g = grid(24, 12, 11)
    box(g, 0, 24, 0, 12, 1, 10, "paint2"); box(g, 1, 23, 1, 11, 10, 11, "steel_d")
    box(g, 2, 4, 2, 10, 0, 1, "tyre"); box(g, 20, 22, 2, 10, 0, 1, "tyre")
    return g


def _tight(img):
    ys, xs = np.where(img[:, :, 3] > 0)
    if len(xs) == 0:
        return img[:1, :1].copy(), (0, 0)
    y0, y1 = int(ys.min()), int(ys.max()) + 1
    x0, x1 = int(xs.min()), int(xs.max()) + 1
    return img[y0:y1, x0:x1].copy(), (x0, y0)


def sprite(g, heading=0, burnt=False):
    """Cropped prop sprite, plus its cast shadow and the shadow's top-left
    relative to the sprite's top-left (both anchored on the ground centre)."""
    sc = canvas_for(g.shape)
    img = render_frame(g, BURNT if burnt else COLORS, heading, canvas=sc)
    img, origin = _tight(img)
    rgb = img[..., :3].astype(float)   # decor rule: desaturate 35% and dim 10%
    lum = rgb @ np.array([0.3, 0.59, 0.11])
    img[..., :3] = np.clip((rgb * 0.65 + lum[..., None] * 0.35) * 0.9, 0, 255).astype(np.uint8)
    shc = shadow_canvas(g.shape)
    sh = render_shadow(g, heading, canvas=shc)
    sh[..., 3] = np.where(sh[..., 3] > 0, int(round(SHADOW_ALPHA * 255)), 0).astype(np.uint8)
    sh, sorigin = _tight(sh)
    # Ground centre pixel in each crop. map_art draws the shadow at sprite + ofs.
    sg = (sc // 2 - origin[0], sc // 2 - origin[1])
    hg = (shc // 2 - sorigin[0], shc // 2 - sorigin[1])
    ofs = (int(sg[0] - hg[0]), int(sg[1] - hg[1]))
    return img, sh, ofs


# --- decals: flat, partly transparent ------------------------------------
def rgba(rgb, alpha):
    return np.concatenate([np.clip(rgb, 0, 255).astype(np.uint8), np.clip(alpha, 0, 255)[..., None].astype(np.uint8)], 2)


def crack(rng, w=48, h=48):
    a = np.zeros((h, w)); x, y = rng.randrange(4, w - 4), 1
    while y < h - 1:
        a[y, x] = 190
        if rng.random() < 0.25:  # branch
            bx, by = x, y
            for _ in range(rng.randrange(3, 9)):
                bx = min(w - 1, max(0, bx + rng.choice((-1, 1)))); by = min(h - 1, by + rng.choice((0, 1)))
                a[by, bx] = 150
        x = min(w - 2, max(1, x + rng.choice((-1, 0, 0, 1)))); y += 1
    return rgba(np.zeros((h, w, 3)) + 10, a)


def disc_decal(rng, size, rgb, alpha, lumpy=4, edge_dark=0.0):
    yy, xx = np.mgrid[:size, :size]
    m = np.zeros((size, size), bool)
    c = size / 2
    for _ in range(lumpy):
        cx, cy, r = c + rng.uniform(-size * .15, size * .15), c + rng.uniform(-size * .1, size * .1), rng.uniform(size * .18, size * .3)
        m |= (xx - cx) ** 2 + (yy - cy) ** 2 < r * r
    col = np.zeros((size, size, 3)) + np.array(rgb, float)
    col += (np.random.RandomState(rng.randrange(1 << 30)).rand(size, size, 1) - 0.5) * 10
    if edge_dark:
        inner = m & np.roll(m, 2, 0) & np.roll(m, -2, 0) & np.roll(m, 2, 1) & np.roll(m, -2, 1)
        col[m & ~inner] *= 1 - edge_dark
    return rgba(col, m * alpha)


def pothole(rng):
    t = disc_decal(rng, 22, f(ROAD, 0.4), 235, 3, 0)
    rim = disc_decal(random.Random(rng.random()), 26, f(ROAD, 1.6), 140, 3)
    rim[2:24, 2:24][t[..., 3] > 0] = t[t[..., 3] > 0]
    return rim


def puddle(rng):
    t = disc_decal(rng, 40, f(GLASS, 0.75), 150, 5, 0)
    for _ in range(5):  # sky glint
        y, x = rng.randrange(8, 32), rng.randrange(8, 32)
        if t[y, x, 3]:
            t[y, x, :3] = f(GLASS, 1.5)
    return t


def oil(rng):
    return disc_decal(rng, 30, (14, 13, 16), 170, 4, 0)


def scorch(rng):
    t = disc_decal(rng, 64, (16, 14, 13), 120, 6)
    return t


def blood_trail(rng, length=70):
    h = 14; a = np.zeros((h, length)); col = np.zeros((h, length, 3)) + f(PALETTE["enemy_red"], 0.33)
    y = h / 2
    for x in range(length):
        y += rng.uniform(-0.6, 0.6); y = min(h - 4, max(3, y))
        wid = 1.5 + 2.0 * (1 - x / length) + rng.random()
        for yy in range(int(y - wid), int(y + wid) + 1):
            if 0 <= yy < h:
                a[yy, x] = 200 if x % 17 > 2 else 120
    for _ in range(6):  # drops
        x, yy = rng.randrange(length), rng.randrange(h)
        a[yy, x] = 220
    return rgba(col, a)


def blood_pool(rng):
    return disc_decal(rng, 26, f(PALETTE["enemy_red"], 0.3), 210, 5)


def trash(rng):
    w, h = 36, 24; a = np.zeros((h, w)); col = np.zeros((h, w, 3))
    for _ in range(18):
        x, y = rng.randrange(w - 3), rng.randrange(h - 2)
        c = rng.choice([f(PAVE, 1.4), f(PALETTE["bone"], 0.9), f(RUST, 0.8), f(GLASS, 1.2), f(STEEL, 0.7)])
        ww, hh = rng.randrange(1, 4), rng.randrange(1, 3)
        col[y:y + hh, x:x + ww] = c; a[y:y + hh, x:x + ww] = 230
    return rgba(col, a)


def weeds(rng, w=34, h=14):
    a = np.zeros((h, w)); col = np.zeros((h, w, 3))
    base = np.array(f(GRASS, 0.78), float)   # darker and browner than the zombie greens
    for _ in range(30):
        x = rng.randrange(w); top = rng.randrange(1, h - 2)
        c = base * rng.uniform(0.75, 1.1) + np.array([8, 0, -4]) * rng.random()
        col[top:h - 1, x] = c; a[top:h - 1, x] = 230
        col[top, x] = c * 1.25
    return rgba(col, a)


def graffiti(rng, w=40, h=16):
    a = np.zeros((h, w)); col = np.zeros((h, w, 3))
    c = np.array(rng.choice([f(PALETTE["enemy_red"], 0.5), f(GLASS, 1.6), f(PALETTE["bone"], 0.8), f(PALETTE["goop"], 0.6)]), float)
    x, y = 2, rng.randrange(4, h - 4)
    while x < w - 2:  # one loopy tag stroke
        for dy in (0, 1):
            a[min(h - 1, max(0, int(y) + dy)), x] = 200
        y += rng.choice((-2, -1, 0, 1, 2)); y = min(h - 3, max(2, y))
        if rng.random() < 0.2:
            for yy in range(2, h - 2):
                a[yy, x] = 190
        x += 1
    col[:] = c
    return rgba(col, a)


def pack(items, W=512, limit=2048):
    """items: name -> image. Stays within `limit` so the Compatibility renderer
    can upload the atlas (bake-time only; the map itself is chunked to 2048)."""
    x = y = row = 0
    regions = {}
    sheet = np.zeros((limit, W, 4), np.uint8)
    for k, t in items.items():
        h, w = t.shape[:2]
        if w > W or h > limit:
            raise SystemExit("prop %s is %dx%d, over the atlas limit" % (k, w, h))
        if x + w > W:
            x, y, row = 0, y + row + 1, 0
        if y + h > limit:
            raise SystemExit("props sheet exceeds %d px" % limit)
        sheet[y:y + h, x:x + w] = t
        regions[k] = [int(x), int(y), int(w), int(h)]
        x += w + 1
        row = max(row, h)
    return sheet[:y + row + 1], regions


def dist(a, b):
    return float(np.linalg.norm(np.array(a[:3], float) - np.array(b[:3], float)))


def check_readability(items, near=18.0, share=0.12):
    """No decor piece may have more than 12% of its pixels within 18 RGB units
    of COL_ZOMBIE or COL_ZOMBIE_DARK, so the horde never melts into decor."""
    bad = []
    zs = np.array([ZOMBIE, ZOMBIE_DARK], float)
    for k, t in items.items():
        m = t[..., 3] > 0
        if not m.any():
            continue
        px = t[..., :3][m].astype(float)
        d = np.linalg.norm(px[:, None, :] - zs[None], axis=2).min(1)
        frac = float((d < near).mean())
        if frac > share:
            bad.append((k, round(frac, 2)))
    return bad


def add(it, shadows, name, grid, heading, burnt=False):
    img, sh, ofs = sprite(grid, heading, burnt)
    it[name] = img
    shadows[name] = (sh, ofs)


def main():
    rng = random.Random(6061)
    it = {}
    shadows = {}
    paints = ["paint0", "paint1", "paint2"]
    for i, p in enumerate(paints):
        g = car(p, rng)
        add(it, shadows, "car%d_h" % i, g, 0)
        add(it, shadows, "car%d_v" % i, g, 90)
        add(it, shadows, "car%d_a" % i, g, 200)
    for i in range(2):
        g = car(paints[i], rng)
        add(it, shadows, "burnt%d_h" % i, g, 0 if i == 0 else 160, burnt=True)
        add(it, shadows, "burnt%d_v" % i, g, 90 if i == 0 else 290, burnt=True)
    add(it, shadows, "jersey_h", jersey(), 0); add(it, shadows, "jersey_v", jersey(), 90)
    add(it, shadows, "sandbags_h", sandbags(), 0); add(it, shadows, "sandbags_v", sandbags(), 90)
    add(it, shadows, "fence_h", fence(), 0); add(it, shadows, "fence_v", fence(), 90)
    add(it, shadows, "wfence_h", fence(48, True), 0); add(it, shadows, "wfence_v", fence(48, True), 90)
    add(it, shadows, "light_e", streetlight(), 0); add(it, shadows, "light_w", streetlight(), 180)
    add(it, shadows, "light_s", streetlight(), 90); add(it, shadows, "light_n", streetlight(), 270)
    add(it, shadows, "stop", stop_sign(), 0)
    add(it, shadows, "ac", ac_unit(), 0); add(it, shadows, "vent", vent(), 0); add(it, shadows, "tank", water_tank(), 0)
    add(it, shadows, "dumpster", dumpster(), 0); add(it, shadows, "tyres", tyres(), 0)
    for i in range(3):
        add(it, shadows, "debris_%d" % i, debris(rng), 0)
    for i in range(4):
        it["crack_%d" % i] = crack(rng)
        it["trash_%d" % i] = trash(rng)
        it["weeds_%d" % i] = weeds(rng)
    for i in range(3):
        it["pothole_%d" % i] = pothole(rng)
        it["puddle_%d" % i] = puddle(rng)
        it["oil_%d" % i] = oil(rng)
        it["graffiti_%d" % i] = graffiti(rng)
    for i in range(2):
        it["blood_trail_%d" % i] = blood_trail(rng)
        it["blood_pool_%d" % i] = blood_pool(rng)
        it["scorch_%d" % i] = scorch(rng)
    bad = check_readability(it)
    if bad:
        raise SystemExit("decor too close to zombie colours: %s" % bad)
    # Shadows pack after the sprites so a missing shadow sheet never shifts a
    # sprite region that map_art already found by name. Alpha is already 0.5.
    packed = dict(it)
    for name, (sh, _ofs) in shadows.items():
        packed["@shadow/" + name] = sh
    sheet, regions = pack(packed)
    shadow_meta = {}
    for name, (_sh, ofs) in shadows.items():
        shadow_meta[name] = {"rect": regions.pop("@shadow/" + name), "ofs": [int(ofs[0]), int(ofs[1])]}
    if sheet.shape[0] > 2048 or sheet.shape[1] > 2048:
        raise SystemExit("props atlas %s exceeds 2048" % (sheet.shape,))
    os.makedirs(OUT, exist_ok=True)
    Image.fromarray(sheet, "RGBA").save(os.path.join(OUT, "outer_props.png"))
    json.dump({"regions": regions, "shadows": shadow_meta,
               "shadow_rgb": [20, 11, 6], "shadow_alpha": SHADOW_ALPHA},
              open(os.path.join(OUT, "outer_props.json"), "w"), indent=1)
    lamp = shadow_meta["light_e"]
    print("outer_props:", sheet.shape, len(regions), "regions;", len(shadow_meta),
          "shadows; light_e ofs", lamp["ofs"], "rect", lamp["rect"], "; readability ok")


if __name__ == "__main__":
    main()
