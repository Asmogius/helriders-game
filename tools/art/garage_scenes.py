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
import voxel_render  # noqa: E402
from voxel_render import write_import  # noqa: E402

from voxel_render import render_frame  # noqa: E402  (side-face fix landed in #56)
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
# Now in tuning.gd as COL_GARAGE_* (PR #42); keep both in step:
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
    """V2 calm pass (Cameron: the first bay was cluttered and hard to read).
    Room: x right, y toward the viewer, z up. Almost empty on purpose: a dark
    slab, a plain dark back wall, one floor pad under the rig and a pool of
    light on it. No tool wall, door, tyres or welding bench, so the part cards
    and stats sit on quiet, dark negative space and the rig is the focus."""
    rng = np.random.default_rng(3)
    g = np.zeros((X, Y, Z), np.int16)
    mid = X // 2
    ly = 62
    # dark slab, with a few faint oil stains well away from the cards
    box(g, 0, X, 0, Y, 0, 1, "road")
    # spotlight pool: the slab lifts to the bay floor colour around the pad,
    # dithered at the edge so the light falls off in pixel steps
    for x in range(mid - 120, mid + 121):
        for y in range(ly - 70, ly + 71):
            if not (0 <= x < X and 0 <= y < Y):
                continue
            d = math.hypot((x - mid) / 120.0, (y - ly) / 70.0)
            if d < 0.75 or (d < 1.0 and rng.random() < (1.0 - d) / 0.25):
                g[x, y, 0] = IDX["garage_floor"]
    for _ in range(3):
        cx, cy, r = mid + rng.integers(-60, 60), ly + rng.integers(30, 60), rng.integers(3, 6)
        for x in range(cx - r, cx + r):
            for y in range(cy - r // 2, cy + r // 2 + 1):
                if rng.random() < 0.7:
                    g[x, y, 0] = IDX["garage_oil"]
    # back wall: plain sheet with a few panel seams, a steel baseboard and a
    # rail at the top (v5: a little richer, still calm)
    box(g, 0, X, 0, 8, 0, Z, "garage_wall")
    for x in range(mid % 48, X, 48):
        box(g, x, x + 1, 8, 9, 6, Z - 6, "steel_dark")
    box(g, 0, X, 8, 10, 0, 5, "steel_dark")
    box(g, 0, X, 8, 9, Z - 6, Z - 4, "steel_dark")
    # two quiet props at the far edges, in the vignette: a tyre pair (left)
    # and a low tool chest (right), well away from the cards and stats
    tyre_stack(g, 40, 30, 2)
    box(g, X - 70, X - 40, 12, 26, 0, 14, "steel_dark")
    box(g, X - 69, X - 41, 13, 25, 14, 15, "rust")
    # floor pad (the old lift, quieter): dark disc, thin steel rim, a few cyan
    # marker dots instead of the busy hazard ring
    cyl(g, mid, ly, 44, 1, 3, "steel_dark")
    cyl(g, mid, ly, 42, 3, 4, "steel_dark")
    for a in range(0, 360, 2):
        x = mid + 42 * math.cos(math.radians(a)); y = ly + 42 * math.sin(math.radians(a))
        box(g, int(x), int(x) + 1, int(y), int(y) + 1, 4, 5, "steel")
    for a in (0, 90, 180, 270):
        x = mid + 39 * math.cos(math.radians(a)); y = ly + 39 * math.sin(math.radians(a))
        box(g, int(x), int(x) + 2, int(y), int(y) + 2, 4, 5, "cyan")
    # one overhead tube on the back wall, centred over the rig (the light source)
    box(g, mid - 30, mid + 30, 9, 11, 70, 72, "cyan")
    box(g, mid - 32, mid + 32, 8, 9, 69, 73, "steel_dark")
    return g, (mid, ly, 5)


def vignette(img, lx, ly, rx, ry, floor=0.45):
    """Darken towards the edges in 4 hard steps (pixel look, no smooth blur)."""
    h, w = img.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w]
    d = np.sqrt(((xx - lx) / rx) ** 2 + ((yy - ly) / ry) ** 2)
    k = np.clip(1.0 - np.floor(np.clip(d - 0.6, 0, None) * 4.0) / 4.0 * (1.0 - floor) * 1.6, floor, 1.0)
    out = img.copy()
    out[..., :3] = (img[..., :3] * k[..., None]).astype(np.uint8)
    return out


def render(g, cols, view_w, lift):
    X, Y, Z = g.shape
    canvas = int(math.hypot(X, Y)) + Z + 8
    img = render_frame(g, cols, 0.0, canvas=canvas, hd=True)   # v5: soft light + baked AO
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
    full = vignette(full, lx, ly, 150.0, 95.0)
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
