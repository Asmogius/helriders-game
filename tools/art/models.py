"""Code-defined voxel models at 1 voxel = 1 px (hull ~64x36 on screen).
x = forward (nose at high x), y = right, z = up.

Each model is a dict of named CHUNKS, all the same grid shape, so they render
aligned. The composite sheet is every chunk together; each chunk also gets its
own sheet for the wreck explosion (plates fly apart). Hull and turret are
separate models because turrets aim on their own."""
import numpy as np
from palette import NAMES, colors_for

C = {n: i for i, n in enumerate(NAMES)}


class Model:
    def __init__(self, shape):
        self.shape = shape
        self.chunks = {}
        self.points = {}   # name -> (x, y, z) in voxels; projected per heading

    def g(self, name):
        if name not in self.chunks:
            self.chunks[name] = np.zeros(self.shape, np.int16)
        return self.chunks[name]


def box(g, x0, x1, y0, y1, z0, z1, c):
    g[x0:x1, y0:y1, z0:z1] = C[c]


def wheel(g, x0, length, y0, width, radius, outer_y):
    """Round-profile tyre: alternating tread blocks, a steel hub on the outer face."""
    cx, cz = x0 + length / 2.0, radius
    for x in range(x0, x0 + length):
        for z in range(0, 2 * radius):
            dx, dz = (x + 0.5 - cx) / (length / 2.0), (z + 0.5 - cz) / radius
            if dx * dx + dz * dz > 1.0:
                continue
            rim = dx * dx + dz * dz > 0.55
            tread = rim and ((x // 2) % 2 == 0)
            g[x, y0:y0 + width, z] = C["tyre"] if not tread else C["steel_dark"]
            if dx * dx + dz * dz < 0.3:            # hub on the outer face
                g[x, outer_y, z] = C["steel"]
            if dx * dx + dz * dz < 0.06:
                g[x, outer_y, z] = C["bone"]


def rivets(g, x0, x1, y0, y1, z, step=4):
    for x in range(x0 + 1, x1 - 1, step):
        for y in range(y0 + 1, y1 - 1, step):
            g[x, y, z] = C["steel_dark"]


def scrap_frame():
    """Player starter: Scrap Frame. Footprint 64x36 like vehicle.gd's default body."""
    m = Model((64, 36, 20))
    w = m.g("wheels")
    for x0 in (6, 42):
        wheel(w, x0, 14, 0, 6, 6, 0)
        wheel(w, x0, 14, 30, 6, 6, 35)
    c = m.g("chassis")
    box(c, 2, 62, 7, 29, 3, 9, "steel_dark")        # tub
    box(c, 4, 58, 6, 30, 9, 11, "steel")            # deck
    for x0 in (5, 41):                               # fenders arch over wheels
        box(c, x0, x0 + 16, 5, 7, 11, 14, "rust"); box(c, x0, x0 + 16, 29, 31, 11, 14, "rust")
        box(c, x0, x0 + 2, 1, 6, 9, 13, "rust"); box(c, x0 + 14, x0 + 16, 1, 6, 9, 13, "rust")
        box(c, x0, x0 + 2, 30, 35, 9, 13, "rust"); box(c, x0 + 14, x0 + 16, 30, 35, 9, 13, "rust")
    box(c, 22, 40, 6, 7, 10, 12, "cyan"); box(c, 22, 40, 29, 30, 10, 12, "cyan")  # edge lights
    box(c, 2, 5, 9, 27, 6, 11, "steel_dark")        # rear bumper
    c[2, 9:12, 8:10] = C["orange"]; c[2, 24:27, 8:10] = C["orange"]  # tail lights
    cab = m.g("cab")
    box(cab, 28, 47, 9, 27, 11, 18, "steel")
    box(cab, 30, 45, 11, 25, 18, 19, "steel_dark")  # roof
    box(cab, 43, 47, 11, 25, 13, 18, "glass")       # windscreen
    box(cab, 28, 43, 9, 10, 13, 16, "glass"); box(cab, 28, 43, 26, 27, 13, 16, "glass")  # side windows
    for y in (13, 18, 23):                            # roof rack bars
        box(cab, 31, 44, y, y + 1, 19, 20, "rust")
    fp = m.g("front_plate")
    for x in range(56, 64):                           # sloped ram plate
        top = 14 - (x - 56)
        box(fp, x, x + 1, 4, 32, 3, max(5, top), "rust")
    rivets(fp, 56, 60, 4, 32, 13, 3)
    fp[63, 5:8, 4:6] = C["cyan"]; fp[63, 28:31, 4:6] = C["cyan"]   # headlights
    m.points["turret_mount"] = (24.0, 18.0, 11.0)   # deck between rear plates and cab
    rp = m.g("rear_plates")
    box(rp, 6, 20, 9, 27, 11, 13, "rust")
    box(rp, 8, 18, 11, 25, 13, 14, "steel_dark")
    rivets(rp, 6, 20, 9, 27, 13, 4)
    return m


def pintle_turret():
    m = Model((30, 16, 10))
    m.points["pivot"] = (6.5, 8.0, 0.0)   # turret ring centre: sits on the hull mount
    b = m.g("mount")
    for x in range(0, 14):                            # round base
        for y in range(0, 16):
            if (x - 6.5) ** 2 + (y - 7.5) ** 2 <= 42:
                b[x, y, 0:3] = C["steel_dark"]
    box(b, 2, 11, 3, 13, 3, 6, "steel")               # gun body
    box(b, 3, 9, 12, 15, 2, 6, "rust")                # ammo box
    box(b, 1, 4, 5, 11, 6, 7, "steel_dark")           # shield lip
    g = m.g("barrel")
    box(g, 11, 29, 7, 9, 4, 6, "steel")
    box(g, 11, 20, 6, 10, 3, 7, "steel_dark")         # shroud
    box(g, 29, 30, 7, 9, 4, 6, "orange")              # muzzle
    return m


def outrider():
    """Enemy Outrider: low, fast, wedge nose, twin forward guns, red lights."""
    m = Model((68, 32, 16))
    w = m.g("wheels")
    for x0, ln, r in ((6, 12, 5), (46, 12, 5)):
        wheel(w, x0, ln, 0, 5, r, 0)
        wheel(w, x0, ln, 27, 5, r, 31)
    c = m.g("chassis")
    box(c, 2, 64, 6, 26, 2, 7, "steel_dark")
    box(c, 3, 42, 5, 27, 7, 10, "rust")
    for x in range(42, 66):                            # wedge nose
        inset = (x - 42) // 3
        box(c, x, x + 1, 5 + inset, 27 - inset, 6, 10 - (x - 42) // 8, "rust")
    box(c, 3, 40, 15, 17, 10, 11, "enemy_red")        # light bar
    c[2, 7:10, 5:7] = C["enemy_red"]; c[2, 22:25, 5:7] = C["enemy_red"]
    ck = m.g("cockpit")
    box(ck, 18, 34, 9, 23, 10, 14, "steel")
    box(ck, 30, 34, 10, 22, 11, 14, "glass")
    box(ck, 19, 30, 10, 22, 14, 15, "steel_dark")
    m.points["turret_mount"] = (24.0, 16.0, 15.0)   # cockpit roof (unused: Outrider guns are fixed)
    gn = m.g("guns")
    for y0 in (2, 26):
        box(gn, 44, 67, y0, y0 + 4, 7, 10, "steel")
        box(gn, 44, 52, y0, y0 + 4, 10, 11, "steel_dark")
        gn[67, y0 + 1:y0 + 3, 8:9] = C["enemy_red"]
    return m


def ALL():
    col = colors_for()
    return {"scrap_frame": (scrap_frame(), col),
            "pintle_turret": (pintle_turret(), col),
            "outrider": (outrider(), col)}
