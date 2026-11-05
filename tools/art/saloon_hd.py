#!/usr/bin/env python3
"""Saloon C — high-detail night voxel diorama.

voxel_render HD (ppv≥2, smooth light + AO) at PR #70 tilt 45°.
Strong #512b11 night grade; fireplace + lanterns are the hero lights;
upper-left key is dim moonlight with hard cast shadows.
Crew modelled at high voxel density so a 2× crop reads as a hand-detailed
character, then framed so on-screen size matches a0c1213 (~84×230 opaque).
"""
from __future__ import annotations
import glob, json, math, os, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import voxel_render as vr
from voxel_render import write_import, render_frame
from palette import PALETTE
from saloon_iso import night_grade, ui, GOLD, F_title

OUT = os.path.join(HERE, "..", "..", "art", "saloon")
CONCEPT_HD = "/workspace/concepts/saloon_hd"

TILT_GAME = 45.0
TILT_CONCEPT = 52.0
PPV = 3
HEADING = 0.0  # +x screen-right; bar left, fire centre-back

# Dense room; layout scaled from concept C (160×72)
SX, SY, SZ = 340, 190, 110
SX_S, SY_S = SX / 160.0, SY / 72.0

SEAT_IDS = ["bar_left", "table_left", "table_mid", "table_right"]
# Seated hip height on tall stools
SEATS_VOX = [
    (int(24 * SX_S), int(22 * SY_S), 18),
    (int(38 * SX_S), int(50 * SY_S), 18),
    (int(58 * SX_S), int(46 * SY_S), 18),
    (int(78 * SX_S), int(52 * SY_S), 18),
]
FIRE_X0, FIRE_X1 = int(80 * SX_S), int(104 * SX_S)
FIRE_Y0, FIRE_Y1 = 8, 26

# Target opaque crew size from a0c1213
TARGET_CREW_H = 230
TARGET_CREW_W = 84

C = {
    "floor_a": (78, 58, 42), "floor_b": (68, 50, 36), "floor_gap": (48, 34, 24),
    "wall": (62, 50, 42), "wall_dark": (44, 34, 28), "beam": (50, 36, 26),
    "beam_bracket": (110, 90, 55),
    "wood_dk": (98, 70, 46), "wood_mid": (120, 88, 58), "wood_top": (148, 112, 76),
    "wood_grain": (88, 62, 40), "wood_hi": (168, 128, 90),
    "brass": (168, 130, 58), "brass_dk": (110, 82, 36),
    "stool_top": (112, 78, 50), "stool_leg": (64, 46, 34),
    "table_top": (132, 100, 68), "table_leg": (72, 52, 38),
    "stone": (92, 86, 80), "stone_lt": (118, 112, 104), "stone_dk": (64, 60, 56),
    "mortar": (48, 44, 40), "ash": (30, 22, 16),
    "log": (58, 38, 24), "log_end": (132, 100, 62), "ember": PALETTE["orange"],
    "fire_orange": PALETTE["orange"], "fire_hot": PALETTE["white_hot"],
    "lantern": PALETTE["orange"], "lantern_hot": PALETTE["white_hot"],
    "lantern_frame": (70, 60, 48), "lantern_glass": (160, 170, 150),
    "bottle_g": (48, 140, 72), "bottle_a": (160, 78, 36), "bottle_b": (70, 90, 180),
    "bottle_r": (180, 48, 52), "cork": (140, 110, 70),
    "glass": (170, 200, 210), "liquid_a": (180, 120, 48), "liquid_b": (90, 40, 30),
    "rug_a": (104, 42, 38), "rug_b": (78, 30, 28), "rug_trim": (150, 110, 55),
    "rug_pat": (130, 70, 50),
    "crate": (112, 82, 50), "crate_dk": (84, 60, 38), "crate_band": (70, 55, 40),
    "skull": (200, 190, 165), "skull_dk": (110, 100, 85), "horn": (180, 170, 145),
    "dart": (140, 100, 62), "dart_face": (210, 200, 180), "dart_ring": (150, 45, 38),
    "metal": (88, 86, 80), "metal_dk": (42, 40, 38),
    "pants": (44, 42, 40), "pants_hi": (58, 56, 52), "belt": (30, 24, 18),
    "boot": (36, 28, 22), "boot_hi": (55, 42, 32),
    # crew palettes
    "c0_shirt": (62, 92, 118), "c0_shirt_dk": (42, 68, 90), "c0_skin": (198, 156, 114),
    "c0_skin_dk": (150, 110, 78), "c0_hat": (118, 42, 36), "c0_hair": (40, 28, 22),
    "c1_shirt": (158, 132, 58), "c1_shirt_dk": (120, 98, 40), "c1_skin": (168, 122, 86),
    "c1_skin_dk": (120, 84, 56), "c1_hat": (188, 188, 178), "c1_hair": (90, 70, 50),
    "c2_shirt": (68, 98, 62), "c2_shirt_dk": (48, 72, 44), "c2_skin": (140, 100, 72),
    "c2_skin_dk": (100, 70, 48), "c2_hat": (96, 80, 56), "c2_hair": (30, 22, 16),
    "c3_shirt": (128, 56, 48), "c3_shirt_dk": (96, 40, 34), "c3_skin": (210, 172, 134),
    "c3_skin_dk": (160, 120, 90), "c3_hat": (160, 48, 40), "c3_hair": (160, 48, 40),
    "bt_shirt": (86, 52, 46), "bt_shirt_dk": (64, 38, 34), "bt_skin": (196, 150, 112),
    "bt_skin_dk": (148, 108, 76), "bt_hat": (68, 48, 40), "bt_hair": (40, 30, 24),
    "eye": (22, 18, 14), "eye_w": (220, 210, 195), "nose": (160, 110, 80),
    "beard": (55, 40, 30), "shadow": (22, 14, 10),
}
NAMES = ["_"] + list(C)
IDX = {n: i for i, n in enumerate(NAMES)}
EMISSIVE_NAMES = {"fire_orange", "fire_hot", "lantern", "lantern_hot", "ember"}


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
    x0, x1 = max(0, int(x0)), min(sx, int(x1))
    y0, y1 = max(0, int(y0)), min(sy, int(y1))
    z0, z1 = max(0, int(z0)), min(sz, int(z1))
    if x0 >= x1 or y0 >= y1 or z0 >= z1:
        return
    g[x0:x1, y0:y1, z0:z1] = IDX[n]
    if own is not None and oid:
        own[x0:x1, y0:y1, z0:z1] = oid


def noise_box(g, x0, x1, y0, y1, z0, z1, n, alt, amount, seed, own=None, oid=0):
    rng = np.random.default_rng(seed)
    sx, sy, sz = g.shape
    x0, x1 = max(0, int(x0)), min(sx, int(x1))
    y0, y1 = max(0, int(y0)), min(sy, int(y1))
    z0, z1 = max(0, int(z0)), min(sz, int(z1))
    for x in range(x0, x1):
        for y in range(y0, y1):
            for z in range(z0, z1):
                g[x, y, z] = IDX[alt if rng.random() < amount else n]
                if own is not None and oid:
                    own[x, y, z] = oid


def cyl(g, cx, cy, r, z0, z1, n, own=None, oid=0):
    for x in range(int(cx - r), int(cx + r) + 1):
        for y in range(int(cy - r), int(cy + r) + 1):
            if 0 <= x < SX and 0 <= y < SY and (x - cx) ** 2 + (y - cy) ** 2 <= r * r + 0.2:
                g[x, y, z0:z1] = IDX[n]
                if own is not None and oid:
                    own[x, y, z0:z1] = oid


def wood_grain_top(g, x0, x1, y0, y1, z, seed=0):
    rng = np.random.default_rng(seed)
    box(g, x0, x1, y0, y1, z, z + 1, "wood_top")
    for x in range(x0 + 1, x1, 2 + int(rng.integers(0, 2))):
        if rng.random() < 0.75:
            box(g, x, x + 1, y0, y1, z, z + 1, "wood_grain")
        if rng.random() < 0.25:
            box(g, x, min(x1, x + 2), y0 + 1, y1 - 1, z, z + 1, "wood_hi")


# ---------- furniture / props ----------
def stool(g, x, y):
    for lx, ly in ((x + 2, y + 2), (x + 12, y + 2), (x + 2, y + 12), (x + 12, y + 12)):
        box(g, lx, lx + 2, ly, ly + 2, 2, 17, "stool_leg")
    # ring brace
    box(g, x + 3, x + 13, y + 3, y + 13, 8, 9, "stool_leg")
    box(g, x, x + 16, y, y + 16, 17, 18, "stool_top")
    box(g, x + 1, x + 15, y + 1, y + 15, 18, 19, "stool_top")
    wood_grain_top(g, x + 2, x + 14, y + 2, y + 14, 18, seed=x + y)


def table(g, x, y, w=36, d=22, h=18):
    cx, cy = x + w // 2, y + d // 2
    box(g, cx - 3, cx + 3, cy - 3, cy + 3, 2, h, "table_leg")
    box(g, cx - 5, cx + 5, cy - 1, cy + 1, 8, 9, "table_leg")
    wood_grain_top(g, x, x + w, y, y + d, h, seed=x * 5 + y)
    box(g, x, x + w, y, y + d, h + 1, h + 2, "wood_top")
    # edge lip
    box(g, x, x + w, y, y + 1, h, h + 2, "wood_dk")
    box(g, x, x + w, y + d - 1, y + d, h, h + 2, "wood_dk")


def bottle(g, x, y, z, kind="bottle_g"):
    box(g, x, x + 3, y, y + 3, z, z + 7, kind)
    box(g, x + 1, x + 2, y + 1, y + 2, z + 7, z + 10, "glass")
    box(g, x + 1, x + 2, y + 1, y + 2, z + 10, z + 11, "cork")
    box(g, x, x + 3, y, y + 3, z + 1, z + 4, "liquid_a" if kind != "bottle_r" else "liquid_b")


def glass_mug(g, x, y, z, own=None, oid=0, liquid="liquid_a"):
    box(g, x, x + 4, y, y + 4, z, z + 6, "glass", own, oid)
    box(g, x + 1, x + 3, y + 1, y + 3, z + 1, z + 4, liquid, own, oid)
    # handle
    box(g, x + 4, x + 5, y + 1, y + 3, z + 2, z + 5, "glass", own, oid)


def lantern(g, x, y, z0=20, pulse=0):
    # metal frame with glass panes + bright core
    box(g, x, x + 10, y, y + 10, z0, z0 + 1, "lantern_frame")
    box(g, x, x + 10, y, y + 10, z0 + 10, z0 + 11, "lantern_frame")
    for ox, oy in ((0, 0), (9, 0), (0, 9), (9, 9)):
        box(g, x + ox, x + ox + 1, y + oy, y + oy + 1, z0, z0 + 11, "lantern_frame")
    box(g, x + 1, x + 9, y + 1, y + 2, z0 + 1, z0 + 10, "lantern_glass")
    box(g, x + 1, x + 9, y + 8, y + 9, z0 + 1, z0 + 10, "lantern_glass")
    box(g, x + 1, x + 2, y + 1, y + 9, z0 + 1, z0 + 10, "lantern_glass")
    box(g, x + 8, x + 9, y + 1, y + 9, z0 + 1, z0 + 10, "lantern_glass")
    if pulse % 2 == 0:
        box(g, x + 2, x + 8, y + 2, y + 8, z0 + 2, z0 + 9, "lantern")
        box(g, x + 3, x + 7, y + 3, y + 7, z0 + 3, z0 + 8, "lantern_hot")
        box(g, x + 4, x + 6, y + 4, y + 6, z0 + 4, z0 + 7, "fire_hot")
    else:
        box(g, x + 3, x + 7, y + 3, y + 7, z0 + 3, z0 + 8, "lantern")
        box(g, x + 4, x + 6, y + 4, y + 6, z0 + 4, z0 + 7, "lantern_hot")
    box(g, x + 4, x + 6, y + 4, y + 6, z0 + 11, z0 + 14, "metal")



def fireplace(g, frame=0):
    x0, x1, y0, y1 = FIRE_X0, FIRE_X1, FIRE_Y0, FIRE_Y1
    # stone body with individual courses
    for z in range(2, 42, 3):
        for x in range(x0, x1, 4):
            off = 2 if ((z // 3) % 2) else 0
            col = "stone_lt" if ((x + z) // 4) % 3 == 0 else ("stone_dk" if ((x + z) // 3) % 2 else "stone")
            box(g, x + off, min(x1, x + off + 4), y0, y1, z, z + 3, col)
            # mortar lines
            box(g, x + off, min(x1, x + off + 4), y0, y1, z, z + 1, "mortar")
    # hearth opening
    box(g, x0 + 6, x1 - 6, y1 - 6, y1, 2, 26, "ash")
    # mantel
    box(g, x0 - 3, x1 + 3, y0 - 1, y1 + 1, 40, 43, "stone_lt")
    box(g, x0 - 2, x1 + 2, y0, y1, 43, 44, "stone")
    # side pillars
    box(g, x0, x0 + 5, y0, y1, 2, 40, "stone_dk")
    box(g, x1 - 5, x1, y0, y1, 2, 40, "stone_dk")
    # logs
    box(g, x0 + 10, x1 - 10, y1 - 5, y1 - 2, 3, 7, "log")
    box(g, x0 + 12, x1 - 14, y1 - 5, y1 - 2, 6, 9, "log")
    box(g, x0 + 10, x0 + 12, y1 - 5, y1 - 2, 3, 7, "log_end")
    box(g, x1 - 12, x1 - 10, y1 - 5, y1 - 2, 6, 9, "log_end")
    # embers
    for ex in range(x0 + 12, x1 - 12, 3):
        box(g, ex, ex + 2, y1 - 4, y1 - 2, 4, 5, "ember")
    # layered flames — push to the FRONT of the opening so the camera sees them
    h = 18 + (frame % 4) * 4
    inset = (frame % 2)
    box(g, x0 + 8 + inset, x1 - 8 - inset, y1 - 3, y1 + 1, 6, 6 + h, "fire_orange")
    box(g, x0 + 12, x1 - 12, y1 - 2, y1 + 2, 8, 8 + max(8, h - 3), "fire_hot")
    box(g, x0 + 16, x1 - 16, y1 - 1, y1 + 2, 10, 12 + (frame % 3) * 2, "fire_hot")
    # protruding tongue of flame toward camera
    box(g, x0 + 14, x1 - 14, y1, y1 + 3, 7, 7 + h // 2, "fire_orange")


def figure(g, own, oid, x, y, z, shirt, shirt_dk, skin, skin_dk, hat, hair,
           hatstyle="cap", facing="back", seated=True, drink=False, breath=0, drink_frame=0,
           beard=False):
    """Hand-detailed seated/standing crew. ~48×30×70 vox so 2× crops read."""
    bob = breath % 2
    W, D = 48, 30
    # --- legs / seat ---
    if seated:
        # hips
        box(g, x + 4, x + W - 4, y + 4, y + D - 2, z, z + 8, "pants", own, oid)
        box(g, x + 6, x + W - 6, y + 6, y + D - 4, z + 1, z + 7, "pants_hi", own, oid)
        # thighs forward
        box(g, x + 6, x + 14, y + D - 4, y + D + 6, z - 2, z + 6, "pants", own, oid)
        box(g, x + W - 14, x + W - 6, y + D - 4, y + D + 6, z - 2, z + 6, "pants", own, oid)
        # shins down to floor
        box(g, x + 7, x + 13, y + D + 4, y + D + 8, z - 14, z - 2, "pants", own, oid)
        box(g, x + W - 13, x + W - 7, y + D + 4, y + D + 8, z - 14, z - 2, "pants", own, oid)
        # boots
        box(g, x + 6, x + 14, y + D + 5, y + D + 10, z - 16, z - 12, "boot", own, oid)
        box(g, x + W - 14, x + W - 6, y + D + 5, y + D + 10, z - 16, z - 12, "boot", own, oid)
        box(g, x + 7, x + 13, y + D + 8, y + D + 10, z - 15, z - 13, "boot_hi", own, oid)
        box(g, x + W - 13, x + W - 7, y + D + 8, y + D + 10, z - 15, z - 13, "boot_hi", own, oid)
        bz = z + 8 + bob
    else:
        box(g, x + 8, x + 14, y + 6, y + D - 4, z, z + 22, "pants", own, oid)
        box(g, x + W - 14, x + W - 8, y + 6, y + D - 4, z, z + 22, "pants", own, oid)
        box(g, x + 7, x + 15, y + 5, y + D - 3, z, z + 4, "boot", own, oid)
        box(g, x + W - 15, x + W - 7, y + 5, y + D - 3, z, z + 4, "boot", own, oid)
        bz = z + 22 + bob
    # belt
    box(g, x + 4, x + W - 4, y + 4, y + D - 2, bz, bz + 2, "belt", own, oid)
    box(g, x + W // 2 - 2, x + W // 2 + 2, y + D - 3, y + D - 1, bz, bz + 2, "brass", own, oid)
    # torso
    box(g, x + 6, x + W - 6, y + 5, y + D - 2, bz + 2, bz + 26, shirt, own, oid)
    box(g, x + 8, x + W - 8, y + 7, y + D - 4, bz + 4, bz + 24, shirt_dk, own, oid)
    # buttons
    for bz_b in range(bz + 8, bz + 22, 4):
        box(g, x + W // 2 - 1, x + W // 2 + 1, y + D - 3, y + D - 1, bz_b, bz_b + 1, "brass", own, oid)
    # collar
    box(g, x + 14, x + W - 14, y + 7, y + D - 4, bz + 24, bz + 26, skin, own, oid)
    box(g, x + 10, x + 16, y + 6, y + D - 3, bz + 22, bz + 26, shirt_dk, own, oid)
    box(g, x + W - 16, x + W - 10, y + 6, y + D - 3, bz + 22, bz + 26, shirt_dk, own, oid)
    # sleeves / arms — reach forward a bit when seated
    arm_y1 = y + D + 2 if seated else y + D - 4
    box(g, x - 4, x + 7, y + 7, arm_y1, bz + 4, bz + 24, shirt, own, oid)
    box(g, x + W - 7, x + W + 4, y + 7, arm_y1, bz + 4, bz + 24, shirt, own, oid)
    box(g, x - 3, x + 5, y + 8, arm_y1 - 1, bz + 6, bz + 22, shirt_dk, own, oid)
    box(g, x + W - 5, x + W + 3, y + 8, arm_y1 - 1, bz + 6, bz + 22, shirt_dk, own, oid)
    # hands with fingers
    hand_lift = 5 if drink and (drink_frame % 4) >= 2 else 0
    hy1 = arm_y1
    box(g, x - 4, x + 5, y + 10, hy1, bz + 2 + hand_lift, bz + 7 + hand_lift, skin, own, oid)
    box(g, x + W - 5, x + W + 4, y + 10, hy1, bz + 2 + hand_lift, bz + 7 + hand_lift, skin, own, oid)
    for fx in range(0, 4):
        box(g, x - 4 + fx, x - 3 + fx, y + 12, y + 14, bz + 2 + hand_lift, bz + 3 + hand_lift, skin_dk, own, oid)
        box(g, x + W + fx, x + W + 1 + fx, y + 12, y + 14, bz + 2 + hand_lift, bz + 3 + hand_lift, skin_dk, own, oid)
    if drink:
        glass_mug(g, x + W - 1, y + 12, bz + 7 + hand_lift, own, oid)
    # head (large)
    box(g, x + 10, x + W - 10, y + 6, y + D - 4, bz + 22, bz + 42, skin, own, oid)
    box(g, x + 12, x + W - 12, y + 8, y + D - 6, bz + 24, bz + 40, skin_dk, own, oid)
    # ears
    box(g, x + 8, x + 11, y + 10, y + D - 8, bz + 30, bz + 36, skin, own, oid)
    box(g, x + W - 11, x + W - 8, y + 10, y + D - 8, bz + 30, bz + 36, skin, own, oid)
    # hair under hat
    box(g, x + 11, x + W - 11, y + 5, y + D - 3, bz + 40, bz + 44, hair, own, oid)
    # face
    if facing == "front":
        # brows
        box(g, x + 14, x + 20, y + D - 5, y + D - 3, bz + 36, bz + 38, "beard", own, oid)
        box(g, x + W - 20, x + W - 14, y + D - 5, y + D - 3, bz + 36, bz + 38, "beard", own, oid)
        # eye whites + pupils (multi-voxel)
        box(g, x + 14, x + 20, y + D - 5, y + D - 2, bz + 32, bz + 36, "eye_w", own, oid)
        box(g, x + W - 20, x + W - 14, y + D - 5, y + D - 2, bz + 32, bz + 36, "eye_w", own, oid)
        box(g, x + 16, x + 19, y + D - 4, y + D - 2, bz + 33, bz + 36, "eye", own, oid)
        box(g, x + W - 19, x + W - 16, y + D - 4, y + D - 2, bz + 33, bz + 36, "eye", own, oid)
        # nose bridge + tip
        box(g, x + W // 2 - 2, x + W // 2 + 2, y + D - 5, y + D - 2, bz + 28, bz + 33, "nose", own, oid)
        box(g, x + W // 2 - 3, x + W // 2 + 3, y + D - 3, y + D - 1, bz + 27, bz + 29, skin_dk, own, oid)
        # mouth + lip
        box(g, x + W // 2 - 5, x + W // 2 + 5, y + D - 4, y + D - 2, bz + 24, bz + 26, "eye", own, oid)
        box(g, x + W // 2 - 4, x + W // 2 + 4, y + D - 4, y + D - 2, bz + 26, bz + 27, skin_dk, own, oid)
        if beard:
            box(g, x + 12, x + W - 12, y + D - 5, y + D - 2, bz + 22, bz + 27, "beard", own, oid)
            box(g, x + W // 2 - 6, x + W // 2 + 6, y + D - 4, y + D - 1, bz + 20, bz + 24, "beard", own, oid)
    else:
        box(g, x + 12, x + W - 12, y + 4, y + 7, bz + 30, bz + 40, hair, own, oid)
    # hat
    if hatstyle == "cap":
        box(g, x + 10, x + W - 10, y + 5, y + D - 3, bz + 42, bz + 48, hat, own, oid)
        brim = 7 if facing == "front" else -5
        box(g, x + 10, x + W - 10, y + brim, y + brim + 5, bz + 42, bz + 45, hat, own, oid)
    elif hatstyle == "wide":
        box(g, x + 0, x + W, y + 0, y + D + 2, bz + 42, bz + 45, hat, own, oid)
        box(g, x + 10, x + W - 10, y + 5, y + D - 3, bz + 45, bz + 50, hat, own, oid)
    elif hatstyle == "mohawk":
        box(g, x + W // 2 - 4, x + W // 2 + 4, y + 6, y + D - 4, bz + 42, bz + 58, hat, own, oid)
        box(g, x + W // 2 - 3, x + W // 2 + 3, y + 7, y + D - 5, bz + 58, bz + 62, hat, own, oid)
    elif hatstyle == "hood":
        box(g, x + 8, x + W - 8, y + 4, y + D - 2, bz + 22, bz + 48, hat, own, oid)
        fy = y + D - 4 if facing == "front" else y + 5
        box(g, x + 12, x + W - 12, fy, fy + 4, bz + 30, bz + 40, skin, own, oid)
        if facing == "front":
            box(g, x + 15, x + 19, fy + 2, fy + 4, bz + 34, bz + 37, "eye_w", own, oid)
            box(g, x + W - 19, x + W - 15, fy + 2, fy + 4, bz + 34, bz + 37, "eye_w", own, oid)
            box(g, x + 16, x + 18, fy + 3, fy + 4, bz + 35, bz + 37, "eye", own, oid)
            box(g, x + W - 18, x + W - 16, fy + 3, fy + 4, bz + 35, bz + 37, "eye", own, oid)


def bake_cast_shadows(g):
    L = np.array([-0.45, -0.55, 0.70], dtype=np.float64)
    L /= np.linalg.norm(L)
    inv = -L
    filled = g > 0
    top = filled.copy()
    top[:, :, :-1] &= ~filled[:, :, 1:]
    xs, ys, zs = np.nonzero(top & (np.arange(SZ)[None, None, :] >= 3))
    floor_mats = {IDX[n] for n in ("floor_a", "floor_b", "floor_gap", "rug_a", "rug_b", "rug_trim", "rug_pat")}
    for x, y, z in zip(xs.tolist(), ys.tolist(), zs.tolist()):
        t = (1.5 - z) / inv[2]
        if t <= 0:
            continue
        fx = int(round(x + inv[0] * t + 2.0))
        fy = int(round(y + inv[1] * t + 2.5))
        for dx in range(-1, 2):
            for dy in range(-1, 4):
                xx, yy = fx + dx, fy + dy
                if 0 <= xx < SX and 0 <= yy < SY and g[xx, yy, 1] in floor_mats:
                    g[xx, yy, 1] = IDX["shadow"]
                    g[xx, yy, 0] = IDX["shadow"]


def build_room(with_hireables=True, fire_frame=0, lantern_pulse=0, breath=0, drink_frame=0):
    g = np.zeros((SX, SY, SZ), np.int16)
    own = np.zeros((SX, SY, SZ), np.int16)
    # floor boards
    board = 6
    for x in range(0, SX, board):
        n = "floor_a" if (x // board) % 2 == 0 else "floor_b"
        box(g, x, min(SX, x + board), 0, SY, 0, 2, n)
        if x > 0:
            box(g, x, x + 1, 0, SY, 1, 2, "floor_gap")
        for y in range(6, SY - 6, 12):
            box(g, x + board // 2, x + board // 2 + 1, y, y + 1, 1, 2, "metal_dk")
    # walls
    noise_box(g, 0, SX, 0, 10, 2, 58, "wall", "wall_dark", 0.22, 4)
    box(g, 0, 5, 0, SY, 2, 58, "wall_dark")
    box(g, SX - 5, SX, 0, SY, 2, 58, "wall_dark")
    for x in range(14, SX - 20, 32):
        box(g, x, x + 4, 5, 10, 2, 58, "beam")
    # ceiling beams + brackets
    for y in (12, 28):
        box(g, 10, SX - 10, y, y + 4, 70, 76, "beam")
        for x in range(24, SX - 24, 40):
            box(g, x, x + 3, y - 1, y + 5, 66, 70, "beam_bracket")
            box(g, x, x + 3, y + 1, y + 3, 62, 66, "beam_bracket")
    # patterned rug
    rx0, rx1 = int(28 * SX_S), int(88 * SX_S)
    ry0, ry1 = int(36 * SY_S), int(60 * SY_S)
    box(g, rx0, rx1, ry0, ry1, 2, 3, "rug_a")
    for i in range(0, rx1 - rx0, 5):
        n = "rug_b" if (i // 5) % 2 else "rug_pat"
        box(g, rx0 + i, rx0 + i + 3, ry0 + 2, ry1 - 2, 2, 3, n)
    for j in range(0, ry1 - ry0, 5):
        box(g, rx0 + 2, rx1 - 2, ry0 + j, ry0 + j + 1, 2, 3, "rug_trim")
    box(g, rx0, rx1, ry0, ry0 + 1, 2, 3, "rug_trim")
    box(g, rx0, rx1, ry1 - 1, ry1, 2, 3, "rug_trim")

    fireplace(g, frame=fire_frame)

    # bar
    bx0, bx1 = int(6 * SX_S), int(64 * SX_S)
    by0, by1 = int(12 * SY_S), int(22 * SY_S)
    noise_box(g, bx0, bx1, by0, by1, 2, 16, "wood_dk", "wood_grain", 0.18, 9)
    wood_grain_top(g, bx0 - 1, bx1 + 1, by0 - 1, by1 + 1, 16, seed=11)
    box(g, bx0 - 1, bx1 + 1, by0 - 1, by1 + 1, 17, 18, "wood_hi")
    # brass foot rail
    box(g, bx0 + 2, bx1 - 2, by1, by1 + 2, 6, 8, "brass")
    box(g, bx0 + 2, bx1 - 2, by1, by1 + 2, 6, 7, "brass_dk")
    for x in range(bx0 + 6, bx1 - 4, 14):
        box(g, x, x + 2, by1, by1 + 2, 2, 6, "brass_dk")
    # back shelves + bottles
    box(g, bx0, bx1, 4, 9, 18, 20, "wood_mid")
    box(g, bx0, bx1, 4, 9, 28, 30, "wood_mid")
    box(g, bx0, bx1, 4, 9, 38, 40, "wood_mid")
    kinds = ["bottle_g", "bottle_a", "bottle_b", "bottle_r"]
    for i, x in enumerate(range(bx0 + 4, bx1 - 4, 5)):
        bottle(g, x, 5, 20, kinds[i % 4])
        if i % 2 == 0:
            bottle(g, x + 1, 6, 30, kinds[(i + 1) % 4])
        if i % 3 == 0:
            bottle(g, x, 5, 40, kinds[(i + 2) % 4])
    # glasses on bar
    for x in range(bx0 + 10, bx1 - 10, 12):
        box(g, x, x + 3, by1 - 4, by1 - 1, 18, 22, "glass")
        box(g, x, x + 3, by1 - 4, by1 - 1, 18, 20, "liquid_a")
    for x in (int(12 * SX_S), int(32 * SX_S), int(50 * SX_S)):
        stool(g, x, int(22 * SY_S))

    # tables + lanterns
    for (tx, ty) in ((int(20 * SX_S), int(44 * SY_S)), (int(50 * SX_S), int(40 * SY_S))):
        table(g, tx, ty, w=int(24 * SX_S), d=int(16 * SY_S), h=18)
        lantern(g, tx + int(9 * SX_S), ty + int(5 * SY_S), z0=20, pulse=lantern_pulse)

    for (x, y) in ((int(14 * SX_S), int(48 * SY_S)),) + tuple((s[0], s[1]) for s in SEATS_VOX):
        stool(g, x, y)

    # crates
    box(g, int(3 * SX_S), int(15 * SX_S), int(54 * SY_S), int(66 * SY_S), 2, 14, "crate")
    box(g, int(4 * SX_S), int(14 * SX_S), int(55 * SY_S), int(65 * SY_S), 14, 15, "crate_dk")
    box(g, int(3 * SX_S), int(15 * SX_S), int(54 * SY_S), int(66 * SY_S), 7, 8, "crate_band")
    box(g, int(15 * SX_S), int(24 * SX_S), int(56 * SY_S), int(66 * SY_S), 2, 10, "crate")
    box(g, int(15 * SX_S), int(24 * SX_S), int(56 * SY_S), int(66 * SY_S), 5, 6, "crate_band")

    # mounted skull
    sx0 = FIRE_X0 - 28
    box(g, sx0, sx0 + 14, 5, 10, 32, 44, "skull")
    box(g, sx0 + 3, sx0 + 6, 9, 10, 37, 40, "skull_dk")
    box(g, sx0 + 8, sx0 + 11, 9, 10, 37, 40, "skull_dk")
    box(g, sx0 + 5, sx0 + 9, 9, 10, 33, 36, "skull_dk")
    box(g, sx0 - 5, sx0, 6, 9, 40, 48, "horn")
    box(g, sx0 + 14, sx0 + 19, 6, 9, 40, 48, "horn")

    # dartboard
    dx0 = min(SX - 24, FIRE_X1 + 12)
    cyl(g, dx0 + 8, 9, 8, 30, 32, "dart")
    cyl(g, dx0 + 8, 9, 8, 32, 33, "dart_face")
    cyl(g, dx0 + 8, 9, 5, 32, 33, "dart_ring")
    cyl(g, dx0 + 8, 9, 2, 32, 33, "dart_face")
    box(g, dx0 + 7, dx0 + 9, 8, 9, 33, 38, "metal_dk")

    # bartender
    figure(g, own, 0, int(24 * SX_S), 6, 2,
           "bt_shirt", "bt_shirt_dk", "bt_skin", "bt_skin_dk", "bt_hat", "bt_hair",
           hatstyle="hood", facing="front", seated=False, breath=breath)

    pals = [
        ("c0_shirt", "c0_shirt_dk", "c0_skin", "c0_skin_dk", "c0_hat", "c0_hair", "wide", "back", False, True),
        ("c1_shirt", "c1_shirt_dk", "c1_skin", "c1_skin_dk", "c1_hat", "c1_hair", "wide", "front", True, True),
        ("c2_shirt", "c2_shirt_dk", "c2_skin", "c2_skin_dk", "c2_hat", "c2_hair", "cap", "back", True, False),
        ("c3_shirt", "c3_shirt_dk", "c3_skin", "c3_skin_dk", "c3_hat", "c3_hair", "mohawk", "front", False, False),
    ]
    if with_hireables:
        for i, (st, p) in enumerate(zip(SEATS_VOX, pals), 1):
            shirt, sdk, skin, skdk, hat, hair, hs, facing, drink, beard = p
            figure(g, own, i, st[0], st[1], st[2], shirt, sdk, skin, skdk, hat, hair,
                   hatstyle=hs, facing=facing, seated=True, drink=drink, breath=breath,
                   drink_frame=drink_frame if drink else 0, beard=beard)

    bake_cast_shadows(g)
    return g, own


def canvas_size(tilt, ppv=PPV):
    r = math.hypot(SX, SY) / 2
    return 2 * int(math.ceil((r + SZ * math.sin(math.radians(tilt))) * ppv)) + 16


def render_scene(g, own, tilt, heading=HEADING, ppv=PPV, light_only=False):
    cols = colors_rgba(light_only=light_only)
    canvas = canvas_size(tilt, ppv)
    img, own_img = render_frame(g, cols, heading_deg=heading, ppv=ppv, tilt=tilt,
                                canvas=canvas, owner=own, hd=True)
    return img, own_img, canvas


def place_on_room(img, own_img, room=(1280, 720), target_crew_h=TARGET_CREW_H):
    """Crop empty margins and scale so a hireable figure ≈ target_crew_h px tall."""
    W, H = room
    a = img[:, :, 3] > 0
    if not a.any():
        return np.zeros((H, W, 4), np.uint8), np.zeros((H, W), np.int16), np.zeros((H, W), bool), (0, 0, 0, 0, 1.0)
    ys, xs = np.where(a)
    # trim very empty outer bands (alpha < 2% in a row/col)
    row_f = a.mean(1); col_f = a.mean(0)
    y0 = int(np.argmax(row_f > 0.02)); y1 = int(len(row_f) - np.argmax(row_f[::-1] > 0.02))
    x0 = int(np.argmax(col_f > 0.02)); x1 = int(len(col_f) - np.argmax(col_f[::-1] > 0.02))
    crop = img[y0:y1, x0:x1]
    own_c = own_img[y0:y1, x0:x1]
    # measure a crew owner's height in the crop to pick scale
    scale = min((W - 16) / crop.shape[1], (H - 16) / crop.shape[0])
    for oid in range(1, 5):
        m = own_c == oid
        if not m.any():
            continue
        yy, _ = np.where(m)
        ch = int(yy.max() - yy.min() + 1)
        if ch > 8:
            scale = max(scale, target_crew_h / ch)
        break
    # cap so we still fit
    scale = min(scale, min((W - 8) / crop.shape[1], (H - 8) / crop.shape[0]))
    nw, nh = max(1, int(crop.shape[1] * scale)), max(1, int(crop.shape[0] * scale))
    crop_r = np.array(Image.fromarray(crop).resize((nw, nh), Image.Resampling.NEAREST))
    own_r = np.array(Image.fromarray(own_c.astype(np.int32)).resize((nw, nh), Image.Resampling.NEAREST)).astype(np.int16)
    out = np.zeros((H, W, 4), np.uint8)
    ow = np.zeros((H, W), np.int16)
    px = max(0, (W - nw) // 2)
    py = max(0, min(H - nh, (H - nh) // 2 - 10))
    out[py:py + nh, px:px + nw] = crop_r
    ow[py:py + nh, px:px + nw] = own_r
    rgb = out[:, :, :3].astype(np.int16)
    # fire/lantern only: very bright warm OR near-white hot
    em = (out[:, :, 3] > 0) & (rgb[:, :, 0] > 200) & (rgb[:, :, 1] > 90) & (rgb[:, :, 0] > rgb[:, :, 2] + 40) & (rgb[:, :, 1] > rgb[:, :, 2])
    em |= (out[:, :, 3] > 0) & (rgb[:, :, 0] > 240) & (rgb[:, :, 1] > 220) & (rgb[:, :, 2] > 170)
    return out, ow, em, (px, py, nw, nh, scale)


def grade_night(rgba, em):
    """#512b11 night like a0c1213: dark corners, hero fire/lantern pools, dim moon key."""
    rgb = rgba[:, :, :3].astype(np.float32)
    graded = night_grade(rgb, em).astype(np.float32)
    body = (rgba[:, :, 3] > 0) & ~em
    # land near a0 mean (~68,38,15): gentle crush, not a black-out
    graded[body] = graded[body] * 0.92
    heat = np.array(Image.fromarray((em.astype(np.uint8) * 255)).filter(
        ImageFilter.GaussianBlur(42))).astype(np.float32) / 255.0
    warm = np.array([1.70, 1.10, 0.45], dtype=np.float32)
    # outside pools go darker; inside pools warm up
    graded = graded * (0.75 + 0.90 * heat[..., None] * warm)
    graded[body] = np.clip(graded[body] * 1.12 + 6.0, 0, 255)
    e = np.zeros_like(graded)
    e[em] = np.maximum(rgb[em] * 1.15, graded[em])
    glow = np.array(Image.fromarray(np.clip(e, 0, 255).astype(np.uint8)).filter(
        ImageFilter.GaussianBlur(16))).astype(np.float32)
    out = np.clip(graded + glow * 2.0, 0, 255)
    out[em] = np.clip(rgb[em] * 0.65 + out[em] * 0.35 + 50, 0, 255)
    H, W = out.shape[:2]
    Y, X = np.mgrid[0:H, 0:W].astype(np.float32)
    v = np.clip((np.hypot((X - W / 2) / (W * 0.58), (Y - H * 0.42) / (H * 0.58)) - 0.70) / 0.50, 0, 1)
    out *= (1.0 - 0.55 * v)[..., None]
    return np.clip(out, 0, 255).astype(np.uint8)


def lights_overlay(rgb, em):
    out = np.zeros((rgb.shape[0], rgb.shape[1], 4), np.uint8)
    out[em, :3] = rgb[em]
    out[em, 3] = 255
    bloom = np.array(Image.fromarray(out).filter(ImageFilter.GaussianBlur(10))).astype(np.float32)
    bloom[..., 3] *= 0.6
    return Image.alpha_composite(
        Image.fromarray(np.clip(bloom, 0, 255).astype(np.uint8), "RGBA"),
        Image.fromarray(out, "RGBA"))


def variant_sprite(base_rgba, mode):
    im = Image.fromarray(base_rgba).convert("RGBA")
    if mode == "idle":
        return im
    a = np.array(im).astype(np.float32)
    if mode == "dim":
        a[..., :3] *= 0.38
        a[..., 3] *= 0.82
        return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA")
    mask = a[..., 3] > 10
    dil = np.array(Image.fromarray((mask.astype(np.uint8) * 255)).filter(ImageFilter.MaxFilter(9))) > 0
    a[dil & ~mask] = (225, 180, 65, 255)
    a[mask, :3] = np.clip(a[mask, :3] * 1.18, 0, 255)
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA")


def crop_owner(rgba, own, owner_id, pad=14):
    ys, xs = np.where(own == owner_id)
    if len(xs) == 0:
        return None, None
    x0, x1 = max(0, int(xs.min()) - pad), min(rgba.shape[1], int(xs.max()) + pad + 1)
    y0, y1 = max(0, int(ys.min()) - pad), min(rgba.shape[0], int(ys.max()) + pad + 1)
    spr = rgba[y0:y1, x0:x1].copy()
    spr[own[y0:y1, x0:x1] != owner_id, 3] = 0
    return spr, (x0, y0)


def bake(tilt=TILT_GAME, write_assets=True):
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(CONCEPT_HD, exist_ok=True)
    for f in glob.glob(os.path.join(OUT, "crew_*.png*")):
        os.remove(f)
    for f in glob.glob(os.path.join(OUT, "fireplace_*.png*")):
        os.remove(f)
    for f in glob.glob(os.path.join(OUT, "saloon_room_lights_pulse*.png*")):
        os.remove(f)

    g_full, own_full = build_room(True, fire_frame=1, lantern_pulse=0, breath=0)
    img_full, own_img, canvas = render_scene(g_full, own_full, tilt)
    rgba_full, ow, em, place = place_on_room(img_full, own_img)
    graded = grade_night(rgba_full, em)

    g_bg, own_bg = build_room(False, fire_frame=1, lantern_pulse=0, breath=0)
    img_bg, own_bg_img, _ = render_scene(g_bg, own_bg, tilt)
    rgba_bg, ow_bg, em_bg, _ = place_on_room(img_bg, own_bg_img)
    graded_bg = grade_night(rgba_bg, em_bg)

    room_path = os.path.join(OUT, "saloon_room.png")
    lights_path = os.path.join(OUT, "saloon_room_lights.png")
    Image.fromarray(graded_bg, "RGB").save(room_path)
    lights_overlay(np.maximum(graded_bg, graded), em_bg | em).save(lights_path)
    write_import(room_path); write_import(lights_path)

    rgba_crew = np.concatenate([graded, np.where(ow > 0, 255, 0).astype(np.uint8)[..., None]], -1)

    seats_out = []
    for slot, sid in enumerate(SEAT_IDS):
        owner = slot + 1
        spr, local = crop_owner(rgba_crew, ow, owner, pad=14)
        if spr is None:
            print("WARN missing", sid); continue
        # enforce near-a0 on-screen size via nearest resize of the sprite itself
        idle0 = variant_sprite(spr, "idle")
        a = np.array(idle0)
        bb = Image.fromarray(a).getbbox()
        if bb:
            oh = bb[3] - bb[1]
            if oh > 0 and abs(oh - TARGET_CREW_H) > 12:
                sc = TARGET_CREW_H / oh
                nw = max(16, int(idle0.width * sc))
                nh = max(16, int(idle0.height * sc))
                # also rescale position around sprite centre
                cx = local[0] + idle0.width / 2
                cy = local[1] + idle0.height / 2
                idle0 = idle0.resize((nw, nh), Image.Resampling.NEAREST)
                hi0 = variant_sprite(spr, "highlight").resize((nw, nh), Image.Resampling.NEAREST)
                dim0 = variant_sprite(spr, "dim").resize((nw, nh), Image.Resampling.NEAREST)
                local = (int(cx - nw / 2), int(cy - nh / 2))
            else:
                hi0 = variant_sprite(spr, "highlight")
                dim0 = variant_sprite(spr, "dim")
        else:
            hi0 = variant_sprite(spr, "highlight")
            dim0 = variant_sprite(spr, "dim")
        idle, hi, dim = idle0, hi0, dim0
        nw, nh = idle.size
        pos = [int(local[0]), int(local[1])]
        for im, name in ((idle, f"crew_{sid}_idle.png"),
                         (hi, f"crew_{sid}_highlight.png"),
                         (dim, f"crew_{sid}_dim.png")):
            path = os.path.join(OUT, name); im.save(path); write_import(path)
        ax = pos[0] + nw // 2
        ay = pos[1] + max(10, nh // 5)
        hw = max(64, nw + 28); hh = max(64, nh + 28)
        hx = int(np.clip(pos[0] + nw / 2 - hw / 2, 0, 1280 - hw))
        hy = int(np.clip(pos[1] + nh / 2 - hh / 2, 0, 720 - hh))
        # All cards open on the right (x>=900); fireplace is centre-back and clear.
        side = "right"
        seats_out.append({
            "id": sid, "slot": slot, "pos": pos, "z": int(pos[1] + nh),
            "hit_rect": [hx, hy, hw, hh], "anchor": [ax, ay], "card_side": side,
            "sprites": {
                "idle": f"res://art/saloon/crew_{sid}_idle.png",
                "highlight": f"res://art/saloon/crew_{sid}_highlight.png",
                "dim": f"res://art/saloon/crew_{sid}_dim.png",
            },
        })
        print(f"  {sid} opaque~", Image.open(os.path.join(OUT, f"crew_{sid}_idle.png")).getbbox(),
              "size", (nw, nh), "pos", pos)

    # animations (cheap)
    fire_frames = []
    for fi in range(4):
        gf, of = build_room(False, fire_frame=fi, lantern_pulse=0, breath=0)
        im, oi, _ = render_scene(gf, of, tilt, light_only=True)
        rgba, _, emf, _ = place_on_room(im, oi)
        fr = meta_fire = [500, 40, 360, 260]
        fx, fy, fw, fh = 500, 40, 360, 260
        arr = np.concatenate([rgba[:, :, :3], np.where(emf, 255, 0).astype(np.uint8)[..., None]], -1)
        fire_frames.append(Image.fromarray(arr[fy:fy + fh, fx:fx + fw]))
    fw, fh = fire_frames[0].size
    fire_strip = Image.new("RGBA", (fw * 4, fh))
    for i, fr in enumerate(fire_frames):
        fire_strip.paste(fr, (i * fw, 0))
    fp = os.path.join(OUT, "fireplace_flicker.png"); fire_strip.save(fp); write_import(fp)

    for li in range(2):
        gf, of = build_room(False, fire_frame=1, lantern_pulse=li, breath=0)
        im, oi, _ = render_scene(gf, of, tilt)
        rgba, _, eml, _ = place_on_room(im, oi)
        graded_l = grade_night(rgba, eml)
        lights_overlay(graded_l, eml).save(os.path.join(OUT, f"saloon_room_lights_pulse{li}.png"))
        write_import(os.path.join(OUT, f"saloon_room_lights_pulse{li}.png"))

    for slot, sid in enumerate(SEAT_IDS):
        frames = []
        drink = sid in ("table_left", "table_mid")
        for bi in range(4):
            gf, of = build_room(True, fire_frame=1, lantern_pulse=bi % 2, breath=bi,
                                drink_frame=bi if drink else 0)
            im, oi, _ = render_scene(gf, of, tilt)
            rgba, ow2, em2, _ = place_on_room(im, oi)
            graded2 = grade_night(rgba, em2)
            rgba_c = np.concatenate([graded2, np.where(ow2 == slot + 1, 255, 0).astype(np.uint8)[..., None]], -1)
            seat = seats_out[slot]
            x, y = seat["pos"]
            idle_p = Image.open(os.path.join(OUT, f"crew_{sid}_idle.png"))
            w, h = idle_p.size
            # crop then resize to idle size
            ys, xs = np.where(ow2 == slot + 1)
            if len(xs) == 0:
                frames.append(idle_p); continue
            spr, loc = crop_owner(rgba_c, ow2, slot + 1, pad=14)
            fr = Image.fromarray(spr).resize((w, h), Image.Resampling.NEAREST)
            frames.append(fr)
        strip = Image.new("RGBA", (frames[0].width * 4, frames[0].height))
        for i, fr in enumerate(frames):
            strip.paste(fr, (i * fr.width, 0))
        sp = os.path.join(OUT, f"crew_{sid}_idle_anim.png"); strip.save(sp); write_import(sp)
        seats_out[slot]["sprites"]["idle_anim"] = f"res://art/saloon/crew_{sid}_idle_anim.png"
        seats_out[slot]["anim"] = {"idle_frames": 4, "idle_frame_w": frames[0].width, "fps": 4}

    # fireplace_rect clear of card x=900
    ys, xs = np.where(em_bg | em)
    fire_rect = [560, 50, 280, 180]
    if len(xs):
        fx0, fx1 = max(480, int(xs.min())), min(880, int(xs.max()))
        fy0, fy1 = max(20, int(ys.min()) - 8), min(400, int(ys.max()) + 8)
        if fx1 > fx0 and fy1 > fy0:
            fire_rect = [fx0, fy0, fx1 - fx0, fy1 - fy0]
            if fire_rect[0] + fire_rect[2] > 900:
                fire_rect[2] = 900 - fire_rect[0] - 8

    meta = {
        "room_size": [1280, 720],
        "fireplace_rect": fire_rect,
        "card_left_rect": [24, 72, 356, 448],
        "card_right_rect": [900, 72, 356, 448],
        "camera": f"voxel_render HD ppv={PPV} tilt={tilt}° heading={HEADING}° (PR #70)",
        "tilt_deg": tilt,
        "px_per_voxel": PPV,
        "hd": True,
        "sun": "dim moonlight upper-left → hard cast shadows down-right; fire/lanterns hero lights",
        "night": "#512b11 world grade + vignette; emissive pools untinted on lights plate",
        "background": "res://art/saloon/saloon_room.png",
        "lights": "res://art/saloon/saloon_room_lights.png",
        "lights_note": "Fireplace + lantern glow. Composite above world night grade; do not CanvasModulate.",
        "animations": {
            "fireplace_flicker": {"sheet": "res://art/saloon/fireplace_flicker.png", "frames": 4, "fps": 8},
            "lantern_pulse": {"plates": [f"res://art/saloon/saloon_room_lights_pulse{i}.png" for i in range(2)], "fps": 2},
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
    nbytes = sum(os.path.getsize(os.path.join(OUT, f)) for f in os.listdir(OUT) if f.endswith(".png"))
    print("baked tilt", tilt, "fire", fire_rect, f"png_bytes={nbytes} place={place}")
    print([(s["id"], s["pos"], s["card_side"], s["hit_rect"][2:]) for s in seats_out])
    return meta, graded_bg, graded, ow, em_bg | em


if __name__ == "__main__":
    tilt = float(sys.argv[1]) if len(sys.argv) > 1 else TILT_GAME
    bake(tilt=tilt)
