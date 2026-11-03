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
}
const MISSION_NAMES := {
	"clear": ["Laundromat Row", "Bus Depot", "Parking Structure", "Pawn Alley", "Cinema Lot"],
	"survive": ["Hold the Overpass", "Pharmacy Siege", "Gas Station Stand", "Rooftop Relay", "Tow Yard"],
	"hunt": ["Rustjaw", "Widowmaker", "Gutter King", "Red Mare", "Sawtooth"],
	"courier": ["Medicine Run", "Battery Drop", "Signal Parts", "Ammo Relay", "Water Filters"],
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
const SLIME_LINGER := 0.5              # ...and for this long after
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
const BULWARK_FRONT_MULT := 0.5     # damage from hits on its armored front...
const BULWARK_FRONT_ARC := 0.785    # ...within 45 degrees either side of the nose
const BULWARK_BACKOFF := 0.5        # seconds it backs off after ramming you
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

# --- Scrapper (enemy rig: trap layer; agreed with the owner) ------------------
# Fast and light. Circles you at 250-400 px, cutting across your path, and
# every 6 s drops a trap behind it: a mine, then an oil slick, alternating.
# One weak turret. Drops the Oil Slick utility.
const SCRAPPER_RANGE_MIN := 250.0
const SCRAPPER_RANGE_MAX := 400.0
const SCRAPPER_TRAP_EVERY := 6.0
const SCRAPPER_MINE_DAMAGE := 40.0
const SCRAPPER_MINE_RADIUS := 70.0
const SCRAPPER_MINE_ARM := 0.6
const SCRAPPER_MINE_LIFE := 25.0
const SCRAPPER_SCRAP := 25
const SCRAPPER_SCRAP_CACHE := 25
const SCRAPPER_SPAWN_TIME := 60.0   # Clear: seconds in, or...
const SCRAPPER_SPAWN_KILLS := 20    # ...after this many kills
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
const RESEARCH_GROWTH := 0.04          # each level past 1: +4% to the part's main stats
# A level costs base x the level you're buying (Common L2 = 30, Rare L12 = 720).
const RESEARCH_COST_BASE := {"Common": 15, "Uncommon": 30, "Rare": 60, "Epic": 110, "Legendary": 180}
const RESEARCH_DAILY_CAP := 3          # levels you can buy per day (Second Shift adds 1 each)
# Which stats grow, by category. Power draw and weight never change.
# Internal parts grow their modifier instead (see Parts.at_level).
const RESEARCH_STATS := {
	"Chassis": ["armor", "weight_capacity"],
	"Engine": ["power_output", "acceleration"],
	"Drive": ["turn_mult", "grip"],
	"Armor": ["armor"],
	"Weapon": ["bullet_damage"],
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
const CREW_PRICES := {"Common": 0, "Uncommon": 80, "Rare": 200, "Epic": 450, "Legendary": 900, "Mythic": 1600}

# --- Rigs ----------------------------------------------------------------------
# The player's rig is built from parts: see parts.gd (schematics and the
# starter loadout) and loadout.gd (how parts combine into these stats).

# Overload (DESIGN §4: overload reduces mobility). Power drawn over the
# engine's output, or weight over the chassis's capacity, scales acceleration
# and top speed by (limit / load) ^ exponent. Both together multiply.
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

const GUNNER := {
	"name": "Gunner Rig",
	"max_speed": 500.0,
	"reverse_speed": 260.0,
	"acceleration": 600.0,
	"brake": 1500.0,
	"coast": 280.0,
	"turn_rate": 3.0,
	"grip": 7.0,
	"armor": 340.0,
	"ram_damage": 40.0,
	"mount": 0,                # turret on top
	"gun_id": "gunner_rig",
	"fire_rate": 1.0 / 1.4,    # a burst every 1.4 s...
	"burst": 4,                # ...of 4 rounds...
	"burst_rate": 10.0,
	"bullet_damage": 7.0,      # ...of 7 damage: about 20 damage/s
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
	"armor": 200.0,
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
	"armor": 650.0,            # the front ram takes half (BULWARK_FRONT_MULT)
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
	"armor": 300.0,
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
	"armor": 520.0,            # front quarter takes half (BULWARK_FRONT_MULT)
	"ram_damage": 80.0,
	"mount": 1,                # one light gun fixed forward
	"fire_rate": 3.0,
	"bullet_damage": 5.0,
	"bullet_speed": 1100.0,
	"spread_deg": 5.0,
	"turret_turn_rate": 0.0,
	"lock_range": 0.0,
}
