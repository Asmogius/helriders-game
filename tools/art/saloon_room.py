#!/usr/bin/env python3
"""Saloon C bake from the approved concept C scene (near-iso ~52°)."""
from __future__ import annotations
import glob, json, os, sys
import numpy as np
from PIL import Image, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "art", "saloon")
# concepts vendored
from saloon_iso import night_grade, S, TOP, FRONT  # noqa: E402
from saloon_concept_c import build_C as _build_C  # noqa: E402

SPRITE_SCALE = 1.35
SEAT_IDS = ["bar_left", "table_left", "table_mid", "table_right"]
# Concept C crew() seat voxel centres
SEAT_VOX = [(32, 21, 9), (44, 46, 9), (58, 42, 9), (86, 42, 9)]


def write_import(path: str) -> None:
    try:
        sys.path.insert(0, HERE)
        from voxel_render import write_import as _wi
        _wi(path); return
    except Exception:
        pass
    rel = "res://" + os.path.relpath(path, os.path.join(HERE, "..", "..")).replace("\\", "/")
    open(path + ".import", "w").write(
        f'[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n'
        f'uid="uid://s{abs(hash(path)) % 10**10}"\n'
        f'path="res://.godot/imported/{os.path.basename(path)}.ctex"\n\n'
        f'[deps]\n\nsource_file="{rel}"\n\n[params]\n\ncompress/mode=0\nmipmaps/generate=false\n'
    )


def build_C(with_hireables: bool):
    sc, light, _seats = _build_C(with_hireables=with_hireables)
    return sc, light


def lights_overlay(em_mask, rgb):
    out = np.zeros((720, 1280, 4), np.uint8)
    out[em_mask, :3] = np.clip(rgb[em_mask], 0, 255).astype(np.uint8)
    out[em_mask, 3] = 255
    bloom = np.array(Image.fromarray(out).filter(ImageFilter.GaussianBlur(7))).astype(np.float32)
    bloom[..., 3] *= 0.55
    base = Image.fromarray(np.clip(bloom, 0, 255).astype(np.uint8), "RGBA")
    return Image.alpha_composite(base, Image.fromarray(out, "RGBA"))


def grade_with_glow(img, em):
    a = night_grade(np.clip(img, 0, 255), em).astype(np.float32)
    e = np.zeros_like(a); e[em] = a[em]
    glow = np.array(
        Image.fromarray(np.clip(e, 0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(12))
    ).astype(np.float32)
    return a + glow * 1.55


def variant_sprite(base_rgba, mode):
    im = Image.fromarray(base_rgba).convert("RGBA")
    if mode == "idle":
        return im
    a = np.array(im).astype(np.float32)
    if mode == "dim":
        a[..., :3] *= 0.42; a[..., 3] *= 0.85
        return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA")
    mask = a[..., 3] > 10
    dil = np.array(Image.fromarray((mask.astype(np.uint8) * 255)).filter(ImageFilter.MaxFilter(9))) > 0
    a[dil & ~mask] = (225, 180, 65, 255)
    a[mask, :3] = np.clip(a[mask, :3] * 1.15, 0, 255)
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA")


def crop_owner(rgba, own, owner_id, pad=8):
    ys, xs = np.where(own == owner_id)
    if len(xs) == 0:
        return None, None
    x0, x1 = max(0, int(xs.min()) - pad), min(rgba.shape[1], int(xs.max()) + pad + 1)
    y0, y1 = max(0, int(ys.min()) - pad), min(rgba.shape[0], int(ys.max()) + pad + 1)
    spr = rgba[y0:y1, x0:x1].copy()
    spr[own[y0:y1, x0:x1] != owner_id, 3] = 0
    return spr, (x0, y0)


def vox_to_px(x, y, z, oy):
    return int(x * S + S / 2), int(oy + y * TOP - z * FRONT - FRONT / 2)


def main():
    os.makedirs(OUT, exist_ok=True)
    # wipe obsolete seat sprites from prior bake
    for f in glob.glob(os.path.join(OUT, "crew_*.png*")):
        os.remove(f)

    sc_bg, light = build_C(False)
    img_bg, own_bg, em_bg, oy = sc_bg.render(light)
    graded_bg = grade_with_glow(img_bg, em_bg)
    room = Image.fromarray(np.clip(graded_bg, 0, 255).astype(np.uint8), "RGB").convert("RGBA")
    lights = lights_overlay(em_bg, np.clip(img_bg, 0, 255))
    room_path = os.path.join(OUT, "saloon_room.png")
    lights_path = os.path.join(OUT, "saloon_room_lights.png")
    room.save(room_path); lights.save(lights_path)
    write_import(room_path); write_import(lights_path)

    sc_full, light = build_C(True)
    img_full, own_full, em_full, oy = sc_full.render(light)
    graded = grade_with_glow(img_full, em_full)
    body = (own_full > 0) & ~em_full
    graded[body, :3] = np.clip(graded[body, :3] * 1.40 + 14.0, 0, 255)
    rgba = np.concatenate([
        np.clip(graded, 0, 255).astype(np.uint8),
        np.where(own_full > 0, 255, 0).astype(np.uint8)[..., None],
    ], -1)

    seats_out = []
    for slot, sid in enumerate(SEAT_IDS):
        owner = slot + 1
        spr, local = crop_owner(rgba, own_full, owner, pad=8)
        if spr is None:
            print("WARN missing", sid); continue
        idle0 = variant_sprite(spr, "idle")
        nw = max(16, int(idle0.width * SPRITE_SCALE))
        nh = max(16, int(idle0.height * SPRITE_SCALE))
        idle = idle0.resize((nw, nh), Image.Resampling.NEAREST)
        hi = variant_sprite(spr, "highlight").resize((nw, nh), Image.Resampling.NEAREST)
        dim = variant_sprite(spr, "dim").resize((nw, nh), Image.Resampling.NEAREST)
        cx = local[0] + spr.shape[1] / 2
        cy = local[1] + spr.shape[0] / 2
        pos = [int(cx - nw / 2), int(cy - nh / 2)]
        for im, name in ((idle, f"crew_{sid}_idle.png"),
                         (hi, f"crew_{sid}_highlight.png"),
                         (dim, f"crew_{sid}_dim.png")):
            path = os.path.join(OUT, name); im.save(path); write_import(path)
        sx, sy, sz = SEAT_VOX[slot]
        ax, ay = vox_to_px(sx + 3, sy + 2, sz + 14, oy)
        ax = int(np.clip(ax, 0, 1279)); ay = int(np.clip(ay, 0, 719))
        hw = max(64, nw + 24); hh = max(64, nh + 24)
        hx = int(np.clip(pos[0] + nw / 2 - hw / 2, 0, 1280 - hw))
        hy = int(np.clip(pos[1] + nh / 2 - hh / 2, 0, 720 - hh))
        side = "right" if (pos[0] + nw // 2) < 700 else "left"
        seats_out.append({
            "id": sid, "slot": slot, "pos": pos, "z": int(pos[1] + nh),
            "hit_rect": [hx, hy, hw, hh], "anchor": [ax, ay], "card_side": side,
            "sprites": {
                "idle": f"res://art/saloon/crew_{sid}_idle.png",
                "highlight": f"res://art/saloon/crew_{sid}_highlight.png",
                "dim": f"res://art/saloon/crew_{sid}_dim.png",
            },
        })

    meta = {
        "room_size": [1280, 720],
        "camera": "near-isometric ~52° (S=8,TOP=5,FRONT=10,SIDE=4) — identical to saloon_v2 concept C",
        "tilt_note": "Not garage TILT 30°. Matches approved concepts/saloon_v2/saloon_c_*.png.",
        "sun": "upper-left → hard shadows down-right",
        "night": "#512b11 world grade; fire/lanterns untinted on lights plate",
        "background": "res://art/saloon/saloon_room.png",
        "lights": "res://art/saloon/saloon_room_lights.png",
        "lights_note": "Fireplace + lantern glow. Composite above world night grade; do not CanvasModulate.",
        "sprite_scale": SPRITE_SCALE,
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
    json.dump(meta, open(os.path.join(OUT, "saloon_room.json"), "w"), indent=1)
    print("baked", [(s["id"], s["pos"], s["card_side"], s["hit_rect"][2:]) for s in seats_out])


if __name__ == "__main__":
    main()
