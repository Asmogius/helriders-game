#!/usr/bin/env python3
"""V2 style sample: the Workshop bay as a voxel diorama (P6 Garage).

Built from voxels and rendered once with voxel_render.render_frame at the rig
tilt (30 deg), 1 px per voxel. The garage shows the rig at RIG_SCALE 3.4, so the
room is displayed at the same 3.4x: one room voxel = one rig voxel on screen.

Writes art/garage/:
  workshop_bay.png        backdrop, 376x212 voxels-px (1280x720 at 3.4x)
  workshop_bay_wide.png   459x212 (1560x720, ~19.5:9 phones)
  workshop_bay_lights.png light-only overlay (tubes, lamps, door glow), for flicker
  workshop_bay.json       sizes, scale, the lift centre (where the rig sits), light spots
Moving things (flicker, dust, sparks) are code-drawn by garage_ambient.gd.
"""
import json, math, os, sys
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import inspect  # noqa: E402
import voxel_render  # noqa: E402
from voxel_render import write_import  # noqa: E402

# voxel_render.render_frame culls side faces with view = (0, -sin t, cos t), so
# it draws the up-screen (north) sides and drops the south sides, which the
# projection and depth order say face the camera. Small free-standing rigs hide
# this; a room can't (no back-wall face, holes in front of objects). The sample
# renders through a local copy with the sign fixed; fixing the shared renderer
# would re-render every rig sheet, so it's raised in the PR instead.
_src = inspect.getsource(voxel_render.render_frame).replace(
    "view = np.array([0.0, -st, ct])", "view = np.array([0.0, st, ct])")
assert "[0.0, st, ct]" in _src
_ns = dict(vars(voxel_render))
exec(_src, _ns)
render_frame = _ns["render_frame"]
from palette import PALETTE  # noqa: E402

OUT = os.path.join(HERE, "..", "..", "art", "garage")
SCALE = 3.4                 # garage.gd RIG_SCALE
VIEW = (376, 212)           # 1280x720 / 3.4
WIDE = (459, 212)           # 1560x720 / 3.4

# tuning.gd colours (0-255)
C = {
    "concrete": (41, 41, 43),       # COL_CONCRETE
    "building": (54, 52, 51),       # COL_BUILDING
    "roof": (69, 66, 62),           # COL_ROOF
    "road": (27, 27, 29),           # COL_ROAD
    "steel": PALETTE["steel"], "steel_dark": PALETTE["steel_dark"], "rust": PALETTE["rust"],
    "tyre": PALETTE["tyre"], "glass": PALETTE["glass"],
    "cyan": PALETTE["cyan"], "orange": PALETTE["orange"], "white_hot": PALETTE["white_hot"],
}
# Sample-local (proposed for tuning.gd via UI/P0):
SAMPLE_COLOURS = {
    "GARAGE_FLOOR": (58, 57, 55),       # workshop slab, a step lighter than the street
    "GARAGE_FLOOR_LINE": (120, 104, 60),# worn bay paint (desaturated road-line yellow)
    "GARAGE_OIL": (24, 23, 24),
    "GARAGE_PEGBOARD": (74, 60, 44),
    "GARAGE_WALL": (46, 48, 52),        # corrugated sheet
    "GARAGE_STREET_NIGHT": (30, 34, 44),# outside the roll-up door
    "GARAGE_GAS_RED": (110, 40, 34),    # welding cylinders (muted, not enemy red)
}
C.update({k.lower(): v for k, v in SAMPLE_COLOURS.items()})
LIGHTS = {"cyan", "orange", "white_hot"}

NAMES = ["_"] + list(C)
IDX = {n: i for i, n in enumerate(NAMES)}


def colors(light_only=False):
    out = [(0, 0, 0, 0)]
    for n in NAMES[1:]:
        if light_only and n not in LIGHTS:
            out.append((0, 0, 0, 0))
        else:
            out.append(tuple(C[n]) + (255,))
    return out


def box(g, x0, x1, y0, y1, z0, z1, n):
    sx, sy, sz = g.shape
    g[max(0, x0):min(sx, x1), max(0, y0):min(sy, y1), max(0, z0):min(sz, z1)] = IDX[n]


def cyl(g, cx, cy, r, z0, z1, n):
    sx, sy, _ = g.shape
    for x in range(int(cx - r), int(cx + r) + 1):
        for y in range(int(cy - r), int(cy + r) + 1):
            if 0 <= x < sx and 0 <= y < sy and (x - cx) ** 2 + (y - cy) ** 2 <= r * r:
                g[x, y, z0:z1] = IDX[n]


def tyre_stack(g, cx, cy, n):
    for k in range(n):
        cyl(g, cx, cy, 9, 1 + k * 5, 5 + k * 5, "tyre")
        cyl(g, cx, cy, 4, 1 + k * 5, 5 + k * 5, "steel_dark") if k == n - 1 else None
        g[int(cx - 4):int(cx + 5), int(cy - 4):int(cy + 5), 5 + k * 5 - 1] = np.where(
            g[int(cx - 4):int(cx + 5), int(cy - 4):int(cy + 5), 5 + k * 5 - 1] > 0, IDX["tyre"], 0)


def build(X, Y=240, Z=78):
    """Room: x right, y toward the viewer, z up. Back wall at small y."""
    rng = np.random.default_rng(3)
    g = np.zeros((X, Y, Z), np.int16)
    mid = X // 2
    # floor slab with bay lines and oil stains
    box(g, 0, X, 0, Y, 0, 1, "garage_floor")
    for x0 in (mid - 70, mid + 66):
        box(g, x0, x0 + 4, 40, Y - 10, 0, 1, "garage_floor_line")
    for _ in range(18):
        cx, cy, r = rng.integers(10, X - 10), rng.integers(50, Y - 10), rng.integers(3, 9)
        for x in range(cx - r, cx + r):
            for y in range(cy - r // 2, cy + r // 2 + 1):
                if 0 <= x < X and 0 <= y < Y and rng.random() < 0.75:
                    g[x, y, 0] = IDX["garage_oil"]
    # back wall (corrugated: alternating depth) with a door opening on the right
    door0, door1 = X - 150, X - 60
    for x in range(X):
        d = 8 + (1 if (x // 3) % 2 else 0)
        if door0 <= x < door1:
            continue
        box(g, x, x + 1, 0, d, 0, Z, "garage_wall")
    # roll-up door: frame, half-raised shutter, street outside
    box(g, door0 - 4, door0, 0, 12, 0, Z, "steel_dark")
    box(g, door1, door1 + 4, 0, 12, 0, Z, "steel_dark")
    for z in range(46, Z):
        box(g, door0, door1, 2, 6, z, z + 1, "steel" if z % 3 else "steel_dark")
    box(g, door0, door1, 0, 2, 0, 46, "garage_street_night")
    for x in range(door0 + 6, door1 - 6, 18):           # far street: a wreck silhouette and a lamp
        box(g, x, x + 10, 0, 1, 4, 10 + (x % 5), "road")
    box(g, door1 - 20, door1 - 18, 0, 1, 10, 40, "steel_dark")
    box(g, door1 - 24, door1 - 14, 0, 1, 38, 40, "orange")   # street lamp head
    box(g, door0, door1, 2, 10, 44, 46, "orange")        # warning strip on the shutter edge
    # tool wall (pegboard) left of centre, with tools as steel shapes
    box(g, mid - 150, mid - 40, 8, 10, 22, 62, "garage_pegboard")
    for k in range(12):
        tx = mid - 144 + k * 9
        h = 8 + (k * 7) % 10
        box(g, tx, tx + 2, 10, 11, 56 - h, 56, "steel")
        if k % 3 == 0:
            box(g, tx - 2, tx + 4, 10, 11, 56 - h - 3, 56 - h, "steel_dark")
    box(g, mid - 150, mid - 40, 10, 22, 18, 21, "steel_dark")   # workbench top
    for lx in (mid - 148, mid - 44):
        box(g, lx, lx + 3, 12, 20, 0, 18, "steel_dark")
    box(g, mid - 120, mid - 96, 12, 20, 21, 27, "gas_dummy" if False else "rust")  # toolbox
    # fluorescent tubes (cyan) on the back wall and an orange work lamp
    for x0 in (mid - 140, mid - 20, mid + 90):
        box(g, x0, x0 + 40, 9, 11, 68, 70, "cyan")
        box(g, x0 - 2, x0 + 42, 8, 9, 67, 71, "steel_dark")
    # welding station, right of centre
    wx = mid + 110
    box(g, wx, wx + 30, 20, 40, 0, 16, "steel_dark")
    box(g, wx + 2, wx + 28, 22, 38, 16, 18, "steel")
    cyl(g, wx + 40, 22, 4, 0, 30, "garage_gas_red")
    cyl(g, wx + 50, 22, 4, 0, 30, "steel")
    box(g, wx + 6, wx + 10, 24, 28, 18, 24, "orange")    # hot weld glow on the bench
    # tyre stacks, left
    tyre_stack(g, 30, 40, 4)
    tyre_stack(g, 52, 32, 3)
    tyre_stack(g, 36, 66, 2)
    # hydraulic lift in the middle: round platform on a post, hazard ring
    ly = 62
    cyl(g, mid, ly, 44, 1, 3, "steel_dark")
    cyl(g, mid, ly, 42, 3, 5, "steel")
    for a in range(0, 360, 6):
        if (a // 12) % 2 == 0:
            x = mid + 41 * math.cos(math.radians(a)); y = ly + 41 * math.sin(math.radians(a))
            box(g, int(x), int(x) + 2, int(y), int(y) + 2, 5, 6, "orange")
    cyl(g, mid, ly, 6, 0, 1, "steel_dark")
    # orange work lamp on a stand, near the lift
    box(g, mid + 64, mid + 66, 70, 72, 0, 40, "steel_dark")
    box(g, mid + 60, mid + 70, 66, 74, 40, 44, "orange")
    # crates / barrels front-left (low, so they don't hide controls)
    box(g, 70, 96, Y - 40, Y - 16, 0, 14, "rust")
    box(g, 72, 94, Y - 38, Y - 18, 14, 15, "steel_dark")
    cyl(g, 108, Y - 30, 7, 0, 18, "steel")
    return g, (mid, ly, 5)


def render(g, cols, view_w, lift):
    X, Y, Z = g.shape
    canvas = int(math.hypot(X, Y)) + Z + 8
    img = render_frame(g, cols, 0.0, canvas=canvas)
    # project the lift centre to crop around it
    t = math.radians(30.0)
    cx, cy = X / 2.0, Y / 2.0
    lx = (lift[0] - cx) + canvas / 2
    ly_ = ((lift[1] - cy) * math.cos(t) - lift[2] * math.sin(t)) + canvas / 2
    return img, (lx, ly_)


def main():
    os.makedirs(OUT, exist_ok=True)
    meta = {"scale": SCALE, "sample_colours": {k: list(v) for k, v in SAMPLE_COLOURS.items()}}
    g, lift = build(WIDE[0] + 6)
    full, (lx, ly) = render(g, colors(), WIDE[0], lift)
    # This projection shows top faces and the up-screen sides (like the rig
    # sheets); where an object stands on the slab, the strip in front of it has
    # no face. Composite over a floor-only render so the slab shows there.
    floor = g.copy()
    floor[:, :, 1:] = 0
    base, _ = render(floor, colors(), WIDE[0], lift)
    a = full[..., 3:4] > 0
    full = np.where(a, full, base)
    lights, _ = render(g, colors(True), WIDE[0], lift)
    # The rig sits at garage.gd (size.x * 0.5, 290) on a 720-high screen -> 290/3.4 px down.
    top = int(round(ly - 290 / SCALE))
    for name, (w, h) in (("workshop_bay", VIEW), ("workshop_bay_wide", WIDE)):
        left = int(round(lx - w / 2))
        Image.fromarray(full[top:top + h, left:left + w]).save(os.path.join(OUT, name + ".png"))
        write_import(os.path.join(OUT, name + ".png"))
        meta[name] = {"size": [w, h], "lift": [w / 2, 290 / SCALE]}
        if name == "workshop_bay_wide":
            lt = lights[top:top + h, left:left + w].copy()
            Image.fromarray(lt).save(os.path.join(OUT, "workshop_bay_lights.png"))
            write_import(os.path.join(OUT, "workshop_bay_lights.png"))
    json.dump(meta, open(os.path.join(OUT, "workshop_bay.json"), "w"), indent=1)
    print("workshop bay rendered", meta["workshop_bay"], meta["workshop_bay_wide"])


if __name__ == "__main__":
    main()
