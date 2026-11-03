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

# --- Arena ---------------------------------------------------------------------
const WORLD_SIZE := Vector2(3200, 2400)
const SPAWN_MIN_DISTANCE := 850.0  # keep spawns off-screen

# --- Missions -------------------------------------------------------------------
# Defaults (a Clear at threat 2); missions.gd scales these per type and threat.
const CLEAR_SHAMBLERS := 40    # shamblers in the block
const CLEAR_TARGET := CLEAR_SHAMBLERS + 2  # + one Hunter + one Outrider
const ZOMBIE_START := 12       # alive at the start
const ZOMBIE_CAP := 28         # design cap is 25-30 alive at once
const ZOMBIE_RAMP_SECONDS := 4.0  # +1 allowed alive every N seconds
const MAX_ENEMY_RIGS := 3      # DESIGN §8

# Per mission type: label, one-line brief, scrap reward on success by threat 1/2/3,
# and what each threat level puts in the block. Lists are indexed by threat - 1.
const MISSIONS := {
	"clear": {
		"label": "CLEAR", "brief": "Kill everything in the block.",
		"reward": [60, 90, 130],
		"shamblers": [30, 40, 50], "hunters": [1, 1, 2], "outriders": [0, 1, 2],
		"cap": [24, 28, 28],
	},
	"survive": {
		"label": "SURVIVE", "brief": "Hold out until the timer runs down.",
		"reward": [70, 100, 140],
		"seconds": [120, 150, 180],
		"cap": [20, 26, 28], "ramp": [3.0, 2.5, 2.0],
		# [seconds into the run, what arrives]
		"events": [
			[[60, "hunter"]],
			[[45, "hunter"], [90, "outrider"], [110, "hunter"]],
			[[30, "hunter"], [60, "outrider"], [95, "hunter"], [120, "outrider"]],
		],
	},
	"hunt": {
		"label": "HUNT", "brief": "Wreck the marked rig and grab its schematic.",
		"reward": [80, 120, 170],
		"elite_armor": [1.6, 2.0, 2.5], "elite_damage": [1.0, 1.2, 1.4],
		"escorts": [0, 0, 1], "hunters": [0, 1, 1], "cap": [12, 16, 20],
	},
	"courier": {
		"label": "COURIER", "brief": "Hit every checkpoint in order. Faster pays more.",
		"reward": [50, 80, 110],
		"checkpoints": [5, 6, 7], "cap": [8, 12, 16],
		"hunters": [0, 1, 1], "outriders": [0, 0, 1],
	},
}
const MISSION_NAMES := {
	"clear": ["Laundromat Row", "Bus Depot", "Parking Structure", "Pawn Alley", "Cinema Lot"],
	"survive": ["Hold the Overpass", "Pharmacy Siege", "Gas Station Stand", "Rooftop Relay", "Tow Yard"],
	"hunt": ["Rustjaw", "Widowmaker", "Gutter King", "Red Mare", "Sawtooth"],
	"courier": ["Medicine Run", "Battery Drop", "Signal Parts", "Ammo Relay", "Water Filters"],
}
const MISSION_SCHEMATIC_CHANCE := [0.25, 0.5, 1.0]   # mission reward schematic, by threat
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
# Unlocked by parts score: extracted schematics, rarity points x level.
const RARITY_POINTS := {"Common": 1, "Uncommon": 2, "Rare": 4, "Epic": 7, "Legendary": 12}
const DISTRICTS := [
	{"id": "outer_blocks", "name": "Outer Blocks", "need": 0},
	{"id": "midtown", "name": "Midtown Ruins", "need": 40},
	{"id": "industrial", "name": "Industrial Spine", "need": 120},
	{"id": "core", "name": "Core Collapse", "need": 300},
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

# --- Economy (scrap is the only currency) --------------------------------------
const START_SCRAP := 60
const SCHEMATIC_DROP_CHANCE := 0.5     # a wrecked Outrider drops a schematic, else a scrap cache
const SCRAP_CACHE := 20                # scrap in a cache crate
const WRECK_PENALTY := 0.25            # a wreck costs this x the lost build's value in scrap
const PRESET_COUNT := 3
const BOARD_SIZE := 3                  # missions on the Comms board each day

# Garage upgrade tracks: 3 levels each, bought with scrap.
const UPGRADES := {
	"fabrication": {"name": "Fabrication Discount", "costs": [120, 300, 600], "per_level": 0.10},
	"loot": {"name": "Loot Quality", "costs": [150, 350, 700], "per_level": 0.15},
	"salvage": {"name": "Salvage Yield", "costs": [100, 250, 500], "per_level": 0.15},
	# Comms station (DESIGN §5: more choices, better mission quality).
	"choices": {"name": "Wider Net", "costs": [150, 400], "per_level": 1},
	"quality": {"name": "Better Leads", "costs": [120, 300, 600], "per_level": 0.15},
}

# --- Rigs ----------------------------------------------------------------------
# The player's rig is built from parts: see parts.gd (schematics and the
# starter loadout) and loadout.gd (how parts combine into these stats).

# Power overload (DESIGN §4: overload reduces mobility). Load over the engine's
# output scales acceleration and top speed by (output / load) ^ exponent.
const OVERLOAD_EXPONENT := 1.5
const OVERLOAD_MIN_MOBILITY := 0.5   # never worse than this

# Enemy rigs still use one flat stat dictionary each.
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
	"armor": 260.0,
	"ram_damage": 40.0,
	"mount": 1,                # twin guns fixed forward
	"fire_rate": 8.0,
	"bullet_damage": 6.0,
	"bullet_speed": 1200.0,
	"spread_deg": 4.0,
	"turret_turn_rate": 0.0,
	"lock_range": 0.0,
}
