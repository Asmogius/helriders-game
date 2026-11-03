extends RefCounted
## Turns a loadout (which part sits in which slot) into one flat dictionary of
## rig stats that vehicle.gd applies. The Garage will edit loadouts; this is
## the only place that knows how parts combine.
##
## A loadout looks like Parts.STARTER_LOADOUT:
##   chassis / engine / drive / armor: one part id each
##   weapons / utility / internal: arrays of part ids, limited by the chassis

const Parts := preload("res://scripts/parts.gd")


static func build(loadout: Dictionary) -> Dictionary:
	var chassis := Parts.get_part(loadout.get("chassis", ""))
	var engine := Parts.get_part(loadout.get("engine", ""))
	var drive := Parts.get_part(loadout.get("drive", ""))
	var armor := Parts.get_part(loadout.get("armor", ""))

	# Slotted parts: keep what fits the chassis, report what didn't.
	var dropped: Array[String] = []
	var weapons := _fit(loadout.get("weapons", []), "Weapon", int(chassis.get("hardpoints", 0)), dropped)
	var utility := _fit(loadout.get("utility", []), "Utility", int(chassis.get("utility_slots", 0)), dropped)
	var internal := _fit(loadout.get("internal", []), "Internal", int(chassis.get("internal_slots", 0)), dropped)
	if not dropped.is_empty():
		push_warning("Loadout: no slot for %s" % ", ".join(dropped))

	# One weapon drives the gun stats for now; more hardpoints come later.
	var weapon: Dictionary = weapons[0] if not weapons.is_empty() else {}

	var stats := {
		"name": chassis.get("name", "Rig"),
		"max_speed": float(chassis.get("max_speed", 400.0)) * float(drive.get("speed_mult", 1.0)),
		"reverse_speed": float(chassis.get("reverse_speed", 200.0)),
		"acceleration": float(engine.get("acceleration", 400.0)),
		"brake": float(drive.get("brake", 1200.0)),
		"coast": float(chassis.get("coast", 280.0)),
		"turn_rate": float(chassis.get("turn_rate", 3.0)) * float(drive.get("turn_mult", 1.0)),
		"grip": float(drive.get("grip", 5.0)),
		"armor": float(chassis.get("armor", 0.0)) + float(armor.get("armor", 0.0)),
		"ram_damage": float(armor.get("ram_damage", 30.0)),
		"mount": int(weapon.get("mount", 0)),
		"fire_rate": float(weapon.get("fire_rate", 0.0)),
		"bullet_damage": float(weapon.get("bullet_damage", 0.0)),
		"bullet_speed": float(weapon.get("bullet_speed", 1000.0)),
		"spread_deg": float(weapon.get("spread_deg", 0.0)),
		"turret_turn_rate": float(weapon.get("turret_turn_rate", 0.0)),
		"lock_range": 0.0,
		"power_output": float(engine.get("power_output", 0.0)),
		"power_draw": 0.0,
		"dropped": dropped,
	}

	# Constant draw from everything bolted on.
	var draw := 0.0
	for part: Dictionary in [chassis, engine, drive, armor]:
		draw += float(part.get("power", 0.0))
	for list: Array in [weapons, utility, internal]:
		for part: Dictionary in list:
			draw += float(part.get("power", 0.0))
	stats["power_draw"] = draw

	# Lock needs a lock-capable weapon AND a targeting system in an internal slot.
	for part: Dictionary in internal:
		if part.get("enables_lock", false):
			stats["lock_range"] = float(weapon.get("lock_range", 0.0))
	return stats


static func _fit(ids: Array, category: String, slots: int, dropped: Array[String]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in ids:
		var part := Parts.get_part(id)
		if part.is_empty() or part.category != category:
			push_warning("Loadout: %s is not a %s part" % [id, category])
			continue
		if out.size() >= slots:
			dropped.append(id)
			continue
		out.append(part)
	return out
