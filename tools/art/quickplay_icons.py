"""Quickplay editor tray icons (QP3).

One 64x64 pictorial glyph per placeable id, for the bottom tray on a phone.
Drawn on a 32x32 grid and nearest-neighbour scaled x2 so the pixels stay
chunky. Colours come from scripts/tuning.gd (via palette.tuning_color) and
tools/art/palette.py. No new colours. Transparent ground, 1 px near-black
outline (2 px once scaled).

    python3 tools/art/quickplay_icons.py

Writes art/ui/quickplay/<id>.png. A contact sheet for review goes to
art/previews/quickplay_icons.png (Godot ignores that folder).
"""
import os
from PIL import Image, ImageChops, ImageDraw, ImageFont

from palette import OUTLINE, PALETTE, SHADE_MUL, tuning_color

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
OUT = os.path.join(ROOT, "art", "ui", "quickplay")
SHEET = os.path.join(ROOT, "art", "previews", "quickplay_icons.png")
S = 32
SCALE = 2  # 64x64 on disk

# tuning.gd colours. Emissive lights stay full strength.
CYAN = tuning_color("COL_CYAN")
ORANGE = tuning_color("COL_ORANGE")
ENEMY = tuning_color("COL_ENEMY")
GOLD = tuning_color("COL_UI_ACCENT")
ZOMBIE = tuning_color("COL_ZOMBIE")
ZOMBIE_DARK = tuning_color("COL_ZOMBIE_DARK")
EYE = tuning_color("COL_ZOMBIE_EYE")
SHIRT = tuning_color("COL_ZOMBIE_SHIRT_4")
PANTS = tuning_color("COL_ZOMBIE_PANTS_4")
BUILDING = tuning_color("COL_BUILDING")
RUST = tuning_color("COL_RUST")
STEEL = tuning_color("COL_STEEL")
ACID = tuning_color("COL_ACID_GROUND")  # #99F240
CONCRETE = tuning_color("COL_OB_SIDING")
CONCRETE_DARK = tuning_color("COL_OB_PAVE")
INK = OUTLINE[:3]
TYRE = PALETTE["tyre"]
GLASS = PALETTE["glass"]
GLASS_DARK = tuple(int(c * SHADE_MUL[0]) for c in GLASS)
STEEL_DARK = tuple(int(c * SHADE_MUL[0]) for c in STEEL)
WOOD = tuple(int(c * SHADE_MUL[1]) for c in RUST)
WOOD_DARK = tuple(int(c * SHADE_MUL[0]) for c in RUST)
BONE = PALETTE["bone"]
TEXT = tuning_color("COL_UI_TEXT")
DEEP = tuning_color("COL_UI_DEEP")
SIDING = tuning_color("COL_OB_SIDING")


def _rgba(c):
    return c if len(c) == 4 else c + (255,)


def _rect(d, x, y, w, h, c):
    if w <= 0 or h <= 0:
        return
    d.rectangle([x, y, x + w - 1, y + h - 1], fill=_rgba(c))


def _outline(im):
    """1 px near-black outline on empty neighbours, including diagonals."""
    src = im.copy().load()
    px = im.load()
    nbs = ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1))
    for y in range(S):
        for x in range(S):
            if src[x, y][3] != 0:
                continue
            if any(0 <= x + dx < S and 0 <= y + dy < S and src[x + dx, y + dy][3] > 0 for dx, dy in nbs):
                px[x, y] = INK + (230,)
    return im


def _brackets(d, c=GOLD):
    """Corner brackets: the spawner mark, shared by both spawners."""
    arm = 4
    inset = 2
    corners = (
        (inset, inset, 1, 1),
        (S - 1 - inset, inset, -1, 1),
        (inset, S - 1 - inset, 1, -1),
        (S - 1 - inset, S - 1 - inset, -1, -1),
    )
    for x, y, sx, sy in corners:
        d.line([(x, y), (x + arm * sx, y)], fill=_rgba(c), width=1)
        d.line([(x, y), (x, y + arm * sy)], fill=_rgba(c), width=1)


def _blank():
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    return im, ImageDraw.Draw(im)


def player_start():
    """Spawn flag. Cyan pennant is the player colour; gold finial is the UI accent."""
    im, d = _blank()
    _rect(d, 8, 25, 10, 4, STEEL_DARK)          # base plate
    _rect(d, 9, 25, 8, 1, STEEL)
    _rect(d, 11, 6, 2, 20, STEEL)               # pole
    _rect(d, 11, 6, 1, 20, BONE)                # lit edge
    _rect(d, 10, 3, 4, 4, GOLD)                 # finial
    d.polygon([(13, 7), (27, 12), (13, 18)], fill=_rgba(CYAN))
    d.polygon([(16, 10), (21, 12), (16, 14)], fill=_rgba(GOLD))
    return im


def spawner_zombie():
    """Top-down shambler, arms reaching up (forward), inside spawner brackets."""
    im, d = _blank()
    _brackets(d)
    _rect(d, 12, 21, 3, 6, PANTS)
    _rect(d, 17, 21, 3, 6, PANTS)
    _rect(d, 11, 15, 10, 8, SHIRT)
    _rect(d, 11, 15, 10, 2, ZOMBIE_DARK)        # hunched shoulders
    _rect(d, 7, 11, 5, 4, ZOMBIE)               # arms, forward
    _rect(d, 20, 11, 5, 4, ZOMBIE)
    _rect(d, 7, 9, 4, 3, ZOMBIE_DARK)           # hands
    _rect(d, 21, 9, 4, 3, ZOMBIE_DARK)
    d.ellipse([12, 8, 19, 16], fill=_rgba(ZOMBIE))
    _rect(d, 13, 11, 2, 2, EYE)
    _rect(d, 17, 11, 2, 2, EYE)
    return im


def spawner_rig():
    """Top-down enemy car, nose up, inside the same spawner brackets."""
    im, d = _blank()
    _brackets(d)
    # Tyres sit outside the hull.
    for x, y in ((8, 10), (21, 10), (8, 19), (21, 19)):
        _rect(d, x, y, 3, 5, TYRE)
        _rect(d, x + 1, y + 2, 1, 1, STEEL_DARK)
    _rect(d, 11, 9, 10, 15, ENEMY)
    _rect(d, 11, 8, 10, 2, STEEL)               # front bumper
    _rect(d, 12, 8, 2, 1, TEXT)                 # headlights
    _rect(d, 18, 8, 2, 1, TEXT)
    _rect(d, 11, 22, 10, 2, STEEL_DARK)         # rear bumper
    _rect(d, 13, 13, 6, 6, GLASS)               # cabin
    _rect(d, 14, 14, 4, 4, GLASS_DARK)
    _rect(d, 15, 12, 2, 3, STEEL)               # turret stub, aims forward
    return im


def _building(box, vents, streak=False):
    """Top-down box building. Siding roof sits lighter than the steel wall so
    the block reads on a charcoal tray (map roofs are too dark at icon size)."""
    im, d = _blank()
    x, y, w, h = box
    _rect(d, x, y, w, h, STEEL)
    _rect(d, x, y + h - 3, w, 3, BUILDING)      # near wall
    door = max(2, w // 6)
    _rect(d, x + (w - door) // 2, y + h - 3, door, 3, TYRE)
    _rect(d, x + 2, y + 2, w - 4, h - 6, SIDING)
    for vx, vy, vw, vh in vents:
        _rect(d, vx, vy, vw, vh, STEEL_DARK)
    if streak:
        _rect(d, x + w - 4, y + 4, 2, h - 8, RUST)
    return im


def building_box_s():
    return _building((10, 10, 12, 12), [(14, 14, 4, 3)])


def building_box_m():
    return _building((6, 7, 20, 18), [(9, 11, 5, 3), (17, 16, 5, 3)])


def building_box_l():
    return _building((3, 4, 26, 24), [(6, 8, 5, 3), (14, 12, 6, 4), (21, 18, 5, 3)], streak=True)


def prop_wreck():
    """Same top-down car as the rig spawner, burnt: rust hull, gutted cabin,
    crumpled nose, one wheel thrown clear. No lights, no spawner brackets."""
    im, d = _blank()
    d.ellipse([23, 21, 30, 28], fill=_rgba(TYRE))   # loose wheel
    d.ellipse([25, 23, 28, 26], fill=_rgba(STEEL_DARK))
    for x, y in ((7, 9), (21, 10), (7, 19)):
        _rect(d, x, y, 3, 5, TYRE)
        _rect(d, x + 1, y + 2, 1, 1, STEEL_DARK)
    d.polygon([(11, 10), (21, 8), (22, 22), (10, 24)], fill=_rgba(RUST))
    _rect(d, 13, 8, 6, 3, TYRE)                 # nose bitten off
    _rect(d, 13, 14, 6, 5, TYRE)                # gutted cabin
    _rect(d, 11, 17, 2, 4, WOOD_DARK)           # scorch down the flank
    return im


def prop_barrier():
    """Concrete jersey barrier, top-down, with the arena's orange stripes."""
    im, d = _blank()
    d.polygon([(3, 13), (28, 13), (26, 21), (5, 21)], fill=_rgba(CONCRETE))
    _rect(d, 4, 13, 24, 2, TEXT)                # lit top edge
    for x in (6, 13, 20):
        _rect(d, x, 15, 4, 4, ORANGE)
    _rect(d, 5, 19, 22, 2, CONCRETE_DARK)
    return im


def _crate(d, x, y, w, h, fill):
    _rect(d, x, y, w, h, fill)
    _rect(d, x, y + h // 2, w, 1, WOOD_DARK)
    _rect(d, x + w // 2, y, 1, h, WOOD_DARK)
    _rect(d, x, y, w, 1, RUST)


def prop_crates():
    im, d = _blank()
    _crate(d, 4, 17, 14, 12, WOOD)       # lower
    _crate(d, 16, 12, 12, 12, WOOD)
    _crate(d, 8, 4, 11, 11, RUST)        # top crate, lighter rust
    return im


def _barrel(body, band, band_h, drip):
    im, d = _blank()
    d.ellipse([5, 4, 26, 25], fill=_rgba(STEEL_DARK))   # rim
    d.ellipse([7, 6, 24, 23], fill=_rgba(body))
    band_layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    bd = ImageDraw.Draw(band_layer)
    _rect(bd, 7, 13, 18, band_h, band)
    _rect(bd, 7, 19, 18, 1, STEEL)                      # lower hoop
    circle = Image.new("L", (S, S), 0)
    ImageDraw.Draw(circle).ellipse([7, 6, 24, 23], fill=255)
    # Paste only the band. A full-circle mask would wipe the body with
    # the band layer's empty pixels.
    mask = ImageChops.multiply(band_layer.split()[-1], circle)
    im.paste(band_layer, (0, 0), mask)
    d.ellipse([14, 12, 17, 15], fill=_rgba(INK))        # bung
    if drip:
        _rect(d, 15, 25, 2, 2, body)
        _rect(d, 16, 27, 1, 2, body)
    return im


def barrel_fuel():
    """Red explosive barrel with a wide orange band (fire / explosive pair)."""
    return _barrel(ENEMY, ORANGE, 4, False)


def barrel_acid():
    """Acid barrel in #99F240, a thin steel hoop, bubbles and a drip."""
    im = _barrel(ACID, STEEL, 2, True)
    d = ImageDraw.Draw(im)
    d.ellipse([10, 8, 13, 11], fill=_rgba(TEXT))
    d.ellipse([17, 9, 19, 11], fill=_rgba(TEXT))
    return im


def pickup_scrap():
    """Loose metal: rust plate, steel offcut, a bolt, an orange glint like a scrap cache."""
    im, d = _blank()
    d.polygon([(6, 18), (18, 14), (22, 20), (10, 25)], fill=_rgba(RUST))
    d.polygon([(14, 8), (24, 11), (21, 16), (12, 14)], fill=_rgba(STEEL))
    d.polygon([(8, 10), (14, 8), (13, 14), (7, 15)], fill=_rgba(STEEL_DARK))
    _rect(d, 18, 18, 6, 3, BONE)
    _rect(d, 20, 17, 2, 5, STEEL_DARK)                  # bolt
    _rect(d, 23, 12, 2, 2, ORANGE)                      # glint
    _rect(d, 9, 20, 3, 2, WOOD_DARK)
    return im


ICONS = [
    ("player_start", player_start),
    ("spawner_zombie", spawner_zombie),
    ("spawner_rig", spawner_rig),
    ("building_box_s", building_box_s),
    ("building_box_m", building_box_m),
    ("building_box_l", building_box_l),
    ("prop_wreck", prop_wreck),
    ("prop_barrier", prop_barrier),
    ("prop_crates", prop_crates),
    ("barrel_fuel", barrel_fuel),
    ("barrel_acid", barrel_acid),
    ("pickup_scrap", pickup_scrap),
]


def _finish(im):
    _outline(im)
    return im.resize((S * SCALE, S * SCALE), Image.Resampling.NEAREST)


def _sheet(tiles):
    """Charcoal contact sheet. Icons are the committed 64px art, nearest-scaled."""
    font_path = os.path.join(ROOT, "art", "ui", "fonts", "Inter-Regular.ttf")
    font = ImageFont.truetype(font_path, 16)
    title_font = ImageFont.truetype(font_path, 22)
    cols = 4
    # Show the committed 64 px art nearest-scaled to 128 so review matches the file.
    shown = 128
    pad = 28
    label_h = 26
    cell_w = shown + pad
    cell_h = shown + label_h + 16
    rows = (len(tiles) + cols - 1) // cols
    header = 64
    sheet = Image.new("RGBA", (cols * cell_w + pad, header + rows * cell_h + pad), DEEP + (255,))
    draw = ImageDraw.Draw(sheet)
    draw.text((pad, 18), "Quickplay tray icons  ·  64×64", font=title_font, fill=GOLD + (255,))
    for i, (name, im) in enumerate(tiles):
        col, row = i % cols, i // cols
        x = pad + col * cell_w
        y = header + row * cell_h
        big = im.resize((shown, shown), Image.Resampling.NEAREST)
        plate = Image.new("RGBA", (shown + 8, shown + 8), (24, 29, 32, 255))
        sheet.paste(plate, (x - 4, y - 4))
        sheet.paste(big, (x, y), big)
        draw.text((x, y + shown + 6), name, font=font, fill=TEXT + (255,))
    os.makedirs(os.path.dirname(SHEET), exist_ok=True)
    sheet.convert("RGB").save(SHEET)
    return SHEET


def main():
    os.makedirs(OUT, exist_ok=True)
    tiles = []
    for name, fn in ICONS:
        im = _finish(fn())
        path = os.path.join(OUT, name + ".png")
        im.save(path)
        tiles.append((name, im))
        print("wrote %s (%dx%d)" % (os.path.relpath(path, ROOT), im.size[0], im.size[1]))
    sheet = _sheet(tiles)
    print("wrote %s" % os.path.relpath(sheet, ROOT))


if __name__ == "__main__":
    main()
