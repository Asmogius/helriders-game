#!/usr/bin/env python3
"""Helriders pixel-voxel renderer.

Voxel models (defined in code via models.py, or loaded from MagicaVoxel .vox)
are rendered to sprite sheets at N headings for Godot's rotation-locked,
slightly angled top-down camera.

Conventions: model axes x = forward (+x is the nose, matching Godot's
Vector2.RIGHT heading), y = right, z = up. Frame i of a sheet shows the model
at heading i * 360/N degrees, clockwise on screen (Godot rotation sign).

  python3 tools/art/voxel_render.py            # render all models in models.py
  python3 tools/art/voxel_render.py --vox f.vox --name thing
"""
import argparse, json, math, os, struct, sys
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from palette import PALETTE, OUTLINE, shade  # noqa: E402

# --- defaults (see docs/ART_PIPELINE.md) ---
DIRECTIONS = 32      # headings per sheet
PX_PER_VOXEL = 1     # 1 voxel = 1 game px; a 64x36 hull = 64x36 px (vehicle.gd body)
TILT_DEG = 30.0      # camera tilt off straight-down; 0 = pure top-down
SAMPLES = 3          # face samples per voxel edge per pixel (anti-hole)
LIGHT = np.array([-0.45, -0.55, 0.70])  # from upper-left of the screen, above


def load_vox(path):
    """Minimal MagicaVoxel .vox reader: first model + palette -> (grid, rgba list)."""
    data = open(path, "rb").read()
    assert data[:4] == b"VOX ", "not a .vox"
    i, size, voxels, pal = 8, None, None, None
    while i < len(data):
        cid, n, m = data[i:i + 4], *struct.unpack("<ii", data[i + 4:i + 12])
        body = data[i + 12:i + 12 + n]
        if cid == b"SIZE" and size is None:
            size = struct.unpack("<iii", body[:12])
        elif cid == b"XYZI" and voxels is None:
            cnt = struct.unpack("<i", body[:4])[0]
            voxels = np.frombuffer(body[4:4 + cnt * 4], dtype=np.uint8).reshape(-1, 4)
        elif cid == b"RGBA":
            pal = [tuple(body[k * 4:k * 4 + 4]) for k in range(256)]
        i += 12 + (n if cid != b"MAIN" else 0)
    grid = np.zeros(size, dtype=np.int16)
    for x, y, z, c in voxels:
        grid[x, y, z] = c
    return grid, pal


def render_frame(grid, colors, heading_deg, ppv=PX_PER_VOXEL, tilt=TILT_DEG, canvas=None):
    """grid[x,y,z] = palette index (0 empty). Returns RGBA uint8 image."""
    sx, sy, sz = grid.shape
    cx, cy = sx / 2.0, sy / 2.0
    a = math.radians(heading_deg)
    ca, sa = math.cos(a), math.sin(a)
    t = math.radians(tilt)
    ct, st = math.cos(t), math.sin(t)
    if canvas is None:
        r = math.hypot(sx, sy) / 2 + 1
        canvas = int(math.ceil((2 * r) * ppv)) + 4
        canvas += canvas % 2
    W = H = canvas
    zbuf = np.full((H, W), -1e9)
    out = np.zeros((H, W, 4), dtype=np.uint8)
    filled = np.argwhere(grid > 0)
    occ = grid > 0
    k = max(3, SAMPLES * ppv)
    offs = (np.arange(k) + 0.5) / k
    uu, vv = np.meshgrid(offs, offs)
    uu, vv = uu.ravel(), vv.ravel()
    faces = [((1, 0, 0)), ((-1, 0, 0)), ((0, 1, 0)), ((0, -1, 0)), ((0, 0, 1)), ((0, 0, -1))]
    L = LIGHT / np.linalg.norm(LIGHT)
    for n in faces:
        n = np.array(n)
        # rotated normal; drop back faces (view dir = toward camera)
        rnx, rny = n[0] * ca - n[1] * sa, n[0] * sa + n[1] * ca
        view = np.array([0.0, -st, ct])  # camera sits above and toward screen-bottom
        rn = np.array([rnx, rny, n[2]])
        if rn @ view <= 1e-6:
            continue
        nb = filled + n
        inside = (nb >= 0).all(1) & (nb < np.array(grid.shape)).all(1)
        exposed = np.ones(len(filled), bool)
        exposed[inside] = ~occ[nb[inside, 0], nb[inside, 1], nb[inside, 2]]
        vox = filled[exposed]
        if not len(vox):
            continue
        # face sample points in model space
        ax = [i for i in range(3) if n[i] == 0]
        base = vox[:, None, :].astype(float) + np.where(n > 0, 1.0, 0.0)[None, None, :]
        pts = np.repeat(base, len(uu), 1)
        pts[:, :, ax[0]] += uu[None, :]
        pts[:, :, ax[1]] += vv[None, :]
        pts = pts.reshape(-1, 3)
        idx = np.repeat(grid[vox[:, 0], vox[:, 1], vox[:, 2]], len(uu))
        x, y, z = pts[:, 0] - cx, pts[:, 1] - cy, pts[:, 2]
        wx, wy = x * ca - y * sa, x * sa + y * ca  # world (screen x right, y down)
        px = wx * ppv + W / 2
        py = (wy * ct - z * st) * ppv + H / 2 + (sz * st * ppv) / 2
        depth = wy * st + z * ct
        ix, iy = np.floor(px).astype(int), np.floor(py).astype(int)
        ok = (ix >= 0) & (ix < W) & (iy >= 0) & (iy < H)
        ix, iy, depth, idx = ix[ok], iy[ok], depth[ok], idx[ok]
        lum = float(np.clip(rn @ L, -1, 1))
        level = 2 if lum > 0.45 else (1 if lum > -0.05 else 0)
        if n[2] == 1:
            level = 2
        order = np.argsort(depth)
        ix, iy, depth, idx = ix[order], iy[order], depth[order], idx[order]
        lin = iy * W + ix
        # last write wins = nearest (sorted ascending)
        zf = zbuf.ravel()
        keep = depth >= zf[lin]
        lin, depth, idx = lin[keep], depth[keep], idx[keep]
        zf[lin] = depth
        flat = out.reshape(-1, 4)
        cols = np.array([shade(colors[c], level) for c in range(len(colors))], dtype=np.uint8)
        flat[lin] = cols[idx]
    return outline(out)


def outline(img):
    a = img[:, :, 3] > 0
    ring = np.zeros_like(a)
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        ring |= np.roll(np.roll(a, dy, 0), dx, 1)
    ring &= ~a
    img[ring] = OUTLINE
    return img


def _canvas(shape, ppv):
    r = math.hypot(shape[0], shape[1]) / 2 + 1
    c = int(math.ceil(2 * r * ppv + shape[2] * math.sin(math.radians(TILT_DEG)) * ppv)) + 4
    return c + c % 2


def _sheet(frames, cols):
    fw, fh = frames[0].shape[1], frames[0].shape[0]
    rows = math.ceil(len(frames) / cols)
    sheet = Image.new("RGBA", (fw * cols, fh * rows))
    for i, f in enumerate(frames):
        sheet.paste(Image.fromarray(f), ((i % cols) * fw, (i // cols) * fh))
    return sheet


def project_point(pt, shape, heading_deg, ppv=PX_PER_VOXEL, tilt=TILT_DEG):
    """Pixel offset of model point (x, y, z voxels) from the frame centre,
    using the same projection as render_frame."""
    sx, sy, sz = shape
    a, t = math.radians(heading_deg), math.radians(tilt)
    x, y, z = pt[0] - sx / 2.0, pt[1] - sy / 2.0, pt[2]
    wx, wy = x * math.cos(a) - y * math.sin(a), x * math.sin(a) + y * math.cos(a)
    return [round(wx * ppv, 2), round((wy * math.cos(t) - z * math.sin(t) + sz * math.sin(t) / 2) * ppv, 2)]


def render_model(name, chunks, colors, outdir, directions=DIRECTIONS, ppv=PX_PER_VOXEL, points=None):
    """chunks: {chunk_name: grid} (same shape). Writes <name>.png (all chunks),
    <name>__<chunk>.png per chunk (wreck pieces, aligned to the same frame
    centre) and <name>.json describing frames and per-heading chunk offsets."""
    shape = next(iter(chunks.values())).shape
    canvas = _canvas(shape, ppv)
    cols = 8
    full = np.zeros(shape, np.int16)
    for g in chunks.values():
        full = np.where(g > 0, g, full)
    os.makedirs(outdir, exist_ok=True)
    heads = [i * 360.0 / directions for i in range(directions)]
    frames = [render_frame(full, colors, h, ppv, canvas=canvas) for h in heads]
    _sheet(frames, cols).save(os.path.join(outdir, f"{name}.png"))
    write_import(os.path.join(outdir, f"{name}.png"))
    meta = {"sheet": f"{name}.png", "frame_w": canvas, "frame_h": canvas, "columns": cols,
            "directions": directions, "px_per_voxel": ppv, "tilt_deg": TILT_DEG,
            "heading_0": "+x (Vector2.RIGHT), frames turn clockwise",
            "origin": "frame centre = model footprint centre at ground level",
            "points": {pn: [project_point(pt, shape, h, ppv) for h in heads] for pn, pt in (points or {}).items()},
            "chunks": {}}
    for cname, g in chunks.items():
        cf = [render_frame(g, colors, h, ppv, canvas=canvas) for h in heads]
        fn = f"{name}__{cname}.png"
        _sheet(cf, cols).save(os.path.join(outdir, fn))
        write_import(os.path.join(outdir, fn))
        offs = []
        for f in cf:   # centroid of the chunk's pixels, relative to frame centre
            ys, xs = np.nonzero(f[:, :, 3])
            offs.append([round(float(xs.mean()) + 0.5 - canvas / 2, 1),
                         round(float(ys.mean()) + 0.5 - canvas / 2, 1)] if len(xs) else [0, 0])
        meta["chunks"][cname] = {"sheet": fn, "voxels": int((g > 0).sum()), "offsets": offs}
    json.dump(meta, open(os.path.join(outdir, f"{name}.json"), "w"), indent=1)
    return meta


def write_import(png):
    """Godot 4 .import: lossless, no mipmaps. Nearest filtering is set on the node."""
    rel = os.path.relpath(png, os.path.join(HERE, "..", "..")).replace(os.sep, "/")
    if os.path.exists(png + ".import"):   # keep Godot's uid once it has imported
        return
    open(png + ".import", "w").write(f"""[remap]

importer="texture"
type="CompressedTexture2D"

[deps]

source_file="res://{rel}"

[params]

compress/mode=0
compress/high_quality=false
compress/lossy_quality=0.7
compress/hdr_compression=1
compress/normal_map=0
compress/channel_pack=0
mipmaps/generate=false
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=0
""")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--vox")
    ap.add_argument("--name")
    ap.add_argument("--out", default=os.path.join(HERE, "..", "..", "art", "sprites"))
    ap.add_argument("--directions", type=int, default=DIRECTIONS)
    a = ap.parse_args()
    if a.vox:
        grid, pal = load_vox(a.vox)
        render_model(a.name or os.path.splitext(os.path.basename(a.vox))[0], {"body": grid},
                     [(0, 0, 0, 0)] + list(pal), a.out, a.directions)
        return
    import models
    for name, (m, colors) in models.ALL().items():
        render_model(name, m.chunks, colors, a.out, a.directions, points=m.points)
        print("rendered", name, list(m.chunks))


if __name__ == "__main__":
    main()
