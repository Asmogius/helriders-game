extends RefCounted
## Turns a loadout (which part sits in which slot) into one flat dictionary of
## rig stats that vehicle.gd applies. This is the only place that knows how
## parts combine.
##
## A loadout looks like Parts.STARTER_LOADOUT:
##   chassis / engine / drive: one part id each
##   armor_front / armor_sides / armor_rear: one armor part each (§14); the
##     Sides part covers both flanks, `front_only` plates fit the Front only
##   weapons / utility / internal: arrays of part ids, limited by the chassis
##
## `levels` maps part id -> Research level (Profile.levels); parts not in it
## are level 1. Enemy rigs and tests can leave it out.
##
## The stats keep the first weapon's numbers at the top level (fire_rate,
## bullet_damage...) for simple readers, and list every weapon in "weapons".

const Parts := preload("res://scripts/parts.gd")
const T := preload("res://scripts/tuning.gd")

const ARMOR_SLOTS := ["armor_front", "armor_sides", "armor_rear"]


## Speed/acceleration multiplier for `used` against a budget of `limit`
## (power against output, weight against capacity). 1.0 within budget.
static func mobility_factor(used: float, limit: float) -> float:
	if limit <= 0.0 or used <= limit:
		return 1.0
	return clampf(pow(limit / used, T.OVERLOAD_EXPONENT), T.OVERLOAD_MIN_MOBILITY, 1.0)


## Both budgets together: power overload and weight overload stack.
static func mobility(stats: Dictionary) -> float:
	var power := mobility_factor(float(stats.get("power_draw", 0.0)), float(stats.get("power_output", 0.0)))
	var weight := mobility_factor(float(stats.get("weight", 0.0)), float(stats.get("weight_capacity", 0.0)))
	return maxf(power * weight, T.OVERLOAD_MIN_MOBILITY)


## Sustained damage per second of every weapon in a stats dictionary
## (magazines count their reload, heat guns their lockout).
static func total_dps(stats: Dictionary) -> float:
	var dps := 0.0
	for w: Dictionary in stats.get("weapons", []):
		var per_shot := float(w.bullet_damage) * int(w.get("pellets", 1)) * int(w.get("burst", 1))
		var mag := int(w.get("mag", 0))
		var heat := float(w.get("heat_time", 0.0))
		if mag > 0 and float(w.fire_rate) > 0.0:
			# A magazine: fire it dry, then reload (the reload starts on the last round).
			dps += per_shot * mag / ((mag - 1) / float(w.fire_rate) + float(w.get("reload", 0.0)))
		elif heat > 0.0:
			# Heat: fire until it overheats, then sit out the lockout.
			dps += float(w.fire_rate) * per_shot * heat / (heat + float(w.get("lockout", 0.0)))
		else:
			dps += float(w.fire_rate) * per_shot
	return dps


static func build(loadout: Dictionary, levels: Dictionary = {}) -> Dictionary:
	var chassis := _part(str(loadout.get("chassis", "")), levels)
	var engine := _part(str(loadout.get("engine", "")), levels)
	var drive := _part(str(loadout.get("drive", "")), levels)
	var plates := {}
	# An old-style loadout with one "armor" plate: it goes on all three slots
	# (a front-only plate on the front only), as in old saves.
	var legacy := str(loadout.get("armor", "")) if not loadout.has("armor_front") else ""
	for slot: String in ARMOR_SLOTS:
		var p := _part(str(loadout.get(slot, legacy)), levels)
		if legacy != "" and slot != "armor_front" and bool(p.get("front_only", false)):
			p = {}
		if not p.is_empty() and (p.category != "Armor" or (slot != "armor_front" and bool(p.get("front_only", false)))):
			push_warning("Loadout: %s can't go in %s" % [p.id, slot])
			p = {}
		plates[slot] = p
	var front: Dictionary = plates.armor_front

	# Slotted parts: keep what fits the chassis, report what didn't.
	var dropped: Array[String] = []
	var weapon_parts := _fit(loadout.get("weapons", []), "Weapon", int(chassis.get("hardpoints", 0)), dropped, levels)
	var utility := _fit(loadout.get("utility", []), "Utility", int(chassis.get("utility_slots", 0)), dropped, levels)
	var internal := _fit(loadout.get("internal", []), "Internal", int(chassis.get("internal_slots", 0)), dropped, levels)
	if not dropped.is_empty():
		push_warning("Loadout: no slot for %s" % ", ".join(dropped))

	# Internal modifiers.
	var fire_mult := 1.0
	var damage_mult := 1.0
	var lock_mult := 1.0
	var aim_mult := 1.0
	var hp_bonus := 0.0
	var shield := {}
	var ram_bonus := 0.0
	var injury_mult := 1.0
	var heat_mult := 1.0
	var cool_mult := 1.0
	var lockout_mult := 1.0
	var has_targeting := false
	var manual_aim := false
	for part: Dictionary in internal:
		fire_mult *= float(part.get("fire_rate_mult", 1.0))
		damage_mult *= float(part.get("damage_mult", 1.0))
		lock_mult *= float(part.get("lock_range_mult", 1.0))
		aim_mult *= float(part.get("turret_aim_mult", 1.0))
		hp_bonus += float(part.get("hp_bonus", 0.0))
		if float(part.get("shield", 0.0)) > float(shield.get("shield", 0.0)):
			shield = part   # one shield: the strongest generator fitted counts
		ram_bonus += float(part.get("ram_bonus", 0.0))
		injury_mult *= float(part.get("injury_mult", 1.0))
		heat_mult *= float(part.get("heat_time_mult", 1.0))
		cool_mult *= float(part.get("cool_mult", 1.0))         # Fins mod
		lockout_mult *= float(part.get("lockout_mult", 1.0))   # Vent Purge mod
		has_targeting = has_targeting or bool(part.get("enables_lock", false))
		manual_aim = manual_aim or bool(part.get("manual_aim", false))

	# Every weapon, modifiers applied. Lock needs a targeting system AND a
	# weapon that supports it; the longest lock range wins.
	var weapons: Array[Dictionary] = []
	var lock_range := 0.0
	for part: Dictionary in weapon_parts:
		var w := {
			"id": part.id,
			"mount": int(part.get("mount", 0)),
			"fire_rate": float(part.get("fire_rate", 0.0)) * fire_mult,
			"bullet_damage": float(part.get("bullet_damage", 0.0)) * damage_mult,
			"bullet_speed": float(part.get("bullet_speed", 1000.0)),
			"spread_deg": float(part.get("spread_deg", 0.0)),
			"turret_turn_rate": float(part.get("turret_turn_rate", 0.0)) * aim_mult,
			"lock_range": float(part.get("lock_range", 0.0)) * lock_mult,
			"pellets": int(part.get("pellets", 1)),
			"burst": int(part.get("burst", 1)),
			"burst_rate": float(part.get("burst_rate", 0.0)),
			"kind": str(part.get("kind", "")),
			"mag": int(part.get("mag", 0)),
			"reload": float(part.get("reload", 0.0)),
		}
		# Special weapons carry their own numbers (Harpoon, Mortar).
		for key: String in ["range", "cable", "pierce", "blast", "min_range", "max_range", "flight", "heat_time", "lockout", "cool", "dtype", "chain", "puddle_add", "reel_speed", "reel_to", "mods"]:
			if part.has(key):
				w[key] = part[key]
		if w.has("heat_time"):
			w["heat_time"] = float(w.heat_time) * heat_mult   # Ceramic Heat Sink
			w["lockout"] = float(w.get("lockout", 1.0)) * lockout_mult
			w["cool"] = float(w.get("cool", 0.25)) * cool_mult
		if int(w.mount) == 1:
			w["fire_rate"] = float(w.fire_rate) * float(chassis.get("fixed_fire_mult", 1.0))   # Gun Rack mod
		if part.has("zombie_damage"):
			w["zombie_damage"] = float(part.zombie_damage) * damage_mult
		weapons.append(w)
		if has_targeting:
			lock_range = maxf(lock_range, float(w.lock_range))
	var first: Dictionary = weapons[0] if not weapons.is_empty() else {}
	var has_turret := false
	for w in weapons:
		has_turret = has_turret or int(w.mount) == 0

	var abilities: Array[Dictionary] = []
	for part: Dictionary in utility:
		abilities.append(part)

	var draw := 0.0
	var weight := 0.0
	for part: Dictionary in [chassis, engine, drive]:
		draw += float(part.get("power", 0.0))
		weight += float(part.get("weight", 0.0))
	for slot: String in ARMOR_SLOTS:
		var plate: Dictionary = plates[slot]
		var sides := slot == "armor_sides"
		draw += float(plate.get("power_sides" if sides else "power", plate.get("power", 0.0)))
		weight += float(plate.get("weight_sides" if sides else "weight", plate.get("weight", 0.0)))
	for list: Array in [weapon_parts, utility, internal]:
		for part: Dictionary in list:
			draw += float(part.get("power", 0.0))
			weight += float(part.get("weight", 0.0))

	var body: Array = chassis.get("body", [64.0, 36.0])
	var out := {
		"name": chassis.get("name", "Rig"),
		"max_speed": float(chassis.get("max_speed", 400.0)) * float(drive.get("speed_mult", 1.0)),
		"reverse_speed": float(chassis.get("reverse_speed", 200.0)),
		"acceleration": float(engine.get("acceleration", 400.0)),
		"brake": float(drive.get("brake", 1200.0)),
		"coast": float(chassis.get("coast", 280.0)),
		"turn_rate": float(chassis.get("turn_rate", 3.0)) * float(drive.get("turn_mult", 1.0)),
		"grip": float(drive.get("grip", 5.0)),
		"hp": float(chassis.get("hp", 0.0)) + hp_bonus,
		"front": float(front.get("armor", 0.0)),
		"side": float((plates.armor_sides as Dictionary).get("armor", 0.0)),
		"rear": float((plates.armor_rear as Dictionary).get("armor", 0.0)),
		"shield": float(shield.get("shield", 0.0)),
		"shield_delay": float(shield.get("shield_delay", T.DEFAULT_SHIELD_DELAY)),
		"shield_refill": float(shield.get("shield_refill", T.DEFAULT_SHIELD_REFILL)),
		"ram_damage": float(front.get("ram_damage", 30.0)) + ram_bonus,
		"resist": resistances(plates, chassis, internal),
		"mount": int(first.get("mount", 0)),
		"fire_rate": float(first.get("fire_rate", 0.0)),
		"bullet_damage": float(first.get("bullet_damage", 0.0)),
		"bullet_speed": float(first.get("bullet_speed", 1000.0)),
		"spread_deg": float(first.get("spread_deg", 0.0)),
		"turret_turn_rate": float(first.get("turret_turn_rate", 0.0)),
		"pellets": int(first.get("pellets", 1)),
		"weapons": weapons,
		"lock_range": lock_range,
		"manual_aim": manual_aim,       # turrets can be aimed with no Gunner
		"has_turret": has_turret,
		"injury_mult": injury_mult,     # crew injury chance (Roll Cage)
		"abilities": abilities,
		"power_output": float(engine.get("power_output", 0.0)),
		"power_draw": draw,
		"weight": weight,
		"weight_capacity": float(chassis.get("weight_capacity", 0.0)),
		"body": [float(body[0]), float(body[1])],
		"dropped": dropped,
		# Which parts are on, so the rig can draw them.
		"look": {
			"chassis": chassis.get("id", ""),
			"engine": engine.get("id", ""),   # display only: the engine block layer
			"drive": drive.get("id", ""),
			"armor": front.get("id", ""),
			"armor_sides": (plates.armor_sides as Dictionary).get("id", ""),
			"armor_rear": (plates.armor_rear as Dictionary).get("id", ""),
			"weapon": first.get("id", ""),
			"weapons": weapons.map(func(w: Dictionary) -> String: return str(w.id)),
			"internal": internal.map(func(p: Dictionary) -> String: return str(p.id)),
			"utility": utility.map(func(p: Dictionary) -> String: return str(p.id)),
		},
	}
	out["armor"] = toughness(out)
	# Unlocked part mods with a rule the game checks (Mods), every fitted part.
	var mods: Array[String] = []
	var fitted: Array = [chassis, engine, drive, plates.armor_front, plates.armor_sides, plates.armor_rear]
	fitted.append_array(weapon_parts)
	fitted.append_array(utility)
	fitted.append_array(internal)
	for part: Dictionary in fitted:
		for m: String in part.get("mods", []):
			if not mods.has(m):
				mods.append(m)
	out["mods"] = mods
	return out


## Status resistances (§14), shock fire acid toxic slime goop. The rig starts
## at T.STATUS_RESIST_BASE; every fitted plate adds its profile's step, and the
## chassis and internals add any `resist_bonus` they carry (agreed with the
## owner: all of it adds up). Capped at T.STATUS_RESIST_CAP.
static func resistances(plates: Dictionary, chassis: Dictionary, internal: Array[Dictionary]) -> Array:
	var out: Array = []
	for k in 6:
		out.append(T.STATUS_RESIST_BASE)
	for slot: String in ARMOR_SLOTS:
		var profile: Array = (plates[slot] as Dictionary).get("resist", [])
		for k in mini(profile.size(), 6):
			out[k] = float(out[k]) + float(T.STATUS_RESIST_STEP.get(str(profile[k]), 0.0))
	var extras: Array[Dictionary] = [chassis]
	extras.append_array(internal)
	for part: Dictionary in extras:
		var bonus: Array = part.get("resist_bonus", [])
		for k in mini(bonus.size(), 6):
			out[k] = float(out[k]) + float(bonus[k])
	for k in 6:
		out[k] = minf(float(out[k]), T.STATUS_RESIST_CAP)
	return out


## Everything that has to come off before the rig is wrecked: HP plus every
## facing's armor (both flanks count). The shield, which recharges, is extra.
static func toughness(stats: Dictionary) -> float:
	return float(stats.get("hp", 0.0)) + float(stats.get("front", 0.0)) + 2.0 * float(stats.get("side", 0.0)) + float(stats.get("rear", 0.0))


## A part at its Research level, or {} if unknown.
static func _part(id: String, levels: Dictionary) -> Dictionary:
	return Parts.at_level(Parts.get_part(id), int(levels.get(id, 1)))


static func _fit(ids: Array, category: String, slots: int, dropped: Array[String], levels: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in ids:
		var part := _part(id, levels)
		if part.is_empty() or part.category != category:
			push_warning("Loadout: %s is not a %s part" % [id, category])
			continue
		if out.size() >= slots:
			dropped.append(id)
			continue
		out.append(part)
	return out
