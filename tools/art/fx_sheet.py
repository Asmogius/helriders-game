#!/usr/bin/env python3
"""V4 style sample: the particle atlas for one explosion and the new tracers.

Writes art/fx/fx_atlas.png + fx_atlas.json (region rects by name). Pixel art at
1 px per texel, like the 1 px-per-voxel rigs: hard edges, 4-5 quantised tones,
ordered dithering instead of soft gradients. Deterministic (fixed seed).

Colours: tuning.gd COL_ORANGE / COL_ENEMY / COL_STEEL / COL_RUST and the
smoke grey already used in fx.gd. Sample-local colours that UI may want to move
into tuning.gd are in SAMPLE_COLOURS (listed in the PR).
Regions are white/grey where the game tints them (tracer glow), coloured where
the colour is part of the look (fireball, flash).
"""
import json, os
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "art", "fx")

# tuning.gd colours (0-255)
ORANGE = (237, 122, 43)     # COL_ORANGE
STEEL = (79, 82, 85)        # COL_STEEL
RUST = (117, 64, 33)        # COL_RUST
SMOKE = (89, 84, 77)        # fx.gd dust Color(0.35, 0.33, 0.3)
# Sample-local (proposed for tuning.gd, owned by UI/P0):
SAMPLE_COLOURS = {
    "FX_HOT": (255, 217, 102),       # fireball core yellow (fx.gd uses 1.0,0.85,0.4 inline)
    "FX_WHITE_HOT": (255, 242, 204), # flash / tracer core
    "FX_EMBER": (153, 46, 20),       # cooling fireball edge
    "FX_SCORCH": (18, 16, 15),       # scorch decal
}
HOT, WHITE, EMBER, SCORCH = (SAMPLE_COLOURS[k] for k in ("FX_HOT", "FX_WHITE_HOT", "FX_EMBER", "FX_SCORCH"))
BAYER = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) / 16.0
rng = np.random.default_rng(7)


def rgba(c, a=255):
    return np.array([*c, a], np.uint8)


def radial(n, cx=None, cy=None):
    cx = (n - 1) / 2 if cx is None else cx
    cy = (n - 1) / 2 if cy is None else cy
    y, x = np.mgrid[0:n, 0:n]
    return np.hypot(x - cx, y - cy), np.arctan2(y - cy, x - cx)


def dither(v, w, h):
    """Ordered-dither a 0..1 field to hard steps."""
    return v + (np.tile(BAYER, (h // 4 + 1, w // 4 + 1))[:h, :w] - 0.5) * 0.18


def ramp(field, stops, alpha_cut=0.0):
    """field 0..1 -> stepped colours; stops = [(threshold, colour)], high first."""
    h, w = field.shape
    img = np.zeros((h, w, 4), np.uint8)
    for th, c in reversed(stops):
        img[field >= th] = rgba(c)
    img[field < alpha_cut] = 0
    return img


def flash(k):
    n = 24
    d, a = radial(n)
    rays = 4 + 2 * k
    star = np.cos(a * 4 + k * 0.4) ** 8 * (1.0 - d / (n / 2)) * 1.3
    core = 1.0 - d / (5 + k * 2)
    v = np.maximum(star, core)
    return ramp(dither(v, n, n), [(0.85, WHITE), (0.55, HOT), (0.3, ORANGE)], 0.3)


def fireball(k, n=40):
    """6 frames: grows, then the core cools and it breaks up."""
    d, a = radial(n)
    t = k / 5.0
    r = n / 2 * (0.45 + 0.5 * min(1.0, t * 1.6))
    noise = rng.random((n // 4 + 1, n // 4 + 1))
    noise = np.kron(noise, np.ones((4, 4)))[:n, :n]
    v = (1.0 - d / r) + (noise - 0.5) * (0.35 + 0.4 * t) + 0.08 * np.cos(a * 5 + k)
    v = dither(v, n, n) - t * 0.25
    stops = [(0.75 - t * 0.2, WHITE if t < 0.3 else HOT), (0.5, HOT), (0.28, ORANGE), (0.1, EMBER)]
    return ramp(v, stops, 0.1)


def ring(n=64):
    d, _ = radial(n)
    v = 1.0 - np.abs(d - (n / 2 - 3)) / 2.2
    img = ramp(dither(v, n, n), [(0.7, WHITE), (0.35, HOT)], 0.35)
    return img


def smoke(n):
    d, a = radial(n)
    noise = np.kron(rng.random((n // 2 + 1, n // 2 + 1)), np.ones((2, 2)))[:n, :n]
    v = 1.0 - d / (n / 2) + (noise - 0.5) * 0.5
    img = ramp(dither(v, n, n), [(0.55, tuple(int(c * 1.25) for c in SMOKE)), (0.3, SMOKE), (0.12, tuple(int(c * 0.7) for c in SMOKE))], 0.12)
    img[..., 3] = np.where(img[..., 3] > 0, 210, 0)
    return img


def chip(c, k):
    img = np.zeros((5, 5, 4), np.uint8)
    shape = [(1, 1), (2, 1), (1, 2), (2, 2), (3, 2), (2, 3)][: 4 + k % 3]
    for x, y in shape:
        img[y, x] = rgba(c)
    img[1, 1] = rgba(tuple(min(255, int(v * 1.35)) for v in c))
    return img


def scorch(n=64):
    d, a = radial(n)
    noise = np.kron(rng.random((n // 4 + 1, n // 4 + 1)), np.ones((4, 4)))[:n, :n]
    v = 1.0 - d / (n / 2) + (noise - 0.5) * 0.6 + 0.15 * np.cos(a * 7)
    img = ramp(dither(v, n, n), [(0.45, SCORCH), (0.15, (38, 34, 30))], 0.15)
    img[..., 3] = np.where(img[..., 3] > 0, np.where(v >= 0.45, 230, 150), 0).astype(np.uint8)
    return img


def tracer_glow(w=28, h=6):
    """White streak, bright at the head (right), fading to the tail; tinted by team."""
    y, x = np.mgrid[0:h, 0:w]
    v = (x / (w - 1)) * (1.0 - np.abs(y - (h - 1) / 2) / (h / 2))
    img = ramp(dither(v, w, h), [(0.55, (255, 255, 255)), (0.3, (200, 200, 200)), (0.12, (130, 130, 130))], 0.12)
    return img


def tracer_core(w=12, h=2):
    img = np.zeros((h, w, 4), np.uint8)
    img[:, w // 3:] = rgba(WHITE)
    img[:, : w // 3] = rgba(HOT)
    return img


def main():
    regions = {}
    tiles = []
    for k in range(3):
        tiles.append((f"flash_{k}", flash(k)))
    for k in range(6):
        tiles.append((f"fireball_{k}", fireball(k)))
    tiles.append(("ring", ring()))
    for i, n in enumerate((8, 12, 16, 24)):
        tiles.append((f"smoke_{i}", smoke(n)))
    for k in range(3):
        tiles.append((f"chip_rust_{k}", chip(RUST, k)))
        tiles.append((f"chip_steel_{k}", chip(STEEL, k)))
    tiles.append(("scorch", scorch()))
    tiles.append(("tracer_glow", tracer_glow()))
    tiles.append(("tracer_core", tracer_core()))
    # Shelf packing into a 256-wide atlas, 1 px gutter.
    W, x, y, row_h = 256, 0, 0, 0
    placed = []
    for name, img in tiles:
        h, w = img.shape[:2]
        if x + w > W:
            x, y, row_h = 0, y + row_h + 1, 0
        placed.append((name, img, x, y))
        regions[name] = [x, y, w, h]
        x += w + 1
        row_h = max(row_h, h)
    H = y + row_h
    atlas = np.zeros((H, W, 4), np.uint8)
    for name, img, x, y in placed:
        h, w = img.shape[:2]
        atlas[y:y + h, x:x + w] = img
    os.makedirs(OUT, exist_ok=True)
    Image.fromarray(atlas, "RGBA").save(os.path.join(OUT, "fx_atlas.png"))
    meta = {"texture": "fx_atlas.png", "regions": regions,
            "sequences": {"flash": 3, "fireball": 6}, "sample_colours": SAMPLE_COLOURS}
    json.dump(meta, open(os.path.join(OUT, "fx_atlas.json"), "w"), indent=1)
    print("fx atlas", W, "x", H, len(regions), "regions")


if __name__ == "__main__":
    main()
