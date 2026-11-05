#!/usr/bin/env python3
"""Saloon C — high-detail voxel diorama (HD render_frame, ≥2 px/voxel).

Replaces the coarse near-iso painter with MagicaVoxel-style grids rendered
through voxel_render.render_frame(hd=True), matching the garage HD workshop
rig look: continuous light + soft AO, fine material detail.

Layout (concept C) is preserved: bar left, two tables, fireplace centre-back
clear of the right hire-card strip (x≥900), four hireable seats.
"""
from __future__ import annotations
import glob, json, math, os, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import voxel_render as vr
from voxel_render import write_import, render_frame
from palette import PALETTE, shade, OUTLINE
from saloon_iso import night_grade

OUT = os.path.join(HERE, "..", "..", "art", "saloon")
CONCEPT_HD = "/workspace/concepts/saloon_hd"
BEFORE_DIR = "/tmp/saloon_before"

# Camera: PR #70 game tilt is 45°. Also render 52° for a side-by-side pick.
TILT_GAME = 45.0
TILT_CONCEPT = 52.0
PPV = 3
HEADING = 0.0    # +x = screen-right; bar left, fireplace centre-back, card strip clear

# Fine voxel room (≈2.25× concept C linear resolution)
SX, SY, SZ = 360, 200, 80
# Concept C was 160×72×28; scale seats/layout by SX/160, SY/72
SX_S, SY_S = SX / 160.0, SY / 72.0

SEAT_IDS = ["bar_left", "table_left", "table_mid", "table_right"]
# concept seats × scale
SEATS_VOX = [
    (int(28 * SX_S), int(22 * SY_S), 16),
    (int(42 * SX_S), int(48 * SY_S), 16),
    (int(58 * SX_S), int(44 * SY_S), 16),
    (int(74 * SX_S), int(50 * SY_S), 16),
]
# Fireplace centre-back (concept 72–100 × scale) — must stay left of card x=900
FIRE_X0, FIRE_X1 = int(78 * SX_S), int(102 * SX_S)
FIRE_Y0, FIRE_Y1 = 6, 22

# Palette entries (name → RGB). Emissives use PALETTE orange/white_hot so shade() keeps them bright.
C = {
    "floor_a": (86, 64, 46), "floor_b": (76, 56, 40), "floor_gap": (58, 42, 30),
    "wall": (70, 56, 46), "wall_dark": (52, 40, 32), "beam": (58, 42, 30),
    "wood_dk": (108, 78, 52), "wood_mid": (132, 98, 68), "wood_top": (158, 120, 84),
    "wood_grain": (96, 70, 48), "stool_top": (118, 82, 54), "stool_leg": (70, 52, 40),
    "table_top": (140, 106, 74), "table_leg": (78, 58, 42),
    "stone": (96, 90, 84), "stone_dk": (70, 66, 62), "ash": (36, 28, 22),
    "log": (62, 42, 28), "log_end": (140, 110, 70),
    "fire_orange": PALETTE["orange"], "fire_hot": PALETTE["white_hot"],
    "lantern": PALETTE["orange"], "lantern_hot": PALETTE["white_hot"],
    "bottle_g": (40, 90, 55), "bottle_a": (90, 55, 30), "bottle_b": (50, 60, 110),
    "glass": (160, 190, 200), "liquid": (180, 120, 50),
    "rug_a": (110, 48, 42), "rug_b": (86, 36, 32), "rug_trim": (160, 120, 60),
    "crate": (120, 88, 55), "crate_dk": (90, 66, 42),
    "skull": (210, 200, 175), "skull_dk": (120, 110, 95),
    "dart": (150, 110, 70), "dart_face": (220, 210, 190), "dart_ring": (160, 50, 40),
    "metal": (90, 88, 82), "metal_dk": (48, 46, 44),
    "pants": (48, 46, 42),
    # crew (4 hireables + bartender)
    "c0_shirt": (68, 100, 122), "c0_skin": (200, 158, 116), "c0_hat": (124, 46, 38),
    "c1_shirt": (162, 136, 62), "c1_skin": (164, 118, 82), "c1_hat": (178, 178, 168),
    "c2_shirt": (74, 106, 68), "c2_skin": (136, 96, 68), "c2_hat": (100, 84, 60),
    "c3_shirt": (132, 62, 52), "c3_skin": (208, 170, 132), "c3_hat": (200, 112, 48),
    "bt_shirt": (92, 58, 50), "bt_skin": (198, 152, 114), "bt_hat": (72, 52, 44),
    "eye": (28, 24, 20), "shadow": (28, 18, 12),
}
NAMES = ["_"] + list(C)
IDX = {n: i for i, n in enumerate(NAMES)}
EMISSIVE_NAMES = {"fire_orange", "fire_hot", "lantern", "lantern_hot"}


def colors_rgba(light_only=False):
    out = [(0, 0, 0, 0)]
    for n in NAMES[1:]:
        if light_only and n not in EMISSIVE_NAMES:
            out.append((0, 0, 0, 0))
        else:
            out.append(tuple(C[n]) + (255,))
    return out


def box(g, x0, x1, y0, y1, z0, z1, n, own=None, oid=0):
    sx, sy, sz = g.shape
    x0, x1 = max(0, x0), min(sx, x1)
    y0, y1 = max(0, y0), min(sy, y1)
    z0, z1 = max(0, z0), min(sz, z1)
    if x0 >= x1 or y0 >= y1 or z0 >= z1:
        return
    g[x0:x1, y0:y1, z0:z1] = IDX[n]
    if own is not None and oid:
        own[x0:x1, y0:y1, z0:z1] = oid


def noise_box(g, x0, x1, y0, y1, z0, z1, n, alt, amount, seed, own=None, oid=0):
    rng = np.random.default_rng(seed)
    sx, sy, sz = g.shape
    x0, x1 = max(0, x0), min(sx, x1)
    y0, y1 = max(0, y0), min(sy, y1)
    z0, z1 = max(0, z0), min(sz, z1)
    for x in range(x0, x1):
        for y in range(y0, y1):
            for z in range(z0, z1):
                g[x, y, z] = IDX[alt if rng.random() < amount else n]
                if own is not None and oid:
                    own[x, y, z] = oid


def cyl(g, cx, cy, r, z0, z1, n, own=None, oid=0):
    for x in range(int(cx - r), int(cx + r) + 1):
        for y in range(int(cy - r), int(cy + r) + 1):
            if 0 <= x < SX and 0 <= y < SY and (x - cx) ** 2 + (y - cy) ** 2 <= r * r:
                g[x, y, z0:z1] = IDX[n]
                if own is not None and oid:
                    own[x, y, z0:z1] = oid


# ---------- props ----------
def wood_grain_top(g, x0, x1, y0, y1, z, seed=0):
    """Stripe a bar/table top with grain lines."""
    rng = np.random.default_rng(seed)
    box(g, x0, x1, y0, y1, z, z + 1, "wood_top")
    for x in range(x0 + 2, x1, 3 + int(rng.integers(0, 2))):
        if rng.random() < 0.7:
            box(g, x, x + 1, y0, y1, z, z + 1, "wood_grain")


def stool(g, x, y, own=None, oid=0):
    for lx, ly in ((x + 2, y + 2), (x + 10, y + 2), (x + 2, y + 10), (x + 10, y + 10)):
        box(g, lx, lx + 2, ly, ly + 2, 2, 14, "stool_leg", own, oid)
    box(g, x, x + 14, y, y + 14, 14, 15, "stool_top", own, oid)
    box(g, x + 1, x + 13, y + 1, y + 13, 15, 16, "stool_top", own, oid)


def table(g, x, y, w=28, d=16, h=14):
    # pedestal + thick top with grain
    cx, cy = x + w // 2, y + d // 2
    box(g, cx - 2, cx + 2, cy - 2, cy + 2, 2, h, "table_leg")
    wood_grain_top(g, x, x + w, y, y + d, h, seed=x * 3 + y)
    box(g, x, x + w, y, y + d, h + 1, h + 2, "wood_top")


def bottle(g, x, y, z, kind="bottle_g"):
    box(g, x, x + 2, y, y + 2, z, z + 5, kind)
    box(g, x, x + 2, y, y + 2, z + 5, z + 7, "glass")
    box(g, x, x + 2, y, y + 2, z + 1, z + 3, "liquid")


def lantern(g, x, y, z0=18):
    box(g, x, x + 6, y, y + 6, z0, z0 + 1, "metal_dk")
    box(g, x + 1, x + 5, y + 1, y + 5, z0 + 1, z0 + 7, "lantern")
    box(g, x + 2, x + 4, y + 2, y + 4, z0 + 2, z0 + 6, "lantern_hot")
    box(g, x, x + 6, y, y + 6, z0 + 7, z0 + 8, "metal")


def fireplace(g, frame=0):
    """Stone fireplace with logs + fire. frame 0..3 flickers the flame."""
    x0, x1, y0, y1 = FIRE_X0, FIRE_X1, FIRE_Y0, FIRE_Y1
    noise_box(g, x0, x1, y0, y1, 2, 38, "stone", "stone_dk", 0.25, 8)
    # brick courses
    for z in range(4, 36, 4):
        for x in range(x0, x1, 5):
            off = 2 if (z // 4) % 2 else 0
            box(g, x + off, min(x1, x + off + 4), y0, y1, z, z + 1, "stone_dk")
    # mantel
    box(g, x0 - 2, x1 + 2, y0, y1, 36, 39, "stone")
    box(g, x0 - 1, x1 + 1, y0, y1, 39, 40, "stone_dk")
    # hearth cavity
    box(g, x0 + 6, x1 - 6, y1 - 4, y1, 2, 22, "ash")
    # logs
    box(g, x0 + 10, x1 - 10, y1 - 3, y1 - 1, 3, 6, "log")
    box(g, x0 + 12, x1 - 14, y1 - 3, y1 - 1, 6, 8, "log")
    box(g, x0 + 10, x0 + 12, y1 - 3, y1 - 1, 3, 6, "log_end")
    # flame (flicker by frame) — large enough to read at HD
    h = 16 + (frame % 4) * 3
    inset = 1 if frame % 2 else 0
    box(g, x0 + 8 + inset, x1 - 8 - inset, y1 - 5, y1, 5, 5 + h, "fire_orange")
    box(g, x0 + 12, x1 - 12, y1 - 4, y1 - 1, 8, 8 + max(6, h - 3), "fire_hot")
    if frame % 2 == 0:
        box(g, x0 + 16, x1 - 16, y1 - 3, y1 - 1, 12, 14 + (frame % 3), "fire_hot")


def figure(g, own, oid, x, y, z, shirt, skin, hat, hatstyle="cap", facing="back",
           seated=True, drink=False, breath=0, drink_frame=0):
    """Large HD crew (~16×40×28 vox) so on-screen size matches concept C."""
    bob = (breath % 2)
    W, D = 16, 11  # torso footprint
    if seated:
        box(g, x, x + W, y, y + D, z, z + 7, "pants", own, oid)
        box(g, x + 2, x + 6, y + D - 1, y + D + 3, z - 9, z, "pants", own, oid)
        box(g, x + W - 6, x + W - 2, y + D - 1, y + D + 3, z - 9, z, "pants", own, oid)
        box(g, x + 2, x + 6, y + D + 1, y + D + 4, z - 10, z - 8, "metal_dk", own, oid)
        box(g, x + W - 6, x + W - 2, y + D + 1, y + D + 4, z - 10, z - 8, "metal_dk", own, oid)
        bz = z + 7 + bob
    else:
        box(g, x + 2, x + 6, y + 2, y + D - 1, z, z + 18, "pants", own, oid)
        box(g, x + W - 6, x + W - 2, y + 2, y + D - 1, z, z + 18, "pants", own, oid)
        box(g, x + 2, x + 6, y + 2, y + D - 1, z, z + 3, "metal_dk", own, oid)
        box(g, x + W - 6, x + W - 2, y + 2, y + D - 1, z, z + 3, "metal_dk", own, oid)
        bz = z + 18 + bob
    # torso + vest detail
    box(g, x, x + W, y, y + D, bz, bz + 16, shirt, own, oid)
    box(g, x + 3, x + W - 3, y + 2, y + D - 2, bz + 2, bz + 14, shirt, own, oid)
    box(g, x + W // 2 - 1, x + W // 2 + 1, y + 1, y + D - 1, bz, bz + 16, "shadow", own, oid)
    # arms
    box(g, x - 5, x, y + 2, y + D - 2, bz + 2, bz + 15, shirt, own, oid)
    box(g, x + W, x + W + 5, y + 2, y + D - 2, bz + 2, bz + 15, shirt, own, oid)
    hand_z = bz + 1 + (3 if drink and (drink_frame % 4) >= 2 else 0)
    box(g, x - 5, x, y + 3, y + D - 2, hand_z, hand_z + 3, skin, own, oid)
    box(g, x + W, x + W + 5, y + 3, y + D - 2, hand_z, hand_z + 3, skin, own, oid)
    if drink:
        gx = x + W + 1
        box(g, gx, gx + 3, y + 4, y + 7, hand_z + 3, hand_z + 9, "glass", own, oid)
        box(g, gx, gx + 3, y + 4, y + 7, hand_z + 3, hand_z + 6, "liquid", own, oid)
    # head + face
    box(g, x + 3, x + W - 3, y + 2, y + D - 2, bz + 16, bz + 26, skin, own, oid)
    if facing == "front":
        box(g, x + 5, x + 7, y + D - 2, y + D - 1, bz + 21, bz + 23, "eye", own, oid)
        box(g, x + W - 7, x + W - 5, y + D - 2, y + D - 1, bz + 21, bz + 23, "eye", own, oid)
        box(g, x + 7, x + W - 7, y + D - 2, y + D - 1, bz + 18, bz + 19, "shadow", own, oid)
    else:
        box(g, x + 5, x + W - 5, y, y + 2, bz + 20, bz + 24, hat, own, oid)
    if hatstyle == "cap":
        box(g, x + 3, x + W - 3, y + 2, y + D - 2, bz + 25, bz + 28, hat, own, oid)
        brim = 5 if facing == "front" else -3
        box(g, x + 3, x + W - 3, y + brim, y + brim + 3, bz + 25, bz + 26, hat, own, oid)
    elif hatstyle == "wide":
        box(g, x - 2, x + W + 2, y - 2, y + D + 2, bz + 25, bz + 27, hat, own, oid)
        box(g, x + 3, x + W - 3, y + 2, y + D - 2, bz + 27, bz + 30, hat, own, oid)
    elif hatstyle == "mohawk":
        box(g, x + W // 2 - 2, x + W // 2 + 2, y + 2, y + D - 2, bz + 26, bz + 34, hat, own, oid)
    elif hatstyle == "hood":
        box(g, x + 1, x + W - 1, y, y + D, bz + 16, bz + 28, hat, own, oid)
        fy = y + D - 2 if facing == "front" else y + 1
        box(g, x + 4, x + W - 4, fy, fy + 2, bz + 20, bz + 25, skin, own, oid)


def bake_cast_shadows(g):
    """Darken floor voxels under a hard upper-left key light (shadows fall down-right)."""
    # Light direction matching voxel_render.LIGHT ≈ (-0.45,-0.55,0.70) → shadow dir opposite xy
    L = np.array([-0.45, -0.55, 0.70], dtype=np.float64)
    L /= np.linalg.norm(L)
    inv = -L
    filled = g > 0
    # surface-ish: any filled with empty above
    top = filled.copy()
    top[:, :, :-1] &= ~filled[:, :, 1:]
    xs, ys, zs = np.nonzero(top & (np.arange(SZ)[None, None, :] >= 3))
    floor_z = 1
    for x, y, z in zip(xs.tolist(), ys.tolist(), zs.tolist()):
        t = (floor_z + 0.5 - z) / inv[2]
        if t <= 0:
            continue
        fx = int(round(x + inv[0] * t + 1.5))
        fy = int(round(y + inv[1] * t + 2.0))
        for dx in range(-1, 2):
            for dy in range(-1, 3):
                xx, yy = fx + dx, fy + dy
                if 0 <= xx < SX and 0 <= yy < SY and g[xx, yy, floor_z] in (IDX["floor_a"], IDX["floor_b"], IDX["floor_gap"], IDX["rug_a"], IDX["rug_b"], IDX["rug_trim"]):
                    g[xx, yy, floor_z] = IDX["shadow"]
                    if floor_z + 1 < SZ and g[xx, yy, floor_z + 1] in (IDX["floor_a"], IDX["floor_b"]):
                        g[xx, yy, 0] = IDX["shadow"]


def build_room(with_hireables=True, fire_frame=0, lantern_pulse=0, breath=0, drink_frame=0):
    g = np.zeros((SX, SY, SZ), np.int16)
    own = np.zeros((SX, SY, SZ), np.int16)
    # floor boards
    board = 8
    for x in range(0, SX, board):
        n = "floor_a" if (x // board) % 2 == 0 else "floor_b"
        box(g, x, min(SX, x + board), 0, SY, 0, 2, n)
        if x > 0:
            box(g, x, x + 1, 0, SY, 1, 2, "floor_gap")
        # nail heads / grain ticks
        for y in range(4, SY - 4, 14):
            box(g, x + board // 2, x + board // 2 + 1, y, y + 1, 1, 2, "floor_gap")
    # back wall + side walls
    noise_box(g, 0, SX, 0, 8, 2, 55, "wall", "wall_dark", 0.18, 4)
    box(g, 0, 4, 0, SY, 2, 55, "wall_dark")
    box(g, SX - 4, SX, 0, SY, 2, 55, "wall_dark")
    # vertical studs
    for x in range(12, SX - 20, 36):
        box(g, x, x + 3, 4, 8, 2, 55, "beam")
    # ceiling beams — only over the back half so the seating reads clear
    for y in (18, 42):
        box(g, 8, SX - 8, y, y + 4, 58, 62, "beam")
    # rug under tables
    box(g, int(30 * SX_S), int(85 * SX_S), int(36 * SY_S), int(58 * SY_S), 2, 3, "rug_a")
    for i in range(0, int(55 * SX_S), 6):
        n = "rug_b" if (i // 6) % 2 else "rug_a"
        box(g, int(30 * SX_S) + i, int(30 * SX_S) + i + 3,
            int(36 * SY_S), int(58 * SY_S), 2, 3, n)
    box(g, int(30 * SX_S), int(85 * SX_S), int(36 * SY_S), int(36 * SY_S) + 1, 2, 3, "rug_trim")
    box(g, int(30 * SX_S), int(85 * SX_S), int(58 * SY_S) - 1, int(58 * SY_S), 2, 3, "rug_trim")

    fireplace(g, frame=fire_frame)

    # bar counter (short left) with wood grain + back shelves
    bx0, bx1 = int(6 * SX_S), int(62 * SX_S)
    by0, by1 = int(12 * SY_S), int(20 * SY_S)
    noise_box(g, bx0, bx1, by0, by1, 2, 14, "wood_dk", "wood_grain", 0.15, 9)
    wood_grain_top(g, bx0 - 1, bx1 + 1, by0 - 1, by1 + 1, 14, seed=9)
    # back bar shelves with bottles
    box(g, bx0, bx1, 4, 8, 16, 18, "wood_mid")
    box(g, bx0, bx1, 4, 8, 24, 26, "wood_mid")
    for i, x in enumerate(range(bx0 + 4, bx1 - 4, 4)):
        kind = ["bottle_g", "bottle_a", "bottle_b"][i % 3]
        bottle(g, x, 5, 18, kind)
        if i % 2 == 0:
            bottle(g, x + 1, 6, 26, ["bottle_a", "bottle_b", "bottle_g"][i % 3])
    # glasses on bar top
    for x in range(bx0 + 8, bx1 - 8, 10):
        box(g, x, x + 2, by1 - 3, by1 - 1, 15, 18, "glass")
        box(g, x, x + 2, by1 - 3, by1 - 1, 15, 16, "liquid")
    # bar stools
    for x in (int(12 * SX_S), int(32 * SX_S), int(50 * SX_S)):
        stool(g, x, int(21 * SY_S))

    # tables + lanterns
    for (tx, ty) in ((int(22 * SX_S), int(44 * SY_S)), (int(52 * SX_S), int(40 * SY_S))):
        table(g, tx, ty, w=int(22 * SX_S), d=int(14 * SY_S), h=16)
        # lantern on table — pulse by swapping hot core size
        lx, ly = tx + int(7 * SX_S), ty + int(3 * SY_S)
        lantern(g, lx, ly, z0=18)
        if lantern_pulse % 2 == 0:
            box(g, lx + 1, lx + 5, ly + 1, ly + 5, 20, 24, "lantern_hot")
            box(g, lx + 2, lx + 4, ly + 2, ly + 4, 21, 23, "fire_hot")
        else:
            box(g, lx + 2, lx + 4, ly + 2, ly + 4, 20, 22, "lantern")

    # empty stools at table seats + hireable stools
    for (x, y) in ((int(16 * SX_S), int(46 * SY_S)),) + tuple((s[0], s[1]) for s in SEATS_VOX[1:]):
        stool(g, x, y)
    stool(g, SEATS_VOX[0][0], SEATS_VOX[0][1])

    # crates
    box(g, int(4 * SX_S), int(14 * SX_S), int(54 * SY_S), int(64 * SY_S), 2, 10, "crate")
    box(g, int(5 * SX_S), int(13 * SX_S), int(55 * SY_S), int(63 * SY_S), 10, 11, "crate_dk")
    box(g, int(14 * SX_S), int(22 * SX_S), int(56 * SY_S), int(64 * SY_S), 2, 7, "crate")

    # mounted skull on back wall (left of fireplace)
    sx0 = FIRE_X0 - 22
    box(g, sx0, sx0 + 12, 4, 8, 30, 40, "skull")
    box(g, sx0 + 3, sx0 + 5, 7, 8, 34, 36, "skull_dk")
    box(g, sx0 + 7, sx0 + 9, 7, 8, 34, 36, "skull_dk")
    box(g, sx0 + 5, sx0 + 7, 7, 8, 31, 33, "skull_dk")
    box(g, sx0 - 4, sx0, 5, 7, 36, 42, "skull_dk")
    box(g, sx0 + 12, sx0 + 16, 5, 7, 36, 42, "skull_dk")

    # dartboard on right-back wall (still left of card strip in screen space)
    dx0 = min(SX - 20, FIRE_X1 + 14)
    cyl(g, dx0 + 6, 8, 7, 28, 30, "dart")
    cyl(g, dx0 + 6, 8, 7, 30, 31, "dart_face")
    cyl(g, dx0 + 6, 8, 5, 30, 31, "dart_ring")
    cyl(g, dx0 + 6, 8, 2, 30, 31, "dart_face")
    box(g, dx0 + 5, dx0 + 7, 7, 8, 31, 34, "metal_dk")  # dart stuck in

    # bartender (not hireable, own=0)
    figure(g, own, 0, int(26 * SX_S), 8, 2,
           "bt_shirt", "bt_skin", "bt_hat", hatstyle="hood", facing="front", seated=False, breath=breath)

    pals = [
        ("c0_shirt", "c0_skin", "c0_hat", "wide", "back", False),
        ("c1_shirt", "c1_skin", "c1_hat", "wide", "front", True),
        ("c2_shirt", "c2_skin", "c2_hat", "cap", "back", True),
        ("c3_shirt", "c3_skin", "c3_hat", "mohawk", "front", False),
    ]
    if with_hireables:
        for i, (st, p) in enumerate(zip(SEATS_VOX, pals), 1):
            shirt, skin, hat, hs, facing, drink = p
            figure(g, own, i, st[0], st[1], st[2], shirt, skin, hat,
                   hatstyle=hs, facing=facing, seated=True, drink=drink,
                   breath=breath, drink_frame=drink_frame)

    bake_cast_shadows(g)
    return g, own


def canvas_size(tilt, ppv=PPV):
    r = math.hypot(SX, SY) / 2
    return 2 * int(math.ceil((r + SZ * math.sin(math.radians(tilt))) * ppv)) + 16


def render_scene(g, own, tilt, heading=HEADING, ppv=PPV, light_only=False):
    cols = colors_rgba(light_only=light_only)
    canvas = canvas_size(tilt, ppv)
    # owner must match grid; 0 is valid (background) — render_frame uses owner ids as-is
    img, own_img = render_frame(g, cols, heading_deg=heading, ppv=ppv, tilt=tilt,
                                canvas=canvas, owner=own, hd=True)
    return img, own_img, canvas


def place_on_room(img, own_img, room= (1280, 720)):
    """Centre the rendered diorama onto a 1280×720 plate; return rgb, own, em mask."""
    W, H = room
    # content bbox
    a = img[:, :, 3] > 0
    if not a.any():
        return np.zeros((H, W, 3), np.uint8), np.zeros((H, W), np.int16), np.zeros((H, W), bool)
    ys, xs = np.where(a)
    x0, x1 = int(xs.min()), int(xs.max()) + 1
    y0, y1 = int(ys.min()), int(ys.max()) + 1
    crop = img[y0:y1, x0:x1]
    own_c = own_img[y0:y1, x0:x1]
    ch, cw = crop.shape[:2]
    # scale to fit with small margin
    margin = 12
    scale = min((W - 2 * margin) / cw, (H - 2 * margin) / ch)
    if scale > 1.0:
        scale = min(scale, 1.55)
    nw, nh = max(1, int(cw * scale)), max(1, int(ch * scale))
    crop_r = Image.fromarray(crop).resize((nw, nh), Image.Resampling.NEAREST)
    own_r = Image.fromarray(own_c.astype(np.int32)).resize((nw, nh), Image.Resampling.NEAREST)
    crop_r = np.array(crop_r)
    own_r = np.array(own_r).astype(np.int16)
    out = np.zeros((H, W, 4), np.uint8)
    ow = np.zeros((H, W), np.int16)
    # place: bias slightly up so floor isn't cropped; centre x
    px = (W - nw) // 2
    py = max(8, (H - nh) // 2 - 20)
    out[py:py + nh, px:px + nw] = crop_r
    ow[py:py + nh, px:px + nw] = own_r
    # emissive: bright orange/white-ish pixels (fire/lantern)
    rgb = out[:, :, :3].astype(np.int16)
    em = (out[:, :, 3] > 0) & (rgb[:, :, 0] > 180) & (rgb[:, :, 1] > 80) & (rgb[:, :, 0] > rgb[:, :, 2] + 30)
    # also white_hot
    em |= (out[:, :, 3] > 0) & (rgb[:, :, 0] > 240) & (rgb[:, :, 1] > 220) & (rgb[:, :, 2] > 180)
    return out, ow, em, (px, py, nw, nh, scale)


def grade_with_glow(rgba, em):
    """Mild #512b11 night: keep material colour, warm the shadows, lift crew."""
    rgb = rgba[:, :, :3].astype(np.float32)
    tint = np.array([0x51, 0x2b, 0x11], dtype=np.float32)
    # Preserve more of the source than saloon_iso.night_grade so HD detail reads
    lum = (rgb @ np.array([0.299, 0.587, 0.114], dtype=np.float32))[..., None]
    graded = np.clip(rgb * 0.55 + (lum * tint[None, None, :] / 80.0) * 0.45, 0, 255)
    # warm uplift near emissives (fire/lantern pools)
    if em.any():
        heat = np.array(Image.fromarray((em.astype(np.uint8) * 255)).filter(
            ImageFilter.GaussianBlur(28))).astype(np.float32) / 255.0
        warm = np.array([1.35, 1.05, 0.70], dtype=np.float32)
        graded = np.clip(graded * (1.0 + heat[..., None] * 0.55) * (0.85 + 0.15 * warm), 0, 255)
    body = (rgba[:, :, 3] > 0) & ~em
    graded[body] = np.clip(graded[body] * 1.35 + 22.0, 0, 255)
    e = np.zeros_like(graded)
    e[em] = np.maximum(rgb[em], graded[em])
    glow = np.array(Image.fromarray(np.clip(e, 0, 255).astype(np.uint8)).filter(
        ImageFilter.GaussianBlur(12))).astype(np.float32)
    out = np.clip(graded + glow * 1.25, 0, 255).astype(np.uint8)
    out[em] = np.clip(rgb[em] * 0.55 + out[em] * 0.45 + 30, 0, 255).astype(np.uint8)
    return out


def lights_overlay(rgba, em):
    out = np.zeros_like(rgba)
    out[em, :3] = rgba[em, :3]
    out[em, 3] = 255
    bloom = np.array(Image.fromarray(out).filter(ImageFilter.GaussianBlur(8))).astype(np.float32)
    bloom[..., 3] *= 0.55
    return Image.alpha_composite(
        Image.fromarray(np.clip(bloom, 0, 255).astype(np.uint8), "RGBA"),
        Image.fromarray(out, "RGBA"))


def variant_sprite(base_rgba, mode):
    im = Image.fromarray(base_rgba).convert("RGBA")
    if mode == "idle":
        return im
    a = np.array(im).astype(np.float32)
    if mode == "dim":
        a[..., :3] *= 0.42
        a[..., 3] *= 0.85
        return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA")
    mask = a[..., 3] > 10
    dil = np.array(Image.fromarray((mask.astype(np.uint8) * 255)).filter(ImageFilter.MaxFilter(9))) > 0
    a[dil & ~mask] = (225, 180, 65, 255)
    a[mask, :3] = np.clip(a[mask, :3] * 1.15, 0, 255)
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA")


def crop_owner(rgba, own, owner_id, pad=10):
    ys, xs = np.where(own == owner_id)
    if len(xs) == 0:
        return None, None
    x0, x1 = max(0, int(xs.min()) - pad), min(rgba.shape[1], int(xs.max()) + pad + 1)
    y0, y1 = max(0, int(ys.min()) - pad), min(rgba.shape[0], int(ys.max()) + pad + 1)
    spr = rgba[y0:y1, x0:x1].copy()
    spr[own[y0:y1, x0:x1] != owner_id, 3] = 0
    return spr, (x0, y0)


def project_anchor(seat_vox, place, canvas, tilt, heading=HEADING, ppv=PPV):
    """Approximate head anchor in room pixels from voxel seat + place transform."""
    # Use render_frame's project convention relative to grid centre
    sx, sy, sz = seat_vox[0] + 5, seat_vox[1] + 3, seat_vox[2] + 28  # head
    cx, cy = SX / 2.0, SY / 2.0
    a = math.radians(heading)
    ca, sa = math.cos(a), math.sin(a)
    t = math.radians(tilt)
    ct, st = math.cos(t), math.sin(t)
    x, y, z = sx - cx, sy - cy, sz
    wx, wy = x * ca - y * sa, x * sa + y * ca
    px = wx * ppv + canvas / 2
    py = (wy * ct - z * st) * ppv + canvas / 2
    # map through the same crop/scale/place as place_on_room — approximate via
    # stored place tuple (px0, py0, nw, nh, scale) AND we need crop origin.
    # Caller passes place_info with crop offsets.
    return px, py


def bake(tilt=TILT_GAME, write_assets=True):
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(CONCEPT_HD, exist_ok=True)

    # Full scene with hireables (for shadows on floor + sprite extract)
    g_full, own_full = build_room(True, fire_frame=0, lantern_pulse=0, breath=0)
    img_full, own_img, canvas = render_scene(g_full, own_full, tilt)
    rgba_full, ow, em, place = place_on_room(img_full, own_img)
    graded = grade_with_glow(rgba_full, em)

    # Background without hireables (stools remain)
    g_bg, own_bg = build_room(False, fire_frame=0, lantern_pulse=0, breath=0)
    img_bg, own_bg_img, _ = render_scene(g_bg, own_bg, tilt)
    rgba_bg, ow_bg, em_bg, _ = place_on_room(img_bg, own_bg_img)
    graded_bg = grade_with_glow(rgba_bg, em_bg)

    # Room plate: bg grade; hireable pixels already absent
    room_rgb = graded_bg.copy()
    # Keep cast-shadow silhouettes from full render under hireable footprints
    hire = ow > 0
    # where full has shadow-dark floor under a hireable, bg already has stool — OK
    room_path = os.path.join(OUT, "saloon_room.png")
    lights_path = os.path.join(OUT, "saloon_room_lights.png")
    Image.fromarray(room_rgb, "RGB").save(room_path)
    lights_overlay(
        np.concatenate([graded_bg, np.full((*graded_bg.shape[:2], 1), 255, np.uint8)], -1),
        em_bg | em  # include fire from either
    ).save(lights_path)
    # Better lights from full emissive on bg geometry
    lights_overlay(
        np.concatenate([np.maximum(graded_bg, graded), np.full((*graded.shape[:2], 1), 255, np.uint8)], -1),
        em_bg | em
    ).save(lights_path)
    write_import(room_path); write_import(lights_path)

    # Sprite sheet from graded full (crew only)
    rgba_crew = np.concatenate([
        graded,
        np.where(ow > 0, 255, 0).astype(np.uint8)[..., None],
    ], -1)

    seats_out = []
    for slot, sid in enumerate(SEAT_IDS):
        owner = slot + 1
        spr, local = crop_owner(rgba_crew, ow, owner, pad=12)
        if spr is None:
            print("WARN missing", sid); continue
        idle = variant_sprite(spr, "idle")
        hi = variant_sprite(spr, "highlight")
        dim = variant_sprite(spr, "dim")
        nw, nh = idle.size
        pos = [int(local[0]), int(local[1])]
        for im, name in ((idle, f"crew_{sid}_idle.png"),
                         (hi, f"crew_{sid}_highlight.png"),
                         (dim, f"crew_{sid}_dim.png")):
            path = os.path.join(OUT, name); im.save(path); write_import(path)
        # anchor near head (top-centre of sprite)
        ax = pos[0] + nw // 2
        ay = pos[1] + max(8, nh // 5)
        hw = max(64, nw + 28); hh = max(64, nh + 28)
        hx = int(np.clip(pos[0] + nw / 2 - hw / 2, 0, 1280 - hw))
        hy = int(np.clip(pos[1] + nh / 2 - hh / 2, 0, 720 - hh))
        cx = pos[0] + nw // 2
        side = "right" if cx < 640 else "left"
        seats_out.append({
            "id": sid, "slot": slot, "pos": pos, "z": int(pos[1] + nh),
            "hit_rect": [hx, hy, hw, hh], "anchor": [ax, ay], "card_side": side,
            "sprites": {
                "idle": f"res://art/saloon/crew_{sid}_idle.png",
                "highlight": f"res://art/saloon/crew_{sid}_highlight.png",
                "dim": f"res://art/saloon/crew_{sid}_dim.png",
            },
        })

    # --- cheap animation loops ---
    anims = {}
    # Fire flicker 4 frames (lights-only strip)
    fire_frames = []
    for fi in range(4):
        gf, of = build_room(False, fire_frame=fi, lantern_pulse=0, breath=0)
        im, oi, _ = render_scene(gf, of, tilt, light_only=True)
        rgba, _, emf, _ = place_on_room(im, oi)
        # extract fireplace region
        fx, fy, fw, fh = 560, 40, 300, 220
        fr_arr = np.concatenate([
            rgba[:, :, :3], np.where(emf, 255, 0).astype(np.uint8)[..., None]
        ], -1)
        fire_frames.append(Image.fromarray(fr_arr[fy:fy + fh, fx:fx + fw]))
    # lantern pulse 2 frames — full lights plate variants
    # crew breath/drink strips per seat
    for slot, sid in enumerate(SEAT_IDS):
        frames = []
        drink = sid in ("table_left", "table_mid")
        for bi in range(4):
            gf, of = build_room(True, fire_frame=0, lantern_pulse=bi, breath=bi,
                                drink_frame=bi if drink else 0)
            im, oi, _ = render_scene(gf, of, tilt)
            rgba, ow2, em2, _ = place_on_room(im, oi)
            graded2 = grade_with_glow(rgba, em2)
            rgba_c = np.concatenate([graded2, np.where(ow2 == slot + 1, 255, 0).astype(np.uint8)[..., None]], -1)
            # crop to that seat's idle bbox
            seat = seats_out[slot]
            x, y = seat["pos"]; idle_p = Image.open(os.path.join(OUT, f"crew_{sid}_idle.png"))
            w, h = idle_p.size
            crop = rgba_c[y:y + h, x:x + w].copy()
            # ensure alpha only this owner
            frames.append(Image.fromarray(crop, "RGBA"))
        # pack horizontal strip
        strip = Image.new("RGBA", (frames[0].width * len(frames), frames[0].height))
        for i, fr in enumerate(frames):
            strip.paste(fr, (i * fr.width, 0))
        sp = os.path.join(OUT, f"crew_{sid}_idle_anim.png")
        strip.save(sp); write_import(sp)
        seats_out[slot]["sprites"]["idle_anim"] = f"res://art/saloon/crew_{sid}_idle_anim.png"
        seats_out[slot]["anim"] = {"idle_frames": 4, "idle_frame_w": frames[0].width, "fps": 4}
        anims[f"crew_{sid}_idle"] = sp

    # fire anim strip
    if fire_frames and fire_frames[0] is not None:
        fh = fire_frames[0].height; fw = fire_frames[0].width
        fire_strip = Image.new("RGBA", (fw * len(fire_frames), fh))
        for i, fr in enumerate(fire_frames):
            fire_strip.paste(fr, (i * fw, 0))
        fp = os.path.join(OUT, "fireplace_flicker.png")
        fire_strip.save(fp); write_import(fp)
        anims["fireplace_flicker"] = fp

    # lantern pulse: 2 full lights plates
    for li in range(2):
        gf, of = build_room(False, fire_frame=0, lantern_pulse=li, breath=0)
        im, oi, _ = render_scene(gf, of, tilt)
        rgba, _, eml, _ = place_on_room(im, oi)
        lights_overlay(np.concatenate([rgba[:, :, :3], np.full((*rgba.shape[:2], 1), 255, np.uint8)], -1), eml).save(
            os.path.join(OUT, f"saloon_room_lights_pulse{li}.png"))
        write_import(os.path.join(OUT, f"saloon_room_lights_pulse{li}.png"))
    anims["lantern_pulse"] = [f"res://art/saloon/saloon_room_lights_pulse{li}.png" for li in range(2)]

    # fireplace_rect: measure non-black structure near centre-back in room plate
    # Keep the proven clear rect so cards at x=900 never overlap.
    fire_rect = [560, 50, 280, 180]
    # Verify against actual emissive bbox if available
    ys, xs = np.where(em_bg | em)
    if len(xs):
        fx0, fx1 = int(xs.min()), int(xs.max())
        fy0, fy1 = int(ys.min()), int(ys.max())
        # structure-ish: clamp width to stay < 900
        fx1 = min(fx1, 880)
        fx0 = max(fx0, 500)
        if fx1 > fx0 and fy1 > fy0:
            fire_rect = [fx0, max(20, fy0 - 10), fx1 - fx0, min(220, fy1 - fy0 + 20)]
            # ensure clear of card_right
            if fire_rect[0] + fire_rect[2] > 900:
                fire_rect[2] = 900 - fire_rect[0] - 8

    meta = {
        "room_size": [1280, 720],
        "fireplace_rect": fire_rect,
        "card_left_rect": [24, 72, 356, 448],
        "card_right_rect": [900, 72, 356, 448],
        "camera": f"voxel_render HD ppv={PPV} tilt={tilt}° heading={HEADING}° (PR #70 game camera)" if tilt == TILT_GAME
                  else f"voxel_render HD ppv={PPV} tilt={tilt}° heading={HEADING}° (concept-near)",
        "tilt_deg": tilt,
        "px_per_voxel": PPV,
        "hd": True,
        "sun": "upper-left → hard shadows down-right (baked into floor voxels)",
        "night": "#512b11 world grade; fire/lanterns untinted on lights plate",
        "background": "res://art/saloon/saloon_room.png",
        "lights": "res://art/saloon/saloon_room_lights.png",
        "lights_note": "Fireplace + lantern glow. Composite above world night grade; do not CanvasModulate.",
        "animations": {
            "fireplace_flicker": {
                "sheet": "res://art/saloon/fireplace_flicker.png",
                "frames": 4, "fps": 8,
            },
            "lantern_pulse": {
                "plates": anims["lantern_pulse"],
                "fps": 2,
            },
        },
        "seats": seats_out,
        "card_side_rule": "Per seat: opens away from the figure. Left/center → right. Fireplace stays clear.",
        "ui_colours_needed": {
            "PANEL": "#181d20", "PANEL_BODY": "#24292f", "HEADER": "#1e1b14",
            "ACCENT_GOLD": "#e1b441", "HAIRLINE": "#3a3d3c", "TEXT": "#ccc8bc",
            "TEXT_DIM": "#8a8a84", "RARITY_COMMON": "#8a8a84", "RARITY_UNCOMMON": "#5aa05a",
            "RARITY_RARE": "#4a7ac8", "RARITY_EPIC": "#9a5ac8", "RARITY_LEGENDARY": "#e1b441",
            "RARITY_MYTHIC": "#c4473f", "NIGHT_WORLD": "#512b11",
        },
        "ui_colours_note": "Do not add these to tuning.gd from this PR.",
    }
    if write_assets:
        json.dump(meta, open(os.path.join(OUT, "saloon_room.json"), "w"), indent=1)
    print("baked tilt", tilt, [(s["id"], s["pos"], s["card_side"], s["hit_rect"][2:]) for s in seats_out])
    print("fire_rect", fire_rect, "asset_bytes", sum(
        os.path.getsize(os.path.join(OUT, f)) for f in os.listdir(OUT) if f.endswith(".png")))
    return meta, graded_bg, graded, ow, em_bg | em


if __name__ == "__main__":
    tilt = float(sys.argv[1]) if len(sys.argv) > 1 else TILT_GAME
    bake(tilt=tilt)
