"""Fixed Helriders palette. Each entry is a base colour; the renderer derives
3 shade levels (0 dark side, 1 mid side, 2 lit top). Taken from scripts/tuning.gd
so sprites match the existing look: muted concrete/steel/rust, cyan (player)
and orange (accent) edge lights, red for enemies."""
OUTLINE = (12, 11, 13, 255)

# name -> RGB. Index order is the model colour index (0 = empty).
NAMES = ["_", "steel", "steel_dark", "rust", "tyre", "glass", "cyan", "orange", "enemy_red", "bone", "elite_gold"]
PALETTE = {
    "steel": (79, 82, 85), "steel_dark": (48, 49, 52), "rust": (117, 64, 33),
    "tyre": (24, 24, 26), "glass": (40, 62, 70), "cyan": (64, 209, 224),
    "orange": (237, 122, 43), "enemy_red": (242, 61, 41), "bone": (176, 166, 140),
    "elite_gold": (255, 199, 64),
}
EMISSIVE = {"cyan", "orange", "enemy_red", "elite_gold"}  # never darkened
SHADE_MUL = (0.62, 0.82, 1.0)


def colors_for(names=NAMES):
    return [(0, 0, 0, 0)] + [PALETTE[n] + (255,) for n in names[1:]]


def shade(c, level):
    if len(c) == 4 and c[3] == 0:
        return (0, 0, 0, 0)
    name = next((k for k, v in PALETTE.items() if v == tuple(c[:3])), None)
    m = 1.0 if name in EMISSIVE else SHADE_MUL[level]
    return tuple(int(min(255, ch * m)) for ch in c[:3]) + (255,)
