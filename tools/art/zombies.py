#!/usr/bin/env python3
"""V3 style sample: voxel zombies (Shambler + Tank) through the rig pipeline.

One humanoid voxel model (14x10x18 voxels, x = forward, y = left-right,
z = up), posed per frame, rendered with voxel_render.render_frame at the same
30 deg tilt, 1 px per voxel, near-black outline and 3-step shading as the rigs.
16 headings; Shambler: 4-frame shamble + 2-frame lunge + hit-flash, in 6
clothing palettes. Tank: the same body built at ~2x with heavier proportions:
4-frame walk, 2-frame roar (wind-up), charge, stumble, hit-flash.

Writes art/zombies/zombies.png (one atlas) + zombies.json:
  kinds.<kind>: {frame_w, frame_h, rows: {pose_name: [x, y]}, variants}
A frame is at (x + heading * frame_w, y) for its row; heading i = i*360/16
deg, the same convention as the rig sheets (frame_for in directional_sprite.gd).
"""
import json, math, os, sys
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import inspect  # noqa: E402
import voxel_render  # noqa: E402
from voxel_render import canvas_for, write_import  # noqa: E402

# Tilt prototype (art/zombie-tilt-proto): the shared voxel_render.render_frame
# culls side faces with view = (0, -sin t, cos t), so it draws the up-screen
# (north) sides and drops the south sides, which the projection and depth order
# say face the camera. On a zombie that hides the front/side/height and the
# figure reads flat next to the rigs. Same fix as the garage sample
# (art/sample-garage, garage_scenes.py): a local copy with the sign fixed. The
# shared renderer is untouched (fixing it re-renders every rig sheet).
_src = inspect.getsource(voxel_render.render_frame).replace(
    "view = np.array([0.0, -st, ct])", "view = np.array([0.0, st, ct])")
assert "[0.0, st, ct]" in _src
_ns = dict(vars(voxel_render))
exec(_src, _ns)
render_frame = _ns["render_frame"]

OUT = os.path.join(HERE, "..", "..", "art", "zombies")
HEADINGS = 16
# The plan's base model is 14x10x18 voxels. At 1 px/voxel that is ~half the
# Shambler's 26 px hit circle and reads far smaller than today's code-drawn body,
# so the sample builds it at 1.8x (~25x18x32) to
# fill the circle the way the rigs fill their bodies; the Tank is 2x that.
SH_SCALE = 1.8
TANK_SCALE = 3.4

# tuning.gd colours (0-255)
ZOMBIE = (115, 128, 94)        # COL_ZOMBIE (skin)
ZOMBIE_DARK = (69, 77, 59)     # COL_ZOMBIE_DARK
TANK = (128, 84, 77)           # COL_TANK
STEEL = (79, 82, 85)           # COL_STEEL
BLOOD = (77, 23, 18)           # COL_BLOOD (opaque here)
# Sample-local (proposed for tuning.gd via UI/P0): 6 Shambler clothing palettes
# (shirt, trousers), muted so they stay below the lights in saturation.
CLOTHES = [
    ((112, 90, 70), (63, 61, 70)),     # brown jacket, grey jeans
    ((90, 102, 119), (73, 63, 53)),     # faded denim blue, brown trousers
    ((134, 126, 112), (56, 58, 63)),   # dirty off-white shirt, dark trousers
    ((107, 70, 65), (80, 78, 70)),     # oxblood hoodie, khaki
    ((85, 97, 75), (61, 53, 48)),     # olive work shirt, dark brown
    ((117, 107, 85), (70, 78, 90)),     # tan coat, slate trousers
]
EYE = (190, 60, 40)                   # dull red eyes (not enemy-rig red, no glow)
FLASH = (240, 232, 214)               # hit-flash (whole silhouette)
TANK_SKIN_DARK = (84, 54, 50)
SAMPLE_COLOURS = {"ZOMBIE_CLOTH_%d" % i: list(c[0]) + list(c[1]) for i, c in enumerate(CLOTHES)}
SAMPLE_COLOURS.update({"ZOMBIE_EYE": list(EYE), "ZOMBIE_FLASH": list(FLASH)})


class Pal:
    def __init__(self):
        self.cols = [(0, 0, 0, 0)]
        self.idx = {}

    def __call__(self, c):
        c = tuple(c)
        if c not in self.idx:
            self.idx[c] = len(self.cols)
            self.cols.append(c + (255,))
        return self.idx[c]


def box(g, x0, x1, y0, y1, z0, z1, v):
    sx, sy, sz = g.shape
    g[max(0, x0):min(sx, x1), max(0, y0):min(sy, y1), max(0, z0):min(sz, z1)] = v


def humanoid(P, s, skin, skin_dark, shirt, trousers, pose, k, heavy=False):
    """Pose a humanoid in a grid. s = scale (1 Shambler, 2 Tank).
    pose: walk (k 0-3), lunge (k 0-1), roar (k 0-1), charge, stumble."""
    L, W, H = int(14 * s), int(10 * s), int(18 * s)
    g = np.zeros((L, W, H), np.int16)
    cx, cy = L // 2, W // 2
    lean = {"walk": 1, "lunge": 2 + k, "roar": -1, "charge": 3, "stumble": 2}.get(pose, 1)
    hunch = int(round(lean * s))
    # legs: walk cycle swings them forward/back
    swing = [2, 0, -2, 0][k % 4] if pose == "walk" else (2 if pose == "charge" else 0)
    sw = int(round(swing * s))
    leg_h = int(7 * s)
    lw = max(2, int(2 * s))
    for side, ph in ((-1, 1), (1, -1)):
        y0 = cy + (1 if side > 0 else -1 - lw) * 1 + (0 if side > 0 else 0)
        y0 = cy + 1 if side > 0 else cy - 1 - lw
        dx = sw * ph
        if pose == "stumble" and side > 0:
            dx = int(3 * s)
        box(g, cx - lw // 2 + dx, cx + lw - lw // 2 + dx, y0, y0 + lw, 0, leg_h, P(trousers))
        box(g, cx - lw // 2 + dx, cx + lw - lw // 2 + dx + int(1 * s), y0, y0 + lw, 0, max(1, int(s)), P(skin_dark))  # feet
    # torso (hunched forward by `hunch` at the top)
    tw = int(7 * s) if not heavy else int(9 * s)
    td = int(4 * s) if not heavy else int(6 * s)
    th = int(6 * s)
    for z in range(leg_h, leg_h + th):
        off = int(round(hunch * (z - leg_h) / max(1, th)))
        box(g, cx - td // 2 + off, cx + td - td // 2 + off, cy - tw // 2, cy + tw - tw // 2, z, z + 1, P(shirt))
    # rips: skin showing through
    box(g, cx + td // 2 - 1 + hunch // 2, cx + td // 2 + hunch // 2, cy - 1, cy + 1, leg_h + 2, leg_h + 3, P(skin))
    box(g, cx - td // 2 + hunch // 3, cx - td // 2 + 1 + hunch // 3, cy + 1, cy + 2, leg_h + 1, leg_h + 2, P(BLOOD))
    top = leg_h + th
    # head
    hs = max(3, int(3.5 * s)) if not heavy else int(3 * s)
    hx = cx + hunch + (int(s) if pose in ("lunge", "charge") else 0)
    hz = top - (int(s) if heavy else 0)
    if pose == "roar":
        hz += int(s)
    box(g, hx - hs // 2, hx + hs - hs // 2, cy - hs // 2, cy + hs - hs // 2, hz, hz + hs, P(skin))
    box(g, hx + hs - hs // 2 - 1, hx + hs - hs // 2, cy - hs // 2, cy - hs // 2 + max(1, hs // 3), hz + hs // 2, hz + hs // 2 + 1, P(EYE))
    box(g, hx + hs - hs // 2 - 1, hx + hs - hs // 2, cy + hs - hs // 2 - max(1, hs // 3), cy + hs - hs // 2, hz + hs // 2, hz + hs // 2 + 1, P(EYE))
    if pose == "roar":   # open jaw
        box(g, hx + hs - hs // 2 - 1, hx + hs - hs // 2, cy - 1, cy + 1, hz, hz + max(1, hs // 3), P(BLOOD))
    # arms: reaching forward (shambler), swinging (tank walk), up (roar)
    aw = max(2, int(2 * s)) if not heavy else int(3 * s)
    az = top - aw
    for side in (-1, 1):
        y0 = cy - tw // 2 - aw if side < 0 else cy + tw - tw // 2
        if pose == "roar":
            box(g, cx + hunch - aw // 2, cx + hunch + aw - aw // 2, y0, y0 + aw, az, min(H, az + int((5 + 2 * k) * s)), P(skin))
            continue
        if heavy and pose in ("walk", "stumble"):
            reach = int((3 + (1 if (k + (side > 0)) % 2 else -1)) * s)
            box(g, cx + hunch - 1, cx + hunch - 1 + max(2, reach), y0, y0 + aw, az - int(4 * s), az + aw, P(skin))
            box(g, cx + hunch - 1, cx + hunch + 1, y0, y0 + aw, az, az + aw, P(shirt))
            continue
        reach = int((6 if pose in ("lunge", "charge") else 4) * s) + (int(2 * s) * k if pose == "lunge" else 0)
        bob = (k + (side > 0)) % 2 if pose == "walk" else 0
        box(g, cx + hunch - 1, cx + hunch - 1 + reach + bob, y0, y0 + aw, az - bob, az + aw - bob, P(skin))
        box(g, cx + hunch - 1, cx + hunch + 1, y0, y0 + aw, az, az + aw, P(shirt))   # sleeve
    if heavy:   # Tank: scrap plates strapped to the back and a shoulder
        box(g, cx - td // 2 - int(1 * s) + hunch // 2, cx - td // 2 + hunch // 2, cy - tw // 2 + int(s), cy + tw - tw // 2 - int(s), leg_h + int(s), top, P(STEEL))
    return g


def flash_of(g):
    f = g.copy()
    f[f > 0] = -1
    return f


def render_rows(rows, n_head, P):
    """rows: list of grids (or ('flash', grid)). Returns (frames[row][h], canvas)."""
    canvas = max(canvas_for(r.shape) for r in rows)
    out = []
    for g in rows:
        cols = list(P.cols)
        if (g < 0).any():
            gi = np.where(g < 0, len(cols), g)
            cols = cols + [FLASH + (255,)]
            g = gi
        out.append([render_frame(g, cols, i * 360.0 / n_head, canvas=canvas) for i in range(n_head)])
    # Crop every frame to one tight square, symmetric about the centre (the
    # ground point stays the frame centre).
    m = 0
    c = canvas // 2
    for row in out:
        for f in row:
            ys, xs = np.nonzero(f[..., 3])
            if len(xs):
                m = max(m, abs(xs - c).max(), abs(ys - c).max())
    m = int(m) + 1
    out = [[f[c - m:c + m, c - m:c + m] for f in row] for row in out]
    return out, int(2 * m)


def build():
    blocks = []
    # Shambler: 6 variants x (walk 4, lunge 2, flash)
    P = Pal()
    sh_rows, names = [], []
    for v, (shirt, trousers) in enumerate(CLOTHES):
        for k in range(4):
            sh_rows.append(humanoid(P, SH_SCALE, ZOMBIE, ZOMBIE_DARK, shirt, trousers, "walk", k)); names.append(f"v{v}_walk_{k}")
        for k in range(2):
            sh_rows.append(humanoid(P, SH_SCALE, ZOMBIE, ZOMBIE_DARK, shirt, trousers, "lunge", k)); names.append(f"v{v}_lunge_{k}")
    sh_rows.append(flash_of(humanoid(P, SH_SCALE, ZOMBIE, ZOMBIE_DARK, *CLOTHES[0], "walk", 0))); names.append("flash")
    fr, cv = render_rows(sh_rows, HEADINGS, P)
    blocks.append(("shambler", fr, cv, names, len(CLOTHES)))
    # Tank: ~2x, heavy
    P = Pal()
    t_rows, tn = [], []
    shirt, trousers = (70, 60, 52), (48, 44, 40)
    for k in range(4):
        t_rows.append(humanoid(P, TANK_SCALE, TANK, TANK_SKIN_DARK, shirt, trousers, "walk", k, heavy=True)); tn.append(f"walk_{k}")
    for k in range(2):
        t_rows.append(humanoid(P, TANK_SCALE, TANK, TANK_SKIN_DARK, shirt, trousers, "roar", k, heavy=True)); tn.append(f"roar_{k}")
    t_rows.append(humanoid(P, TANK_SCALE, TANK, TANK_SKIN_DARK, shirt, trousers, "charge", 0, heavy=True)); tn.append("charge")
    t_rows.append(humanoid(P, TANK_SCALE, TANK, TANK_SKIN_DARK, shirt, trousers, "stumble", 0, heavy=True)); tn.append("stumble")
    t_rows.append(flash_of(t_rows[0])); tn.append("flash")
    fr, cv = render_rows(t_rows, HEADINGS, P)
    blocks.append(("tank", fr, cv, tn, 1))
    # Pack: each row is a strip of 16 headings; strips fill two columns so the
    # atlas stays under 2048 px both ways (safe for GLES3 phones).
    Wd = 2048
    placed, y = [], 0
    for kind, fr, cv, names, variants in blocks:
        cols = max(1, Wd // (cv * HEADINGS))
        per_col = math.ceil(len(fr) / cols)
        rows = {}
        for r in range(len(fr)):
            c, rr = divmod(r, per_col)
            rows[names[r]] = [c * cv * HEADINGS, y + rr * cv]
        placed.append((kind, fr, cv, names, variants, rows))
        y += per_col * cv
    Ht = y
    Wd = max(r[0] + cv * HEADINGS for _, _, cv, _, _, rows in placed for r in rows.values())
    assert Wd <= 2048 and Ht <= 2048, (Wd, Ht)
    atlas = Image.new("RGBA", (Wd, Ht))
    meta = {"texture": "zombies.png", "headings": HEADINGS, "kinds": {}, "sample_colours": SAMPLE_COLOURS}
    for kind, fr, cv, names, variants, rows in placed:
        for r, row in enumerate(fr):
            x0, y0 = rows[names[r]]
            for h, img in enumerate(row):
                atlas.paste(Image.fromarray(img), (x0 + h * cv, y0))
        meta["kinds"][kind] = {"frame_w": cv, "frame_h": cv, "rows": rows, "variants": variants}
        for n, (x0, y0) in rows.items():   # P0 art_atlas.gd regions: "<kind>/<row>/<heading>"
            for h in range(HEADINGS):
                meta.setdefault("regions", {})["%s/%s/%d" % (kind, n, h)] = [x0 + h * cv, y0, cv, cv]
    os.makedirs(OUT, exist_ok=True)
    p = os.path.join(OUT, "zombies.png")
    atlas.save(p)
    write_import(p)
    json.dump(meta, open(os.path.join(OUT, "zombies.json"), "w"), indent=1)
    print("zombies atlas", atlas.size, {k: (v["frame_w"], len(v["rows"])) for k, v in meta["kinds"].items()})


if __name__ == "__main__":
    build()
