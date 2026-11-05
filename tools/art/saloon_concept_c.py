"""Vendored concept-C layout for the Saloon bake (from concepts/saloon_v2)."""
from saloon_iso import *
from saloon_iso import Scene, figure, stool, table, lightfield

WOOD_LT = (138, 108, 78)
WOOD_DK = (102, 78, 56)
WOOD_TOP = (152, 118, 84)
FLOOR_A = (82, 62, 46)
FLOOR_B = (74, 56, 42)
WALL = (68, 56, 48)
TABLE_TOP = (134, 104, 74)
TABLE_LEG = (74, 56, 42)
STOOL_LEG = (66, 52, 42)

P = [
    dict(shirt=(68, 100, 122), skin=(200, 158, 116), hat=(124, 46, 38), hatstyle="wide"),
    dict(shirt=(162, 136, 62), skin=(164, 118, 82), hat=(178, 178, 168), hatstyle="wide", facing="front"),
    dict(shirt=(74, 106, 68), skin=(136, 96, 68), hat=(100, 84, 60), hatstyle="cap"),
    dict(shirt=(132, 62, 52), skin=(208, 170, 132), hat=(200, 112, 48), hatstyle="mohawk", facing="front"),
]

def floor_boards(sc, c1, c2):
    for x in range(0, W, 8):
        sc.box(x, 0, 0, min(W, x + 8), D, 2, c1 if (x // 8) % 2 else c2, noise=0.035, seed=x)
    for x in range(8, W, 8):
        sc.box(x, 0, 1, x + 1, D, 2, tuple(max(0, v - 14) for v in c2))

def build_C(with_hireables=True):
    sc = Scene()
    floor_boards(sc, FLOOR_A, FLOOR_B)
    sc.box(0, 0, 0, W, 5, H, WALL, noise=0.05, seed=4)
    for x in range(6, 140, 30):
        sc.box(x, 3, 0, x + 2, 5, H, (54, 40, 30))
    # Fireplace mid-right
    sc.box(98, 4, 2, 126, 11, 20, (90, 84, 78), noise=0.09, seed=8)
    sc.box(104, 10, 2, 120, 12, 10, (26, 18, 14))
    sc.box(107, 11, 2, 117, 13, 8, (255, 148, 42), em=True)
    sc.box(110, 12, 3, 114, 13, 6, (255, 226, 130), em=True)
    # Short left bar
    sc.box(6, 12, 2, 62, 18, 12, WOOD_DK, noise=0.04, seed=9)
    sc.box(5, 11, 12, 63, 19, 13, WOOD_TOP)
    for x in (12, 32, 50):
        stool(sc, x, 21, (104, 68, 48), STOOL_LEG)
    for x, y in ((24, 44), (66, 40)):
        table(sc, x, y, 18, 10, TABLE_TOP, TABLE_LEG)
        sc.box(x + 7, y + 3, 12, x + 11, y + 7, 16, (255, 196, 100), em=True)
    for x, y in ((16, 46), (44, 46), (58, 42), (86, 42)):
        stool(sc, x, y, (96, 66, 46), STOOL_LEG)
    sc.box(4, 54, 2, 14, 64, 8, (86, 66, 48), noise=0.07, seed=12)
    # Bartender
    figure(sc, 26, 4, 2, (92, 58, 50), (198, 152, 114), (72, 52, 44), 0,
           seated=False, facing="front", hatstyle="hood")
    seats = [(32, 21, 9), (44, 46, 9), (58, 42, 9), (86, 42, 9)]
    pals = [P[0], dict(P[1], hatstyle="wide", hat=(178, 178, 168), facing="front"),
            dict(P[3], hatstyle="cap"), P[2]]
    if with_hireables:
        for i, (st, p) in enumerate(zip(seats, pals), 1):
            kw = dict(p)
            facing = kw.pop("facing", "back")
            hatstyle = kw.pop("hatstyle", "cap")
            figure(sc, *st, own=i, shirt=kw["shirt"], skin=kw["skin"], hat=kw["hat"],
                   seated=True, facing=facing, hatstyle=hatstyle)
    light = lightfield(0.30, [
        (112, 14, 0, 42, 1.10),
        (33, 49, 0, 18, 0.75),
        (75, 45, 0, 18, 0.75),
        (37, 18, 0, 22, 0.30),
    ])
    return sc, light, seats
