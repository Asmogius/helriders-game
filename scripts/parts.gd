extends RefCounted
## Part schematics: every part the player can own, by category (DESIGN §4).
## loadout.gd turns a set of these into a rig's final stats. Numbers here were
## approved by the owner in the "Helriders: New Parts Draft" doc.
##
## Power works like Armored Core's energy load: the engine's `power_output` is
## the budget, and every part's `power` is drawn all the time it's installed.
## Weight works the same way against the chassis's `weight_capacity`: every
## part except the chassis has `weight`. Going over either budget is an
## overload: the rig loses speed and acceleration (tuning.gd).
##
## Scrap: owning a part's schematic lets you build that part any time for its
## `cost` in scrap (profile.gd). Common parts are free to build, so you can
## always put a basic rig together. `cost` is still a Common part's value when
## a wreck's scrap penalty is worked out. Schematics are never lost; built
## parts are.
##
## Internal modifiers (multiply or add to the build): fire_rate_mult,
## damage_mult, hp_bonus (max HP), ram_bonus, lock_range_mult, turret_aim_mult,
## injury_mult (crew injury chance).
##
## Aiming: a turret needs a seated Gunner or a part with `manual_aim` to turn
## at all. LOCK (auto-aim) comes only from a part with `enables_lock` (the
## Advanced Targeting Computer) and a weapon whose lock_range > 0.
##
## Chassis `seats` lists the crew seats the frame has (crew.gd): "driver",
## "gunner", and "open" seats any other class can take (one of each class).
##
## Research levels (DESIGN §4): `at_level` returns a part with its level's
## numbers. Every level past 1 adds T.RESEARCH_GROWTH to the category's main
## stats (T.RESEARCH_STATS); internals grow their modifier, utilities cool
## down faster. Power and weight never change. A Legendary part may carry
##   "legendary_bonus": {"at": level, "add": {stat: amount}, "text": "..."}
## and gets `add` on top once it reaches level `at`.

const T := preload("res://scripts/tuning.gd")
const Mods := preload("res://scripts/mods.gd")

## Rarity colours live in tuning.gd (V1.1); this alias keeps old callers working.
const RARITY_COLORS: Dictionary = T.RARITY_COLORS

const CATALOG := {
	# --- Chassis: slots, weight capacity, base handling --------------------------
	"scrap_frame": {
		"name": "Scrap Frame", "category": "Chassis", "rarity": "Common", "cost": 50, "power": 15.0,
		"hardpoints": 1, "utility_slots": 1, "internal_slots": 2, "weight_capacity": 100.0,
		"hp": 150.0, "max_speed": 495.0, "reverse_speed": 200.0, "coast": 280.0, "turn_rate": 3.05,
		"body": [64.0, 36.0], "seats": ["driver", "gunner", "open"],
	},
	"courier_frame": {
		"name": "Courier Frame", "category": "Chassis", "rarity": "Uncommon", "cost": 90, "power": 12.0,
		"hardpoints": 1, "utility_slots": 2, "internal_slots": 1, "weight_capacity": 80.0,
		"hp": 105.0, "max_speed": 535.0, "reverse_speed": 220.0, "coast": 260.0, "turn_rate": 3.4,
		"body": [66.0, 32.0], "seats": ["driver", "open"],
	},
	"bulwark_frame": {
		"name": "Bulwark Frame", "category": "Chassis", "rarity": "Rare", "cost": 180, "power": 20.0,
		"hardpoints": 2, "utility_slots": 1, "internal_slots": 2, "weight_capacity": 160.0,
		"hp": 270.0, "max_speed": 440.0, "reverse_speed": 185.0, "coast": 300.0, "turn_rate": 2.7,
		"body": [76.0, 42.0], "seats": ["driver", "gunner", "open", "open"],
	},
	# Content proposal 01 (approved by the owner 2026-11-03).
	"raider_frame": {
		"name": "Raider Frame", "category": "Chassis", "rarity": "Uncommon", "cost": 120, "power": 14.0,
		"hardpoints": 2, "utility_slots": 1, "internal_slots": 1, "weight_capacity": 90.0,
		"hp": 125.0, "max_speed": 520.0, "reverse_speed": 210.0, "coast": 270.0, "turn_rate": 3.25,
		"body": [66.0, 34.0], "seats": ["driver", "gunner", "open"],
	},
	"hauler_frame": {
		"name": "Hauler Frame", "category": "Chassis", "rarity": "Epic", "cost": 320, "power": 22.0,
		"hardpoints": 2, "utility_slots": 2, "internal_slots": 3, "weight_capacity": 200.0,
		"hp": 320.0, "max_speed": 415.0, "reverse_speed": 175.0, "coast": 310.0, "turn_rate": 2.45,
		"body": [82.0, 44.0], "seats": ["driver", "gunner", "open", "open", "open"],
	},
	# --- Engines: acceleration and the power budget -------------------------------
	"junk_v6": {
		"name": "Junk V6", "category": "Engine", "rarity": "Common", "cost": 40, "power": 0.0, "weight": 20.0,
		"power_output": 115.0, "acceleration": 560.0,  # power 115 approved with the overload rule (#113); acceleration from the slower-rigs pass (approved)
	},
	"turbo_four": {
		"name": "Turbo Four", "category": "Engine", "rarity": "Uncommon", "cost": 70, "power": 0.0, "weight": 15.0,
		"power_output": 90.0, "acceleration": 670.0,
	},
	"patched_v8": {
		"name": "Patched V8", "category": "Engine", "rarity": "Uncommon", "cost": 80, "power": 0.0, "weight": 25.0,
		"power_output": 125.0, "acceleration": 550.0,
	},
	"diesel_block": {
		"name": "Diesel Block", "category": "Engine", "rarity": "Rare", "cost": 160, "power": 0.0, "weight": 35.0,
		"power_output": 150.0, "acceleration": 510.0,
	},
	# --- Drive: grip, braking, handling ------------------------------------------
	"street_wheels": {
		"name": "Street Wheels", "category": "Drive", "rarity": "Common", "cost": 20, "power": 10.0, "weight": 10.0,
		"grip": 5.5, "brake": 1500.0, "speed_mult": 1.0, "turn_mult": 1.0,
	},
	"outrider_sport_wheels": {
		"name": "Outrider Sport Wheels", "category": "Drive", "rarity": "Uncommon", "cost": 70, "power": 20.0, "weight": 10.0,
		"grip": 6.5, "brake": 1500.0, "speed_mult": 1.07, "turn_mult": 1.06,
	},
	"off_road_tires": {
		"name": "Off-Road Tires", "category": "Drive", "rarity": "Uncommon", "cost": 60, "power": 10.0, "weight": 15.0,
		"grip": 7.5, "brake": 1700.0, "speed_mult": 0.95, "turn_mult": 0.95,
	},
	"half_track": {
		"name": "Half-Track", "category": "Drive", "rarity": "Rare", "cost": 150, "power": 25.0, "weight": 30.0,
		"grip": 9.0, "brake": 2000.0, "speed_mult": 0.88, "turn_mult": 0.9,
	},
	# --- Armor -----------------------------------------------------------------------
	# Armor (§14 defense layers): `armor` is per facing. A rig has three armor
	# slots, Front, Sides (one part covers both flanks) and Rear; `weight` and
	# `power` are for a Front or Rear slot, `weight_sides` / `power_sides` for
	# the Sides slot. `front_only` plates (rams) fit the Front slot only. The
	# Front slot's plate gives the rig its ram damage. `resist` is the plate's
	# status profile (§14), shock fire acid toxic slime goop: each fitted plate
	# adds T.STATUS_RESIST_STEP for its rating to the rig's resistances.
	"scrap_plating": {
		"name": "Scrap Plating", "category": "Armor", "rarity": "Common", "cost": 30, "power": 0.0, "weight": 12.0,
		"weight_sides": 21.0, "armor": 80.0, "ram_damage": 70.0,
		"resist": ["low", "low", "low", "low", "low", "low"],
	},
	"outrider_light_plating": {
		"name": "Outrider Light Plating", "category": "Armor", "rarity": "Uncommon", "cost": 60, "power": 0.0, "weight": 7.0,
		"weight_sides": 12.0, "armor": 62.0, "ram_damage": 45.0,
		"resist": ["medium", "low", "low", "medium", "medium", "medium"],
	},
	"riot_plating": {
		"name": "Riot Plating", "category": "Armor", "rarity": "Uncommon", "cost": 80, "power": 0.0, "weight": 18.0,
		"weight_sides": 33.0, "armor": 115.0, "ram_damage": 80.0,
		"resist": ["high", "medium", "low", "low", "medium", "medium"],
	},
	"spiked_ram_plate": {
		"name": "Zed Sled", "category": "Armor", "rarity": "Uncommon", "cost": 70, "power": 0.0, "weight": 15.0,
		"armor": 71.0, "ram_damage": 130.0, "front_only": true,
		"resist": ["low", "medium", "medium", "low", "high", "high"],
	},
	"cowcatcher_ram": {
		"name": "Cowcatcher Ram", "category": "Armor", "rarity": "Rare", "cost": 180, "power": 0.0, "weight": 22.0,
		"armor": 124.0, "ram_damage": 170.0, "front_only": true,
		"resist": ["low", "medium", "medium", "low", "high", "high"],
	},
	"composite_plating": {
		"name": "Composite Plating", "category": "Armor", "rarity": "Rare", "cost": 170, "power": 4.0, "weight": 17.0,
		"power_sides": 7.0, "weight_sides": 30.0, "armor": 142.0, "ram_damage": 75.0,
		"resist": ["medium", "high", "high", "medium", "low", "low"],
	},
	"slag_plating": {
		"name": "Slag Plating", "category": "Armor", "rarity": "Rare", "cost": 170, "power": 0.0, "weight": 16.0,
		"weight_sides": 28.0, "armor": 125.0, "ram_damage": 80.0,
		"resist": ["low", "high", "high", "medium", "medium", "medium"],
	},
	# --- Weapons (hardpoints). lock_range 0 = this weapon can't be locked ---------
	"pintle_turret": {
		"name": "Pintle Turret", "category": "Weapon", "rarity": "Common", "cost": 40, "power": 50.0, "weight": 15.0,
		"mount": 0, "fire_rate": 7.0, "bullet_damage": 9.0, "bullet_speed": 1500.0,
		"spread_deg": 3.0, "turret_turn_rate": 9.0, "lock_range": 520.0, "pellets": 1,
		"mag": 28, "reload": 2.0,
	},
	"outrider_twin_guns": {
		"name": "Outrider Twin Guns", "category": "Weapon", "rarity": "Uncommon", "cost": 80, "power": 35.0, "weight": 10.0,
		"mount": 1, "fire_rate": 8.0, "bullet_damage": 6.0, "bullet_speed": 1200.0,
		"spread_deg": 4.0, "turret_turn_rate": 0.0, "lock_range": 0.0, "pellets": 1,
		"heat_time": 6.0, "lockout": 3.0, "cool": 0.25,   # overheats after 6 s nonstop
	},
	"scattergun_turret": {
		"name": "Scattergun Turret", "category": "Weapon", "rarity": "Uncommon", "cost": 90, "power": 45.0, "weight": 15.0,
		"mount": 0, "fire_rate": 2.5, "bullet_damage": 6.0, "bullet_speed": 1100.0,
		"spread_deg": 16.0, "turret_turn_rate": 8.0, "lock_range": 380.0, "pellets": 6,
		"mag": 6, "reload": 2.5,
	},
	"heavy_mg_turret": {
		"name": "Heavy MG Turret", "category": "Weapon", "rarity": "Rare", "cost": 190, "power": 65.0, "weight": 30.0,
		"mount": 0, "fire_rate": 9.0, "bullet_damage": 11.0, "bullet_speed": 1700.0,
		"spread_deg": 2.5, "turret_turn_rate": 6.5, "lock_range": 600.0, "pellets": 1,
		"heat_time": 8.0, "lockout": 4.0, "cool": 0.20,
	},
	"harpoon": {
		"name": "Harpoon", "category": "Weapon", "rarity": "Rare", "cost": 170, "power": 40.0, "weight": 20.0,
		"mount": 1, "kind": "harpoon", "fire_rate": 0.4, "bullet_damage": 45.0, "zombie_damage": 30.0, "pierce": 4,
		"bullet_speed": 1600.0, "range": 600.0, "cable": 500.0, "mag": 1, "reload": 2.5,
		"spread_deg": 0.0, "turret_turn_rate": 0.0, "lock_range": 600.0, "pellets": 1,
	},
	"mortar": {
		"name": "Mortar", "category": "Weapon", "rarity": "Uncommon", "cost": 120, "power": 45.0, "weight": 25.0,
		"mount": 0, "kind": "mortar", "fire_rate": 1.6667, "bullet_damage": 60.0, "blast": 90.0,
		"min_range": 300.0, "max_range": 1200.0, "flight": 1.2, "mag": 3, "reload": 4.0,
		"bullet_speed": 1000.0, "spread_deg": 0.0, "turret_turn_rate": 3.0, "lock_range": 1200.0, "pellets": 1,
	},
	"hood_guns": {
		"name": "Hood Guns", "category": "Weapon", "rarity": "Rare", "cost": 170, "power": 40.0, "weight": 20.0,
		"mount": 1, "fire_rate": 8.0, "bullet_damage": 7.0, "bullet_speed": 1300.0,
		"spread_deg": 3.0, "turret_turn_rate": 0.0, "lock_range": 0.0, "pellets": 1,
	},
	# Content proposal 01 (approved 2026-11-03). `dtype` is the damage type the
	# shots carry (builds that status); `chain` jumps each hit to one more target.
	"rivet_gun": {
		"name": "Rivet Gun", "category": "Weapon", "rarity": "Common", "cost": 45, "power": 40.0, "weight": 15.0,
		"mount": 1, "fire_rate": 4.0, "bullet_damage": 16.0, "bullet_speed": 1600.0, "pierce": 1,
		"spread_deg": 2.0, "turret_turn_rate": 0.0, "lock_range": 0.0, "pellets": 1,
		"mag": 12, "reload": 2.2,
	},
	"flame_sprayer": {
		"name": "Flame Sprayer", "category": "Weapon", "rarity": "Uncommon", "cost": 100, "power": 35.0, "weight": 12.0,
		"mount": 1, "fire_rate": 10.0, "bullet_damage": 4.0, "bullet_speed": 580.0, "pierce": 99, "dtype": "fire",
		"spread_deg": 15.0, "turret_turn_rate": 0.0, "lock_range": 0.0, "pellets": 1,   # 220 px, 30 deg cone
		"heat_time": 4.0, "lockout": 2.5, "cool": 0.25,
	},
	"acid_lobber": {
		"name": "Acid Lobber", "category": "Weapon", "rarity": "Uncommon", "cost": 110, "power": 40.0, "weight": 15.0,
		"mount": 0, "kind": "lobber", "dtype": "acid", "fire_rate": 2.0, "bullet_damage": 22.0, "blast": 70.0,
		"min_range": 250.0, "max_range": 750.0, "flight": 0.9, "mag": 5, "reload": 2.5,
		"bullet_speed": 1000.0, "spread_deg": 0.0, "turret_turn_rate": 6.0, "lock_range": 750.0, "pellets": 1,
	},
	"arc_projector": {
		"name": "Arc Projector", "category": "Weapon", "rarity": "Rare", "cost": 180, "power": 55.0, "weight": 20.0,
		"mount": 0, "fire_rate": 6.0, "bullet_damage": 6.0, "bullet_speed": 1000.0, "dtype": "shock", "chain": true,
		"spread_deg": 2.0, "turret_turn_rate": 7.0, "lock_range": 380.0, "pellets": 1,   # 380 px reach
		"heat_time": 5.0, "lockout": 3.0, "cool": 0.25,
	},
	# Burst weapons: `fire_rate` is bursts per second; each burst is `burst`
	# rounds, `burst_rate` rounds per second. Approved with the Gunner Rig.
	"burst_turret": {
		"name": "Burst Turret", "category": "Weapon", "rarity": "Uncommon", "cost": 110, "power": 40.0, "weight": 15.0,
		"mount": 0, "fire_rate": 1.0 / 0.9, "bullet_damage": 14.0, "bullet_speed": 1800.0,
		"spread_deg": 1.5, "turret_turn_rate": 8.0, "lock_range": 600.0, "pellets": 1,
		"burst": 4, "burst_rate": 12.0,
		"mag": 6, "reload": 2.2,   # six bursts
	},
	# --- Internal systems (passive, take internal capacity) -----------------------
	# Shield generators (§14): a recharging layer in front of the armor.
	# `shield_delay` seconds after the last hit it starts refilling, taking
	# `shield_refill` seconds from empty to full.
	"junk_emitter": {
		"name": "Junk Emitter", "category": "Internal", "rarity": "Common", "cost": 30, "power": 25.0, "weight": 5.0,
		"shield": 30.0, "shield_delay": 3.0, "shield_refill": 5.0,
	},
	"capacitor_bank": {
		"name": "Capacitor Bank", "category": "Internal", "rarity": "Uncommon", "cost": 110, "power": 35.0, "weight": 5.0,
		"shield": 75.0, "shield_delay": 4.0, "shield_refill": 6.0,
	},
	"flux_coil": {
		"name": "Flux Coil", "category": "Internal", "rarity": "Uncommon", "cost": 110, "power": 30.0, "weight": 5.0,
		"shield": 45.0, "shield_delay": 2.5, "shield_refill": 1.0,
	},
	"emp_computer": {
		"name": "EMP-Hardened Computer", "category": "Internal", "rarity": "Uncommon", "cost": 90, "power": 30.0, "weight": 5.0,
		"manual_aim": true, "resist_bonus": [15.0, 0.0, 0.0, 0.0, 0.0, 0.0],
	},
	"reflex_emitter": {
		"name": "Reflex Emitter", "category": "Internal", "rarity": "Rare", "cost": 160, "power": 40.0, "weight": 5.0,
		"shield": 45.0, "shield_delay": 1.0, "shield_refill": 3.0,
	},
	"targeting_computer": {
		"name": "Targeting Computer", "category": "Internal", "rarity": "Common", "cost": 30, "power": 25.0, "weight": 5.0,
		"manual_aim": true,
	},
	"coolant_loop": {
		"name": "Coolant Loop", "category": "Internal", "rarity": "Uncommon", "cost": 60, "power": 10.0, "weight": 5.0,
		"fire_rate_mult": 1.15,
	},
	"belt_feed": {
		"name": "Belt Feed", "category": "Internal", "rarity": "Uncommon", "cost": 60, "power": 5.0, "weight": 5.0,
		"damage_mult": 1.12,
	},
	"structural_bracing": {
		"name": "Structural Bracing", "category": "Internal", "rarity": "Uncommon", "cost": 50, "power": 0.0, "weight": 15.0,
		"hp_bonus": 25.0, "ram_bonus": 15.0,
	},
	"advanced_targeting": {
		"name": "Advanced Targeting Computer", "category": "Internal", "rarity": "Rare", "cost": 140, "power": 30.0, "weight": 5.0,
		"manual_aim": true, "enables_lock": true, "lock_range_mult": 1.25, "turret_aim_mult": 1.2,
	},
	"roll_cage": {
		"name": "Roll Cage", "category": "Internal", "rarity": "Uncommon", "cost": 60, "power": 0.0, "weight": 15.0,
		"injury_mult": 0.5,
	},
	"ceramic_heat_sink": {
		"name": "Ceramic Heat Sink", "category": "Internal", "rarity": "Uncommon", "cost": 90, "power": 15.0, "weight": 5.0,
		"heat_time_mult": 1.2, "resist_bonus": [0.0, 5.0, 0.0, 0.0, 0.0, 0.0],
	},
	# --- Utility (active: a HUD button each) --------------------------------------
	"emergency_patch": {
		"name": "Emergency Patch", "category": "Utility", "rarity": "Rare", "cost": 150, "power": 12.0, "weight": 10.0,
		"ability": "patch", "cooldown": 25.0, "heal": 35.0,
	},
	# Your hazards never hurt you (§14): your oil and spikes only catch enemies.
	"oil_slick": {
		"name": "Oil Slick Dropper", "category": "Utility", "rarity": "Uncommon", "cost": 90, "power": 15.0, "weight": 15.0,
		"ability": "oil", "cooldown": 14.0, "oil_radius": 70.0, "oil_time": 12.0,
	},
	"spike_strip": {
		"name": "Spike Strip Dropper", "category": "Utility", "rarity": "Uncommon", "cost": 90, "power": 15.0, "weight": 15.0,
		"ability": "spikes", "cooldown": 12.0, "spike_length": 120.0, "spike_time": 15.0,
	},
	"shock_pulse": {
		"name": "Shock Pulse", "category": "Utility", "rarity": "Uncommon", "cost": 90, "power": 20.0, "weight": 10.0,
		"ability": "pulse", "cooldown": 18.0, "pulse_radius": 180.0, "pulse_damage": 15.0, "pulse_buildup": 90.0,
	},
	"mine_dropper": {
		"name": "Mine Dropper", "category": "Utility", "rarity": "Rare", "cost": 160, "power": 15.0, "weight": 15.0,
		"ability": "mines", "cooldown": 15.0, "mines": 3, "mine_damage": 60.0, "mine_radius": 90.0,
		"mine_arm": 0.5, "mine_life": 20.0,
	},
	"goop_launcher": {
		"name": "Goop Launcher", "category": "Utility", "rarity": "Uncommon", "cost": 100, "power": 15.0, "weight": 10.0,
		"ability": "goop", "cooldown": 16.0, "goop_range": 500.0, "goop_radius": 90.0,
	},
	"nitro_bottle": {
		"name": "Nitro Bottle", "category": "Utility", "rarity": "Uncommon", "cost": 90, "power": 10.0, "weight": 8.0,
		"ability": "nitro", "cooldown": 14.0, "nitro_time": 1.5, "nitro_speed": 0.4, "nitro_accel": 1.0,
	},
}

# What the player's rig rolls out with: 100 / 100 power, 95 / 100 weight.
# Scrap Plating on all three armor slots and a Junk Emitter shield, so a new
# player sees every defense layer (§14). The Gunner seated on it aims the
# turret, so it carries no targeting computer and has no LOCK until you find
# the Advanced Targeting Computer.
const STARTER_LOADOUT := {
	"chassis": "scrap_frame",
	"engine": "junk_v6",
	"drive": "street_wheels",
	"armor_front": "scrap_plating",
	"armor_sides": "scrap_plating",
	"armor_rear": "scrap_plating",
	"weapons": ["pintle_turret"],
	"utility": [],
	"internal": ["junk_emitter"],
}

# --- Endless starter rigs (Quickplay QP8; SPEC: "3 Endless starter rigs: fast,
# balanced, tough", Cameron 2026-11-05) ---------------------------------------
# Keyed by T.ENDLESS_STARTER_RIG_IDS. Part choices approved by the owner (2026-11-05);
# every part already exists in CATALOG and every rig fits its power and weight.
#   fast:     Courier Frame, 77 / 90 power, 69 / 80 weight. Approved
#   balanced: the campaign STARTER_LOADOUT (100 / 100 power, 95 / 100 weight).
#   tough:    Bulwark Frame, 105 / 125 power, 129 / 160 weight. Approved
const ENDLESS_STARTER_RIGS := {
	"fast": {  # approved
		"chassis": "courier_frame",
		"engine": "turbo_four",
		"drive": "outrider_sport_wheels",
		"armor_front": "outrider_light_plating",
		"armor_sides": "outrider_light_plating",
		"armor_rear": "outrider_light_plating",
		"weapons": ["outrider_twin_guns"],
		"utility": ["nitro_bottle"],
		"internal": [],
	},
	"balanced": STARTER_LOADOUT,
	"tough": {  # approved
		"chassis": "bulwark_frame",
		"engine": "patched_v8",
		"drive": "off_road_tires",
		"armor_front": "riot_plating",
		"armor_sides": "riot_plating",
		"armor_rear": "riot_plating",
		"weapons": ["pintle_turret"],
		"utility": [],
		"internal": ["junk_emitter"],
	},
}

# Schematics a new game starts with: the starter's parts plus the Targeting
# Computer, for rigs that run a turret with no Gunner.
const STARTER_SCHEMATICS := ["scrap_frame", "junk_v6", "street_wheels", "scrap_plating", "pintle_turret", "targeting_computer", "junk_emitter"]

# What an Outrider can drop when you wreck it.
const OUTRIDER_DROPS := ["outrider_twin_guns", "outrider_light_plating", "outrider_sport_wheels", "coolant_loop", "shock_pulse", "nitro_bottle"]

# Schematic pools by source (approved in the parts draft).
const DROP_POOLS := {
	"outrider": OUTRIDER_DROPS,
	"elite": ["bulwark_frame", "diesel_block", "half_track", "composite_plating", "heavy_mg_turret", "advanced_targeting", "mine_dropper", "reflex_emitter", "arc_projector"],
	"clear": ["riot_plating", "spiked_ram_plate", "scattergun_turret", "roll_cage", "rivet_gun"],
	"survive": ["structural_bracing", "belt_feed", "patched_v8", "emergency_patch"],
	"courier": ["courier_frame", "turbo_four", "off_road_tires"],
	"bulwark": ["riot_plating", "spiked_ram_plate", "structural_bracing", "roll_cage", "harpoon", "slag_plating"],
	"gunner": ["burst_turret", "belt_feed", "coolant_loop", "mortar", "emp_computer"],
	"scrapper": ["oil_slick", "spike_strip", "mine_dropper", "off_road_tires"],   # the Scrapper Gunner shares it
	"retrieve": ["turbo_four", "off_road_tires", "oil_slick", "mine_dropper", "raider_frame"],
	"escort": ["structural_bracing", "riot_plating", "emergency_patch", "burst_turret"],
	"patcher": ["capacitor_bank", "flux_coil", "emergency_patch", "structural_bracing"],
	"convoy": ["heavy_mg_turret", "composite_plating", "diesel_block", "half_track", "cowcatcher_ram", "hood_guns", "hauler_frame"],
	"torcher": ["flame_sprayer", "ceramic_heat_sink", "patched_v8", "composite_plating"],
	"sludger": ["acid_lobber", "goop_launcher", "slag_plating", "emp_computer"],
}


## A copy of a part's schematic with its id attached, or {} if unknown.
static func get_part(id: String) -> Dictionary:
	if not CATALOG.has(id):
		return {}
	var part: Dictionary = CATALOG[id].duplicate()
	part["id"] = id
	return part


## Highest Research level for a part's rarity.
static func max_level(part: Dictionary) -> int:
	return int(T.RESEARCH_MAX_LEVEL.get(str(part.get("rarity", "")), 1))


## `part` (from get_part) with its stats at Research `level`. Level 1 (or
## below) returns it unchanged.
static func at_level(part: Dictionary, level: int) -> Dictionary:
	if part.is_empty():
		return part
	level = clampi(level, 1, max_level(part))
	var out := part.duplicate()
	out["level"] = level
	var scale := 1.0 + T.RESEARCH_GROWTH * (level - 1)
	var category := str(part.get("category", ""))
	for key: String in T.RESEARCH_STATS.get(category, []):
		if out.has(key):
			out[key] = float(out[key]) * scale
	if category == "Internal":
		for key: String in ["fire_rate_mult", "damage_mult", "lock_range_mult", "turret_aim_mult"]:
			if out.has(key):
				out[key] = 1.0 + (float(out[key]) - 1.0) * scale
		for key: String in ["hp_bonus", "ram_bonus", "shield"]:
			if out.has(key):
				out[key] = float(out[key]) * scale
		if out.has("injury_mult"):
			out["injury_mult"] = maxf(1.0 - (1.0 - float(out.injury_mult)) * scale, 0.0)
	if category == "Utility" and out.has("cooldown"):
		out["cooldown"] = float(out.cooldown) / scale
	var bonus: Dictionary = part.get("legendary_bonus", {})
	if not bonus.is_empty() and level >= int(bonus.get("at", 999)):
		var add: Dictionary = bonus.get("add", {})
		for key: String in add:
			out[key] = float(out.get(key, 0.0)) + float(add[key])
	return Mods.apply(out, level)


## Whether Research changes anything on this part. (The plain Targeting
## Computer only lets turrets aim; there's no number to grow.)
static func can_level(part: Dictionary) -> bool:
	if part.is_empty() or max_level(part) <= 1:
		return false
	var top := at_level(part, max_level(part))
	for key: String in part:
		if key != "level" and part[key] is float and not is_equal_approx(float(part[key]), float(top[key])):
			return true
	return part.has("legendary_bonus")


static func describe(part: Dictionary) -> String:
	return "%s (%s %s)" % [part.name, part.rarity, part.category]


static func color_of(part: Dictionary) -> Color:
	return RARITY_COLORS.get(part.get("rarity", ""), Color.WHITE)
