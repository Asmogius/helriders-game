"""Code-defined voxel models. x = forward (nose at high x), y = right, z = up.
Hull and turret are separate sheets: the turret aims independently in game."""
import numpy as np
from palette import NAMES, colors_for

C = {n: i for i, n in enumerate(NAMES)}


def box(g, x0, x1, y0, y1, z0, z1, c):
    g[x0:x1, y0:y1, z0:z1] = C[c]


def scrap_frame_hull():
    """Player starter: Scrap Frame, 32x18 voxels = 64x36 px like vehicle.gd."""
    g = np.zeros((32, 18, 10), np.int16)
    for x0 in (3, 22):                      # chunky wheels
        box(g, x0, x0 + 7, 0, 3, 0, 5, "tyre"); box(g, x0, x0 + 7, 15, 18, 0, 5, "tyre")
    box(g, 1, 31, 3, 15, 1, 5, "steel_dark")    # chassis tub
    box(g, 2, 30, 2, 16, 3, 6, "steel")         # deck
    box(g, 26, 32, 2, 16, 2, 5, "rust")          # front ram plate
    box(g, 30, 32, 4, 14, 5, 6, "rust")
    box(g, 16, 25, 4, 14, 6, 9, "steel")        # cab
    box(g, 22, 25, 5, 13, 7, 9, "glass")        # windscreen
    box(g, 4, 9, 4, 14, 6, 7, "rust")           # rear scrap plates
    box(g, 2, 4, 3, 15, 5, 7, "steel_dark")     # rear bumper
    g[31, 3, 4] = g[31, 14, 4] = C["cyan"]      # headlights
    box(g, 2, 28, 2, 3, 5, 6, "cyan"); box(g, 2, 28, 15, 16, 5, 6, "cyan")  # edge lights
    g[1, 4, 4] = g[1, 13, 4] = C["orange"]      # tail lights
    return g


def pintle_turret():
    g = np.zeros((14, 8, 5), np.int16)
    box(g, 0, 6, 1, 7, 0, 3, "steel_dark")
    box(g, 1, 5, 2, 6, 3, 4, "steel")
    box(g, 6, 14, 3, 5, 1, 3, "steel")           # barrel along +x
    g[13, 3:5, 1:3] = C["orange"]
    return g


def outrider_hull():
    """Enemy Outrider: low, fast, wedge nose, forward guns, red lights."""
    g = np.zeros((34, 16, 8), np.int16)
    for x0 in (3, 24):
        box(g, x0, x0 + 6, 0, 3, 0, 4, "tyre"); box(g, x0, x0 + 6, 13, 16, 0, 4, "tyre")
    box(g, 1, 32, 3, 13, 1, 4, "steel_dark")
    for x in range(20, 34):                      # wedge nose
        inset = (x - 20) // 3
        box(g, x, x + 1, 3 + inset, 13 - inset, 3, 5, "rust")
    box(g, 2, 21, 2, 14, 3, 5, "rust")
    box(g, 9, 17, 4, 12, 5, 7, "steel")          # low cockpit
    box(g, 14, 17, 5, 11, 6, 7, "glass")
    box(g, 22, 33, 1, 3, 4, 6, "steel"); box(g, 22, 33, 13, 15, 4, 6, "steel")  # side guns
    g[33, 1:3, 4:6] = C["enemy_red"]; g[33, 13:15, 4:6] = C["enemy_red"]
    box(g, 2, 20, 7, 9, 5, 6, "enemy_red")       # racing stripe / light bar
    g[1, 4, 3] = g[1, 11, 3] = C["enemy_red"]
    return g


def ALL():
    col = colors_for()
    return {"scrap_frame_hull": (scrap_frame_hull(), col),
            "pintle_turret": (pintle_turret(), col),
            "outrider_hull": (outrider_hull(), col)}
