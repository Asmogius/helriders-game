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
## damage_mult, armor_bonus, ram_bonus, lock_range_mult, turret_aim_mult,
## injury_mult (crew injury chance).
##
## Aiming: a turret needs a seated Gunner or a part with `manual_aim` to turn
## at all. LOCK (auto-aim) comes only from a part with `enables_lock` (the
## Advanced Targeting Computer) and a weapon whose lock_range > 0.
##
## Chassis `seats` lists the crew seats the frame has (crew.gd): "driver",
## "gunner", and "open" seats any other class can take (one of each class).

const RARITY_COLORS := {
	"Common": Color(0.75, 0.75, 0.72),
	"Uncommon": Color(0.4, 0.85, 0.45),
	"Rare": Color(0.35, 0.6, 1.0),
	"Epic": Color(0.75, 0.45, 1.0),
	"Legendary": Color(1.0, 0.72, 0.25),
}

const CATALOG := {
	# --- Chassis: slots, weight capacity, base handling --------------------------
	"scrap_frame": {
		"name": "Scrap Frame", "category": "Chassis", "rarity": "Common", "cost": 50, "power": 15.0,
		"hardpoints": 1, "utility_slots": 1, "internal_slots": 2, "weight_capacity": 100.0,
		"armor": 60.0, "max_speed": 560.0, "reverse_speed": 230.0, "coast": 280.0, "turn_rate": 3.4,
		"body": [64.0, 36.0], "seats": ["driver", "gunner", "open"],
	},
	"courier_frame": {
		"name": "Courier Frame", "category": "Chassis", "rarity": "Uncommon", "cost": 90, "power": 12.0,
		"hardpoints": 1, "utility_slots": 2, "internal_slots": 1, "weight_capacity": 80.0,
		"armor": 45.0, "max_speed": 610.0, "reverse_speed": 250.0, "coast": 260.0, "turn_rate": 3.8,
		"body": [66.0, 32.0], "seats": ["driver", "open"],
	},
	"bulwark_frame": {
		"name": "Bulwark Frame", "category": "Chassis", "rarity": "Rare", "cost": 180, "power": 20.0,
		"hardpoints": 2, "utility_slots": 1, "internal_slots": 2, "weight_capacity": 160.0,
		"armor": 110.0, "max_speed": 500.0, "reverse_speed": 210.0, "coast": 300.0, "turn_rate": 3.0,
		"body": [76.0, 42.0], "seats": ["driver", "gunner", "open", "open"],
	},
	# --- Engines: acceleration and the power budget -------------------------------
	"junk_v6": {
		"name": "Junk V6", "category": "Engine", "rarity": "Common", "cost": 40, "power": 0.0, "weight": 20.0,
		"power_output": 100.0, "acceleration": 640.0,
	},
	"turbo_four": {
		"name": "Turbo Four", "category": "Engine", "rarity": "Uncommon", "cost": 70, "power": 0.0, "weight": 15.0,
		"power_output": 90.0, "acceleration": 760.0,
	},
	"patched_v8": {
		"name": "Patched V8", "category": "Engine", "rarity": "Uncommon", "cost": 80, "power": 0.0, "weight": 25.0,
		"power_output": 125.0, "acceleration": 620.0,
	},
	"diesel_block": {
		"name": "Diesel Block", "category": "Engine", "rarity": "Rare", "cost": 160, "power": 0.0, "weight": 35.0,
		"power_output": 150.0, "acceleration": 580.0,
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
	"scrap_plating": {
		"name": "Scrap Plating", "category": "Armor", "rarity": "Common", "cost": 30, "power": 0.0, "weight": 35.0,
		"armor": 90.0, "ram_damage": 70.0,
	},
	"outrider_light_plating": {
		"name": "Outrider Light Plating", "category": "Armor", "rarity": "Uncommon", "cost": 60, "power": 0.0, "weight": 20.0,
		"armor": 70.0, "ram_damage": 45.0,
	},
	"riot_plating": {
		"name": "Riot Plating", "category": "Armor", "rarity": "Uncommon", "cost": 80, "power": 0.0, "weight": 55.0,
		"armor": 130.0, "ram_damage": 80.0,
	},
	"spiked_ram_plate": {
		"name": "Spiked Ram Plate", "category": "Armor", "rarity": "Uncommon", "cost": 70, "power": 0.0, "weight": 45.0,
		"armor": 80.0, "ram_damage": 130.0,
	},
	"composite_plating": {
		"name": "Composite Plating", "category": "Armor", "rarity": "Rare", "cost": 170, "power": 10.0, "weight": 50.0,
		"armor": 160.0, "ram_damage": 75.0,
	},
	# --- Weapons (hardpoints). lock_range 0 = this weapon can't be locked ---------
	"pintle_turret": {
		"name": "Pintle Turret", "category": "Weapon", "rarity": "Common", "cost": 40, "power": 50.0, "weight": 15.0,
		"mount": 0, "fire_rate": 7.0, "bullet_damage": 9.0, "bullet_speed": 1500.0,
		"spread_deg": 3.0, "turret_turn_rate": 9.0, "lock_range": 520.0, "pellets": 1,
	},
	"outrider_twin_guns": {
		"name": "Outrider Twin Guns", "category": "Weapon", "rarity": "Uncommon", "cost": 80, "power": 35.0, "weight": 10.0,
		"mount": 1, "fire_rate": 8.0, "bullet_damage": 6.0, "bullet_speed": 1200.0,
		"spread_deg": 4.0, "turret_turn_rate": 0.0, "lock_range": 0.0, "pellets": 1,
	},
	"scattergun_turret": {
		"name": "Scattergun Turret", "category": "Weapon", "rarity": "Uncommon", "cost": 90, "power": 45.0, "weight": 15.0,
		"mount": 0, "fire_rate": 2.5, "bullet_damage": 6.0, "bullet_speed": 1100.0,
		"spread_deg": 16.0, "turret_turn_rate": 8.0, "lock_range": 380.0, "pellets": 6,
	},
	"heavy_mg_turret": {
		"name": "Heavy MG Turret", "category": "Weapon", "rarity": "Rare", "cost": 190, "power": 65.0, "weight": 30.0,
		"mount": 0, "fire_rate": 9.0, "bullet_damage": 11.0, "bullet_speed": 1700.0,
		"spread_deg": 2.5, "turret_turn_rate": 6.5, "lock_range": 600.0, "pellets": 1,
	},
	# --- Internal systems (passive, take internal capacity) -----------------------
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
		"armor_bonus": 25.0, "ram_bonus": 15.0,
	},
	"advanced_targeting": {
		"name": "Advanced Targeting Computer", "category": "Internal", "rarity": "Rare", "cost": 140, "power": 30.0, "weight": 5.0,
		"manual_aim": true, "enables_lock": true, "lock_range_mult": 1.25, "turret_aim_mult": 1.2,
	},
	"roll_cage": {
		"name": "Roll Cage", "category": "Internal", "rarity": "Uncommon", "cost": 60, "power": 0.0, "weight": 15.0,
		"injury_mult": 0.5,
	},
	# --- Utility (active: a HUD button each) --------------------------------------
	"emergency_patch": {
		"name": "Emergency Patch", "category": "Utility", "rarity": "Rare", "cost": 150, "power": 12.0, "weight": 10.0,
		"ability": "patch", "cooldown": 25.0, "heal": 35.0,
	},
	"mine_dropper": {
		"name": "Mine Dropper", "category": "Utility", "rarity": "Rare", "cost": 160, "power": 15.0, "weight": 15.0,
		"ability": "mines", "cooldown": 15.0, "mines": 3, "mine_damage": 60.0, "mine_radius": 90.0,
		"mine_arm": 0.5, "mine_life": 20.0,
	},
}

# What the player's rig rolls out with: 75 / 100 power, 80 / 100 weight. The
# Gunner seated on it aims the turret, so it carries no targeting computer and
# has no LOCK until you find the Advanced Targeting Computer.
const STARTER_LOADOUT := {
	"chassis": "scrap_frame",
	"engine": "junk_v6",
	"drive": "street_wheels",
	"armor": "scrap_plating",
	"weapons": ["pintle_turret"],
	"utility": [],
	"internal": [],
}

# Schematics a new game starts with: the starter's parts plus the Targeting
# Computer, for rigs that run a turret with no Gunner.
const STARTER_SCHEMATICS := ["scrap_frame", "junk_v6", "street_wheels", "scrap_plating", "pintle_turret", "targeting_computer"]

# What an Outrider can drop when you wreck it.
const OUTRIDER_DROPS := ["outrider_twin_guns", "outrider_light_plating", "outrider_sport_wheels", "coolant_loop"]

# Schematic pools by source (approved in the parts draft).
const DROP_POOLS := {
	"outrider": OUTRIDER_DROPS,
	"elite": ["bulwark_frame", "diesel_block", "half_track", "composite_plating", "heavy_mg_turret", "advanced_targeting", "mine_dropper"],
	"clear": ["riot_plating", "spiked_ram_plate", "scattergun_turret", "roll_cage"],
	"survive": ["structural_bracing", "belt_feed", "patched_v8", "emergency_patch"],
	"courier": ["courier_frame", "turbo_four", "off_road_tires"],
	"bulwark": ["riot_plating", "spiked_ram_plate", "structural_bracing", "roll_cage"],
}


## A copy of a part's schematic with its id attached, or {} if unknown.
static func get_part(id: String) -> Dictionary:
	if not CATALOG.has(id):
		return {}
	var part: Dictionary = CATALOG[id].duplicate()
	part["id"] = id
	return part


static func describe(part: Dictionary) -> String:
	return "%s (%s %s)" % [part.name, part.rarity, part.category]


static func color_of(part: Dictionary) -> Color:
	return RARITY_COLORS.get(part.get("rarity", ""), Color.WHITE)
