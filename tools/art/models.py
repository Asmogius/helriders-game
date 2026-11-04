"""Code-defined voxel models at 1 voxel = 1 px. x = forward (nose at high x),
y = right, z = up.

Chassis models (Scrap Frame, Bulwark Frame) are a core (chunks) plus LAYERS
picked by the equipped parts: one drive, one front armor and any extras. Every
layer is built for its chassis's own dimensions (a roll cage fits that cab).
Wheels are one piece each, so a wreck throws them separately."""
import numpy as np
from palette import NAMES, colors_for

C = {n: i for i, n in enumerate(NAMES)}


class Model:
    def __init__(self, shape):
        self.shape = shape
        self.chunks = {}
        self.layers = {}     # id -> {"slot": str, "pieces": {name: grid}}
        self.defaults = []   # layer ids in the composite preview (stock parts)
        self.points = {}     # name -> (x, y, z) in voxels; projected per heading

    def g(self, name):
        if name not in self.chunks:
            self.chunks[name] = np.zeros(self.shape, np.int16)
        return self.chunks[name]

    def layer(self, lid, slot, piece="all"):
        L = self.layers.setdefault(lid, {"slot": slot, "pieces": {}})
        return L["pieces"].setdefault(piece, np.zeros(self.shape, np.int16))


def box(g, x0, x1, y0, y1, z0, z1, c):
    g[max(0, x0):x1, max(0, y0):y1, max(0, z0):z1] = C[c]


def wheel(g, x0, length, y0, width, radius, outer_y, tread_step=2, hub="steel", hub_r=0.3):
    """Round-profile tyre: tread blocks on the rim, a hub on the outer face."""
    cx, cz = x0 + length / 2.0, radius
    for x in range(x0, x0 + length):
        for z in range(0, 2 * radius):
            dx, dz = (x + 0.5 - cx) / (length / 2.0), (z + 0.5 - cz) / radius
            r2 = dx * dx + dz * dz
            if r2 > 1.0:
                continue
            tread = r2 > 0.55 and ((x // tread_step) % 2 == 0)
            g[x, y0:y0 + width, z] = C["steel_dark"] if tread else C["tyre"]
            if r2 < hub_r:
                g[x, outer_y, z] = C[hub]
            if r2 < 0.06:
                g[x, outer_y, z] = C["bone"]


def track(g, x0, x1, y0, width, height, outer_y):
    """Half-track belt: rounded ends, cleats, road wheels on the outer face."""
    for x in range(x0, x1):
        end = min(x - x0, x1 - 1 - x)
        top = height if end >= 2 else height - (2 - end)
        g[x, y0:y0 + width, 0:top] = C["tyre"]
        if x % 3 == 0:
            g[x, y0:y0 + width, top - 1] = C["steel_dark"]
    for xc in range(x0 + 3, x1 - 2, 6):
        box(g, xc, xc + 3, outer_y, outer_y + 1, 2, height - 2, "steel")


def rivets(g, x0, x1, y0, y1, z, step=4):
    for x in range(x0 + 1, x1 - 1, step):
        for y in range(y0 + 1, y1 - 1, step):
            g[x, y, z] = C["steel_dark"]


def chassis_layers(m, L, W, wheels_x, wheel_len, deck_z, cab, nose_x):
    """Drive, front armor and extras for a chassis L x W voxels.
    wheels_x: wheel start x per axle; cab = (x0, x1, y0, y1, z0, z1)."""
    # --- drives: one piece per wheel ---
    def axle_set(lid, fn):
        for i, x0 in enumerate(wheels_x):
            fn(m.layer(lid, "drive", f"wheel_{i}_l"), x0, 0, 0)
            fn(m.layer(lid, "drive", f"wheel_{i}_r"), x0, W - 6, W - 1)
    axle_set("drive:street_wheels", lambda g, x0, y0, oy: wheel(g, x0, wheel_len, y0, 6, 6, oy))
    axle_set("drive:off_road_tires", lambda g, x0, y0, oy: wheel(g, x0 - 1, wheel_len + 2, y0, 6, 7, oy, tread_step=3))
    axle_set("drive:outrider_sport_wheels", lambda g, x0, y0, oy: wheel(g, x0, wheel_len, y0, 6, 6, oy, hub="orange", hub_r=0.45))
    # Half-track: tracks over the rear axles, small wheels on the front axle.
    rear_end = wheels_x[-2] + wheel_len + 2 if len(wheels_x) > 2 else wheels_x[0] + wheel_len + 4
    for side, y0, oy in (("l", 0, 0), ("r", W - 6, W - 1)):
        track(m.layer("drive:half_track", "drive", f"track_{side}"), 3, rear_end, y0, 6, 10, oy)
        wheel(m.layer("drive:half_track", "drive", f"wheel_{side}"), wheels_x[-1] + 2, wheel_len - 4, y0, 6, 4, oy)
    # --- front armor (one plate each) ---
    def plate(lid):
        return m.layer(lid, "armor")
    g = plate("armor:scrap_plating")
    for x in range(nose_x, L):
        box(g, x, x + 1, 4, W - 4, 3, max(5, deck_z + 3 - (x - nose_x)), "rust")
    rivets(g, nose_x, nose_x + 4, 4, W - 4, deck_z + 2, 3)
    g[L - 1, 5:8, 4:6] = C["cyan"]; g[L - 1, W - 8:W - 5, 4:6] = C["cyan"]
    g = plate("armor:riot_plating")
    box(g, nose_x - 4, L, 2, W - 2, 3, deck_z + 5, "steel")
    for y in range(5, W - 5, 6):
        box(g, nose_x - 3, L - 1, y, y + 2, deck_z + 5, deck_z + 6, "steel_dark")
    box(g, L - 1, L, 6, W - 6, 6, 8, "steel_dark")
    g = plate("armor:spiked_ram_plate")
    box(g, nose_x - 2, L - 4, 4, W - 4, 3, deck_z + 2, "rust")
    for y in range(6, W - 6, 6):
        for k in range(4):
            box(g, L - 4 + k, L - 3 + k, y + k // 2, y + 3 - k // 2, 6, 9 - k // 2, "bone")
    g = plate("armor:composite_plating")
    box(g, nose_x - 2, L, 3, W - 3, 3, deck_z + 3, "steel_dark")
    box(g, nose_x - 2, L, 3, 4, deck_z + 2, deck_z + 3, "cyan"); box(g, nose_x - 2, L, W - 4, W - 3, deck_z + 2, deck_z + 3, "cyan")
    box(g, L - 1, L, 4, W - 4, deck_z + 2, deck_z + 3, "cyan")
    g = plate("armor:outrider_light_plating")
    box(g, nose_x + 2, L, 5, W - 5, 3, deck_z + 1, "rust")
    box(g, nose_x + 2, L, W // 2 - 1, W // 2 + 1, deck_z + 1, deck_z + 2, "enemy_red")
    g = plate("armor:cowcatcher_ram")   # angled bar grille sweeping out to a point
    for x in range(nose_x - 2, L):
        inset = (x - (nose_x - 2)) * 2
        y0, y1 = 3 + inset // 2, W - 3 - inset // 2
        box(g, x, x + 1, y0, y0 + 2, 3, deck_z + 1, "steel"); box(g, x, x + 1, y1 - 2, y1, 3, deck_z + 1, "steel")
        if x % 2 == 0:
            box(g, x, x + 1, y0, y1, 4, 6, "steel_dark")
    box(g, nose_x - 2, nose_x, 3, W - 3, 3, deck_z + 2, "rust")
    m.defaults += ["drive:street_wheels", "armor:scrap_plating"]
    # --- extras ---
    for lid, tip in (("nose_guns", "steel_dark"), ("nose_guns_hot", "white_hot")):
        g = m.layer(lid, "extra")
        for y0 in (1, W - 5):
            box(g, nose_x - 8, L - 1, y0, y0 + 4, deck_z, deck_z + 3, "steel")
            box(g, nose_x - 8, nose_x - 2, y0, y0 + 4, deck_z + 3, deck_z + 4, "steel_dark")
            box(g, L - 1, L, y0 + 1, y0 + 3, deck_z + 1, deck_z + 2, tip)
    g = m.layer("patch_kit", "extra")
    box(g, 8, 16, W - 12, W - 5, deck_z + 1, deck_z + 5, "steel_dark")
    box(g, 11, 13, W - 11, W - 6, deck_z + 5, deck_z + 6, "patch_green")
    box(g, 9, 15, W - 9, W - 8, deck_z + 5, deck_z + 6, "patch_green")
    g = m.layer("mine_rack", "extra")
    box(g, 0, 4, W // 2 - 10, W // 2 + 10, 5, 10, "steel_dark")
    for y in range(W // 2 - 8, W // 2 + 9, 6):
        box(g, 0, 3, y, y + 3, 10, 12, "bone")
        g[1, y + 1, 12] = C["enemy_red"]
    g = m.layer("sensor_dish", "extra")
    box(g, 6, 8, W // 2 - 1, W // 2 + 1, deck_z, deck_z + 6, "steel_dark")
    for x in range(3, 11):
        for y in range(W // 2 - 4, W // 2 + 4):
            if (x - 6.5) ** 2 + (y - W / 2 + 0.5) ** 2 <= 13:
                g[x, y, deck_z + 6] = C["steel"]
    g[6, W // 2, deck_z + 7] = C["cyan"]
    # Roll cage sized to this chassis's cab: bars round the cab, one over the top.
    cx0, cx1, cy0, cy1, cz0, cz1 = cab
    g = m.layer("roll_cage", "extra")
    x0, x1, y0, y1, top = cx0 - 1, cx1 + 1, cy0 - 1, cy1 + 1, cz1 + 2
    for x in (x0, x1 - 1):
        for y in (y0, y1 - 1):
            box(g, x, x + 1, y, y + 1, cz0, top, "steel_dark")
    box(g, x0, x1, y0, y0 + 1, top - 1, top, "steel_dark"); box(g, x0, x1, y1 - 1, y1, top - 1, top, "steel_dark")
    box(g, x0, x0 + 1, y0, y1, top - 1, top, "steel_dark"); box(g, x1 - 1, x1, y0, y1, top - 1, top, "steel_dark")
    mid = (x0 + x1) // 2
    box(g, mid, mid + 1, y0, y1, top - 1, top, "steel_dark")


def scrap_frame():
    """Player starter: Scrap Frame. Footprint 64x36 like vehicle.gd's default body."""
    m = Model((64, 36, 22))
    c = m.g("chassis")
    box(c, 2, 62, 7, 29, 3, 9, "steel_dark")        # tub
    box(c, 4, 58, 6, 30, 9, 11, "steel")            # deck
    for x0 in (5, 41):                               # fender lips over the wheels
        box(c, x0, x0 + 16, 5, 7, 11, 14, "rust"); box(c, x0, x0 + 16, 29, 31, 11, 14, "rust")
    box(c, 22, 40, 6, 7, 10, 12, "cyan"); box(c, 22, 40, 29, 30, 10, 12, "cyan")  # edge lights
    box(c, 2, 5, 9, 27, 6, 11, "steel_dark")        # rear bumper
    c[2, 9:12, 8:10] = C["orange"]; c[2, 24:27, 8:10] = C["orange"]
    cab = m.g("cab")
    box(cab, 28, 47, 9, 27, 11, 18, "steel")
    box(cab, 30, 45, 11, 25, 18, 19, "steel_dark")
    box(cab, 43, 47, 11, 25, 13, 18, "glass")
    box(cab, 28, 43, 9, 10, 13, 16, "glass"); box(cab, 28, 43, 26, 27, 13, 16, "glass")
    for y in (13, 18, 23):
        box(cab, 31, 44, y, y + 1, 19, 20, "rust")
    rp = m.g("rear_plates")
    box(rp, 6, 20, 9, 27, 11, 13, "rust")
    box(rp, 8, 18, 11, 25, 13, 14, "steel_dark")
    rivets(rp, 6, 20, 9, 27, 13, 4)
    chassis_layers(m, 64, 36, (6, 42), 14, 11, (28, 47, 9, 27, 11, 19), 56)
    m.points["turret_mount"] = (24.0, 18.0, 11.0)
    return m


def bulwark_frame():
    """Bulwark Frame: 76x42, slab sides, six wheels, two hardpoints."""
    m = Model((76, 42, 22))
    c = m.g("chassis")
    box(c, 2, 74, 6, 36, 3, 10, "steel_dark")
    box(c, 3, 70, 5, 37, 10, 12, "steel")
    box(c, 24, 52, 6, 7, 11, 13, "cyan"); box(c, 24, 52, 35, 36, 11, 13, "cyan")
    c[2, 8:11, 7:10] = C["orange"]; c[2, 31:34, 7:10] = C["orange"]
    sk = m.g("skirts")
    box(sk, 8, 68, 4, 6, 6, 14, "steel_dark"); box(sk, 8, 68, 36, 38, 6, 14, "steel_dark")
    rivets(sk, 8, 68, 4, 6, 13, 5); rivets(sk, 8, 68, 36, 38, 13, 5)
    cab = m.g("cab")
    box(cab, 30, 46, 10, 32, 12, 18, "steel")
    box(cab, 43, 46, 12, 30, 13, 18, "glass")
    box(cab, 31, 44, 12, 30, 18, 19, "steel_dark")
    rp = m.g("rear_plates")
    box(rp, 4, 12, 8, 34, 12, 14, "rust")
    rivets(rp, 4, 12, 8, 34, 14, 4)
    chassis_layers(m, 76, 42, (6, 30, 54), 14, 12, (30, 46, 10, 32, 12, 19), 68)
    m.points["mount_a"] = (53.0, 21.0, 12.0)
    m.points["mount_b"] = (15.0, 21.0, 14.0)
    m.points["turret_mount"] = (24.0, 21.0, 12.0)
    return m


def pintle_turret():
    m = Model((30, 16, 10))
    m.points["pivot"] = (6.5, 8.0, 0.0)
    m.points["muzzle"] = (29.5, 8.0, 5.0)
    b = m.g("mount")
    for x in range(0, 14):
        for y in range(0, 16):
            if (x - 6.5) ** 2 + (y - 7.5) ** 2 <= 42:
                b[x, y, 0:3] = C["steel_dark"]
    box(b, 2, 11, 3, 13, 3, 6, "steel")
    box(b, 3, 9, 12, 15, 2, 6, "rust")
    box(b, 1, 4, 5, 11, 6, 7, "steel_dark")
    g = m.g("barrel")
    box(g, 11, 29, 7, 9, 4, 6, "steel")
    box(g, 11, 20, 6, 10, 3, 7, "steel_dark")
    box(g, 29, 30, 7, 9, 4, 6, "orange")
    return m


def outrider():
    """Enemy Outrider: low, fast, wedge nose, twin forward guns, red lights."""
    m = Model((68, 32, 16))
    for i, x0 in enumerate((6, 46)):
        wheel(m.g(f"wheel_{i}_l"), x0, 12, 0, 5, 5, 0)
        wheel(m.g(f"wheel_{i}_r"), x0, 12, 27, 5, 5, 31)
    c = m.g("chassis")
    box(c, 2, 64, 6, 26, 2, 7, "steel_dark")
    box(c, 3, 42, 5, 27, 7, 10, "rust")
    for x in range(42, 66):
        inset = (x - 42) // 3
        box(c, x, x + 1, 5 + inset, 27 - inset, 6, 10 - (x - 42) // 8, "rust")
    box(c, 3, 40, 15, 17, 10, 11, "enemy_red")
    c[2, 7:10, 5:7] = C["enemy_red"]; c[2, 22:25, 5:7] = C["enemy_red"]
    ck = m.g("cockpit")
    box(ck, 18, 34, 9, 23, 10, 14, "steel")
    box(ck, 30, 34, 10, 22, 11, 14, "glass")
    box(ck, 19, 30, 10, 22, 14, 15, "steel_dark")
    m.points["turret_mount"] = (24.0, 16.0, 15.0)
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
            "outrider": (outrider(), col),
            "bulwark_frame": (bulwark_frame(), col)}
