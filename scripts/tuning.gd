extends RefCounted
## Shared constants: collision layers, palette, and balance numbers.
## Tune the game here rather than inside gameplay scripts.

# --- Collision layers (bit values) -------------------------------------------
const LAYER_WORLD := 1
const LAYER_VEHICLE := 2     # the player's rig
const LAYER_ZOMBIE := 4      # shamblers and hunters
const LAYER_ENEMY := 8       # enemy rigs

# --- Palette (rust, concrete, practical cyan/orange lights) -------------------
const COL_CONCRETE := Color(0.16, 0.16, 0.17)
const COL_ROAD := Color(0.105, 0.105, 0.115)
const COL_ROAD_LINE := Color(0.62, 0.55, 0.32, 0.45)
const COL_BUILDING := Color(0.21, 0.205, 0.2)
const COL_ROOF := Color(0.27, 0.26, 0.245)
const COL_RUST := Color(0.46, 0.25, 0.13)
const COL_STEEL := Color(0.31, 0.32, 0.335)
const COL_CYAN := Color(0.25, 0.82, 0.88)
const COL_ORANGE := Color(0.93, 0.48, 0.17)
const COL_ENEMY := Color(0.95, 0.24, 0.16)      # enemy rig lights and bullets
const COL_ZOMBIE := Color(0.45, 0.5, 0.37)
const COL_ZOMBIE_DARK := Color(0.27, 0.3, 0.23)
const COL_HUNTER := Color(0.74, 0.36, 0.28)
const COL_ELITE := Color(1.0, 0.78, 0.25)       # named Hunt targets
const COL_BLOOD := Color(0.3, 0.09, 0.07, 0.85)

# --- Rarity colours (VISUAL_PLAN V1.1) -----------------------------------------
# The one source of truth: Parts, Crew and UI.rarity_* all read this.
const RARITY_ORDER := ["Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic"]
const RARITY_COLORS := {
	"Common": Color(0.75, 0.75, 0.72),
	"Uncommon": Color(0.4, 0.85, 0.45),
	"Rare": Color(0.35, 0.6, 1.0),
	"Epic": Color(0.75, 0.45, 1.0),
	"Legendary": Color(1.0, 0.72, 0.25),
	"Mythic": Color(1.0, 0.36, 0.42),
}
# Perk tiers show as a rarity frame (V1.3): minor, major, signature.
const PERK_TIER_RARITY := {"minor": "Rare", "major": "Epic", "signature": "Legendary"}
# Fight crate beam height (px) per rarity tier 1..6 (V1.3; art only).
const RARITY_BEAM := [0.0, 40.0, 80.0, 140.0, 220.0, 320.0]

# --- Art colours (VISUAL_PLAN rule 3; added through P0) -----------------------
# Art-only colours for the style samples. No gameplay reads these. Generators in
# tools/art/ may read them by name (palette.tuning_color, which expects the
# `const NAME := Color(...)` form used here). Grouped by package / feature.

# P4 Maps: Outer Blocks district style (V5.1/V5.2/V5.5; PR #38).
const COL_OB_GRASS := Color(0.46, 0.47, 0.27)           # dry yellowed lawn #757845 (tiles.py), ~1.9:1 vs COL_ZOMBIE_DARK
const COL_OB_PAVE := Color(0.36, 0.35, 0.33)            # sidewalk slabs (tiles.py)
const COL_OB_SIDING := Color(0.45, 0.43, 0.38)          # house siding (buildings.py)
const COL_OB_ROOF := Color(0.3, 0.25, 0.23)             # shingles (buildings.py)
const COL_OB_GRADE := Color(1.0, 0.96, 0.88)            # warm colour grade, a modulate (arena.gd)
const COL_OB_MOTE := Color(0.86, 0.82, 0.62, 0.55)      # seed fluff motes (map_ambient.gd)

# P2 Effects: explosions and tracers (V4.3/V4.4; PR #33). Additive lights.
const COL_FX_HOT := Color(1, 0.851, 0.4)                # fireball core (255,217,102; fx.gd inline 1.0,0.85,0.4)
const COL_FX_WHITE_HOT := Color(1, 0.949, 0.8)          # flash, tracer core (255,242,204; = palette.py white_hot)
const COL_FX_EMBER := Color(0.6, 0.18, 0.078)           # cooling fireball edge (153, 46, 20)
const COL_FX_SCORCH := Color(0.071, 0.063, 0.059)       # scorch decal core (18, 16, 15)
const COL_FX_SCORCH_EDGE := Color(0.149, 0.133, 0.118)  # scorch decal outer fringe, lighter, half alpha (38, 34, 30; fx_sheet.py scorch())
const COL_FX_SMOKE := Color(0.349, 0.329, 0.302)        # smoke puffs, mid shade of the ramp (89, 84, 77; fx_sheet.py SMOKE = fx.gd dust 0.35,0.33,0.3)
const COL_FX_TRACER_RIVET := Color(1, 0.588, 0.275)     # rivet_gun tracer glow, hot rivet slug (255, 150, 70; PR #33 tracer_styles.gd Color8)
const COL_FX_TRACER_ENEMY_CORE := Color(1.0, 0.6, 0.55) # enemy tracer core: DEFAULT_ENEMY, convoy_nose, scrapper (255, 153, 140; PR #33 tracer_styles.gd)
const COL_FX_TRACER_HARPOON_CABLE := Color(0.8, 0.78, 0.6) # harpoon tracer glow, the cable line (204, 199, 153; PR #33 tracer_styles.gd)
const COL_FX_TRACER_HARPOON_STEEL := Color(0.655, 0.66, 0.668) # harpoon tracer core, steel hook head (167, 168, 170; PR #33 tracer_styles.gd)

# P6 Garage: Workshop bay room (V2.1/V2.2; PR #37). Dark, unlit surfaces.
const COL_GARAGE_FLOOR := Color(0.227, 0.224, 0.216)    # bay slab (58, 57, 55)
const COL_GARAGE_FLOOR_LINE := Color(0.471, 0.408, 0.235)# painted bay lines (120, 104, 60)
const COL_GARAGE_OIL := Color(0.094, 0.09, 0.094)       # oil stains on the slab (24, 23, 24)
const COL_GARAGE_PEGBOARD := Color(0.29, 0.235, 0.173)  # tool pegboard (74, 60, 44)
const COL_GARAGE_WALL := Color(0.18, 0.188, 0.204)      # corrugated back wall (46, 48, 52)
const COL_GARAGE_STREET_NIGHT := Color(0.118, 0.133, 0.173)# street past the roll-up door (30, 34, 44)
const COL_GARAGE_GAS_RED := Color(0.431, 0.157, 0.133)  # welding gas cylinders (110, 40, 34)
const COL_GARAGE_DUST := Color(0.9, 0.88, 0.8)          # drifting dust motes, drawn at alpha 0.02-0.18 (230, 224, 204; garage_ambient.gd)
const COL_GARAGE_SPARK := Color(1.0, 0.85, 0.5)         # weld sparks, alpha fades with life (255, 217, 128; garage_ambient.gd)

# P3 Zombies: Shambler and Tank sheets (V3.1/V3.2; PR #34). Baked by zombies.py.
# Shambler clothing variants 0-5: shirt / trousers.
const COL_ZOMBIE_SHIRT_0 := Color(0.439, 0.353, 0.275)  # brown jacket (112, 90, 70)
const COL_ZOMBIE_PANTS_0 := Color(0.247, 0.239, 0.275)  # grey jeans (63, 61, 70)
const COL_ZOMBIE_SHIRT_1 := Color(0.353, 0.4, 0.467)    # faded denim (90, 102, 119)
const COL_ZOMBIE_PANTS_1 := Color(0.286, 0.247, 0.208)  # brown trousers (73, 63, 53)
const COL_ZOMBIE_SHIRT_2 := Color(0.525, 0.494, 0.439)  # dirty off-white (134, 126, 112)
const COL_ZOMBIE_PANTS_2 := Color(0.22, 0.227, 0.247)   # dark trousers (56, 58, 63)
const COL_ZOMBIE_SHIRT_3 := Color(0.42, 0.275, 0.255)   # oxblood hoodie (107, 70, 65)
const COL_ZOMBIE_PANTS_3 := Color(0.314, 0.306, 0.275)  # khaki (80, 78, 70)
const COL_ZOMBIE_SHIRT_4 := Color(0.333, 0.38, 0.294)   # olive work shirt (85, 97, 75)
const COL_ZOMBIE_PANTS_4 := Color(0.239, 0.208, 0.188)  # dark brown (61, 53, 48)
const COL_ZOMBIE_SHIRT_5 := Color(0.459, 0.42, 0.333)   # tan coat (117, 107, 85)
const COL_ZOMBIE_PANTS_5 := Color(0.275, 0.306, 0.353)  # slate (70, 78, 90)
const COL_ZOMBIE_EYE := Color(0.745, 0.235, 0.157)      # dull red eyes, no glow (190, 60, 40)
const COL_ZOMBIE_FLASH := Color(0.941, 0.91, 0.839)     # hit flash (240, 232, 214)
const COL_TANK_SHIRT := Color(0.275, 0.235, 0.204)      # Tank clothes, top (70, 60, 52)
const COL_TANK_PANTS := Color(0.188, 0.173, 0.157)      # Tank clothes, bottom (48, 44, 40)
const COL_TANK_SKIN := Color(0.329, 0.212, 0.196)       # Tank dark skin (darker than COL_TANK) (84, 54, 50)

# --- Arena ---------------------------------------------------------------------
const WORLD_SIZE := Vector2(3200, 2400)
const SPAWN_MIN_DISTANCE := 850.0  # keep spawns off-screen

# --- Missions -------------------------------------------------------------------
# Defaults (a 3-skull Clear); missions.gd scales these per type and skulls.
const CLEAR_SHAMBLERS := 38    # shamblers in the block
const CLEAR_TARGET := CLEAR_SHAMBLERS + 2  # + one Hunter + one Outrider
const ZOMBIE_START := 12       # alive at the start
const ZOMBIE_CAP := 28         # design cap is 25-30 alive at once
const ZOMBIE_RAMP_SECONDS := 4.0  # +1 allowed alive every N seconds
const MAX_ENEMY_RIGS := 3      # DESIGN §8

# Difficulty is 1 to 6 skulls (1 easiest). The range is the old threat 1-3 in
# finer steps: 1 skull = old threat 1, 6 skulls = old threat 3.
const MAX_SKULLS := 6

# Per mission type: label, one-line brief, scrap reward on success, and what
# each skull level puts in the block. Lists are indexed by skulls - 1.
const MISSIONS := {
	"clear": {
		"label": "CLEAR", "brief": "Kill everything in the block.",
		"reward": [60, 72, 84, 98, 114, 130],
		"shamblers": [30, 34, 38, 42, 46, 50],
		"hunters": [1, 1, 1, 1, 2, 2],
		"outriders": [0, 0, 0, 1, 2, 2],
		"bulwarks": [0, 0, 1, 1, 1, 1],
		"gunners": [0, 0, 1, 1, 1, 1],
		"scrappers": [0, 1, 1, 1, 1, 1],
		"cap": [24, 26, 27, 28, 28, 28],
	},
	"survive": {
		"label": "SURVIVE", "brief": "Hold out until the timer runs down.",
		"reward": [70, 82, 94, 108, 124, 140],
		"seconds": [120, 130, 145, 155, 170, 180],
		"cap": [20, 22, 25, 26, 27, 28],
		"ramp": [3.0, 2.8, 2.6, 2.4, 2.2, 2.0],
		# [seconds into the run, what arrives]
		"events": [
			[[60, "hunter"]],
			[[55, "hunter"], [105, "hunter"]],
			[[45, "hunter"], [70, "scrapper"], [90, "bulwark"]],
			[[45, "hunter"], [65, "scrapper"], [90, "outrider"], [100, "gunner"], [110, "hunter"], [130, "bulwark"]],
			[[35, "hunter"], [55, "scrapper"], [70, "outrider"], [85, "gunner"], [100, "hunter"], [120, "bulwark"], [140, "hunter"]],
			[[30, "hunter"], [50, "scrapper"], [60, "outrider"], [80, "gunner"], [95, "hunter"], [120, "outrider"], [150, "bulwark"]],
		],
	},
	"hunt": {
		"label": "HUNT", "brief": "Wreck the marked rig and grab its schematic.",
		"reward": [80, 96, 112, 130, 150, 170],
		"elite_armor": [1.6, 1.75, 1.9, 2.1, 2.3, 2.5],
		"elite_damage": [1.0, 1.1, 1.15, 1.25, 1.3, 1.4],
		"escorts": [0, 0, 0, 0, 1, 1],
		"bulwark_escorts": [0, 0, 1, 1, 1, 1],
		"gunner_escorts": [0, 0, 0, 0, 1, 1],    # joins when there's room under the rig cap
		"hunters": [0, 0, 1, 1, 1, 1],
		"cap": [12, 14, 15, 17, 18, 20],
	},
	"courier": {
		"label": "COURIER", "brief": "Hit every checkpoint in order. Faster pays more.",
		"reward": [50, 62, 74, 86, 98, 110],
		"checkpoints": [5, 5, 6, 6, 7, 7],
		"cap": [8, 10, 11, 13, 14, 16],
		"hunters": [0, 0, 1, 1, 1, 1],
		"outriders": [0, 0, 0, 0, 1, 1],
		"gunners": [0, 0, 0, 1, 1, 1],          # parks by a checkpoint and covers it
		"scrappers": [0, 1, 1, 1, 1, 1],        # lays traps along your route
	},
	# Retrieve-and-extract (agreed with the owner): grab caches around the
	# block, leave through the extraction point whenever you like. Every cache
	# grabbed and every RETRIEVE_STEP_SECONDS raise the danger a step. One
	# "deep" cache sits far out under a Gunner Rig's guard: worth double, and a
	# sure schematic. Pay = reward x (30% + 70% x the cache share brought out).
	"retrieve": {
		"label": "RETRIEVE", "brief": "Grab the caches, then get out. Every cache stirs the block up.",
		"reward": [78, 94, 109, 127, 148, 169],   # ~1.3x a Clear with every cache
		"caches": [3, 3, 4, 4, 5, 5],              # including the deep cache
		"cap": [14, 16, 18, 20, 22, 24],           # crowd at step 0; +RETRIEVE_CAP_STEP a step
		"hunters": [0, 1, 1, 1, 2, 2],
		"rig_calls": [0, 1, 1, 2, 2, 3],           # rigs called in as the danger climbs
	},
	# Escort (agreed with the owner): a friendly salvage truck drives to sites
	# and works each one while you keep zombies and rigs off it. After the
	# first site the driver radios about an optional, nastier site.
	"escort": {
		"label": "ESCORT", "brief": "Keep the salvage truck alive while it works each site.",
		"reward": [70, 82, 94, 108, 124, 140],
		"sites": [2, 2, 3, 3, 3, 3],
		"cap": [16, 18, 20, 22, 24, 26],
		"ramp": [3.0, 2.8, 2.6, 2.4, 2.2, 2.0],
		"hunters": [0, 1, 1, 1, 2, 2],
		# [seconds into the run, what arrives]
		"events": [
			[],
			[[70, "scrapper"]],
			[[60, "scrapper"], [110, "outrider"]],
			[[50, "outrider"], [90, "scrapper"], [130, "bulwark"]],
			[[45, "outrider"], [80, "scrapper"], [115, "gunner"], [150, "bulwark"]],
			[[40, "outrider"], [70, "scrapper"], [100, "gunner"], [130, "outrider"], [160, "bulwark"]],
		],
	},
}
const MISSION_NAMES := {
	"clear": ["Laundromat Row", "Bus Depot", "Parking Structure", "Pawn Alley", "Cinema Lot"],
	"survive": ["Hold the Overpass", "Pharmacy Siege", "Gas Station Stand", "Rooftop Relay", "Tow Yard"],
	"hunt": ["Rustjaw", "Widowmaker", "Gutter King", "Red Mare", "Sawtooth"],
	"courier": ["Medicine Run", "Battery Drop", "Signal Parts", "Ammo Relay", "Water Filters"],
	"retrieve": ["Dead Drop", "Lost Shipment", "Abandoned Depot", "Scattered Cargo", "Black Boxes"],
	"escort": ["Salvage Crew", "Wrecker Run", "Scrap Haul", "Parts Pull", "Copper Strip"],
}
# Chance a job pays a schematic from its type's pool, by skulls 1-6. Courier
# only pays one on a gold time; a Hunt Elite always drops one.
const MISSION_SCHEMATIC_CHANCE := [0.0, 0.15, 0.30, 0.50, 0.75, 1.0]
# How often the board rolls each skull level inside a district's band
# (lowest first), weighted toward the easier middle like the old threat roll.
const SKULL_WEIGHTS := [3, 4, 3, 2]
const ELITE_SCRAP_CACHE := 60      # an Elite drops this if you own its whole pool
const ELITE_SCRAP := 40            # kill scrap for the Elite itself

# Courier par times: route length along the nav grid / speed, plus a pause
# per checkpoint. Silver and bronze stretch the gold time.
const COURIER_PAR_SPEED := 380.0
const COURIER_PAR_PER_CHECKPOINT := 0.5   # gold is ~1.2-1.4x a perfect autopilot line
const COURIER_SILVER := 1.3
const COURIER_BRONZE := 1.7
const COURIER_TIER_PAY := {"gold": 1.0, "silver": 0.75, "bronze": 0.5, "late": 0.25}
const COURIER_RADIUS := 90.0

# --- Districts (DESIGN §7) ----------------------------------------------------
# Unlocked by parts score: extracted schematics, rarity points x Research level.
const RARITY_POINTS := {"Common": 1, "Uncommon": 2, "Rare": 4, "Epic": 7, "Legendary": 12}
# Each district's board rolls jobs inside its skull band.
const DISTRICTS := [
	{"id": "outer_blocks", "name": "Outer Blocks", "need": 0, "skulls": [1, 4]},
	{"id": "midtown", "name": "Midtown Ruins", "need": 40, "skulls": [2, 5]},
	{"id": "industrial", "name": "Industrial Spine", "need": 120, "skulls": [3, 6]},
	{"id": "core", "name": "Core Collapse", "need": 300, "skulls": [4, 6]},
]
const SCRAP_PER_KILL := 2
const HORDE_SIZE := Vector2i(3, 6)  # zombies spawn in packs of this many
const STRAGGLER_ARROWS := 6    # point at the last N shamblers

# --- Shambler ------------------------------------------------------------------
const SHAMBLER_HP := 40.0
const SHAMBLER_SPEED := 85.0
const SHAMBLER_RADIUS := 13.0
const SHAMBLER_DPS := 3.0        # chip damage per zombie in contact
const SHAMBLER_SEPARATION := 34.0

# --- Zombie variants (DESIGN §8; agreed with the owner) ------------------------
# All share the Shambler pool and steering loop (zombie_director.gd); a
# zombie's `kind` picks its row here. "bullet" is the share of bullet damage
# it takes (rams and mines always do full); "knock" scales how far hits push it.
const ZOMBIE_KINDS := {
	"shambler": {"hp": SHAMBLER_HP, "speed": SHAMBLER_SPEED, "radius": SHAMBLER_RADIUS, "dps": SHAMBLER_DPS, "bullet": 1.0, "knock": 1.0, "scrap": SCRAP_PER_KILL},
	"brute": {"hp": 200.0, "speed": 70.0, "radius": 19.0, "dps": 8.0, "bullet": 0.5, "knock": 0.3, "scrap": 6},
	"tank": {"hp": 450.0, "speed": 75.0, "radius": 25.0, "dps": 8.0, "bullet": 0.5, "knock": 0.1, "scrap": 15},
	"boomer": {"hp": 60.0, "speed": 60.0, "radius": 16.0, "dps": 0.0, "bullet": 1.0, "knock": 0.8, "scrap": 3},
	"slimer": {"hp": 70.0, "speed": 95.0, "radius": 14.0, "dps": 3.0, "bullet": 1.0, "knock": 1.0, "scrap": 3},
}
# Share of each horde by skulls 1-6 (the rest are Shamblers). Tanks are
# capped per mission instead. Courier jobs only get Slimers and Boomers.
const ZOMBIE_MIX := {
	"slimer": [0.0, 0.06, 0.07, 0.08, 0.09, 0.10],
	"brute": [0.0, 0.0, 0.05, 0.07, 0.09, 0.10],
	"boomer": [0.0, 0.0, 0.04, 0.05, 0.07, 0.08],
}
const COURIER_KINDS := ["slimer", "boomer"]
const TANKS_PER_MISSION := [0, 0, 0, 1, 1, 2]
const TANK_PACK_CHANCE := 0.3          # each pack after TANK_EARLIEST may bring one
const TANK_EARLIEST := 30.0            # seconds into the run
const BRUTE_SHOVE := 140.0             # push on the rig per second of contact
const TANK_CHARGE_RANGE := 350.0
const TANK_CHARGE_COOLDOWN := 8.0
const TANK_WINDUP := 0.8               # roar before the charge...
const TANK_AIM_LOCK := 0.3             # ...it stops tracking for the last part of it
const TANK_CHARGE_SPEED := 520.0
const TANK_CHARGE_TIME := 0.9          # longest charge (~470 px)
const TANK_CHARGE_DAMAGE := 25.0
const TANK_SHOVE := 620.0              # velocity added to the rig it hits
const TANK_STUMBLE := 1.5              # after a miss: stands still, open to rams
const TANK_CACHE := 20                 # scrap crate a Tank drops
const BOOMER_POOL_RADIUS := 70.0       # 140 wide
const BOOMER_POOL_TIME := 8.0
const BILE_MARK_TIME := 6.0            # a rig caught in the burst is marked this long...
const BILE_MARK_RANGE := 500.0         # ...and zombies this close rush it...
const BILE_FRENZY := 1.6               # ...at this speed (also inside a pool)
const SLIME_DROP_EVERY := 0.3          # seconds between trail blobs
const SLIME_RADIUS := 22.0
const SLIME_TIME := 10.0
const SLIME_PUDDLE_RADIUS := 60.0      # left where a Slimer dies
const SLIME_GRIP := 0.35               # rig grip on slime...
const COL_BRUTE := Color(0.42, 0.4, 0.36)
const COL_TANK := Color(0.5, 0.33, 0.3)
const COL_BOOMER := Color(0.66, 0.7, 0.3)
const COL_SLIMER := Color(0.36, 0.62, 0.5)
const COL_SLIME := Color(0.45, 0.85, 0.6, 0.35)
const COL_BILE := Color(0.75, 0.8, 0.2, 0.28)

# --- Hunter --------------------------------------------------------------------
const HUNTER_HP := 60.0
const HUNTER_SPEED := 250.0          # outrun it at full throttle (rig does 560)
const HUNTER_RADIUS := 12.0
const HUNTER_POUNCE_RANGE := 180.0
const HUNTER_WINDUP := 0.35          # telegraph before the leap
const HUNTER_POUNCE_SPEED := 640.0
const HUNTER_POUNCE_TIME := 0.4
const HUNTER_DPS := 8.0              # while latched on the hull
const HUNTER_CRUSH_SPEED := 200.0    # hit a wall this hard on its side: dead
const HUNTER_SCRAPE_SPEED := 140.0   # grind it along a wall this fast...
const HUNTER_SCRAPE_DPS := 120.0     # ...and it takes this much per second
const HUNTER_JOLT_SPEED := 320.0     # any crash this hard throws it off
const HUNTER_SPAWN_TIME := 25.0      # seconds into the mission, or...
const HUNTER_SPAWN_KILLS := 10       # ...after this many kills
const HUNTER_SCRAP := 10

# --- Outrider (enemy rig: light flanker) -------------------------------------
const OUTRIDER_SPAWN_TIME := 45.0
const OUTRIDER_SPAWN_KILLS := 20
const OUTRIDER_SCRAP := 25

# --- Bulwark (enemy rig: heavy rammer; approved in the "Helriders: Bulwark
# Draft" doc) ---------------------------------------------------------------------
const BULWARK_FRONT_ARC := 0.785    # its heavy front plate: grey sparks within 45 deg of the nose
const BULWARK_BACKOFF := 0.5        # seconds it backs off after ramming you
# Bulwark charge (content proposal 01 §1.2, approved): lined up within 15°
# at 250-700 px, it winds up 0.5 s (headlight flare telegraph), charges up to
# 1.5 s at top speed; a miss overshoots into a 1.0 s recovery turn.
const BULWARK_CHARGE_CONE := deg_to_rad(15.0)
const BULWARK_CHARGE_RANGE := [250.0, 700.0]
const BULWARK_WINDUP := 0.5
const BULWARK_CHARGE_TIME := 1.5
const BULWARK_RECOVER := 1.0
# Outrider flank and break (proposal §1.1, approved): orbit 220-350 px into the
# player's side/rear arcs (outside the front ±45° facing), strafe when within
# ±10° of its gun line until it overheats, then break 500-700 px away (also
# when one of its facings is stripped) and re-flank.
const OUTRIDER_ORBIT := [220.0, 350.0]
const OUTRIDER_FRONT_ARC := deg_to_rad(45.0)
const OUTRIDER_STRAFE_CONE := deg_to_rad(10.0)
const OUTRIDER_BREAK := [500.0, 700.0]
const OUTRIDER_BREAK_MAX := 3.0      # gap-filler: give up a break after this many s
const BULWARK_SCRAP := 40
const BULWARK_SCRAP_CACHE := 40     # dropped instead of a schematic
const BULWARK_SPAWN_TIME := 60.0    # Clear: seconds in, or...
const BULWARK_SPAWN_KILLS := 25     # ...after this many kills

# --- Gunner Rig (enemy rig: standoff turret; agreed with the owner) -----------
# Keeps its distance and works you over with a slow turret firing bursts. It
# turns the turret on zombies that get close to it. Drops the Burst Turret.
const GUNNER_RANGE_MIN := 350.0     # backs off if you get closer...
const GUNNER_RANGE_MAX := 550.0     # ...closes in if you're further
const GUNNER_GUARD_RADIUS := 300.0  # Courier: stays this close to its checkpoint
const GUNNER_GUARD_LEASH := 700.0   # ...and only engages you this close to it
const GUNNER_SELF_DEFENSE := 120.0  # zombies this close get the turret
const GUNNER_FIRE_CONE := 0.12      # radians: turret this close to the target to fire
const GUNNER_SCRAP := 30
const GUNNER_SCRAP_CACHE := 30      # dropped instead of a schematic
const GUNNER_SPAWN_TIME := 75.0     # Clear: seconds in, or...
const GUNNER_SPAWN_KILLS := 30      # ...after this many kills

# --- Scrapper (enemy rig: hazard layer; §14, agreed with the owner) -----------
# Fast, light and unarmed. Cuts across your path 250-400 px out and every 3 s
# lays a hazard behind it, alternating oil and a spike strip; at most 6 of its
# hazards at once (the oldest go first). Drops hazard utilities and grip parts.
const SCRAPPER_RANGE_MIN := 250.0
const SCRAPPER_RANGE_MAX := 400.0
const SCRAPPER_TRAP_EVERY := 3.0
const SCRAPPER_MAX_HAZARDS := 6
const SCRAPPER_OIL_RADIUS := 45.0   # 90 px wide...
const SCRAPPER_OIL_TIME := 12.0     # ...for 12 s
# The Scrapper Gunner (agreed with the owner): the original Scrapper, a little
# harder. Tougher, with a weak turret, and every 4 s it lays a mine, oil or a
# spike strip in turn. From 4 skulls, half the jobs that bring a Scrapper
# bring one of these instead (seeded per job, shown on Comms).
const SCRAPPER_GUNNER_TRAP_EVERY := 4.0
const SCRAPPER_GUNNER_SKULLS := 4
const SCRAPPER_GUNNER_CHANCE := 0.5
const SCRAPPER_GUNNER_SCRAP := 35
const SCRAPPER_GUNNER_SCRAP_CACHE := 35
# Spike strips (Scrapper and the Spike Strip Dropper): a strip laid across the
# road behind the rig. Rigs crossing it (of the other side) drive 30% slower
# for 3 s; zombies on it take 10 damage a second and move at half speed.
const SPIKE_LENGTH := 120.0
const SPIKE_TIME := 15.0
const SPIKE_HALF_WIDTH := 14.0      # how close to the strip counts as on it
const SPIKE_RIG_SPEED := 0.7
const SPIKE_RIG_TIME := 3.0
const SPIKE_ZOMBIE_DPS := 10.0
const SPIKE_ZOMBIE_SPEED := 0.5
const SCRAPPER_MINE_DAMAGE := 40.0
const SCRAPPER_MINE_RADIUS := 70.0
const SCRAPPER_MINE_ARM := 0.6
const SCRAPPER_MINE_LIFE := 25.0
const SCRAPPER_SCRAP := 25
const SCRAPPER_SCRAP_CACHE := 25
const SCRAPPER_SPAWN_TIME := 60.0   # Clear: seconds in, or...
const SCRAPPER_SPAWN_KILLS := 20    # ...after this many kills
# --- New weapons (§14; agreed with the owner) ----------------------------------
# Harpoon: a spear on a 500 px cable from a fixed mount. It pierces zombies
# (up to 4) and stops in the first rig, tethering it; the cable reels in, and
# mass (hull size) decides who gets pulled. It pops like the Patcher's hook
# (a big hit to either rig or a hard crash); firing again lets go first.
const HARPOON_REEL_TO := 200.0      # reels in to this length...
const HARPOON_REEL_SPEED := 100.0   # ...this fast (px/s)
const HARPOON_POP_HIT := 0.15       # share of a rig's max taken in 1 s that pops it
const HARPOON_POP_CRASH := 380.0    # wall crash speed that pops it
# Mortar: lobs shells over buildings (walls don't stop them). The right
# stick's push sets the distance (300-1200 px, shown as a landing circle) and
# it fires while held; LOCK aims at where the target will be. Blast damage
# falls off to half at the edge.
const MORTAR_EDGE_DAMAGE := 0.5
const MORTAR_AIM_CONE := 0.12       # radians off the aim the turret will still fire
const SHELL_CAP := 12
# --- Patcher (support enemy rig, §14; agreed with the owner) -----------------
# Unarmed. Hooks a cable onto an ally and repairs it; the ally can drag it.
# The hook pops on a big hit to either rig (over 15% of its max in 1 s), a
# hard crash, or you ramming the cable at speed; re-hooking takes a 3 s
# wind-up. With no ally alive it revives a wreck to 10% over 4 s (any damage
# interrupts). From 3 skulls, only alongside another rig; the chance a job
# brings one rises with skulls (seeded per job, shown on Comms).
const PATCHER_CHANCE := [0.0, 0.0, 0.25, 0.4, 0.55, 0.7]
const PATCHER_CABLE := 400.0        # cable length
const PATCHER_HOOK_RANGE := 450.0   # how far it can throw the hook
const PATCHER_REPAIR := 12.0        # armor/s to the ally's most damaged facing
const PATCHER_REHOOK := 3.0         # wind-up before a hook flies
const PATCHER_POP_HIT := 0.15       # share of a rig's max taken in 1 s that pops it
const PATCHER_POP_CRASH := 380.0    # wall crash speed that pops it
const PATCHER_POP_RAM := 300.0      # your speed across the cable that cuts it
const PATCHER_REVIVE_TIME := 4.0
const PATCHER_REVIVE_TO := 0.10     # share of max HP and armor a revived rig gets
const PATCHER_REVIVE_REACH := 140.0 # parks this close to a wreck to revive it
const PATCHER_KEEP := 260.0         # hangs this far off its ally, away from you
const PATCHER_SCRAP := 35
const PATCHER_MAX_REVIVES := 3     # per job (proposal 01, approved 2026-11-03; was unlimited)
const PATCHER_SCRAP_CACHE := 35
# --- Convoy Lead (elite enemy rig; agreed with the owner) ---------------------
# An armored semi with a ram, towing a short trailer with a heavy turret on a
# hitch. It hunts and rams like a slow Bulwark (the ram takes half damage);
# two small fixed guns on the nose cover the front, because the trailer turret
# can't fire forward through the cab. The trailer has its own armor: shoot it
# off and the cab drives on lighter, or wreck the cab to finish both.
# Chance a job brings one (seeded per job, shown on Comms), by skulls 1-6. It
# takes an Outrider's place.
const CONVOY_CHANCE := {
	"clear": [0.0, 0.0, 0.0, 0.35, 0.35, 0.5],
	"survive": [0.0, 0.0, 0.0, 0.35, 0.35, 0.5],
	"hunt": [0.0, 0.0, 0.0, 0.0, 0.35, 0.5],
}
const CONVOY_TURRET_BLOCK := 0.785  # trailer turret can't fire within 45 deg of the cab
const CONVOY_HITCH_GAP := 8.0
const CONVOY_MAX_JACKKNIFE := 1.4   # radians (80 deg): the hitch won't fold further
const CONVOY_UNHITCHED_SPEED := 1.15  # the cab without its trailer: faster...
const CONVOY_UNHITCHED_ACCEL := 1.2   # ...quicker off the line...
const CONVOY_UNHITCHED_TURN := 1.15   # ...and a little nimbler
const CONVOY_SCRAP := 60
const CONVOY_SCRAP_CACHE := 60
const CONVOY_TRAILER_CRATE := 30      # dropped when the trailer is shot off

# --- Retrieve and Escort jobs ---------------------------------------------------
const RETRIEVE_STEP_SECONDS := 40.0   # the danger also climbs a step every this long
const RETRIEVE_CAP_STEP := 2          # +zombies allowed alive per step (up to ZOMBIE_CAP)
const RETRIEVE_SPEED_STEP := 0.05     # +zombie speed per step
const RETRIEVE_RIG_STEPS := [2, 4, 6] # steps that call in a rig (up to the job's rig_calls)
const RETRIEVE_DEEP_MULT := 2.0       # the deep cache counts double toward pay
const RETRIEVE_BASE_SHARE := 0.3      # paid for getting out at all (with at least one cache)
const CACHE_RADIUS := 60.0            # drive this close to grab a cache
const EXTRACT_RADIUS := 110.0
const EXTRACT_ARM_DISTANCE := 300.0   # leave the zone once before it counts
const ESCORT_SALVAGE_TIME := 20.0
const ESCORT_OPTIONAL_TIME := 30.0
const ESCORT_OPTIONAL_PAY := 1.6      # with the optional site
const ESCORT_OPTIONAL_WAVE := 10      # extra zombies the optional site wakes
const ESCORT_SITE_RADIUS := 90.0
# Escort truck at 3 skulls; mission.truck_sheet() scales armor and HP by ENEMY_DAMAGE_BY_SKULL
# (agreed with the owner, audit 2026-11-04).
const TRUCK := {
	"name": "Salvage Truck",
	"max_speed": 260.0,
	"reverse_speed": 150.0,
	"acceleration": 300.0,
	"brake": 1300.0,
	"coast": 300.0,
	"turn_rate": 2.0,
	"grip": 8.0,
	"armor": 400.0,            # total of the layers below
	"hp": 120.0, "front": 70.0, "side": 70.0, "rear": 70.0,
	"resist": [45.0, 45.0, 45.0, 45.0, 45.0, 45.0],   # shock fire acid toxic slime goop
	"ram_damage": 40.0,
	"mount": 1,
	"fire_rate": 0.0,          # no guns: that's your job
	"bullet_damage": 0.0,
	"bullet_speed": 1000.0,
	"spread_deg": 0.0,
	"turret_turn_rate": 0.0,
	"lock_range": 0.0,
}
const COL_TRUCK := Color(0.45, 0.85, 0.5)

# Oil (the Scrapper's slicks and your Oil Slick utility): rigs on it keep
# SLIME_GRIP, zombies in it move at OIL_ZOMBIE_SPEED.
const OIL_RADIUS := 70.0            # 140 wide
const OIL_TIME_SCRAPPER := 15.0
const OIL_ZOMBIE_SPEED := 0.5
const COL_OIL := Color(0.05, 0.05, 0.06, 0.6)

# --- Economy (scrap is the only currency) --------------------------------------
const START_SCRAP := 60
const SCHEMATIC_DROP_CHANCE := 0.5     # a wrecked Outrider drops a schematic, else a scrap cache
const SCRAP_CACHE := 20                # scrap in a cache crate
const WRECK_PENALTY := 0.25            # a wreck costs this x the lost build's value in scrap
const PRESET_COUNT := 3
const PRESET_NAME_MAX := 18     # characters in a preset's name
const BOARD_SIZE := 3                  # missions on the Comms board each day

# Garage upgrade tracks: 3 levels each, bought with scrap.
const UPGRADES := {
	"fabrication": {"name": "Fabrication Discount", "costs": [120, 300, 600], "per_level": 0.10},
	"loot": {"name": "Loot Quality", "costs": [150, 350, 700], "per_level": 0.15},
	"salvage": {"name": "Salvage Yield", "costs": [100, 250, 500], "per_level": 0.15},
	# Comms station (DESIGN §5: more choices, better mission quality).
	"choices": {"name": "Wider Net", "costs": [150, 400], "per_level": 1},
	"quality": {"name": "Better Leads", "costs": [120, 300, 600], "per_level": 0.15},
	# Research station (DESIGN §4: cost efficiency and levelling speed only).
	"research_discount": {"name": "Bench Discount", "costs": [150, 350, 700], "per_level": 0.10},
	"research_speed": {"name": "Second Shift", "costs": [200, 450], "per_level": 1},
	# Inn (DESIGN §5; agreed with the owner).
	"bunkhouse": {"name": "Bunkhouse", "costs": [150, 400], "per_level": 1},              # roster +1
	"drill_yard": {"name": "Drill Yard", "costs": [120, 300], "per_level": 0.25},         # idle crew get this x mission XP
	"infirmary": {"name": "Infirmary", "costs": [250], "per_level": 1},                   # rest days -1 (min 1)
	"second_team": {"name": "Second Team", "costs": [200, 500], "per_level": 1},          # expeditions out at once +1
	"scout_network": {"name": "Scout Network", "costs": [100, 250, 500], "per_level": 0.05},  # expedition odds +5%
	"last_rites": {"name": "Last Rites", "costs": [600, 1200], "per_level": 0.10},       # wreck survival per crew member
	# Saloon (DESIGN §5; agreed with the owner).
	"back_room": {"name": "Back Room", "costs": [150, 400], "per_level": 1},              # offers per day +1
	"word_around": {"name": "Word Gets Around", "costs": [200, 450, 900], "per_level": 1},  # odds shift (SALOON_ODDS_STEP)
	"seasoned_hands": {"name": "Seasoned Hands", "costs": [250, 600], "per_level": 1},   # hires start a level higher
	"house_credit": {"name": "House Credit", "costs": [120, 300, 600], "per_level": 0.10},  # hire prices -10%
	"old_faces": {"name": "Old Faces", "costs": [150, 350, 700], "per_level": 0.10},     # rehires a further -10%
}
const LAST_RITES_DISTRICT := 2         # Last Rites is for sale once Industrial Spine is open
const LAST_RITES_REST := 3             # survivors rest this many days
# Word Gets Around: each step moves these percentage points (from Uncommon).
const SALOON_ODDS_STEP := {"Uncommon": -7.0, "Rare": 5.0, "Epic": 2.0}

# --- Expeditions (DESIGN §5, §6; agreed with the owner) --------------------------
# Benched crew go out for 1-3 days on a job from the Inn's daily board. Their
# total level against the job's recommended level sets the odds; nobody is
# ever lost.
const EXPEDITION_UNLOCK_CLEARS := 3    # successful missions before the board opens
const EXPEDITION_BOARD_SIZE := 3
const EXPEDITION_MAX_TEAM := 6
const EXPEDITION_AT_ONCE := 1          # Second Team adds one per step
const EXPEDITION_TEAM_LEVEL := [3, 6, 10, 15, 21, 28]   # recommended team level, skulls 1-6
const EXPEDITION_ODDS := 0.70          # at exactly the recommended level...
const EXPEDITION_ODDS_OVER := 0.04     # ...plus this per level over...
const EXPEDITION_ODDS_UNDER := 0.08    # ...minus this per level under
const EXPEDITION_ODDS_MAX := 0.95
const EXPEDITION_ODDS_MIN := 0.05
const EXPEDITION_SCRAP := [20, 30, 42, 56, 72, 90]       # by skulls, for a 1-day trip
const EXPEDITION_DAY_MULT := [1.0, 1.8, 2.5]             # 1, 2, 3 days
# XP is skulls x days, split among the team.
const EXPEDITION_BONUS_SHARE := 0.25   # share of board entries with a bonus find
const EXPEDITION_BONUS_CHANCE := 0.03  # per skull per day
const EXPEDITION_FAIL_SCRAP := 0.25    # a failed trip brings back this share of the scrap...
const EXPEDITION_FAIL_XP := 0.5        # ...and of the XP, no bonus find...
const EXPEDITION_FAIL_INJURY := 0.25   # ...and each member may come back injured
const EXPEDITION_NAMES := ["Fuel Depot Sweep", "Overpass Salvage", "Rail Yard Run", "Mall Basement",
	"Quarry Road", "Radio Tower", "Hospital Wing", "Drowned Metro", "Truck Stop", "Scrap Barge",
	"Water Works", "Old Armory", "Cold Storage", "Bridge Toll", "Junk Canyon", "Signal Hill"]

# --- Research (DESIGN §4; agreed with the owner) --------------------------------
# Levels belong to the schematic: every copy you build has it, and a wreck
# never takes it away. Build cost and the wreck penalty ignore levels.
const RESEARCH_MAX_LEVEL := {"Common": 5, "Uncommon": 8, "Rare": 12, "Epic": 16, "Legendary": 20}
# Part mods (DESIGN §14): the Research level each tier unlocks at.
# Implement-03: ability numbers from DESIGN §14 (agreed), perk numbers from
# proposal 01 §3.1. Gap-fillers are marked.
# Implement-04 perk numbers. Approved (proposal 01 §3.1 / DESIGN §14 table):
const AFTERBURN_WIDTH := 50.0        # trail width (px)
const AFTERBURN_TIME := 3.0          # each patch burns 3 s
const AFTERBURN_BUILDUP := 20.0      # fire buildup/s on contact
const AFTERGLOW_TIME := 4.0
const ARC_FEEDBACK_SHOCK := 30.0
const ARC_FEEDBACK_CD := 0.5
const BULLDOG_REEL_TO := 120.0
const CHAIN_REACTION_OIL := 200.0
const CONTAGION_RADIUS := 120.0
const CONTAGION_BUILDUP := 40.0
const COUNTERWEIGHT := 1.25
const FLASHBANG_STUN := 1.5
const MAGNESIUM_BUILDUP := 15.0      # fire buildup/s inside the Flare
const SHRAPNEL_RADIUS := 40.0
const STRIP_MINE_PER := 40.0         # armor per scrap
const STRIP_MINE_CAP := 25.0
const TAIL_SWIPE_SHARE := 0.6
const RACING_LINE_ADD := 0.5
# Agreed with the owner (2026-11-04; first drafted by the Grok content bots):
const CLEAR_OUT_PUSH := 2.0          # Shockwave knockback x2 with Clear Out
const JUGGERNAUT_FLING := 0.8        # the rammed rig is thrown at 1.8x the impact speed
const SLINGSHOT_SPEED := 250.0       # "at speed" = over 250 px/s when Chain Drag ends
const SLINGSHOT_FLING := 1.0         # the flung rig gets 100% of your velocity
const SLINGSHOT_TIME := 1.5          # a wall crash within 1.5 s counts as the RAM
const TAIL_SWIPE_TIME := 0.6         # "while swinging" = 0.6 s after the Bootleg Turn
const NEAR_MISS_RANGE := 60.0        # an enemy round within 60 px that flies on
const RACING_LINE_CAP := 3.0         # at most +3 s per Hard Line
const SHRAPNEL_DAMAGE := 0.5         # splash = 50% of the round
const SHRAPNEL_STORM_DAMAGE := 15.0  # per pulled item
const SHRAPNEL_STORM_RADIUS := 80.0  # around where it lay
const DRONE_BAIT_ORBIT := 160.0      # Bait Drones hover further out
const DRONE_ZOMBIE_DPS := 8.0        # a zombie touching a drone (shambler dps)
const POWER_DIVERT_CAP := 80.0       # +1 shield per unused power point, cap 80
const DRONE_ORBIT := 70.0            # gap-filler: drones circle this far out
const DRONE_RANGE := 380.0           # gap-filler: same reach as a 1000 px/s gun
const SECOND_CHARGE_PAUSE := 0.5     # gap-filler: the second charge needs this long
const MOD_UNLOCK := {"minor": 3, "major": 7, "signature": 11, "major2": 14, "unique": 18}
const RESEARCH_GROWTH := 0.04          # each level past 1: +4% to the part's main stats
# A level costs base x the level you're buying (Common L2 = 30, Rare L12 = 720).
const RESEARCH_COST_BASE := {"Common": 15, "Uncommon": 30, "Rare": 60, "Epic": 110, "Legendary": 180}
const RESEARCH_DAILY_CAP := 3          # levels you can buy per day (Second Shift adds 1 each)
# Which stats grow, by category. Power draw and weight never change.
# Internal parts grow their modifier instead (see Parts.at_level).
const RESEARCH_STATS := {
	"Chassis": ["hp", "weight_capacity"],
	"Engine": ["power_output", "acceleration"],
	"Drive": ["turn_mult", "grip"],
	"Armor": ["armor"],
	"Weapon": ["bullet_damage", "zombie_damage"],
}

# --- Crew (DESIGN §6; role tables live in crew.gd) ----------------------------
const ROSTER_SIZE := 6                 # crew the Inn can hold
const CREW_BIG_HIT := 0.15             # damage within 1 s, as a share of max armor
const CREW_INJURY_CHANCE := 0.2        # per big hit (Roll Cage halves it)
const CREW_INJURED_MULT := 0.5         # injured Driver: turn rate; injured Gunner: turret aim
const CREW_REST_DAYS := 2              # days at the Inn after an injury...
const CREW_REST_DAYS_HARD := 3         # ...after a 5- or 6-skull job
const SALOON_OFFERS := 3               # paid hires on offer each day
# Daily offer odds (percent) and prices by rarity. Common hires are always on
# offer for free.
const SALOON_ODDS := {"Uncommon": 60.0, "Rare": 28.0, "Epic": 9.0, "Legendary": 2.5, "Mythic": 0.5}
const CREW_WHEEL_SLOWMO := 0.25       # game speed while the crew wheel is open
const CREW_WHEEL_COOLDOWN := 3.0       # seconds after it closes before it opens again
# --- Settings (pause menu; agreed with the owner) ------------------------------
# Quality presets: frame cap (0 = no cap), share of particles and blood
# splats drawn, and screen shake. The game picks one for the phone at first
# launch; the player can change it.
const QUALITY := {
	"Low": {"fps": 30, "fx": 0.4, "splats": 0.4, "shake": 0.6},
	"Medium": {"fps": 30, "fx": 0.7, "splats": 0.7, "shake": 1.0},
	"High": {"fps": 60, "fx": 0.85, "splats": 1.0, "shake": 1.0},
	"Ultra": {"fps": 0, "fx": 1.0, "splats": 1.0, "shake": 1.0},
}
const QUALITY_ORDER := ["Low", "Medium", "High", "Ultra"]

# Tutorial (optional, from MENU): the Training Run's loaner rig and the part
# it salvages for the garage tour.
const TUTORIAL_LOADOUT := {
	"chassis": "scrap_frame", "engine": "patched_v8", "drive": "street_wheels",
	"armor_front": "scrap_plating", "armor_sides": "scrap_plating", "armor_rear": "scrap_plating",
	"weapons": ["pintle_turret"], "utility": [], "internal": ["advanced_targeting"],   # V8 carries the computer
}
const TUTORIAL_PART := "riot_plating"

# Wreck sequence (agreed with the owner: about 4 s, a tap skips it).
const WRECK_TIME := 4.0          # real seconds before the results card
const WRECK_SLOWMO := 0.3        # game speed on the final hit...
const WRECK_SLOWMO_TIME := 0.8   # ...for this long (real seconds)
const WRECK_SWARM := 6           # zombies that close on the wreck
const WRECK_SWARM_RANGE := 280.0

# Keywords DRIFT and OVERLOAD (§14; the owner approved gap-filler definitions,
# 2026-11-04). DRIFT: sliding sideways faster than DRIFT_SIDE_SPEED while
# rolling; it "ends" when the slide dies, if it lasted DRIFT_MIN_TIME.
# OVERLOAD: a heat gun running at OVERLOAD_HEAT or more of its bar (before it
# locks hot). Enemy heat guns can be OVERLOADed too.
const COOK_OFF_BARREL_MULT := 1.5   # Demolisher: barrels set off during Cook Off +50% (proposal 01)
const OUTRIDER_RETREAT_HP := 0.25      # an Outrider this hurt runs to a Patcher, if one's alive...
const OUTRIDER_RETREAT_DONE := 0.45    # ...until it's patched back up to this
const OUTRIDER_DRIFT_KICK := 0.5       # its break-off turn slides: grip cut for this long...
const OUTRIDER_DRIFT_GRIP := 0.3       # ...to this share
const BULWARK_SCREEN_RANGE := 400.0    # it body-blocks for a Gunner Rig or Patcher this close
const BULWARK_SCREEN_GAP := 160.0      # standing this far out from the ally, toward you
const DRIFT_SIDE_SPEED := 160.0
const DRIFT_MIN_FWD := 150.0
const DRIFT_MIN_TIME := 0.4
const OVERLOAD_HEAT := 0.75
const HIT_AND_RUN_TIME := 2.0      # Raider frame mod: after a DRIFT...
const HIT_AND_RUN_DAMAGE := 0.15   # ...+15% damage
const DRIFT_FUEL_REFUND := 3.0     # Nitro Bottle mod: seconds off its cooldown per DRIFT
const CLEAN_EXIT_REFUND := 1.0     # Wheelman perk: seconds off Hard Line per DRIFT during it
const OVERLOAD_COIL_JUMPS := 3     # Arc Projector mod: the chain hits 2 extra targets
const MOBILE_WORKSHOP_AT := 0.30   # Hauler mod: when HP first falls under 30%...
const MOBILE_WORKSHOP_HEAL := 0.15 # ...restore 15% of max HP, once per mission

# Combat contract (DESIGN: time to wreck 15/13/11/9/7.5/6 s at skulls 1-6, for
# a build that fits the skull; agreed with the owner 2026-11-04). Measured by
# tools/balance/balance_report.gd. Enemy rigs' guns and rams, zombies and
# Hunters deal this share of their damage at skulls 1-6; hordes at skulls 1-2
# are this much smaller (alive at once).
const ENEMY_DAMAGE_BY_SKULL := [0.85, 0.95, 1.0, 1.1, 1.95, 1.95]
const HORDE_SCALE_BY_SKULL := [0.8, 0.9, 1.0, 1.0, 1.0, 1.0]

const CREW_PRICES := {"Common": 0, "Uncommon": 80, "Rare": 200, "Epic": 450, "Legendary": 900, "Mythic": 1600}
# Lost crew (§14; agreed with the owner): a crew member lost in a wreck turns
# up again after 3 days (Uncommon), a day more per rarity step, and joins the
# rehire pool at level 1 with the same specialty and rarity (perks reset).
# Commons don't come back (the Saloon always has free ones). The Saloon shows
# one rehire card a day, 20% below a normal hire (Old Faces: a further 10%
# per step); House Credit and Seasoned Hands apply too.
const LOST_RETURN_DAYS := {"Uncommon": 3, "Rare": 4, "Epic": 5, "Legendary": 6, "Mythic": 7}
const REHIRE_DISCOUNT := 0.20

# --- Rigs ----------------------------------------------------------------------
# The player's rig is built from parts: see parts.gd (schematics and the
# starter loadout) and loadout.gd (how parts combine into these stats).

# --- Defense layers (§14; agreed with the owner) --------------------------------
# Every rig: shield (recharges) -> armor per facing (never regenerates
# mid-run) -> HP (zero = wreck). Facings are four 90-degree arcs: front, left,
# right, rear. A hit drains its arc's armor; a stripped facing passes hits to
# HP. Explosions hit the nearest facing in full and each adjacent one at
# SPLASH_ADJACENT, and never reduce HP while any armor remains. Repairs go
# to the most damaged facing (never past its max; the rest is lost).
const SPLASH_ADJACENT := 0.25
const DEFAULT_SHIELD_DELAY := 3.0
const DEFAULT_SHIELD_REFILL := 5.0
const COL_SHIELD := Color(0.55, 0.75, 1.0)

# --- Statuses and damage types (§14; agreed with the owner) ----------------------
# Every status uses buildup: typed hits fill a 100-point bar that drains over
# time; a full bar triggers the status. Order everywhere: shock, fire, acid,
# toxic, slime, goop -> STUNNED, BURNING, CORRODED, TOXIC, SLICK, GOOPED.
const STATUS_NAMES := ["STUNNED", "BURNING", "CORRODED", "TOXIC", "SLICK", "GOOPED"]
const STATUS_TYPES := ["shock", "fire", "acid", "toxic", "slime", "goop"]
# Keyword colors (content proposal 01, approved 2026-11-03): no threat colors.
const STATUS_COLORS := [Color(0.949, 0.961, 1.000), Color(1.000, 0.353, 0.122), Color(0.600, 0.949, 0.251),
	Color(0.702, 0.400, 0.902), Color(0.180, 0.769, 0.651), Color(0.878, 0.643, 0.345)]
const STATUS_BAR := 100.0
# Buildup taken = hit buildup x (100 - resistance) / 50 (0 = x2, 50 = x1, 100 = immune).
const STATUS_DRAIN := 15.0            # per second, once nothing's added for...
const STATUS_DRAIN_DELAY := 1.5       # ...this long
const STATUS_AFTERGLOW := 3.0         # after a trigger, buildup runs at half speed this long
const STATUS_HIT_BUILDUP := 2.0       # a typed hit adds this x its damage as buildup
const STATUS_POOL_BUILDUP := 25.0     # per second inside slime, oil, fire ground (and Miasma)
const STATUS_SHIELD_RESIST := 15.0    # an active shield adds this to every resistance (cap 100)
const STATUS_RESIST_BASE := 30.0      # the player's rig before parts (agreed with the owner)...
const STATUS_RESIST_STEP := {"low": 5.0, "medium": 10.0, "high": 15.0}   # ...plus each plate's profile
const STATUS_RESIST_CAP := 95.0       # parts alone never make you immune
const ZOMBIE_RESIST := 50.0           # zombies are neutral to everything
# How long each lasts, on rigs and on zombies (seconds).
const STATUS_TIME_RIG := [1.2, 5.0, 6.0, 8.0, 3.0, 6.0]
const STATUS_TIME_ZOMBIE := [2.0, 5.0, 6.0, 8.0, 3.0, 6.0]
const BURNING_RIG_DPS := 6.0          # across the facings, by the splash rule
const BURNING_ZOMBIE_DPS := 15.0      # and it spreads to zombies it touches...
const BURNING_SPREAD := 50.0          # ...as this much fire buildup a second (2 s of contact)
const BURNING_TOUCH := 50.0           # "touching": centres this close
const CORRODED_TAKEN := 1.25          # +25% damage taken
const TOXIC_DPS := 4.0                # straight to HP (rigs: blocked by a raised shield)...
const TOXIC_FLOOR := 0.1              # ...and never below 10% of max HP
const SLICK_ZOMBIE_SPEED := 0.5
# Damage types: Kinetic (bullets, rams) all-round; the rest get a bonus.
const SHOCK_VS_SHIELD := 1.5
const ACID_VS_ARMOR := 1.5
const FIRE_VS_ZOMBIES := 1.5

# Barrels (§14): battlefield hazards, so they hurt everyone, the player
# included. Shot or rammed; blasts chain. Fixed spots per layout; the type is
# rolled per job.
const BARREL_HP := 20.0
const BARREL_TYPES := ["explosive", "fire", "acid", "slime", "boomer"]
const BARREL_RADIUS := 140.0          # blast reach (Explosive, Fire, Acid)
const BARREL_EXPLOSIVE_DAMAGE := 60.0
const BARREL_EXPLOSIVE_SHOVE := 4000.0
const BARREL_FIRE_DAMAGE := 25.0
const BARREL_FIRE_GROUND_TIME := 6.0
const BARREL_ACID_DAMAGE := 20.0
const BARREL_ACID_BUILDUP := 80.0
const BARREL_SLIME_POOL := 80.0       # radius (a 160 px pool)...
const BARREL_SLIME_TIME := 10.0       # ...for this long
const BARREL_BOOMER_RADIUS := 160.0   # fills the GOOPED bar of everything this close
const BARRELS_PER_JOB := 7
const COL_FIRE_GROUND := Color(1.0, 0.45, 0.1, 0.35)

# Overload (DESIGN §4: overload reduces mobility). Power drawn over the
# engine's output, or weight over the chassis's capacity, scales acceleration
# and top speed by (limit / load) ^ exponent. Both together multiply.
const OVERLOAD_EXPONENT := 1.5
const OVERLOAD_MIN_MOBILITY := 0.5   # never worse than this

# Enemy rigs still use one flat stat dictionary each. `hp`, `front`, `side`
# and `rear` are their defense layers (§14); `armor` is their total.
# mount: 0 = turret (aims independently), 1 = fixed (aims with the vehicle).
const OUTRIDER := {
	"name": "Outrider",
	"max_speed": 600.0,        # faster than the starter rig: it flanks you
	"reverse_speed": 260.0,
	"acceleration": 700.0,
	"brake": 1500.0,
	"coast": 280.0,
	"turn_rate": 3.6,
	"grip": 6.5,
	"armor": 260.0,            # total of the layers below (§14 table)
	"hp": 100.0, "front": 40.0, "side": 40.0, "rear": 40.0,
	"resist": [45.0, 50.0, 50.0, 50.0, 35.0, 50.0],   # shock fire acid toxic slime goop
	"shield": 25.0, "shield_skulls": 5, "shield_delay": 3.0, "shield_refill": 5.0,   # proposal 01: from 5 skulls
	"heat_time": 6.0, "lockout": 3.0, "cool": 0.25,  # proposal 01: the player's Twin Guns heat (~32 sustained)
	"ram_damage": 40.0,
	"mount": 1,                # twin guns fixed forward
	"fire_rate": 8.0,
	"bullet_damage": 6.0,
	"bullet_speed": 1200.0,
	"spread_deg": 4.0,
	"turret_turn_rate": 0.0,
	"lock_range": 0.0,
}

const GUNNER := {
	"name": "Gunner Rig",
	"max_speed": 500.0,
	"reverse_speed": 260.0,
	"acceleration": 600.0,
	"brake": 1500.0,
	"coast": 280.0,
	"turn_rate": 3.0,
	"grip": 7.0,
	"armor": 345.0,            # total of the layers below (§14 table; was 340)
	"hp": 120.0, "front": 60.0, "side": 55.0, "rear": 55.0,
	"resist": [35.0, 55.0, 50.0, 50.0, 55.0, 50.0],   # shock fire acid toxic slime goop
	"shield": 30.0, "shield_skulls": 4, "shield_delay": 3.0, "shield_refill": 5.0,   # a shield from 4 skulls
	"ram_damage": 40.0,
	"mount": 0,                # turret on top
	"gun_id": "gunner_rig",
	"fire_rate": 1.0 / 1.4,    # a burst every 1.4 s...
	"burst": 4,                # ...of 4 rounds...
	"burst_rate": 10.0,
	"bullet_damage": 7.0,      # ...of 7 damage: about 20 damage/s
	"mag": 6, "reload": 2.5,   # proposal 01: six bursts, then the turret droops to reload (~17 sustained)
	"bullet_speed": 1600.0,    # reach ~610 px, past the edge of its standoff ring
	"spread_deg": 3.0,
	"turret_turn_rate": 2.5,   # fast sideways driving outruns its aim
	"lock_range": 0.0,
}

const SCRAPPER := {
	"name": "Scrapper",
	"max_speed": 580.0,
	"reverse_speed": 260.0,
	"acceleration": 680.0,
	"brake": 1500.0,
	"coast": 280.0,
	"turn_rate": 3.5,
	"grip": 6.5,
	"armor": 230.0,            # total of the layers below (§14 table; was 200)
	"hp": 90.0, "front": 35.0, "side": 35.0, "rear": 35.0,
	"resist": [50.0, 30.0, 50.0, 50.0, 90.0, 50.0],   # shock fire acid toxic slime goop
	"ram_damage": 30.0,
	"mount": 1,
	"fire_rate": 0.0,          # unarmed (§14)
	"bullet_damage": 0.0,
	"bullet_speed": 1000.0,
	"spread_deg": 0.0,
	"turret_turn_rate": 0.0,
	"lock_range": 0.0,
}

const PATCHER := {
	"name": "Patcher",
	"max_speed": 540.0,
	"reverse_speed": 250.0,
	"acceleration": 640.0,
	"brake": 1500.0,
	"coast": 280.0,
	"turn_rate": 3.3,
	"grip": 6.5,
	"armor": 170.0,            # total of the layers below (§14 table)
	"hp": 80.0, "front": 30.0, "side": 30.0, "rear": 30.0,
	"resist": [35.0, 50.0, 50.0, 40.0, 50.0, 50.0],   # shock fire acid toxic slime goop
	"ram_damage": 20.0,
	"mount": 1,
	"fire_rate": 0.0,          # unarmed
	"bullet_damage": 0.0,
	"bullet_speed": 1000.0,
	"spread_deg": 0.0,
	"turret_turn_rate": 0.0,
	"lock_range": 0.0,
}

const SCRAPPER_GUNNER := {
	"name": "Scrapper Gunner",
	"max_speed": 580.0,
	"reverse_speed": 260.0,
	"acceleration": 680.0,
	"brake": 1500.0,
	"coast": 280.0,
	"turn_rate": 3.5,
	"grip": 6.5,
	"armor": 290.0,            # total of the layers below
	"hp": 110.0, "front": 45.0, "side": 45.0, "rear": 45.0,
	"resist": [50.0, 30.0, 50.0, 50.0, 90.0, 50.0],   # as the Scrapper
	"ram_damage": 30.0,
	"mount": 0,                # one weak turret
	"gun_id": "scrapper",
	"fire_rate": 2.0,
	"bullet_damage": 5.0,      # about 10 damage/s
	"bullet_speed": 1400.0,    # reach ~530 px
	"spread_deg": 4.0,
	"turret_turn_rate": 3.0,
	"lock_range": 0.0,
}

const CONVOY := {
	"name": "Convoy Lead",
	"max_speed": 420.0,
	"reverse_speed": 180.0,
	"acceleration": 380.0,
	"brake": 1300.0,
	"coast": 300.0,
	"turn_rate": 1.5,          # a wide circle: get beside or behind it
	"grip": 8.0,
	"armor": 650.0,            # total of the layers below (agreed with the owner)
	"hp": 200.0, "front": 250.0, "side": 70.0, "rear": 60.0,   # the plow is a very heavy front plate
	"resist": [60.0, 60.0, 35.0, 55.0, 70.0, 50.0],   # shock fire acid toxic slime goop
	"shield": 30.0, "shield_skulls": 4, "shield_delay": 3.0, "shield_refill": 5.0,   # cab only, from 4 skulls
	"ram_damage": 120.0,
	"mount": 1,                # two small guns fixed on the nose, alternating
	"gun_id": "convoy_nose",
	"fire_rate": 8.0,          # 4 a second each...
	"bullet_damage": 4.0,      # ...of 4: ~32 damage/s, straight ahead only
	"bullet_speed": 1300.0,
	"spread_deg": 4.0,
	"turret_turn_rate": 0.0,
	"lock_range": 0.0,
}

const CONVOY_TRAILER := {
	"name": "Convoy Trailer",
	"max_speed": 420.0,
	"reverse_speed": 180.0,
	"acceleration": 380.0,
	"brake": 1300.0,
	"coast": 300.0,
	"turn_rate": 1.5,
	"grip": 8.0,
	"armor": 350.0,            # total of the layers below (agreed with the owner; was 300)
	"hp": 120.0, "front": 50.0, "side": 65.0, "rear": 50.0,
	"resist": [60.0, 60.0, 35.0, 55.0, 70.0, 50.0],   # shock fire acid toxic slime goop
	"ram_damage": 60.0,
	"mount": 0,                # the heavy turret
	"gun_id": "convoy_turret",
	"fire_rate": 5.0,
	"bullet_damage": 6.0,      # ~30 damage/s
	"bullet_speed": 1500.0,
	"spread_deg": 3.0,
	"turret_turn_rate": 2.0,
	"lock_range": 0.0,
}

const BULWARK := {
	"name": "Bulwark",
	"max_speed": 430.0,        # slower than you: out-run it, out-turn it
	"reverse_speed": 200.0,
	"acceleration": 420.0,
	"brake": 1400.0,
	"coast": 300.0,
	"turn_rate": 1.9,          # 109 deg/s
	"grip": 8.0,
	"armor": 520.0,            # total of the layers below (§14 table)
	"hp": 180.0, "front": 180.0, "side": 55.0, "rear": 50.0,   # a very heavy front plate
	"resist": [60.0, 60.0, 35.0, 55.0, 70.0, 50.0],   # shock fire acid toxic slime goop
	"ram_damage": 80.0,
	"mount": 1,                # one light gun fixed forward
	"fire_rate": 3.0,
	"bullet_damage": 5.0,
	"bullet_speed": 1100.0,
	"spread_deg": 5.0,
	"turret_turn_rate": 0.0,
	"lock_range": 0.0,
}


# --- Content proposal 01 (approved by the owner 2026-11-03) ---------------------
# Keywords: one symbol, one animation and one fixed color each (no threat
# colors). The six statuses share STATUS_COLORS. Throttle: one popup per rig
# every KEYWORD_THROTTLE seconds, at most KEYWORD_MAX_ON_SCREEN at once.
const KEYWORDS := {
	"RAM": {"symbol": "chevron", "anim": "punch", "color": Color(0.910, 0.886, 0.816)},
	"DRIFT": {"symbol": "curve_arrow", "anim": "sweep", "color": Color(0.478, 0.549, 1.000)},
	"BURST": {"symbol": "three_dots", "anim": "pop_seq", "color": Color(1.000, 0.620, 0.780)},
	"MARKED": {"symbol": "crosshair_diamond", "anim": "shrink_pulse", "color": Color(1.000, 0.310, 0.847)},
	"STUNNED": {"symbol": "zigzag", "anim": "jitter", "color": Color(0.949, 0.961, 1.000)},
	"OVERLOAD": {"symbol": "gauge_needle", "anim": "flick", "color": Color(0.239, 0.482, 1.000)},
	"SLICK": {"symbol": "skid_drop", "anim": "slide", "color": Color(0.180, 0.769, 0.651)},
	"BURNING": {"symbol": "flame", "anim": "flicker", "color": Color(1.000, 0.353, 0.122)},
	"CORRODED": {"symbol": "cracked_plate", "anim": "crack", "color": Color(0.600, 0.949, 0.251)},
	"GOOPED": {"symbol": "blob_eyes", "anim": "wobble", "color": Color(0.878, 0.643, 0.345)},
	"TOXIC": {"symbol": "skull_cloud", "anim": "puff", "color": Color(0.702, 0.400, 0.902)},
}
const KEYWORD_THROTTLE := 0.5
const KEYWORD_MAX_ON_SCREEN := 6

# Torcher (fire skirmisher): hoses you from 150-220 px, peels off on lockout.
# A rear hit of TORCHER_RUPTURE_HIT in 1 s (or its wreck) ruptures the tank:
# a Fire-barrel blast that hurts everything, other enemy rigs included.
const TORCHER_CHANCE := {
	"clear": [0.0, 0.0, 0.30, 0.30, 0.45, 0.45],
	"survive": [0.0, 0.0, 0.30, 0.30, 0.45, 0.45],
}
const TORCHER_RANGE := 220.0
const TORCHER_KEEP := 150.0
const TORCHER_RUPTURE_HIT := 40.0
const TORCHER_SCRAP := 30
const TORCHER_SCRAP_CACHE := 30
const TORCHER := {
	"name": "Torcher",
	"max_speed": 540.0, "reverse_speed": 250.0, "acceleration": 640.0, "brake": 1500.0, "coast": 280.0,
	"turn_rate": 3.2, "grip": 6.5,
	"armor": 250.0,            # total of the layers below
	"hp": 110.0, "front": 60.0, "side": 45.0, "rear": 35.0,   # the fuel tank on the back
	"resist": [45.0, 85.0, 45.0, 50.0, 45.0, 50.0],
	"ram_damage": 35.0,
	"mount": 1, "gun_id": "torcher", "dtype": "fire",
	"fire_rate": 10.0, "bullet_damage": 3.0,   # 30 raw, ~18 sustained, + BURNING
	"bullet_speed": 580.0,     # 580 x 0.38 s = 220 px
	"spread_deg": 15.0, "pellets": 1, "pierce": 99,
	"heat_time": 4.0, "lockout": 2.5, "cool": 0.25,
	"turret_turn_rate": 0.0, "lock_range": 0.0,
}

# Sludger (acid / goop artillery): parks 500-800 px off behind its allies and
# lobs shells, alternating acid and goop. Retreats if you close inside 300.
const SLUDGER_CHANCE := {
	"survive": [0.0, 0.0, 0.0, 0.30, 0.40, 0.50],
	"escort": [0.0, 0.0, 0.0, 0.30, 0.40, 0.50],
	"retrieve": [0.0, 0.0, 0.0, 0.30, 0.40, 0.50],
}
const SLUDGER_RANGE_MIN := 500.0
const SLUDGER_RANGE_MAX := 800.0
const SLUDGER_FLEE := 300.0
const SLUDGER_ACID_DAMAGE := 18.0
const SLUDGER_ACID_RADIUS := 70.0
const SLUDGER_GOOP_DAMAGE := 8.0
const SLUDGER_GOOP_RADIUS := 90.0
const SLUDGER_GOOP_BUILDUP := 60.0
const SLUDGER_SCRAP := 35
const SLUDGER_SCRAP_CACHE := 35
const SLUDGER := {
	"name": "Sludger",
	"max_speed": 470.0, "reverse_speed": 230.0, "acceleration": 520.0, "brake": 1400.0, "coast": 290.0,
	"turn_rate": 2.6, "grip": 7.0,
	"armor": 305.0,
	"hp": 130.0, "front": 55.0, "side": 55.0, "rear": 45.0,
	"resist": [40.0, 45.0, 85.0, 60.0, 60.0, 85.0],
	"shield": 20.0, "shield_skulls": 4, "shield_delay": 3.0, "shield_refill": 5.0,
	"ram_damage": 40.0,
	"mount": 0, "gun_id": "sludger", "kind": "lobber", "dtype": "acid",
	"fire_rate": 1.25, "bullet_damage": 18.0,   # a shell every 0.8 s
	"blast": 70.0, "min_range": 300.0, "max_range": 900.0, "flight": 1.1,
	"mag": 4, "reload": 4.0,
	"bullet_speed": 1000.0, "spread_deg": 0.0, "turret_turn_rate": 2.5, "lock_range": 0.0,
}
const SLUDGER_SHIELD_6 := 35.0       # its shield at 6 skulls

# Acid puddles (Acid Lobber globs, Sludger acid shells): acid ground.
const ACID_PUDDLE_RADIUS := 30.0     # 60 px across
const ACID_PUDDLE_TIME := 4.0
const SLUDGER_PUDDLE_RADIUS := 40.0  # 80 px across
const SLUDGER_PUDDLE_TIME := 6.0
const COL_ACID_GROUND := Color(0.6, 0.95, 0.25, 0.3)

# Arc Projector: each hit chains to one more target this close, for this share.
const COOK_OFF_FIRE_RIDER := 0.5   # Demolisher Cook Off: +50% of hit damage as fire
const ARC_CHAIN_RANGE := 150.0
const ARC_CHAIN_SHARE := 0.5

# Nitro Bottle and Goop Launcher (utilities).
const NITRO_RAM := 0.25              # RAM damage bonus while the nitro burns

# Crew (proposal 01): Wrangler's chain and Jammer's static.
const WRANGLER_TETHER := 260.0

# Extract or Push (§14; proposal 01 approved 2026-11-03 with 33%).
const PUSH_CHANCE := 0.33            # share of eligible jobs (seeded per job, hidden until done)
const PUSH_SECONDS := [60.0, 65.0, 70.0, 75.0, 85.0, 90.0]   # by the job's skulls
const PUSH_PAY := 1.5                # job pay x this (kill scrap unchanged)
const PUSH_XP := 1.5                 # crew XP x this
const PUSH_MARKER_GAP := 600.0       # extract and push markers at least this far apart
const PUSH_RADIUS := 110.0
const PUSH_EXTRACT_WINDOW := 20.0    # after the timer: drive in within this, or it ends on its own
const PUSH_NO_TYPES := ["courier"]   # never offered on these
# Agreed with the owner (proposal 01 §3.3): Retrieve offers the push beacon
# once every non-deep cache is taken; Escort offers it only if the optional
# site was skipped. Flip to false to keep Push off both job types.
const PUSH_RETRIEVE_ESCORT := true   # agreed: Retrieve after the non-deep caches, Escort only if the optional site was skipped
# --- Audio (DESIGN "Audio / Soundtrack"; agreed with the owner 2026-11-04) ----------------
const MUSIC_FADE := 1.5             # seconds for a scene change (garage <-> fight)
const MUSIC_LAYER_FADE := 2.0       # seconds for a combat layer to cross in or out
const MUSIC_SILENT_DB := -60.0      # a layer that is "off" (kept playing so it stays in sync)
const MUSIC_INTENSITY_HOLD := 4.0   # seconds before intensity may drop again
const MUSIC_CHECK_EVERY := 0.5      # seconds between intensity checks in the fight
# Intensity 1 (Contact) / 2 (Crossfire): enemy rigs alive OR zombies alive at or above.
const MUSIC_MID_RIGS := 1
const MUSIC_MID_ZOMBIES := 10
const MUSIC_HIGH_RIGS := 2
const MUSIC_HIGH_ZOMBIES := 22
# Boosts: each adds steps on top of the count (result capped at 2, Crossfire).
const MUSIC_ELITE_BOOST := 1           # Hunt's Elite or a Convoy Lead alive
const MUSIC_LOW_ARMOR := 0.3           # player's rig at or under this share of armor
const MUSIC_LOW_ARMOR_BOOST := 1
const MUSIC_SURVIVE_FINAL_SECONDS := 30.0   # Survive's last stretch (the final wave)
const MUSIC_SURVIVE_FINAL_BOOST := 2
const MUSIC_PAUSE_DUCK_DB := -12.0     # music under the pause menu / radio call
const MUSIC_DUCK_FADE := 0.3

# --- Combat SFX (agreed with the owner 2026-11-04) -----------------------------------------------------
const SFX_WINDUP_PITCH := [0.9, 1.25]   # Bulwark roar pitch at wind-up start / end
