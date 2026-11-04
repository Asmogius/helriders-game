"""V6.2 interface 9-slice textures: riveted steel panels with worn edges and
buttons (normal / hover / pressed / disabled). Deterministic (fixed seed).
Writes PNGs into art/ui/ ; ui_theme.gd loads them as StyleBoxTexture with
MARGIN px slices and falls back to flat boxes if they are missing.

    python3 tools/art/ui_panels.py
"""
import os, random
from PIL import Image

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "art", "ui")
SIZE = 48
MARGIN = 12  # keep in sync with ui_theme.gd NINE_MARGIN

# Colours from tuning.gd / ui_theme.gd (PANEL, PANEL_EDGE, COL_ORANGE, COL_CYAN).
PANEL = (22, 22, 24)
EDGE = (66, 69, 74)
ORANGE = (237, 122, 43)
CYAN = (64, 209, 224)


def plate(fill, edge, seed, alpha=248, rivets=True, accent=None):
    rnd = random.Random(seed)
    im = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    px = im.load()
    for y in range(SIZE):
        for x in range(SIZE):
            n = rnd.choice((0, 0, 0, 1, -1))   # faint grain (tiles, see ui_theme)
            c = tuple(max(0, min(255, v + n)) for v in fill)
            px[x, y] = c + (alpha,)
    # 2 px border: light top/left, dark bottom/right (a bevel), worn chips.
    for i in range(SIZE):
        for d in range(2):
            lite = tuple(min(255, v + 14) for v in edge)
            dark = tuple(max(0, v - 18) for v in edge)
            px[i, d] = lite + (255,)
            px[d, i] = lite + (255,)
            px[i, SIZE - 1 - d] = dark + (255,)
            px[SIZE - 1 - d, i] = dark + (255,)
    for _ in range(6):   # worn spots on the edge (only in the stretch-free corners' neighbours)
        i = rnd.randint(MARGIN, SIZE - MARGIN - 1)
        side = rnd.randint(0, 3)
        x, y = [(i, 0), (0, i), (i, SIZE - 1), (SIZE - 1, i)][side]
        px[x, y] = tuple(min(255, v + 40) for v in edge) + (255,)
    if rivets:   # 3x3 domed rivets in each corner (inside the fixed 9-slice corners)
        hi = tuple(min(255, v + 60) for v in edge) + (255,)
        mid = tuple(min(255, v + 20) for v in edge) + (255,)
        lo = (10, 10, 11, 255)
        for cx, cy in [(5, 5), (SIZE - 8, 5), (5, SIZE - 8), (SIZE - 8, SIZE - 8)]:
            for dy in range(3):
                for dx in range(3):
                    px[cx + dx, cy + dy] = mid
            px[cx, cy] = hi
            px[cx + 2, cy + 2] = lo
            px[cx + 3 if cx + 3 < SIZE else cx, cy + 3 if cy + 3 < SIZE else cy] = lo
    # Inner hairline: a second, darker frame line 3 px in (panel depth).
    inner = tuple(max(0, v - 8) for v in fill) + (255,)
    for i in range(3, SIZE - 3):
        px[i, 3] = inner
        px[3, i] = inner
    if accent:   # accent line along the bottom, inside the border
        for x in range(4, SIZE - 4):
            px[x, SIZE - 4] = accent + (255,)
    return im


def main():
    os.makedirs(OUT, exist_ok=True)
    out = {
        "panel": plate(PANEL, EDGE, 1, alpha=247),
        "button_normal": plate((33, 33, 37), EDGE, 2, rivets=False),
        "button_hover": plate((41, 41, 45), EDGE, 3, rivets=False, accent=CYAN),
        "button_pressed": plate((56, 36, 20), ORANGE, 4, rivets=False, accent=ORANGE),
        "button_disabled": plate((25, 25, 27), (46, 46, 48), 5, rivets=False),
    }
    for name, im in out.items():
        im.save(os.path.join(OUT, name + ".png"))
        print("wrote art/ui/%s.png" % name)


if __name__ == "__main__":
    main()
