extends RefCounted
## Part schematics: every part the player can own, by category (DESIGN §4).
## loadout.gd turns a set of these into a rig's final stats.
##
## Power works like Armored Core's energy load: the engine's `power_output` is
## the budget, and every part's `power` is drawn all the time it's installed.
## Fitting a part is the cost, not using it. Going over budget is an overload:
## the rig loses mobility (tuning.gd), so it's a build decision.
##
## Scrap: owning a part's schematic lets you build that part any time for its
## `cost` in scrap (profile.gd). Common parts are free to build, so you can
## always put a basic rig together. `cost` is still a Common part's value when
## a wreck's scrap penalty is worked out. Schematics are never lost; built
## parts are.

const RARITY_COLORS := {
	"Common": Color(0.75, 0.75, 0.72),
	"Uncommon": Color(0.4, 0.85, 0.45),
	"Rare": Color(0.35, 0.6, 1.0),
	"Epic": Color(0.75, 0.45, 1.0),
	"Legendary": Color(1.0, 0.72, 0.25),
}

const CATALOG := {
	# --- Chassis: slots and base handling --------------------------------------
	"scrap_frame": {
		"name": "Scrap Frame", "category": "Chassis", "rarity": "Common", "cost": 50, "power": 15.0,
		"hardpoints": 1, "utility_slots": 1, "internal_slots": 2,
		"armor": 60.0, "max_speed": 560.0, "reverse_speed": 230.0, "coast": 280.0, "turn_rate": 3.4,
	},
	# --- Engine: acceleration and the power budget --------------------------------
	"junk_v6": {
		"name": "Junk V6", "category": "Engine", "rarity": "Common", "cost": 40, "power": 0.0,
		"power_output": 100.0, "acceleration": 640.0,
	},
	# --- Drive: grip, braking, handling ----------------------------------------
	"street_wheels": {
		"name": "Street Wheels", "category": "Drive", "rarity": "Common", "cost": 20, "power": 10.0,
		"grip": 5.5, "brake": 1500.0, "speed_mult": 1.0, "turn_mult": 1.0,
	},
	"outrider_sport_wheels": {
		"name": "Outrider Sport Wheels", "category": "Drive", "rarity": "Uncommon", "cost": 70, "power": 20.0,
		"grip": 6.5, "brake": 1500.0, "speed_mult": 1.07, "turn_mult": 1.06,
	},
	# --- Armor ---------------------------------------------------------------------
	"scrap_plating": {
		"name": "Scrap Plating", "category": "Armor", "rarity": "Common", "cost": 30, "power": 0.0,
		"armor": 90.0, "ram_damage": 70.0,
	},
	"outrider_light_plating": {
		"name": "Outrider Light Plating", "category": "Armor", "rarity": "Uncommon", "cost": 60, "power": 0.0,
		"armor": 70.0, "ram_damage": 45.0,
	},
	# --- Weapons (hardpoints). lock_range 0 = this weapon can't be locked ---------
	"pintle_turret": {
		"name": "Pintle Turret", "category": "Weapon", "rarity": "Common", "cost": 40, "power": 50.0,
		"mount": 0, "fire_rate": 7.0, "bullet_damage": 9.0, "bullet_speed": 1500.0,
		"spread_deg": 3.0, "turret_turn_rate": 9.0, "lock_range": 520.0,
	},
	"outrider_twin_guns": {
		"name": "Outrider Twin Guns", "category": "Weapon", "rarity": "Uncommon", "cost": 80, "power": 35.0,
		"mount": 1, "fire_rate": 8.0, "bullet_damage": 6.0, "bullet_speed": 1200.0,
		"spread_deg": 4.0, "turret_turn_rate": 0.0, "lock_range": 0.0,
	},
	# --- Internal systems (passive, take internal capacity) -----------------------
	"targeting_computer": {
		"name": "Targeting Computer", "category": "Internal", "rarity": "Common", "cost": 30, "power": 25.0,
		"enables_lock": true,
	},
}

# What the player's rig rolls out with: exactly 100 / 100 power. Lock works
# because the Targeting Computer is in an internal slot; pull it and the LOCK
# button goes away, but 25 power frees up for something else.
const STARTER_LOADOUT := {
	"chassis": "scrap_frame",
	"engine": "junk_v6",
	"drive": "street_wheels",
	"armor": "scrap_plating",
	"weapons": ["pintle_turret"],
	"utility": [],
	"internal": ["targeting_computer"],
}

# What an Outrider can drop when you wreck it.
const OUTRIDER_DROPS := ["outrider_twin_guns", "outrider_light_plating", "outrider_sport_wheels"]

# Schematic pools by source. Mission rewards and the Hunt Elite get their own
# parts once the new-parts draft is approved; until then the Elite draws from
# the Outrider pool and mission rewards are scrap only.
const DROP_POOLS := {
	"outrider": OUTRIDER_DROPS,
	"elite": OUTRIDER_DROPS,
	"clear": [],
	"survive": [],
	"courier": [],
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
