#!/usr/bin/env python3
"""Zombie sheets for the 45 deg camera: approved saloon v2 looks, baked like #74.

Eight kinds share one atlas. Shambler variants are the three Cameron approved
(A coat drifter, B hat + blue coat, C skull plate + vest), all in the sickly
green flesh family. Slimer, hunter, brute, tank and boomer are one variant each.

Every body frame goes through voxel_render (same 45 deg tilt and sun as the
rigs), then the #74 dark-mass grade (MASS_DESAT / MASS_DARK). Cast shadows are
voxel_render.render_shadow, one strip per kind. Night is NOT baked: the game
multiplies self_modulate at night.

Row names and counts match what zombie.gd / hunter.gd ask for:
  shambler  v0..v2 x (walk_0..3, lunge_0..1) + flash
  tank      walk_0..3, roar_0..1, charge, stumble, flash
  brute, slimer, boomer   walk_0..3 + flash
  hunter    walk_0..3, windup, pounce, flash
16 headings. Pose slots per heading stay within zombie.gd's *16 redraw key.
"""
import json, math, os, sys
import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from voxel_render import render_frame, canvas_for, write_import, render_shadow, shadow_canvas  # noqa: E402

OUT = os.path.join(HERE, "..", "..", "art", "zombies")
HEADINGS = 16
# #74 draws zombie shadows at 0.5 (the json value shipped with that pass).
# Rigs use SHADOW_ALPHA (0.82). Keep the zombie sheet on the #74 alpha.
ZOMBIE_SHADOW_ALPHA = 0.5
MASS_DESAT = 0.45
MASS_DARK = 0.68

# Day-authored, lifted so midtones survive mass-grade and the #2a3550 night
# multiply (reds ~x0.44, greens ~x0.60). Blood is tuning's #F23D29.
SKIN_A = (200, 230, 188)
SKIN_B = (188, 226, 200)   # cooler
SKIN_C = (214, 226, 176)   # warmer
SKIN = (SKIN_A, SKIN_B, SKIN_C)
BRUISE = (176, 130, 160)
BLOOD = (242, 61, 41)
EYE = (255, 236, 150)
MOUTH = (54, 32, 30)
BONE = (214, 200, 172)
HAIR_A = (150, 108, 74)
HAIR_B = (186, 186, 196)
COAT_A = (208, 174, 134)
COAT_B = (150, 178, 210)
COAT_C = (164, 148, 138)
VEST_A = (158, 148, 138)
VEST_C = (198, 168, 96)
SHIRT_B = (176, 150, 118)
PANTS = (176, 152, 130)
PANTS_B = (158, 130, 104)
BELT = (124, 98, 74)
BOOT = (136, 104, 78)
HAT = (214, 190, 152)
SKULL = (206, 190, 162)
RIM = (190, 212, 228)
STEEL = (188, 196, 206)
STEEL_D = (124, 130, 138)
SPIKE = (158, 140, 120)
CHAIN = (150, 154, 160)
APRON = (194, 158, 130)
STRAP = (148, 116, 86)
SLIME = (172, 228, 96)
SLIME_D = (118, 176, 72)
PUSTULE = (186, 196, 142)
HOOD = (188, 160, 130)
CLAW = (214, 188, 172)
FLASH = (240, 232, 214)
BOOMER = (198, 228, 182)


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
    x0, x1 = max(0, int(x0)), min(sx, int(x1))
    y0, y1 = max(0, int(y0)), min(sy, int(y1))
    z0, z1 = max(0, int(z0)), min(sz, int(z1))
    if x0 < x1 and y0 < y1 and z0 < z1:
        g[x0:x1, y0:y1, z0:z1] = v


class Stamp:
    def __init__(self, shape):
        self.g = np.zeros(shape, np.int16)
        self.P = Pal()

    def box(self, x0, x1, y0, y1, z0, z1, c):
        box(self.g, x0, x1, y0, y1, z0, z1, self.P(c))

    def orb(self, cx, cy, cz, rx, ry, rz, c):
        if rx < 0.4 or ry < 0.4 or rz < 0.4:
            return
        v = self.P(c)
        L, W, H = self.g.shape
        for x in range(max(0, int(cx - rx)), min(L, int(cx + rx) + 1)):
            for y in range(max(0, int(cy - ry)), min(W, int(cy + ry) + 1)):
                for z in range(max(0, int(cz - rz)), min(H, int(cz + rz) + 1)):
                    dx, dy, dz = (x + 0.5 - cx) / rx, (y + 0.5 - cy) / ry, (z + 0.5 - cz) / rz
                    if dx * dx + dy * dy + dz * dz <= 1.0:
                        self.g[x, y, z] = v


def flash_of(g):
    f = g.copy()
    f[f > 0] = -1
    return f


def mass_grade(f):
    """#74 dark mass: pull 45% toward grey, then x0.68. Eyes and the hit-flash stay."""
    f = f.copy()
    rgb = f[..., :3].astype(float)
    keep = (f[..., 3] == 0) | np.all(f[..., :3] == np.array(FLASH), -1)
    eye = (rgb[..., 0] > 200) & (rgb[..., 1] > 185) & (rgb[..., 2] < 170) & (rgb[..., 2] > 90)
    eye &= np.abs(rgb[..., 0] - rgb[..., 1]) < 40
    keep = keep | eye
    grey = rgb.mean(-1, keepdims=True)
    g = (grey + (rgb - grey) * (1 - MASS_DESAT)) * MASS_DARK
    f[..., :3] = np.where(keep[..., None], f[..., :3], np.clip(g, 0, 255).astype(np.uint8))
    return f


def _figure(scale, skin, skin_dark, shirt, trousers, pose, k, heavy=False, kind="shambler"):
    """Stacked humanoid, same layout as the #74 sheets (legs, torso, head, reaching arms).

    `kind` only adds silhouette markers inside that layout: hat, skull plate,
    hood spikes, apron bulk, scrap yoke, slime drips, pustules.
    """
    s = float(scale)
    L, W, H = int(14 * s), int(10 * s), int(18 * s)
    if kind == "boomer":
        W = int(W * 1.35)
        H = int(H * 0.85)
    elif kind == "hunter":
        W = max(8, int(W * 0.8))
        L = int(L * 1.15)
    elif kind == "slimer":
        H = int(H * 0.8)
    st = Stamp((L, W, H))
    cx, cy = L // 2, W // 2
    lean = {"walk": 1, "lunge": 2 + k, "roar": -1, "charge": 3, "stumble": 2, "windup": 1, "pounce": 4}.get(pose, 1)
    hunch = int(round(lean * s))
    swing = [2, 0, -2, 0][k % 4] if pose == "walk" else (2 if pose in ("charge", "pounce") else (1 if pose == "lunge" else 0))
    sw = int(round(swing * s))
    leg_h = int((5 if kind in ("boomer", "slimer") else 7) * s)
    if kind == "hunter":
        leg_h = int(4 * s)
    lw = max(2, int((3 if kind == "boomer" else 2) * s))
    for side, ph in ((-1, 1), (1, -1)):
        y0 = cy + 1 if side > 0 else cy - 1 - lw
        dx = sw * ph
        if pose == "stumble" and side > 0:
            dx = int(3 * s)
        pants_c = BONE if kind == "shambler_b" and side > 0 else trousers
        st.box(cx - lw // 2 + dx, cx + lw - lw // 2 + dx, y0, y0 + lw, 0, leg_h, pants_c)
        st.box(cx - lw // 2 + dx, cx + lw - lw // 2 + dx + int(s), y0, y0 + lw, 0, max(1, int(s)), skin_dark)
    tw = int((9 if kind == "boomer" else 7) * s) if not heavy else int((11 if kind == "tank" else 9) * s)
    td = int((6 if kind == "boomer" else 4) * s) if not heavy else int((8 if kind == "tank" else 6) * s)
    th = int((7 if kind == "boomer" else 6) * s)
    if kind == "slimer":
        tw = int(tw * 1.25)
        td = int(td * 1.2)
        th = int(th * 0.85)
    cloth = APRON if kind == "brute" else shirt
    for z in range(leg_h, leg_h + th):
        off = int(round(hunch * (z - leg_h) / max(1, th)))
        st.box(cx - td // 2 + off, cx + td - td // 2 + off, cy - tw // 2, cy + tw - tw // 2, z, z + 1, cloth)
        if kind == "boomer" and z > leg_h + 1:
            # belly swells past the shirt
            st.box(cx - td // 2 + off - 1, cx + td - td // 2 + off + 1, cy - tw // 2 - 1, cy + tw - tw // 2 + 1, z, z + 1, skin)
    st.box(cx + td // 2 - 1 + hunch // 2, cx + td // 2 + hunch // 2, cy - 1, cy + 1, leg_h + 2, leg_h + 3, skin)
    st.box(cx + 1 + hunch // 2, cx + td // 2 + hunch // 2, cy - 1, cy + 1, leg_h + th // 2, leg_h + th // 2 + max(2, int(s)), BLOOD)
    st.box(cx - td // 2, cx + td // 2, cy - tw // 2, cy + tw // 2, leg_h, leg_h + max(1, int(s)), BELT)
    top = leg_h + th
    hs = max(3, int(3.5 * s)) if not heavy else max(3, int(3 * s))
    if kind == "boomer":
        hs = max(3, int(2.4 * s))
    hx = cx + hunch + (int(s) if pose in ("lunge", "charge", "pounce") else 0)
    hz = top - (int(s) if heavy else 0)
    if pose == "roar":
        hz += int(s)
    if kind == "windup" or pose == "windup":
        hz -= int(s)
    st.box(hx - hs // 2, hx + hs - hs // 2, cy - hs // 2, cy + hs - hs // 2, hz, hz + hs, skin)
    # eyes on the forward face, mouth under them
    eye_x0 = hx + hs - hs // 2 - 1
    eye_x1 = hx + hs - hs // 2
    st.box(eye_x0, eye_x1, cy - hs // 2, cy - hs // 2 + max(1, hs // 3), hz + hs // 2, hz + hs // 2 + 1, EYE)
    st.box(eye_x0, eye_x1, cy + hs - hs // 2 - max(1, hs // 3), cy + hs - hs // 2, hz + hs // 2, hz + hs // 2 + 1, EYE)
    st.box(eye_x0, eye_x1, cy - 1, cy + 1, hz + max(0, hs // 5), hz + max(1, hs // 3), MOUTH if pose != "roar" else BLOOD)
    if kind == "shambler_a":
        st.box(hx - hs // 2, hx + hs // 2, cy - hs // 2 - 1, cy + hs // 2 + 1, hz + hs - 1, hz + hs + int(s) + 1, HAIR_A)
    elif kind == "shambler_b":
        st.box(hx - hs // 2, hx + hs // 2, cy - hs // 2, cy + hs // 2, hz + hs - 1, hz + hs + 1, HAIR_B)
        st.box(hx - hs // 2, hx + hs // 2 + 1, cy - hs // 2 - 1, cy + hs // 2 + 1, hz + hs + int(s), hz + hs + int(2 * s), HAT)
        st.box(hx - 1, hx + hs, cy - hs // 2 - 1, cy + hs // 2 + 1, hz + hs, hz + hs + max(1, int(s)), HAT)
        st.box(eye_x0, eye_x1, cy - 1, cy + 1, hz, hz + max(1, int(s)), BLOOD)
    elif kind == "shambler_c":
        st.box(hx - hs // 2 + 1, hx + hs // 2, cy - hs // 2, cy + hs // 2, hz + hs - 1, hz + hs + int(s) + 1, SKULL)
        st.box(hx + hs // 3, hx + hs // 2, cy - hs // 4, cy, hz + hs, hz + hs + 1, MOUTH)
        st.box(cx + hunch, cx + td // 2 + hunch, cy - tw // 4, cy + tw // 4, leg_h + 1, top - 1, VEST_C)
    elif kind == "hunter":
        st.box(hx - hs // 2 - 1, hx + hs // 2, cy - hs // 2 - 1, cy + hs // 2 + 1, hz + hs // 2, hz + hs + int(s), HOOD)
        for i in range(4):
            st.box(cx - int(2 * s) + i * int(s), cx - int(s) + i * int(s), cy - 1, cy + 1, top - 1, top + int(2 * s), BONE)
    elif kind == "brute":
        st.box(hx + hs // 3, hx + hs // 3 + 1, cy - 1, cy + 1, hz + hs // 2, hz + hs, BLOOD)
    elif kind == "tank":
        st.box(hx - hs // 2, hx + hs // 3, cy - hs // 2, cy + hs // 2, hz + hs - 1, hz + hs + int(s), HAIR_A)
        st.box(cx - td // 2 - int(s) + hunch // 2, cx - td // 2 + hunch // 2, cy - tw // 2 + int(s), cy + tw - tw // 2 - int(s), leg_h + int(s), top + int(s), STEEL)
        st.box(cx - int(s), cx + int(2 * s), cy - tw // 2 - int(s), cy - tw // 2 + int(s), top - int(3 * s), top + int(s), STEEL)
        st.box(cx - int(s), cx + int(2 * s), cy + tw // 2 - int(s), cy + tw // 2 + int(s), top - int(3 * s), top + int(s), STEEL)
        for i in range(0, tw, max(2, int(2 * s))):
            st.box(cx - td // 2 - int(s), cx - td // 2, cy - tw // 2 + i, cy - tw // 2 + i + 1, top, top + int(3 * s), SPIKE)
        for i in range(5):
            st.box(cx + hunch, cx + hunch + max(1, int(s)), cy - tw // 3 + i * max(1, int(s)), cy - tw // 3 + i * max(1, int(s)) + 1, top - int(2 * s), top - int(s), CHAIN)
        st.box(cx - 1, cx + 2, cy - 1, cy + 1, 0, max(1, int(s)), BLOOD)
    elif kind == "slimer":
        st.box(hx, hx + hs // 2, cy - 1, cy + 1, hz, hz + max(1, int(s)), SLIME)
        st.box(cx - 2, cx + int(3 * s), cy - int(2 * s), cy + int(2 * s), 0, max(2, int(s)), SLIME)
    elif kind == "boomer":
        for px, py, pz in ((-2, -2, 2), (1, 2, 3), (-1, 2, 1), (2, -1, 2), (0, 0, 4)):
            st.orb(cx + px * s / 2, cy + py * s / 2, leg_h + th * 0.5 + pz, max(1.2, s * 0.7), max(1.2, s * 0.7), max(1.2, s * 0.7), PUSTULE)
    # arms
    aw = max(2, int(2 * s)) if not heavy else int(3 * s)
    if kind == "tank":
        aw = int(3.5 * s)
    az = top - aw
    reach_base = 7 if kind == "hunter" else (5 if kind == "boomer" else 4)
    for side in (-1, 1):
        y0 = cy - tw // 2 - aw if side < 0 else cy + tw - tw // 2
        if pose == "roar":
            st.box(cx + hunch - aw // 2, cx + hunch + aw - aw // 2, y0, y0 + aw, az, min(H, az + int((5 + 2 * k) * s)), skin)
            continue
        if heavy and pose in ("walk", "stumble") and kind == "tank":
            reach = int((3 + (1 if (k + (side > 0)) % 2 else -1)) * s)
            st.box(cx + hunch - 1, cx + hunch - 1 + max(2, reach), y0, y0 + aw, az - int(3 * s), az + aw, skin)
            st.box(cx + hunch - 1, cx + hunch + 1, y0, y0 + aw, az, az + aw, shirt)
            continue
        reach = int((reach_base if pose not in ("lunge", "charge", "pounce") else reach_base + 2) * s)
        if pose == "lunge":
            reach += int(2 * s) * k
        if pose == "pounce":
            reach += int(3 * s)
        bob = (k + (side > 0)) % 2 if pose == "walk" else 0
        hand = CLAW if kind == "hunter" else skin
        st.box(cx + hunch - 1, cx + hunch - 1 + reach + bob, y0, y0 + aw, az - bob, az + aw - bob, hand if kind == "hunter" else skin)
        st.box(cx + hunch - 1, cx + hunch + max(1, int(s)), y0, y0 + aw, az, az + aw, shirt)
        if kind == "slimer":
            st.box(cx + hunch + reach - 2, cx + hunch + reach, y0, y0 + aw, 0, az, SLIME)
        if kind == "hunter":
            st.box(cx + hunch + reach - 1, cx + hunch + reach + int(s), y0, y0 + max(1, aw // 2), az - bob, az - bob + 1, CLAW)
    # cool rim along the shoulder line so night grade still separates the body
    st.box(cx + hunch, cx + hunch + max(1, int(s)), cy - tw // 2, cy - tw // 2 + max(1, int(s)), top - 1, top, RIM)
    st.box(cx + hunch, cx + hunch + max(1, int(s)), cy + tw // 2 - max(1, int(s)), cy + tw // 2, top - 1, top, RIM)
    return st


def shambler(variant, pose, k):
    kind = ("shambler_a", "shambler_b", "shambler_c")[variant]
    skin = SKIN[variant]
    shirt = (COAT_A, COAT_B, COAT_C)[variant]
    pants = PANTS_B if variant == 1 else PANTS
    if variant == 2:
        shirt = COAT_C
    return _figure(1.8, skin, (160, 186, 150), shirt, pants, pose, k, kind=kind)


def brute(pose, k):
    return _figure(2.55, SKIN_A, (160, 186, 150), APRON, PANTS, pose, k, heavy=True, kind="brute")


def tank(pose, k):
    return _figure(3.55, (186, 218, 176), (140, 170, 134), (172, 152, 132), (154, 134, 116), pose, k, heavy=True, kind="tank")


def slimer(pose, k):
    return _figure(1.7, SKIN_B, (150, 180, 158), (172, 160, 130), PANTS, pose, k, kind="slimer")


def boomer(pose, k):
    return _figure(2.15, BOOMER, (160, 188, 154), COAT_A, PANTS, pose, k, kind="boomer")


def hunter(pose, k):
    return _figure(1.85, SKIN_B, (150, 180, 158), HOOD, PANTS, pose, k, kind="hunter")


def shadow_frames(grid, n_head):
    sc = shadow_canvas(grid.shape)
    fr = [render_shadow(grid, i * 360.0 / n_head, canvas=sc) for i in range(n_head)]
    c = sc // 2
    mx = my = 0
    for f in fr:
        ys, xs = np.nonzero(f[..., 3])
        if len(xs) == 0:
            continue
        mx, my = max(mx, abs(xs - c).max()), max(my, abs(ys - c).max())
    mx, my = int(mx) + 1, int(my) + 1
    return [f[c - my:c + my, c - mx:c + mx] for f in fr], (2 * mx, 2 * my)


def render_rows(rows, n_head, P):
    canvas = max(canvas_for(r.shape) for r in rows)
    out = []
    for g in rows:
        cols = list(P.cols)
        gi = g
        if (g < 0).any():
            gi = np.where(g < 0, len(cols), g)
            cols = cols + [FLASH + (255,)]
        out.append([render_frame(gi, cols, i * 360.0 / n_head, canvas=canvas) for i in range(n_head)])
    mx = my = 0
    c = canvas // 2
    for row in out:
        for f in row:
            ys, xs = np.nonzero(f[..., 3])
            if len(xs):
                mx = max(mx, abs(xs - c).max())
                my = max(my, abs(ys - c).max())
    mx, my = int(mx) + 1, int(my) + 1
    out = [[f[c - my:c + my, c - mx:c + mx] for f in row] for row in out]
    return out, (int(2 * mx), int(2 * my))


def shambler_names():
    for v in range(3):
        for k in range(4):
            yield "v%d_walk_%d" % (v, k), v, "walk", k
        for k in range(2):
            yield "v%d_lunge_%d" % (v, k), v, "lunge", k


def build():
    blocks = []
    shadows = []
    # Shamblers share one palette and one crop so the three variants line up.
    P = Pal()
    sh_rows, sh_names = [], []
    shadow_src = None
    for name, v, pose, k in shambler_names():
        st = shambler(v, pose, k)
        if shadow_src is None:
            # rebuild with the shared pal by re-stamping through P
            pass
        mapped = np.zeros_like(st.g)
        for i, col in enumerate(st.P.cols):
            if i:
                mapped[st.g == i] = P(col[:3])
        if shadow_src is None:
            shadow_src = mapped.copy()
        sh_rows.append(mapped)
        sh_names.append(name)
    sh_rows.append(flash_of(sh_rows[0]))
    sh_names.append("flash")
    raw, cv = render_rows(sh_rows, HEADINGS, P)
    blocks.append(("shambler", raw, cv, sh_names, 3))
    shadows.append(("shambler",) + shadow_frames(np.abs(shadow_src), HEADINGS))

    def add_kind(kind, maker, variants=1):
        rows, names = [], []
        P = None
        src = None
        poses = [("walk", k) for k in range(4)]
        if kind == "tank":
            poses += [("roar", 0), ("roar", 1), ("charge", 0), ("stumble", 0)]
        elif kind == "hunter":
            poses += [("windup", 0), ("pounce", 0)]
        for pose, k in poses:
            st = maker(pose, k)
            if P is None:
                P = Pal()
            mapped = np.zeros_like(st.g)
            for i, col in enumerate(st.P.cols):
                if i:
                    mapped[st.g == i] = P(col[:3])
            if src is None:
                src = mapped.copy()
            rows.append(mapped)
            names.append("%s_%d" % (pose, k) if pose in ("walk", "roar") else pose)
        rows.append(flash_of(rows[0]))
        names.append("flash")
        raw, cv = render_rows(rows, HEADINGS, P)
        blocks.append((kind, raw, cv, names, variants))
        shadows.append((kind,) + shadow_frames(np.abs(src), HEADINGS))

    add_kind("slimer", slimer)
    add_kind("hunter", hunter)
    add_kind("brute", brute)
    add_kind("tank", tank)
    add_kind("boomer", boomer)

    graded_blocks = []
    for kind, raw, cv, names, variants in blocks:
        graded = [[mass_grade(f) for f in row] for row in raw]
        graded_blocks.append((kind, graded, raw, cv, names, variants))

    # Shelf-pack every row strip (16 headings) plus the shadow strips.
    strips = []
    for kind, graded, _raw, (fw, fh), names, _variants in graded_blocks:
        for i, name in enumerate(names):
            strips.append((kind, name, graded[i], fw, fh, False))
    for kind, sfr, (sw, sh) in shadows:
        strips.append((kind, "shadow", sfr, sw, sh, True))
    strips.sort(key=lambda s: -s[4])
    x = y = shelf_h = 0
    placed = []
    for item in strips:
        _kind, _name, frames, fw, fh, _sh = item
        w = fw * HEADINGS
        if w > 2048:
            raise SystemExit("strip wider than 2048: %s %s %d" % (_kind, _name, w))
        if x + w > 2048:
            y += shelf_h
            x = 0
            shelf_h = 0
        placed.append((item, x, y))
        x += w
        shelf_h = max(shelf_h, fh)
    Ht = y + shelf_h
    Wd = 0
    for (item, px, py) in placed:
        fw = item[3]
        Wd = max(Wd, px + fw * HEADINGS)
    if Ht > 2048 or Wd > 2048:
        raise SystemExit("atlas exceeds 2048: %d x %d" % (Wd, Ht))
    atlas = Image.new("RGBA", (Wd, Ht))
    meta = {"texture": "zombies.png", "headings": HEADINGS, "kinds": {}, "sample_colours": {
        "SKIN_A": list(SKIN_A), "SKIN_B": list(SKIN_B), "SKIN_C": list(SKIN_C),
        "BLOOD": list(BLOOD), "EYE": list(EYE), "FLASH": list(FLASH),
        "MASS_DESAT": MASS_DESAT, "MASS_DARK": MASS_DARK,
    }}
    kind_rows = {k: {} for k, *_ in graded_blocks}
    kind_frame = {}
    for kind, _g, _r, (fw, fh), names, variants in graded_blocks:
        kind_frame[kind] = (fw, fh, variants, names)
        meta["kinds"][kind] = {"frame_w": fw, "frame_h": fh, "rows": {}, "variants": variants}
    for (kind, name, frames, fw, fh, is_shadow), px, py in placed:
        for h, img in enumerate(frames):
            atlas.paste(Image.fromarray(img), (px + h * fw, py))
            if is_shadow:
                meta.setdefault("regions", {})["%s/shadow/%d" % (kind, h)] = [px + h * fw, py, fw, fh]
            else:
                meta.setdefault("regions", {})["%s/%s/%d" % (kind, name, h)] = [px + h * fw, py, fw, fh]
        if is_shadow:
            meta["kinds"][kind]["shadow"] = {"frame_w": fw, "frame_h": fh, "alpha": ZOMBIE_SHADOW_ALPHA}
        else:
            meta["kinds"][kind]["rows"][name] = [px, py]
    os.makedirs(OUT, exist_ok=True)
    png = os.path.join(OUT, "zombies.png")
    atlas.save(png)
    write_import(png)
    json.dump(meta, open(os.path.join(OUT, "zombies.json"), "w"), indent=1)
    sw, tw = meta["kinds"]["shambler"]["frame_w"], meta["kinds"]["tank"]["frame_w"]
    print("zombies atlas", atlas.size, {k: (v["frame_w"], v["frame_h"], len(v["rows"]), v["variants"]) for k, v in meta["kinds"].items()})
    if not (tw > sw * 1.6):
        raise SystemExit("tank frame_w %d is not > shambler %d * 1.6" % (tw, sw))
    _compare(graded_blocks)
    _night_report(graded_blocks)
    return meta


def _compare(graded_blocks):
    """Green day render beside the #74 mass grade, plus the grade under night."""
    night = np.array([0x2a / 0x60, 0x35 / 0x59, 1.0], dtype=float)
    thumbs = []
    labels = []
    for kind, graded, raw, _cv, names, _v in graded_blocks:
        # representative row: first walk, heading 3 (a 3/4)
        idx = names.index("v0_walk_0") if kind == "shambler" else names.index("walk_0")
        h = 3
        a, b = raw[idx][h], graded[idx][h]
        c = b.copy()
        rgb = c[..., :3].astype(float) * night
        c[..., :3] = np.clip(rgb, 0, 255).astype(np.uint8)
        thumbs.append((a, b, c))
        labels.append(kind)
    pad = 4
    scale = 3
    tw = max(t[0].shape[1] for t in thumbs)
    th = max(t[0].shape[0] for t in thumbs)
    cell_w, cell_h = tw * scale + pad, th * scale + pad
    cols, rows_n = 3, len(thumbs)
    img = Image.new("RGBA", (cols * cell_w + 80, rows_n * cell_h + 28), (32, 28, 26, 255))
    dr = ImageDraw.Draw(img)
    dr.text((4, 4), "day authored (green v2)   |   #74 mass grade   |   mass grade x night #2a3550", fill=(240, 220, 190, 255))
    for r, (kind, (a, b, c)) in enumerate(zip(labels, thumbs)):
        dr.text((2, 24 + r * cell_h), kind, fill=(220, 210, 190, 255))
        for col, fr in enumerate((a, b, c)):
            big = Image.fromarray(fr).resize((fr.shape[1] * scale, fr.shape[0] * scale), Image.Resampling.NEAREST)
            img.paste(big, (80 + col * cell_w, 22 + r * cell_h), big)
    dest = os.environ.get("ZOMBIE_COMPARE", "/tmp/zombie_v2_green_vs_mass.png")
    os.makedirs(os.path.dirname(dest) or ".", exist_ok=True)
    img.save(dest)
    print("compare", dest, img.size)


def _night_report(graded_blocks):
    night = np.array([0x2a / 0x60, 0x35 / 0x59, 1.0])
    for kind, graded, _raw, _cv, names, _v in graded_blocks:
        idx = 0
        f = graded[idx][3]
        rgb = f[..., :3].astype(float)
        ink = f[..., 3] > 0
        body = ink & (rgb.max(-1) > 28)  # drop the near-black outline
        if not body.any():
            print(kind, "NO BODY")
            continue
        graded_n = rgb[body] * night
        med = np.median(graded_n, 0)
        p20 = np.percentile(graded_n, 20, 0)
        print("%-10s night median RGB %s  p20 %s" % (kind, np.round(med).astype(int).tolist(), np.round(p20).astype(int).tolist()))


if __name__ == "__main__":
    build()
