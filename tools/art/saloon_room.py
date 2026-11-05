#!/usr/bin/env python3
"""Saloon C (night fireplace) voxel diorama — Art package for the hire-crew tab.

Follows tools/art/garage_scenes.py: voxel_render at the shared tilt, bake once,
separate lights overlay, JSON metadata. Room image is 1280x720 (NEAREST from
the workshop-scale crop) so UI seat coords are room-image pixels.

Writes art/saloon/:
  saloon_room.png              backdrop without hireable crew
  saloon_room_lights.png       fireplace + lantern glow only (untinted FX)
  crew_<id>_idle.png           hireable figure sprites (transparent)
  crew_<id>_highlight.png
  crew_<id>_dim.png
  saloon_room.json             UI seat schema (see seats[])

No gameplay / UI code. Colours needed by UI are listed in the JSON under
ui_colours_needed (not written to tuning.gd).
"""
from __future__ import annotations
import json, math, os, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageEnhance

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from voxel_render import render_frame, write_import, TILT_DEG, project_point  # noqa: E402
from palette import PALETTE  # noqa: E402

OUT = os.path.join(HERE, "..", "..", "art", "saloon")
SCALE = 3.4
# Voxel room sized so SCALE * size ~= 1280x720
VIEW = (376, 212)  # same as workshop_bay → 1280x720 at 3.4x
ROOM_PX = (1280, 720)

# Muted night-saloon materials (sample colours; listed for UI, not tuning.gd)
C = {
    "floor_a": (110, 84, 60),
    "floor_b": (98, 74, 52),
    "wall": (96, 78, 64),
    "wall_dk": (52, 40, 32),
    "wood": (120, 90, 64),
    "wood_top": (158, 120, 84),
    "stool": (100, 64, 44),
    "stool_leg": (66, 48, 36),
    "post": (54, 40, 30),
    "stone": (88, 82, 76),
    "hearth": (28, 20, 16),
    "fire": (255, 148, 42),       # emissive
    "fire_hot": (255, 226, 130),  # emissive
    "lantern": (255, 196, 100),   # emissive
    "shirt_a": (90, 140, 170),
    "shirt_b": (200, 170, 70),
    "shirt_c": (180, 80, 64),
    "shirt_d": (96, 150, 90),
    "skin": (220, 175, 135),
    "pants": (52, 48, 44),
    "hat_a": (170, 55, 45),
    "hat_b": (178, 178, 168),
    "hat_c": (100, 84, 60),
    "hat_d": (240, 140, 50),
    "steel": PALETTE["steel_dark"],
}
LIGHTS = {"fire", "fire_hot", "lantern"}
NAMES = ["_"] + list(C)
IDX = {n: i for i, n in enumerate(NAMES)}


def colors(light_only=False):
    out = [(0, 0, 0, 0)]
    for n in NAMES[1:]:
        if light_only and n not in LIGHTS:
            out.append((0, 0, 0, 0))
        else:
            rgb = C[n]
            # emissives: same shade all levels so voxel_render treats as lit
            out.append(tuple(rgb) + (255,))
    return out


def box(g, x0, x1, y0, y1, z0, z1, n):
    sx, sy, sz = g.shape
    g[max(0, x0):min(sx, x1), max(0, y0):min(sy, y1), max(0, z0):min(sz, z1)] = IDX[n]


def figure(g, x, y, z, shirt, hat, own, owner, facing="back", hatstyle="cap"):
    """Seated hireable figure. Stamp owner id on every figure voxel for cropping."""
    # Clear any stool top under the sitter so the body reads.
    box(g, x, x + 6, y, y + 5, z, z + 1, "pants")
    box(g, x, x + 6, y, y + 4, z + 1, z + 8, shirt)          # torso
    box(g, x - 1, x, y, y + 3, z + 3, z + 8, shirt)            # arms
    box(g, x + 6, x + 7, y, y + 3, z + 3, z + 8, shirt)
    box(g, x + 1, x + 5, y, y + 4, z + 8, z + 12, "skin")      # head
    if hatstyle == "wide":
        box(g, x - 1, x + 7, y - 1, y + 5, z + 11, z + 12, hat)
        box(g, x + 1, x + 5, y, y + 4, z + 12, z + 14, hat)
    elif hatstyle == "mohawk":
        box(g, x + 2, x + 4, y, y + 4, z + 12, z + 16, hat)
    elif hatstyle == "hood":
        box(g, x, x + 6, y, y + 4, z + 8, z + 13, hat)
        box(g, x + 1, x + 5, y + 3, y + 4, z + 9, z + 12, "skin")
    else:
        box(g, x + 1, x + 5, y, y + 4, z + 11, z + 13, hat)
        brim = 3 if facing == "front" else -1
        box(g, x + 1, x + 5, y + brim, y + brim + 2, z + 11, z + 12, hat)
    sx, sy, sz = g.shape
    body = {shirt, hat, "skin", "pants"}
    for xx in range(max(0, x - 2), min(sx, x + 8)):
        for yy in range(max(0, y - 2), min(sy, y + 6)):
            for zz in range(max(0, z), min(sz, z + 17)):
                if g[xx, yy, zz] > 0 and NAMES[g[xx, yy, zz]] in body:
                    own[xx, yy, zz] = owner
    return (x + 3, y + 2, z + 13)


def build_room(with_crew=True):
    """Night saloon: left bar, lantern tables, fireplace on the right.
    Hireable seats stay left/center so a left-side hire card never covers the fire.
    """
    X, Y, Z = VIEW[0] + 8, 200, 70
    g = np.zeros((X, Y, Z), np.int16)
    own = np.zeros((X, Y, Z), np.int16)
    rng = np.random.default_rng(9)
    # floor boards
    for x in range(0, X, 8):
        n = "floor_a" if (x // 8) % 2 == 0 else "floor_b"
        box(g, x, min(X, x + 8), 0, Y, 0, 1, n)
    # back wall
    box(g, 0, X, 0, 6, 0, Z, "wall")
    for x in range(8, X, 36):
        box(g, x, x + 2, 4, 7, 0, Z, "post")
    # fireplace mid-right
    box(g, 250, 320, 4, 14, 1, 36, "stone")
    box(g, 262, 308, 12, 15, 2, 18, "hearth")
    box(g, 268, 302, 13, 17, 2, 16, "fire")
    box(g, 276, 294, 14, 17, 4, 13, "fire_hot")
    box(g, 282, 290, 15, 16, 8, 12, "fire_hot")
    # left bar
    box(g, 14, 150, 18, 30, 1, 18, "wood")
    box(g, 12, 152, 16, 32, 18, 20, "wood_top")
    # stools at bar
    bar_stools = [(28, 34), (55, 34), (82, 34), (110, 34)]
    for sx, sy in bar_stools:
        box(g, sx + 2, sx + 4, sy + 1, sy + 3, 1, 12, "stool_leg")
        box(g, sx, sx + 6, sy, sy + 5, 12, 14, "stool")
    # lantern tables (left / center — clear of fireplace & right card strip)
    tables = [(40, 95), (110, 88)]
    for tx, ty in tables:
        box(g, tx + 7, tx + 9, ty + 4, ty + 6, 1, 14, "stool_leg")
        box(g, tx, tx + 18, ty, ty + 12, 14, 16, "wood_top")
        box(g, tx + 6, tx + 12, ty + 3, ty + 9, 16, 24, "lantern")
    # table stools
    table_stools = [(32, 100), (60, 100), (102, 92), (130, 92)]
    for sx, sy in table_stools:
        box(g, sx + 2, sx + 4, sy + 1, sy + 3, 1, 12, "stool_leg")
        box(g, sx, sx + 6, sy, sy + 5, 12, 14, "stool")
    # crate prop
    box(g, 8, 28, 130, 150, 1, 14, "wood")
    # bartender (own=0, not hireable)
    if with_crew:
        figure(g, 60, 8, 2, "shirt_c", "hat_c", own, 0, facing="front", hatstyle="hood")

    # Hireable seats: 4 slots. Voxel footprint centres + head anchors.
    # Keep x well left of fireplace (fireplace starts ~250).
    seats_spec = [
        # id, slot, stool voxel xy, shirt, hat, hatstyle, facing
        ("bar_left", 0, (55, 34), "shirt_a", "hat_a", "wide", "back"),
        ("bar_mid", 1, (110, 34), "shirt_b", "hat_b", "wide", "front"),
        ("table_left", 2, (60, 100), "shirt_d", "hat_c", "cap", "front"),
        ("table_mid", 3, (102, 92), "shirt_c", "hat_d", "mohawk", "front"),
    ]
    anchors_vox = {}
    if with_crew:
        for sid, slot, (sx, sy), shirt, hat, hs, facing in seats_spec:
            owner = slot + 1
            anchors_vox[sid] = figure(g, sx, sy, 14, shirt, hat, own, owner, facing=facing, hatstyle=hs)
    else:
        for sid, slot, (sx, sy), *_ in seats_spec:
            anchors_vox[sid] = (sx + 3, sy + 2, 28)

    return g, own, seats_spec, anchors_vox


def render_crop(g, cols, lift_xy):
    X, Y, Z = g.shape
    canvas = int(math.hypot(X, Y)) + Z + 8
    img = render_frame(g, cols, 0.0, canvas=canvas, hd=True)
    # floor fill under feet
    floor = g.copy()
    floor[:, :, 1:] = 0
    base = render_frame(floor, cols, 0.0, canvas=canvas, hd=True)
    a = img[..., 3:4] > 0
    img = np.where(a, img, base)
    # project lift/focus to crop
    t = math.radians(TILT_DEG)
    cx, cy = X / 2.0, Y / 2.0
    lx = (lift_xy[0] - cx) + canvas / 2
    ly = ((lift_xy[1] - cy) * math.cos(t) - 8 * math.sin(t)) + canvas / 2
    # crop VIEW around a calm centre (slightly left so fireplace sits right)
    left = int(round(lx - VIEW[0] * 0.42))
    top = int(round(ly - 290 / SCALE))
    left = max(0, min(left, img.shape[1] - VIEW[0]))
    top = max(0, min(top, img.shape[0] - VIEW[1]))
    crop = img[top:top + VIEW[1], left:left + VIEW[0]].copy()
    return crop, (left, top), (lx, ly), canvas


def to_room_px(img_view):
    """NEAREST upscale VIEW → 1280x720."""
    return Image.fromarray(img_view).resize(ROOM_PX, Image.Resampling.NEAREST)


def vox_to_room_px(pt, gshape, crop_origin, canvas):
    """Voxel (x,y,z) → room-image pixel via the same projection as the crop."""
    X, Y, Z = gshape
    # project_point returns offset from frame centre; rebuild absolute like render
    t = math.radians(TILT_DEG)
    cx, cy = X / 2.0, Y / 2.0
    # heading 0: same as render_frame(heading_deg=0)
    wx = pt[0] - cx
    wy = pt[1] - cy
    px = wx + canvas / 2
    py = (wy * math.cos(t) - pt[2] * math.sin(t)) + canvas / 2
    vx = px - crop_origin[0]
    vy = py - crop_origin[1]
    return int(round(vx * SCALE)), int(round(vy * SCALE))


def night_tint_rgba(arr):
    """Warm night grade; keep emissives bright. Readable materials, not crushed black."""
    a = arr.astype(np.float32)
    rgb, al = a[..., :3], a[..., 3:4]
    mx = rgb.max(-1); mn = rgb.min(-1)
    sat = (mx - mn) / (mx + 1e-3)
    emis = ((sat > 0.30) & (mx > 140) & (rgb[..., 0] > rgb[..., 2] * 1.05)) | (mx > 220)
    tint = np.array([0x51, 0x2b, 0x11], dtype=np.float32) / 255.0
    base = np.clip(rgb / 255.0, 0, 1)
    lum = (base @ np.array([0.299, 0.587, 0.114]))[..., None]
    # stain + keep some material separation
    graded = np.clip(lum * 0.75 * tint * 2.2 + base * tint * 0.55, 0, 1) * 255.0
    out = np.where(emis[..., None], rgb, graded)
    return np.concatenate([out, al], -1).astype(np.uint8)


def variant_sprite(base_rgba, mode):
    """idle / highlight (gold rim) / dim from a cropped figure RGBA."""
    im = Image.fromarray(base_rgba).convert("RGBA")
    if mode == "idle":
        return im
    a = np.array(im).astype(np.float32)
    if mode == "dim":
        a[..., :3] *= 0.40
        a[..., 3] *= 0.85
        return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA")
    # highlight: gold outline
    mask = a[..., 3] > 10
    mimg = Image.fromarray((mask.astype(np.uint8) * 255))
    dil = np.array(mimg.filter(ImageFilter.MaxFilter(5))) > 0
    edge = dil & ~mask
    a[edge] = (225, 180, 65, 255)  # gold
    a[mask, :3] = np.clip(a[mask, :3] * 1.12, 0, 255)
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA")


def crop_owner(full_rgba, own_map, owner_id, pad=4):
    ys, xs = np.where(own_map == owner_id)
    if len(xs) == 0:
        return None, None
    x0, x1 = max(0, xs.min() - pad), min(full_rgba.shape[1], xs.max() + pad + 1)
    y0, y1 = max(0, ys.min() - pad), min(full_rgba.shape[0], ys.max() + pad + 1)
    sprite = full_rgba[y0:y1, x0:x1].copy()
    # clear non-owner / non-edge
    om = own_map[y0:y1, x0:x1]
    keep = (om == owner_id) | (om == -1)  # -1 unused; we only have owner ids
    # actually own_map elsewhere is 0; zero alpha for other owners
    other = (om != owner_id) & (om != 0)  # wait own empty is 0
    # Better: keep pixels that are this owner OR transparent already
    sprite_a = sprite.copy()
    sprite_a[om != owner_id, 3] = 0
    return sprite_a, (x0, y0)


def main():
    os.makedirs(OUT, exist_ok=True)
    cols = colors(False)
    cols_lights = colors(True)

    # Background without hireable crew (bartender ok)
    g_bg, _, seats_spec, anchors_vox = build_room(with_crew=True)
    # wipe hireable owners 1..4 from bg
    g_bg_only = g_bg.copy()
    # rebuild clean bg: no crew at all then add bartender only
    g_bg, own_bg, seats_spec, anchors_vox = build_room(with_crew=False)
    # bartender alone
    figure(g_bg, 60, 8, 2, "shirt_c", "hat_c", own_bg, 0, facing="front", hatstyle="hood")

    # Full with crew for sprite extraction + seat projection
    g_full, own_full, seats_spec, anchors_vox = build_room(with_crew=True)

    focus = (140, 70)  # room focus left-of-center
    bg_crop, origin, _, canvas = render_crop(g_bg, cols, focus)
    bg_crop = night_tint_rgba(bg_crop)
    # lights-only from full scene (fire + lanterns)
    lights_crop, _, _, _ = render_crop(g_full, cols_lights, focus)

    # Full render with owner map for sprites
    X, Y, Z = g_full.shape
    canvas_f = int(math.hypot(X, Y)) + Z + 8
    full_img, own_img = render_frame(g_full, cols, 0.0, canvas=canvas_f, hd=True, owner=own_full)
    # align crop
    left, top = origin
    # recompute origin consistently from focus
    bg_crop2, origin, _, canvas = render_crop(g_bg, cols, focus)
    left, top = origin
    full_crop_raw = full_img[top:top + VIEW[1], left:left + VIEW[0]].copy()
    own_crop = own_img[top:top + VIEW[1], left:left + VIEW[0]]
    full_crop = night_tint_rgba(full_crop_raw)  # for composites only
    # restore emissives from lights into bg (so fire reads on backdrop too? 
    # No — lights are a separate overlay. Bg keeps baked fire voxels tinted unless emis preserved.
    # Re-apply emis from pre-tint by compositing lights onto bg at bake time is wrong.
    # Better: night_tint already keeps warm bright. Good.

    room = to_room_px(bg_crop)
    lights = to_room_px(lights_crop)
    # boost lights alpha where non-zero
    la = np.array(lights)
    la[..., 3] = np.where(la[..., :3].max(-1) > 8, 255, 0).astype(np.uint8)
    lights = Image.fromarray(la)

    room_path = os.path.join(OUT, "saloon_room.png")
    lights_path = os.path.join(OUT, "saloon_room_lights.png")
    room.save(room_path)
    lights.save(lights_path)
    write_import(room_path)
    write_import(lights_path)

    seats_out = []
    for sid, slot, (sx, sy), shirt, hat, hs, facing in seats_spec:
        owner = slot + 1
        spr, local = crop_owner(full_crop_raw, own_crop, owner, pad=3)
        if spr is None:
            # fallback empty
            spr = np.zeros((24, 16, 4), np.uint8)
            local = (0, 0)
        # upscale sprite
        idle = variant_sprite(spr, "idle").resize(
            (max(16, int(spr.shape[1] * SCALE)), max(16, int(spr.shape[0] * SCALE))),
            Image.Resampling.NEAREST,
        )
        hi = variant_sprite(spr, "highlight").resize(idle.size, Image.Resampling.NEAREST)
        dim = variant_sprite(spr, "dim").resize(idle.size, Image.Resampling.NEAREST)
        idle_p = f"crew_{sid}_idle.png"
        hi_p = f"crew_{sid}_highlight.png"
        dim_p = f"crew_{sid}_dim.png"
        idle.save(os.path.join(OUT, idle_p))
        hi.save(os.path.join(OUT, hi_p))
        dim.save(os.path.join(OUT, dim_p))
        for p in (idle_p, hi_p, dim_p):
            write_import(os.path.join(OUT, p))

        # position: top-left of sprite in room pixels
        pos = (int(local[0] * SCALE), int(local[1] * SCALE))
        # anchor at head
        ax, ay = vox_to_room_px(anchors_vox[sid], g_full.shape, origin, canvas)
        ax = int(np.clip(ax, 0, ROOM_PX[0] - 1))
        ay = int(np.clip(ay, 0, ROOM_PX[1] - 1))
        # hit rect >= 64x64 centred on figure
        hw = max(64, idle.size[0] + 16)
        hh = max(64, idle.size[1] + 16)
        hx = int(pos[0] + idle.size[0] / 2 - hw / 2)
        hy = int(pos[1] + idle.size[1] / 2 - hh / 2)
        hx = int(np.clip(hx, 0, ROOM_PX[0] - hw))
        hy = int(np.clip(hy, 0, ROOM_PX[1] - hh))
        # z-order by screen y (lower on screen = higher z)
        z = int(pos[1] + idle.size[1])
        # fireplace is on the right → cards open on the left
        card_side = "left"
        seats_out.append({
            "id": sid,
            "slot": slot,
            "pos": [pos[0], pos[1]],
            "z": z,
            "hit_rect": [hx, hy, hw, hh],
            "anchor": [ax, ay],
            "card_side": card_side,
            "sprites": {
                "idle": f"res://art/saloon/{idle_p}",
                "highlight": f"res://art/saloon/{hi_p}",
                "dim": f"res://art/saloon/{dim_p}",
            },
        })

    meta = {
        "room_size": [ROOM_PX[0], ROOM_PX[1]],
        "scale": SCALE,
        "tilt_deg": TILT_DEG,
        "background": "res://art/saloon/saloon_room.png",
        "lights": "res://art/saloon/saloon_room_lights.png",
        "lights_note": "Fireplace + lantern glow only. Composite above the world night grade; do not CanvasModulate this layer.",
        "seats": seats_out,
        "ui_colours_needed": {
            "PANEL": "#181d20",
            "PANEL_BODY": "#24292f",
            "HEADER": "#1e1b14",
            "ACCENT_GOLD": "#e1b441",
            "HAIRLINE": "#3a3d3c",
            "TEXT": "#ccc8bc",
            "TEXT_DIM": "#8a8a84",
            "RARITY_COMMON": "#8a8a84",
            "RARITY_UNCOMMON": "#5aa05a",
            "RARITY_RARE": "#4a7ac8",
            "RARITY_EPIC": "#9a5ac8",
            "RARITY_LEGENDARY": "#e1b441",
            "RARITY_MYTHIC": "#c4473f",
            "NIGHT_WORLD": "#512b11",
        },
        "ui_colours_note": "Do not add these to tuning.gd from this PR. UI #68 (or follow-up) owns the palette constants.",
    }
    json.dump(meta, open(os.path.join(OUT, "saloon_room.json"), "w"), indent=1)
    print("saloon room baked", meta["room_size"], "seats", len(seats_out))
    for s in seats_out:
        print(" ", s["id"], "pos", s["pos"], "hit", s["hit_rect"], "anchor", s["anchor"])


if __name__ == "__main__":
    main()
