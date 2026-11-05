"""Saloon v2 concept renderer — Ebbtide style (45–60°, hard sun shadows, charcoal/gold UI)."""
import math
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

BLACK_OPS = "/usr/share/fonts/truetype/sand-box/google/Black Ops One/BlackOpsOne-Regular.ttf"
INTER = "/usr/share/fonts/truetype/sand-box/google/Inter/Inter-VariableFont_opsz,wght.ttf"

def F_title(s):
    return ImageFont.truetype(BLACK_OPS, s)

def F_body(s, weight=450):
    f = ImageFont.truetype(INTER, s)
    try:
        f.set_variation_by_axes([14, weight])
    except Exception:
        pass
    return f

# Near-isometric ~52°: front face dominates over v1's top-down.
S, TOP, FRONT, SIDE = 8, 5, 10, 4
W, D, H = 160, 72, 28

PANEL = (0x18, 0x1d, 0x20)
PANEL_BODY = (0x24, 0x29, 0x2f)
HEADER = (0x1e, 0x1b, 0x14)
GOLD = (0xe1, 0xb4, 0x41)
HAIRLINE = (0x3a, 0x3d, 0x3c)
TEXT = (0xcc, 0xc8, 0xbc)
DIM = (0x8a, 0x8a, 0x84)

RARITY = {
    "Common": (0x8a, 0x8a, 0x84),
    "Uncommon": (0x5a, 0xa0, 0x5a),
    "Rare": (0x4a, 0x7a, 0xc8),
    "Epic": (0x9a, 0x5a, 0xc8),
    "Legendary": (0xe1, 0xb4, 0x41),
    "Mythic": (0xc4, 0x47, 0x3f),
}

# Sun from upper-left → shadows fall down-right.
SUN = np.array([-0.55, -0.40, 0.73], dtype=np.float32)
SUN /= np.linalg.norm(SUN)


class Scene:
    def __init__(self):
        self.g = np.zeros((W, D, H), np.int32)
        self.own = np.zeros((W, D, H), np.int16)
        self.pal = [((0, 0, 0), False)]
        self.pi = {}

    def c(self, rgb, em=False):
        k = (tuple(int(v) for v in rgb), bool(em))
        if k not in self.pi:
            self.pi[k] = len(self.pal)
            self.pal.append(k)
        return self.pi[k]

    def box(self, x0, y0, z0, x1, y1, z1, rgb, em=False, own=0, noise=0, seed=0):
        x0, x1 = max(0, int(x0)), min(W, int(x1))
        y0, y1 = max(0, int(y0)), min(D, int(y1))
        z0, z1 = max(0, int(z0)), min(H, int(z1))
        if x0 >= x1 or y0 >= y1 or z0 >= z1:
            return
        if noise:
            rng = np.random.default_rng(seed + x0 * 7 + y0 * 13 + z0)
            for x in range(x0, x1):
                for y in range(y0, y1):
                    for z in range(z0, z1):
                        f = 1 + rng.uniform(-noise, noise)
                        col = [min(255, max(0, int(v * f))) for v in rgb]
                        self.g[x, y, z] = self.c(col, em)
                        self.own[x, y, z] = own
        else:
            ci = self.c(rgb, em)
            self.g[x0:x1, y0:y1, z0:z1] = ci
            self.own[x0:x1, y0:y1, z0:z1] = own

    def _paint_voxel(self, img, own, em, pal, pem, oy, x, y, z, up, fr, east, nb, light_fn, faces="all"):
        ci = self.g[x, y, z]
        col = pal[ci].copy()
        e = bool(pem[ci])
        o = self.own[x, y, z]
        sx = x * S
        sy = oy + y * TOP - z * FRONT - FRONT
        Lbase = 1.0 if e else float(light_fn(x, y, z))

        if faces in ("all", "top") and not up[x, y, z]:
            ao = 1 - 0.055 * int(nb[x, y, z])
            nl = max(0.40, SUN[2]) if not e else 1.0
            L = (Lbase * nl * ao) if not e else 1.0
            a, b = sy, sy + TOP
            if 0 <= a < 720 and sx < 1280:
                x1 = min(1280, sx + S)
                y0, y1 = max(0, a), min(720, b)
                if y0 < y1 and sx < x1:
                    img[y0:y1, sx:x1] = col * L
                    own[y0:y1, sx:x1] = o
                    em[y0:y1, sx:x1] = e

        if faces in ("all", "sides") and not fr[x, y, z]:
            nl = max(0.28, 0.50) if not e else 0.9
            L = (Lbase * nl * 0.82) if not e else 0.9
            a, b = sy + TOP, sy + TOP + FRONT
            if a < 720 and b > 0 and sx < 1280:
                x1 = min(1280, sx + S)
                y0, y1 = max(0, a), min(720, b)
                if y0 < y1 and sx < x1:
                    img[y0:y1, sx:x1] = col * L
                    own[y0:y1, sx:x1] = o
                    em[y0:y1, sx:x1] = e

        if faces in ("all", "sides") and not east[x, y, z]:
            # East face darkest under upper-left sun
            nl = 0.22 if not e else 0.85
            L = (Lbase * nl) if not e else 0.85
            a, b = sy, sy + TOP + FRONT
            x0 = sx + S
            x1 = min(1280, x0 + SIDE)
            y0, y1 = max(0, a), min(720, b)
            if y0 < y1 and x0 < x1:
                img[y0:y1, x0:x1] = col * L
                own[y0:y1, x0:x1] = o
                em[y0:y1, x0:x1] = e

    def render(self, light_fn):
        oy = H * FRONT + 8
        img = np.zeros((720, 1280, 3), np.float32)
        own = np.zeros((720, 1280), np.int16)
        em = np.zeros((720, 1280), bool)

        g = self.g
        filled = g > 0
        up = np.zeros_like(filled); up[:, :, :-1] = filled[:, :, 1:]
        fr = np.zeros_like(filled); fr[:, :-1, :] = filled[:, 1:, :]
        east = np.zeros_like(filled); east[:-1, :, :] = filled[1:, :, :]

        nb = np.zeros(filled.shape, np.int8)
        for dx, dy in [(-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (1, 1), (-1, 1), (1, -1)]:
            sh = np.zeros_like(filled)
            sx = slice(max(0, dx), W + min(0, dx))
            tx = slice(max(0, -dx), W + min(0, -dx))
            syy = slice(max(0, dy), D + min(0, dy))
            ty = slice(max(0, -dy), D + min(0, -dy))
            sh[tx, ty, :-1] = filled[sx, syy, 1:]
            nb += sh

        pal = np.array([p[0] for p in self.pal], np.float32)
        pem = np.array([p[1] for p in self.pal])

        # Pass 1: floor slabs only (z < 3)
        xs, ys, zs = np.nonzero(filled & (np.arange(H)[None, None, :] < 2))
        order = np.lexsort((zs, ys, xs))
        for i in order:
            self._paint_voxel(img, own, em, pal, pem, oy,
                              int(xs[i]), int(ys[i]), int(zs[i]),
                              up, fr, east, nb, light_fn)

        # Cast hard shadows onto the painted floor (vectorized)
        inv = -SUN
        # Surface voxels (any filled with empty above or side) cast
        surf = filled & (~up | ~fr | ~east)
        xs, ys, zs = np.nonzero(surf)
        # Only cast from z >= 2 (furniture, people, walls)
        m = zs >= 2
        xs, ys, zs = xs[m], ys[m], zs[m]
        t = (1.0 - zs.astype(np.float32)) / inv[2]
        sx_v = xs.astype(np.float32) + inv[0] * t
        sy_v = ys.astype(np.float32) + inv[1] * t
        # Stretch shadow slightly further down-right for Ebbtide read
        sx_v = sx_v + 1.2
        sy_v = sy_v + 1.8

        shad = np.zeros((720, 1280), np.float32)
        px = (sx_v * S).astype(np.int32)
        py = (oy + sy_v * TOP - 1 * FRONT).astype(np.int32)
        for i in range(len(px)):
            x0 = int(px[i]); y0 = int(py[i])
            # Hard stamp elongated down-right
            for oy_ in range(0, TOP + 3):
                for ox_ in range(0, S + SIDE + 2):
                    xx, yy = x0 + ox_, y0 + oy_
                    if 0 <= xx < 1280 and 0 <= yy < 720:
                        # only darken existing floor pixels (already painted, own==0)
                        if own[yy, xx] == 0 and not em[yy, xx] and img[yy, xx].sum() > 10:
                            shad[yy, xx] = max(shad[yy, xx], 0.72)

        shad_img = Image.fromarray((np.clip(shad, 0, 1) * 255).astype(np.uint8))
        shad_img = shad_img.filter(ImageFilter.MaxFilter(3))
        shad = np.array(shad_img).astype(np.float32) / 255.0
        # Hard multiply into floor only
        floor_pix = (own == 0) & (~em) & (img.sum(-1) > 10)
        img[floor_pix] *= (1.0 - 0.70 * shad[floor_pix])[..., None]

        # Pass 2: everything above floor
        xs, ys, zs = np.nonzero(filled & (np.arange(H)[None, None, :] >= 2))
        order = np.lexsort((zs, ys, xs))
        for i in order:
            self._paint_voxel(img, own, em, pal, pem, oy,
                              int(xs[i]), int(ys[i]), int(zs[i]),
                              up, fr, east, nb, light_fn)

        return img, own, em, oy


def figure(sc, x, y, z, shirt, skin, hat, own, seated=True, facing="back",
           pants=(52, 48, 44), hatstyle="cap"):
    if seated:
        sc.box(x, y - 2, z, x + 6, y + 4, z + 3, pants, own=own)
        sc.box(x, y + 3, z - 5, x + 2, y + 4, z, pants, own=own)
        sc.box(x + 4, y + 3, z - 5, x + 6, y + 4, z, pants, own=own)
        bz = z + 3
    else:
        sc.box(x, y, z, x + 2, y + 4, z + 7, pants, own=own)
        sc.box(x + 4, y, z, x + 6, y + 4, z + 7, pants, own=own)
        bz = z + 7
    sc.box(x, y, bz, x + 6, y + 4, bz + 7, shirt, own=own)
    sc.box(x - 2, y, bz + 2, x, y + 3, bz + 7, shirt, own=own)
    sc.box(x + 6, y, bz + 2, x + 8, y + 3, bz + 7, shirt, own=own)
    hand_y = y + (1 if facing == "front" else 0)
    sc.box(x - 2, hand_y, bz + 1, x, hand_y + 2, bz + 2, skin, own=own)
    sc.box(x + 6, hand_y, bz + 1, x + 8, hand_y + 2, bz + 2, skin, own=own)
    sc.box(x + 1, y, bz + 7, x + 5, y + 4, bz + 11, skin, own=own)
    if hatstyle == "cap":
        sc.box(x + 1, y, bz + 10, x + 5, y + 4, bz + 12, hat, own=own)
        brim = 4 if facing == "front" else -2
        sc.box(x + 1, y + brim, bz + 10, x + 5, y + brim + 2, bz + 11, hat, own=own)
    elif hatstyle == "wide":
        sc.box(x - 1, y - 2, bz + 10, x + 7, y + 6, bz + 11, hat, own=own)
        sc.box(x + 1, y, bz + 11, x + 5, y + 4, bz + 13, hat, own=own)
    elif hatstyle == "mohawk":
        sc.box(x + 2, y, bz + 11, x + 4, y + 4, bz + 14, hat, own=own)
    elif hatstyle == "hood":
        sc.box(x, y, bz + 7, x + 6, y + 4, bz + 12, hat, own=own)
        face_y = y + 3 if facing == "front" else y
        sc.box(x + 1, face_y, bz + 8, x + 5, face_y + 1, bz + 11, skin, own=own)
    if facing == "front":
        sc.box(x + 1, y + 4, bz + 8, x + 5, y + 5, bz + 9, (28, 24, 20), own=own)
    return (x + 3, y + 2, bz + 5)


def stool(sc, x, y, top, leg):
    sc.box(x + 2, y + 2, 2, x + 4, y + 4, 8, leg)
    sc.box(x, y, 8, x + 6, y + 5, 9, top)


def table(sc, x, y, w, d, top, leg, h=11):
    sc.box(x + w // 2 - 1, y + d // 2 - 1, 2, x + w // 2 + 1, y + d // 2 + 1, h, leg)
    sc.box(x, y, h, x + w, y + d, h + 1, top, noise=0.04, seed=x + y)


def _brackets(d, x0, y0, x1, y1, col=GOLD, arm=10, w=2):
    for (cx, cy, dx, dy) in [
        (x0, y0, 1, 1), (x1, y0, -1, 1),
        (x0, y1, 1, -1), (x1, y1, -1, -1),
    ]:
        d.line([(cx, cy), (cx + dx * arm, cy)], fill=col, width=w)
        d.line([(cx, cy), (cx, cy + dy * arm)], fill=col, width=w)


def ui(im, sel, card=None, anchor=None, night=False):
    d = ImageDraw.Draw(im, "RGBA")
    d.rectangle((0, 0, 1280, 52), fill=HEADER + (245,))
    d.text((24, 26), "SCRAP", font=F_body(13, 500), fill=DIM, anchor="lm")
    d.text((78, 26), "60", font=F_title(22), fill=GOLD, anchor="lm")
    d.text((160, 26), "DAY", font=F_body(13, 500), fill=DIM, anchor="lm")
    d.text((196, 26), "1", font=F_title(22), fill=TEXT, anchor="lm")
    d.text((250, 26), "ROSTER", font=F_body(13, 500), fill=DIM, anchor="lm")
    d.text((318, 26), "2/6", font=F_title(20), fill=TEXT, anchor="lm")
    d.rectangle((1160, 10, 1256, 42), fill=PANEL + (240,), outline=HAIRLINE)
    d.text((1208, 26), "MENU", font=F_body(14, 600), fill=TEXT, anchor="mm")

    d.rectangle((0, 648, 1280, 720), fill=(0x12, 0x14, 0x16, 255))
    for i, t in enumerate(["GARAGE", "RESEARCH", "SALOON", "INN", "COMMS"]):
        x0 = i * 256
        act = t == "SALOON"
        fill = (0x2a, 0x28, 0x22, 255) if act else (0x1a, 0x1d, 0x20, 255)
        d.rectangle((x0 + 2, 650, x0 + 254, 718), fill=fill)
        if act:
            d.rectangle((x0 + 2, 650, x0 + 254, 654), fill=GOLD)
        d.text((x0 + 128, 686), t, font=F_title(20), fill=GOLD if act else TEXT, anchor="mm")

    if not sel:
        d.rectangle((24, 580, 520, 628), fill=PANEL + (230,), outline=HAIRLINE)
        _brackets(d, 24, 580, 520, 628, arm=8, w=1)
        d.text((40, 604), "SALOON  —  tap a drifter to hire", font=F_body(16, 500), fill=DIM, anchor="lm")
        return

    name, role, rarity, stats, cost = card
    rcol = RARITY.get(rarity, GOLD)
    x0, y0, x1, y1 = 900, 72, 1256, 520
    d.rectangle((x0, y0, x1, y1), fill=PANEL + (245,))
    d.rectangle((x0, y0, x1, y0 + 44), fill=HEADER + (255,))
    d.rectangle((x0, y0, x1, y1), outline=rcol, width=2)
    _brackets(d, x0, y0, x1, y1, col=GOLD, arm=12, w=2)
    d.text((x0 + 18, y0 + 22), name, font=F_title(22), fill=GOLD, anchor="lm")
    chip = rarity.upper()
    tw = d.textlength(chip, font=F_body(12, 600))
    d.rectangle((x1 - 24 - tw, y0 + 12, x1 - 12, y0 + 34), fill=rcol)
    d.text((x1 - 18 - tw / 2, y0 + 23), chip, font=F_body(11, 700), fill=(20, 18, 14), anchor="mm")
    d.text((x0 + 18, y0 + 58), role, font=F_body(15, 500), fill=TEXT)
    yy = y0 + 96
    d.rectangle((x0 + 12, y0 + 84, x1 - 12, y1 - 120), fill=PANEL_BODY + (255,))
    for k, v in stats:
        d.text((x0 + 24, yy), k, font=F_body(14, 450), fill=DIM)
        d.text((x1 - 24, yy), str(v), font=F_title(16), fill=TEXT, anchor="ra")
        d.line((x0 + 24, yy + 24, x1 - 24, yy + 24), fill=(255, 255, 255, 16))
        yy += 36
    d.text((x0 + 18, y1 - 100), "COST", font=F_body(12, 500), fill=DIM)
    d.text((x1 - 18, y1 - 102), f"{cost} SCRAP", font=F_title(18), fill=GOLD, anchor="ra")
    d.rectangle((x0 + 18, y1 - 72, x1 - 18, y1 - 18), fill=GOLD)
    d.text(((x0 + x1) // 2, y1 - 45), "HIRE", font=F_title(24), fill=(24, 20, 12), anchor="mm")

    if anchor:
        ax, ay = anchor
        ex, ey = x0, y0 + 36
        mid = ex - 36
        d.line([(ex, ey), (mid, ey), (ax, ay)], fill=GOLD, width=2)
        d.ellipse((ax - 5, ay - 5, ax + 5, ay + 5), fill=GOLD)


def night_grade(a, em):
    tint = np.array([0x51, 0x2b, 0x11], dtype=np.float32) / 255.0
    rgb = np.clip(a / 255.0, 0, 1)
    lum = (rgb @ np.array([0.299, 0.587, 0.114]))[..., None]
    k = tint / max(float(lum.mean()), 1e-3)
    graded = np.clip(lum * k * 0.85 + rgb * tint[None, None, :] * 0.30, 0, 1) * 255.0
    return np.where(em[..., None], a, graded)


def finish(sc, light, sel, card, path, night=False):
    img, own, em, oy = sc.render(light)
    a = np.clip(img, 0, 255)

    if night:
        a = night_grade(a, em)

    if sel:
        others = (own > 0) & (own != sel) & ~em
        a[others] *= 0.38
        m = own == sel
        mi = Image.fromarray((m.astype(np.uint8) * 255))
        dil = np.array(mi.filter(ImageFilter.MaxFilter(9))) > 0
        edge = dil & ~m
        a[edge] = GOLD
        yy, xx = np.nonzero(m)
        if len(xx):
            cx, cy = xx.mean(), yy.mean()
            Y, X = np.mgrid[0:720, 0:1280]
            r = np.hypot((X - cx) / 1.35, Y - cy)
            f = np.clip((r - 160) / 300, 0, 1) * 0.50
            a *= (1 - f)[..., None]
            a[edge] = GOLD

    e = np.zeros_like(a)
    e[em] = a[em]
    glow = np.array(
        Image.fromarray(np.clip(e, 0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(12))
    ).astype(np.float32)
    a = a + glow * (1.15 if not night else 1.55)

    pil = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)).convert("RGBA")
    Y, X = np.mgrid[0:720, 0:1280]
    v = np.clip((np.hypot((X - 640) / 640, (Y - 340) / 380) - 0.82) / 0.40, 0, 1) * 0.45
    vig = np.zeros((720, 1280, 4), np.uint8)
    vig[..., 3] = (v * 255).astype(np.uint8)
    pil = Image.alpha_composite(pil, Image.fromarray(vig))

    anchor = None
    if sel:
        yy, xx = np.nonzero(own == sel)
        if len(xx):
            anchor = (int(xx.max()) + 6, int(yy.min()) + 10)

    ui(pil, sel, card, anchor, night=night)
    pil.convert("RGB").save(path, optimize=True)
    print("wrote", path)


def lightfield(base, pools):
    def f(x, y, z):
        L = base
        for px, py, pz, rad, amt in pools:
            dd = math.hypot(x - px, (y - py) * 1.15) / rad
            L += amt * max(0.0, 1.0 - dd * dd)
        L += 0.08 * max(0, (1 - x / W)) + 0.05 * max(0, (1 - y / D))
        return max(0.22, min(1.40, L))
    return f
