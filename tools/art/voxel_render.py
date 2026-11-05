#!/usr/bin/env python3
"""Helriders pixel-voxel renderer.

Voxel models (tools/art/models.py, or MagicaVoxel .vox) are rendered to sprite
sheets at 32 headings for the rotation-locked camera, tilted 45 degrees off
straight-down. Frame i shows heading i * 360/N degrees, clockwise from +x
(Godot's convention). The frame centre is the footprint centre at ground level,
which is the rig's collision centre.

A model has:
  chunks  core parts, always drawn (and flung on a wreck, except "chassis")
  layers  optional part sheets (drive, front armor, extras) chosen by the
          equipped parts; each is drawn over the core with core occlusion
          baked in, and splits into pieces (e.g. one per wheel) for the wreck
  points  named model points projected per heading (turret mounts, pivots)

  python3 tools/art/voxel_render.py
  python3 tools/art/voxel_render.py --vox f.vox --name thing
"""
import argparse, json, math, os, re, shutil, struct, sys
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from palette import OUTLINE, shade, burnt_colors  # noqa: E402

DIRECTIONS = 32      # headings per sheet
PX_PER_VOXEL = 1     # 1 voxel = 1 game px; a 64x36 hull = 64x36 px (vehicle.gd body)
TILT_DEG = 45.0      # camera tilt off straight-down; 0 = pure top-down (Ebbtide-matched, Cameron 2026-11-04)
SAMPLES = 3          # face samples per voxel edge per pixel (no holes)
COLUMNS = 8
LIGHT = np.array([-0.45, -0.55, 0.70])  # from upper-left of the screen, above
# The team sun (Ebbtide standard, Cameron 2026-11-04): the same vector lights the
# voxels and casts the baked shadows. Screen-space x right, y down, z up.
# A point at height z lands on the ground at (x, y) + z * SHADOW_DIR, i.e.
# shadows fall down-right; on screen that is (+0.643, +0.786 * cos(tilt)) px per voxel of height.
SHADOW_DIR = (-LIGHT[0] / LIGHT[2], -LIGHT[1] / LIGHT[2])
SHADOW_RGB = (20, 11, 6)   # near-black warm; the game draws the sheet at SHADOW_ALPHA
# Peak opacity at the contact (Cameron, 2026-11-05: stronger than the old 0.5).
# The sheet itself is solid there and eases toward the far cast; this multiplies it.
SHADOW_ALPHA = 0.82
CONTACT_Z = 2.0       # voxels this close to the ground stamp the crisp contact
CAST_FALLOFF = 14.0   # screen voxels over which the cast eases off the contact
FAR_SHEET = 215       # sheet alpha (0-255) at the far end of the cast, before SHADOW_ALPHA
FAR_LIP = 0.58        # outer pixel of the cast, once it has left the contact
# Garage-preview HD set (--garage-hd): the player's chassis and weapon sheets.
GARAGE_HD = ["scrap_frame", "bulwark_frame", "courier_frame", "pintle_turret", "burst_turret", "rivet_gun",
             "flame_sprayer", "arc_projector", "harpoon", "mortar", "acid_lobber"]


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


def render_frame(grid, colors, heading_deg, ppv=PX_PER_VOXEL, tilt=TILT_DEG, canvas=None, owner=None, hd=False):
    """grid[x,y,z] = palette index (0 empty). Returns an RGBA image, or
    (image, owner map) when `owner` (same shape, int) is given: the owner id of
    the voxel each pixel shows, -1 for empty and outline pixels.

    hd=True (opt-in, garage preview sheets only; the in-game sheets never set
    it): continuous light instead of the 3 shade steps, and soft ambient
    occlusion per face sample (a face darkens towards an edge where a voxel
    stands in front of it), so 2 px per voxel shows fine shading."""
    sx, sy, sz = grid.shape
    cx, cy = sx / 2.0, sy / 2.0
    a = math.radians(heading_deg)
    ca, sa = math.cos(a), math.sin(a)
    t = math.radians(tilt)
    ct, st = math.cos(t), math.sin(t)
    W = H = canvas
    zbuf = np.full(H * W, -1e9)
    out = np.zeros((H * W, 4), dtype=np.uint8)
    own = np.full(H * W, -1, dtype=np.int32)
    filled = np.argwhere(grid > 0)
    occ = grid > 0
    k = max(3, SAMPLES * ppv)
    offs = (np.arange(k) + 0.5) / k
    uu, vv = np.meshgrid(offs, offs)
    uu, vv = uu.ravel(), vv.ravel()
    L = LIGHT / np.linalg.norm(LIGHT)
    # Screen y grows with world +y (py = wy*cos t - z*sin t) and nearer points
    # have larger depth (wy*sin t + z*cos t), so the camera sits on the +y
    # (south) side: south-facing sides and tops face it, north sides don't.
    view = np.array([0.0, st, ct])
    cols = np.array([[shade(colors[c], lv) for lv in range(3)] for c in range(len(colors))], dtype=np.uint8)
    emissive = np.array([cols[c, 0, :3].tolist() == cols[c, 2, :3].tolist() for c in range(len(colors))])
    for n in ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)):
        n = np.array(n)
        rn = np.array([n[0] * ca - n[1] * sa, n[0] * sa + n[1] * ca, n[2]])
        if rn @ view <= 1e-6:
            continue
        nb = filled + n
        inside = (nb >= 0).all(1) & (nb < np.array(grid.shape)).all(1)
        exposed = np.ones(len(filled), bool)
        exposed[inside] = ~occ[nb[inside, 0], nb[inside, 1], nb[inside, 2]]
        vox = filled[exposed]
        if not len(vox):
            continue
        ax = [i for i in range(3) if n[i] == 0]
        base = vox[:, None, :].astype(float) + np.where(n > 0, 1.0, 0.0)[None, None, :]
        pts = np.repeat(base, len(uu), 1)
        pts[:, :, ax[0]] += uu[None, :]
        pts[:, :, ax[1]] += vv[None, :]
        pts = pts.reshape(-1, 3)
        idx = np.repeat(grid[vox[:, 0], vox[:, 1], vox[:, 2]], len(uu))
        oid = np.repeat(owner[vox[:, 0], vox[:, 1], vox[:, 2]] if owner is not None else np.zeros(len(vox), int), len(uu))
        x, y, z = pts[:, 0] - cx, pts[:, 1] - cy, pts[:, 2]
        wx, wy = x * ca - y * sa, x * sa + y * ca
        px = wx * ppv + W / 2
        py = (wy * ct - z * st) * ppv + H / 2   # ground centre = frame centre
        depth = wy * st + z * ct
        ix, iy = np.floor(px).astype(int), np.floor(py).astype(int)
        ok = (ix >= 0) & (ix < W) & (iy >= 0) & (iy < H)
        ix, iy, depth, idx, oid = ix[ok], iy[ok], depth[ok], idx[ok], oid[ok]
        lum = float(np.clip(rn @ L, -1, 1))
        level = 2 if (n[2] == 1 or lum > 0.45) else (1 if lum > -0.05 else 0)
        if hd:
            # soft AO: voxels standing in front of this face, across each edge
            def occ_at(d):
                q = vox + n + d
                ins = (q >= 0).all(1) & (q < np.array(grid.shape)).all(1)
                o = np.zeros(len(vox))
                o[ins] = occ[q[ins, 0], q[ins, 1], q[ins, 2]]
                return np.repeat(o, len(uu))
            e0, e1 = np.eye(3, dtype=int)[ax[0]], np.eye(3, dtype=int)[ax[1]]
            su, sv = np.tile(uu, len(vox)), np.tile(vv, len(vox))
            ao = 1.0 - 0.32 * (occ_at(-e0) * np.clip(1 - 2 * su, 0, 1) + occ_at(e0) * np.clip(2 * su - 1, 0, 1)
                               + occ_at(-e1) * np.clip(1 - 2 * sv, 0, 1) + occ_at(e1) * np.clip(2 * sv - 1, 0, 1))
            ao = np.clip(ao, 0.5, 1.0)[ok]
            light = 1.0 if n[2] == 1 else 0.62 + 0.36 * max(lum, 0.0)
            hd_shade = np.clip(light * ao, 0, 1)
        order = np.argsort(depth)
        lin, depth, idx, oid = (iy * W + ix)[order], depth[order], idx[order], oid[order]
        keep = depth >= zbuf[lin]
        lin, depth, idx, oid = lin[keep], depth[keep], idx[keep], oid[keep]
        zbuf[lin] = depth            # sorted ascending: the nearest write wins
        if hd:
            f = hd_shade[order][keep]
            f = np.where(emissive[idx], 1.0, f)
            c = cols[idx, 2].astype(float)
            c[:, :3] *= f[:, None]
            out[lin] = c.astype(np.uint8)
        else:
            out[lin] = cols[idx, level]
        own[lin] = oid
    img = outline(out.reshape(H, W, 4))
    return (img, own.reshape(H, W)) if owner is not None else img


def outline(img):
    a = img[:, :, 3] > 0
    ring = np.zeros_like(a)
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        ring |= np.roll(np.roll(a, dy, 0), dx, 1)
    ring &= ~a
    img[ring] = OUTLINE
    return img


def masked(img, own, target):
    """Pixels showing owner `target`, plus the outline pixels touching them."""
    mine = own == target
    near = np.zeros_like(mine)
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        near |= np.roll(np.roll(mine, dy, 0), dx, 1)
    keep = mine | (near & (own == -1) & (img[:, :, 3] > 0))
    out = np.zeros_like(img)
    out[keep] = img[keep]
    return out


def project_point(pt, shape, heading_deg, ppv=PX_PER_VOXEL, tilt=TILT_DEG):
    """Pixel offset of model point (x, y, z voxels) from the frame centre."""
    sx, sy, sz = shape
    a, t = math.radians(heading_deg), math.radians(tilt)
    x, y, z = pt[0] - sx / 2.0, pt[1] - sy / 2.0, pt[2]
    wx, wy = x * math.cos(a) - y * math.sin(a), x * math.sin(a) + y * math.cos(a)
    return [round(wx * ppv, 2), round((wy * math.cos(t) - z * math.sin(t)) * ppv, 2)]


def canvas_for(shape, ppv=PX_PER_VOXEL):
    r = math.hypot(shape[0], shape[1]) / 2 + 1
    return 2 * int(math.ceil((r + shape[2] * math.sin(math.radians(TILT_DEG))) * ppv)) + 4


def shadow_canvas(shape, ppv=PX_PER_VOXEL):
    r = math.hypot(shape[0], shape[1]) / 2 + 1
    return 2 * int(math.ceil((r + shape[2] * math.hypot(*SHADOW_DIR)) * ppv)) + 4


def _dist_from(contact, limit):
    """Pixel distance to the nearest True cell, capped at `limit`."""
    d = np.where(contact, 0, limit).astype(np.int16)
    for _ in range(int(limit)):
        p = np.pad(d, 1, constant_values=limit)
        neigh = np.minimum(np.minimum(p[:-2, 1:-1], p[2:, 1:-1]), np.minimum(p[1:-1, :-2], p[1:-1, 2:]))
        diag = np.minimum(np.minimum(p[:-2, :-2], p[:-2, 2:]), np.minimum(p[2:, :-2], p[2:, 2:]))
        d = np.minimum(d, np.minimum(neigh + 1, diag + 1))
    return d


def render_shadow(grid, heading_deg, ppv=PX_PER_VOXEL, tilt=TILT_DEG, canvas=None):
    """Baked cast shadow: every voxel projected along the sun onto the ground
    (z = 0), then seen through the tilted camera. SHADOW_RGB silhouette.

    Voxels within CONTACT_Z of the ground (the footprint, plus one screen voxel
    around it) are solid and hard-edged. Farther along the cast the sheet alpha
    eases toward FAR_SHEET, and the outer pixel of that tail is a softer lip.
    The frame centre is the footprint centre at ground level, like the sprite.
    The game multiplies the sheet by SHADOW_ALPHA."""
    sx, sy, sz = grid.shape
    a, t = math.radians(heading_deg), math.radians(tilt)
    ca, sa, ct = math.cos(a), math.sin(a), math.cos(t)
    W = H = canvas
    k = max(2, 2 * ppv)
    o = (np.arange(k) + 0.5) / k
    du, dv, dw = [g.ravel() for g in np.meshgrid(o, o, o)]
    v = np.argwhere(grid > 0).astype(float)
    out = np.zeros((H, W, 4), np.uint8)
    if len(v) == 0:
        return out
    x = (v[:, None, 0] + du[None]) - sx / 2.0
    y = (v[:, None, 1] + dv[None]) - sy / 2.0
    z = v[:, None, 2] + dw[None]
    wx, wy = x * ca - y * sa, x * sa + y * ca
    gx, gy = wx + z * SHADOW_DIR[0], wy + z * SHADOW_DIR[1]
    ix = np.floor(gx * ppv + W / 2).astype(int).ravel()
    iy = np.floor(gy * ct * ppv + H / 2).astype(int).ravel()
    zz = z.ravel()
    ok = (ix >= 0) & (ix < W) & (iy >= 0) & (iy < H)
    min_z = np.full((H, W), 1e9, np.float32)
    np.minimum.at(min_z, (iy[ok], ix[ok]), zz[ok])
    covered = min_z < 1e8
    contact = covered & (min_z <= CONTACT_Z)
    reach = int(math.ceil((CAST_FALLOFF + 4) * ppv))
    if contact.any():
        dist = _dist_from(contact, reach).astype(np.float32)
    else:
        dist = np.full((H, W), float(ppv * 4), np.float32)
    crisp = float(ppv)  # one screen voxel past the footprint stays full
    tnorm = np.clip((dist - crisp) / (CAST_FALLOFF * ppv), 0.0, 1.0)
    tnorm = tnorm * tnorm * (3.0 - 2.0 * tnorm)
    sheet = (1.0 - tnorm) * 255.0 + tnorm * FAR_SHEET
    up = np.zeros_like(covered); up[1:] = covered[:-1]
    dn = np.zeros_like(covered); dn[:-1] = covered[1:]
    lf = np.zeros_like(covered); lf[:, 1:] = covered[:, :-1]
    rt = np.zeros_like(covered); rt[:, :-1] = covered[:, 1:]
    boundary = covered & ~(up & dn & lf & rt)
    far_lip = boundary & (dist >= crisp + 2.0 * ppv)
    sheet = np.where(far_lip, sheet * FAR_LIP, sheet)
    sheet = np.where(covered, sheet, 0.0)
    m = sheet > 0
    out[m, 0] = SHADOW_RGB[0]
    out[m, 1] = SHADOW_RGB[1]
    out[m, 2] = SHADOW_RGB[2]
    out[m, 3] = np.clip(np.rint(sheet[m]), 0, 255).astype(np.uint8)
    return out


def save_sheet(frames, path):
    fh, fw = frames[0].shape[:2]
    rows = math.ceil(len(frames) / COLUMNS)
    sheet = Image.new("RGBA", (fw * COLUMNS, fh * rows))
    for i, f in enumerate(frames):
        sheet.paste(Image.fromarray(f), ((i % COLUMNS) * fw, (i // COLUMNS) * fh))
    sheet.save(path)
    write_import(path)


def centroids(frames, canvas):
    offs = []
    for f in frames:
        ys, xs = np.nonzero(f[:, :, 3])
        offs.append([round(float(xs.mean()) + 0.5 - canvas / 2, 1),
                     round(float(ys.mean()) + 0.5 - canvas / 2, 1)] if len(xs) else [0, 0])
    return offs


def union(grids):
    full = None
    for g in grids:
        full = g.copy() if full is None else np.where(g > 0, g, full)
    return full


def render_model(name, model, colors, outdir, directions=DIRECTIONS, ppv=PX_PER_VOXEL, hd=False):
    """hd=True: the garage preview set (2 px per voxel, soft light + AO): core
    and layer sheets only (no composite, wreck chunks, burnt hull or pieces,
    which the preview never shows)."""
    chunks, layers, points = model.chunks, model.layers, model.points
    shape = next(iter(chunks.values())).shape
    canvas = canvas_for(shape, ppv)
    heads = [i * 360.0 / directions for i in range(directions)]
    core = union(chunks.values())
    os.makedirs(outdir, exist_ok=True)
    meta = {"frame_w": canvas, "frame_h": canvas, "columns": COLUMNS, "directions": directions,
            "px_per_voxel": ppv, "tilt_deg": TILT_DEG,
            "heading_0": "+x (Vector2.RIGHT), frames turn clockwise",
            "anchor": "frame centre = footprint centre at ground level (z = 0) = the rig's collision centre",
            "points": {pn: [project_point(pt, shape, h, ppv) for h in heads] for pn, pt in
                       dict(points, ground_centre=(shape[0] / 2.0, shape[1] / 2.0, 0.0)).items()},
            "chunks": {}, "layers": {}, "defaults": list(model.defaults)}
    # Core sheet (what the hull sprite shows) and a composite with the default layers.
    meta["sheet"] = f"{name}__core.png" if layers else f"{name}.png"
    save_sheet([render_frame(core, colors, h, ppv, canvas=canvas, hd=hd) for h in heads], os.path.join(outdir, meta["sheet"]))
    meta["composite"] = f"{name}.png"
    # Lights sheet: only the emissive pixels of the hull sheet (colours that
    # never shade: cyan, orange, enemy red, elite gold). The night grade tints
    # the hull but not this child, so lights stay bright at night.
    if not hd:
        lit = np.array([shade(c, 2)[:3] for c in colors if shade(c, 0)[:3] == shade(c, 2)[:3] and len(c) > 3 and c[3] > 0])
        if len(lit):
            core_img = np.array(Image.open(os.path.join(outdir, meta["sheet"])).convert("RGBA"))
            m = (core_img[..., 3] > 0) & (core_img[..., :3][:, :, None, :] == lit[None, None]).all(-1).any(-1)
            if m.any():
                li = np.zeros_like(core_img)
                li[m] = core_img[m]
                fn = f"{name}__lights.png"
                Image.fromarray(li).save(os.path.join(outdir, fn))
                write_import(os.path.join(outdir, fn))
                meta["lights"] = {"sheet": fn}
    # Baked cast shadow (hulls only: a model with a "chassis" chunk stands on the
    # ground; turrets and weapons sit on a deck, and the hull's shadow covers them).
    if "chassis" in chunks:
        sgrid = union([core] + [union(layers[d]["pieces"].values()) for d in model.defaults if d in layers])
        sc = shadow_canvas(shape, ppv)
        fn = f"{name}__shadow.png"
        save_sheet([render_shadow(sgrid, h, ppv, canvas=sc) for h in heads], os.path.join(outdir, fn))
        meta["shadow"] = {"sheet": fn, "frame_w": sc, "frame_h": sc, "alpha": SHADOW_ALPHA,
                          "sun": [float(c) for c in LIGHT], "dir": [round(float(c), 3) for c in SHADOW_DIR]}
    if hd:
        meta["hd"] = True
        for lid, L in layers.items():
            lgrid = union(L["pieces"].values())
            combo = np.where(lgrid > 0, lgrid, core)
            owner = np.where(lgrid > 0, 1, 0).astype(np.int32)
            frames = []
            for h in heads:
                img, own = render_frame(combo, colors, h, ppv, canvas=canvas, owner=owner, hd=True)
                frames.append(masked(img, own, 1))
            fn = f"{name}__L_{lid.replace(':', '_')}.png"
            save_sheet(frames, os.path.join(outdir, fn))
            meta["layers"][lid] = {"slot": L["slot"], "sheet": fn, "offsets": centroids(frames, canvas), "pieces": {}}
        json.dump(meta, open(os.path.join(outdir, f"{name}.json"), "w"), indent=1)
        return meta
    if layers:
        comp = union([core] + [union(layers[d]["pieces"].values()) for d in model.defaults])
        save_sheet([render_frame(comp, colors, h, ppv, canvas=canvas) for h in heads], os.path.join(outdir, f"{name}.png"))
    meta["composite"] = f"{name}.png"
    # Chunks of the core (wreck pieces), plus a burnt chassis for the wreck.
    for cname, g in chunks.items():
        fr = [render_frame(g, colors, h, ppv, canvas=canvas) for h in heads]
        fn = f"{name}__{cname}.png"
        save_sheet(fr, os.path.join(outdir, fn))
        meta["chunks"][cname] = {"sheet": fn, "voxels": int((g > 0).sum()), "offsets": centroids(fr, canvas)}
    if "chassis" in chunks:
        fn = f"{name}__chassis_burnt.png"
        save_sheet([render_frame(chunks["chassis"], burnt_colors(colors), h, ppv, canvas=canvas) for h in heads],
                   os.path.join(outdir, fn))
        meta["burnt"] = fn
    # Layers: render core + layer with owner ids, keep only what the layer shows.
    for lid, L in layers.items():
        pieces = L["pieces"]
        lgrid = union(pieces.values())
        combo = np.where(lgrid > 0, lgrid, core)
        owner = np.zeros(shape, np.int32)
        for k, g in enumerate(pieces.values(), start=1):
            owner[g > 0] = k
        frames_by_piece = {pn: [] for pn in pieces}
        layer_frames = []
        for h in heads:
            img, own = render_frame(combo, colors, h, ppv, canvas=canvas, owner=owner)
            layer = np.zeros_like(img)
            for k, pn in enumerate(pieces, start=1):
                m = masked(img, own, k)
                frames_by_piece[pn].append(m)
                layer = np.where(m[:, :, 3:4] > 0, m, layer)
            layer_frames.append(layer)
        safe = lid.replace(":", "_")
        fn = f"{name}__L_{safe}.png"
        save_sheet(layer_frames, os.path.join(outdir, fn))
        entry = {"slot": L["slot"], "sheet": fn, "offsets": centroids(layer_frames, canvas), "pieces": {}}
        for pn, fr in frames_by_piece.items():
            pfn = fn if len(pieces) == 1 else f"{name}__L_{safe}__{pn}.png"
            if len(pieces) > 1:
                save_sheet(fr, os.path.join(outdir, pfn))
            entry["pieces"][pn] = {"sheet": pfn, "offsets": centroids(fr, canvas)}
        meta["layers"][lid] = entry
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


def _patch_shadow_alpha(json_path, alpha):
    """Replace only the recorded shadow alpha. Leaves the rest of the sheet json alone."""
    text = open(json_path).read()
    new, n = re.subn(
        r'("shadow"\s*:\s*\{[^}]*?"alpha"\s*:\s*)([0-9.]+)',
        lambda m: m.group(1) + f"{alpha:.2f}".rstrip("0").rstrip("."),
        text, count=1)
    if n != 1:
        raise SystemExit(f"shadow alpha not found in {json_path}")
    if new != text:
        open(json_path, "w").write(new)


def rebake_shadows(pairs, outdir, ppv):
    """Rewrite `<name>__shadow.png` and the alpha recorded in its json. Hulls only."""
    directions = DIRECTIONS
    heads = [i * 360.0 / directions for i in range(directions)]
    for name, (model, _colors) in pairs:
        if "chassis" not in model.chunks:
            continue
        shape = next(iter(model.chunks.values())).shape
        core = union(model.chunks.values())
        sgrid = union([core] + [union(model.layers[d]["pieces"].values()) for d in model.defaults if d in model.layers])
        sc = shadow_canvas(shape, ppv)
        fn = f"{name}__shadow.png"
        save_sheet([render_shadow(sgrid, h, ppv, canvas=sc) for h in heads], os.path.join(outdir, fn))
        _patch_shadow_alpha(os.path.join(outdir, f"{name}.json"), SHADOW_ALPHA)
        print("shadow", name, sc)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--vox")
    ap.add_argument("--name")
    ap.add_argument("--out", default=os.path.join(HERE, "..", "..", "art", "sprites"))
    ap.add_argument("--directions", type=int, default=DIRECTIONS)
    ap.add_argument("--garage-hd", action="store_true",
                    help="garage preview sheets only: 2 px/voxel, soft light + AO, into art/sprites_hd/")
    ap.add_argument("--shadows-only", action="store_true",
                    help="rebake hull __shadow.png sheets and their meta alpha; leave every other sheet")
    a = ap.parse_args()
    if a.shadows_only:
        import models
        if a.garage_hd:
            out = os.path.join(HERE, "..", "..", "art", "sprites_hd")
            all_models = models.ALL()
            rebake_shadows([(n, all_models[n]) for n in GARAGE_HD], out, ppv=2)
        else:
            rebake_shadows(list(models.ALL().items()), a.out, ppv=1)
        return
    if a.garage_hd:
        import models
        out = os.path.join(HERE, "..", "..", "art", "sprites_hd")
        os.makedirs(out, exist_ok=True)
        for name, (m, colors) in models.ALL().items():
            if name in GARAGE_HD:
                render_model(name, m, colors, out, a.directions, ppv=2, hd=True)
                for f in os.listdir(out):
                    if f.startswith(name) and f.endswith(".png"):
                        write_import(os.path.join(out, f))
                print("hd", name)
        return
    import models
    if a.vox:
        grid, pal = load_vox(a.vox)
        m = models.Model(grid.shape)
        m.chunks["body"] = grid
        render_model(a.name or os.path.splitext(os.path.basename(a.vox))[0], m,
                     [(0, 0, 0, 0)] + list(pal), a.out, a.directions)
        return
    # Fresh output: stale sheets from renamed parts would linger otherwise.
    keep = {}
    if os.path.isdir(a.out):
        for f in os.listdir(a.out):
            if f.endswith(".import"):
                keep[f] = open(os.path.join(a.out, f)).read()
        shutil.rmtree(a.out)
    os.makedirs(a.out)
    for f, txt in keep.items():   # keep Godot uids for sheets that still exist
        open(os.path.join(a.out, f), "w").write(txt)
    for name, (m, colors) in models.ALL().items():
        render_model(name, m, colors, a.out, a.directions)
        print("rendered", name, len(m.chunks), "chunks,", len(m.layers), "layers")
    for f in keep:
        if not os.path.exists(os.path.join(a.out, f[:-len(".import")])):
            os.remove(os.path.join(a.out, f))


if __name__ == "__main__":
    main()
