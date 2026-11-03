extends RefCounted
## The Comms board: which missions are on offer each day, and what each one
## puts in the block. A board is generated from the day number, so it stays
## the same however many times you open Comms that day.
##
## A mission is a plain dictionary (it goes in the save file):
##   type     "clear" | "survive" | "hunt" | "courier"
##   skulls   1..6 difficulty (1 easiest)
##   name     flavor name ("Pharmacy Siege"); for Hunt, the Elite's name
##   seed     drives anything random in the run (Courier route)
##   reward   scrap paid on success, before Courier time tiers

const T := preload("res://scripts/tuning.gd")

const TYPES := ["clear", "survive", "hunt", "courier"]


## Today's board: `count` missions, covering as many types as fit, skulls
## rolled inside the district's band (T.DISTRICTS) and weighted toward its
## easier middle. `quality` (Better Leads level) raises pay.
static func make_board(day: int, count: int, quality: int, district := "outer_blocks") -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("helriders-board-%d" % day)
	var types: Array = TYPES.duplicate()
	_shuffle(types, rng)
	var band := skull_band(district)
	var board: Array = []
	for i in count:
		var type: String = types[i % types.size()]
		board.append(make(type, _roll_skulls(band, rng), rng.randi(), quality, day, i))
	return board


## [lowest, highest] skulls a district's board can roll.
static func skull_band(district: String) -> Vector2i:
	for d: Dictionary in T.DISTRICTS:
		if d.id == district:
			var band: Array = d.skulls
			return Vector2i(int(band[0]), int(band[1]))
	return Vector2i(1, T.MAX_SKULLS)


static func _roll_skulls(band: Vector2i, rng: RandomNumberGenerator) -> int:
	var total := 0
	for k in range(band.x, band.y + 1):
		total += int(T.SKULL_WEIGHTS[mini(k - band.x, T.SKULL_WEIGHTS.size() - 1)])
	var roll := rng.randi_range(1, total)
	for k in range(band.x, band.y + 1):
		roll -= int(T.SKULL_WEIGHTS[mini(k - band.x, T.SKULL_WEIGHTS.size() - 1)])
		if roll <= 0:
			return k
	return band.y


static func make(type: String, level: int, mission_seed: int, quality := 0, day := 0, index := 0) -> Dictionary:
	var info: Dictionary = T.MISSIONS[type]
	var names: Array = T.MISSION_NAMES[type]
	level = clampi(level, 1, T.MAX_SKULLS)
	var base: int = (info.reward as Array)[level - 1]
	return {
		"id": "d%d_%d" % [day, index],
		"type": type,
		"skulls": level,
		"name": str(names[absi(mission_seed) % names.size()]),
		"seed": mission_seed,
		"reward": roundi(base * (1.0 + float(T.UPGRADES.quality.per_level) * quality)),
	}


## The mission tests and a fresh mission scene fall back to.
static func default_mission() -> Dictionary:
	return make("clear", 3, 1)


static func label(mission: Dictionary) -> String:
	return str(T.MISSIONS[mission.type].label)


static func brief(mission: Dictionary) -> String:
	return str(T.MISSIONS[mission.type].brief)


static func skulls(mission: Dictionary) -> int:
	return clampi(int(mission.get("skulls", 1)), 1, T.MAX_SKULLS)


## Chance this job pays a schematic from its type's pool on success.
static func schematic_chance(mission: Dictionary) -> float:
	return float(T.MISSION_SCHEMATIC_CHANCE[skulls(mission) - 1])


## One number from the type's table at this mission's skulls.
static func stat(mission: Dictionary, key: String) -> Variant:
	var list: Array = T.MISSIONS[mission.type][key]
	return list[skulls(mission) - 1]


static func has_stat(mission: Dictionary, key: String) -> bool:
	return (T.MISSIONS[mission.type] as Dictionary).has(key)


## What the board card says is in the block.
static func threats_text(mission: Dictionary) -> String:
	var bits: Array[String] = []
	match str(mission.type):
		"clear":
			bits.append("%d shamblers" % int(stat(mission, "shamblers")))
		"survive":
			var secs := int(stat(mission, "seconds"))
			bits.append("%d:%02d of waves" % [secs / 60, secs % 60])
		"hunt":
			bits.append("Elite rig, armor x%.1f" % float(stat(mission, "elite_armor")))
		"courier":
			bits.append("%d checkpoints" % int(stat(mission, "checkpoints")))
	var hunters := _count(mission, "hunters")
	var rigs := _count(mission, "outriders") + _count(mission, "escorts")
	var heavies := _count(mission, "bulwarks") + _count(mission, "bulwark_escorts")
	if hunters > 0:
		bits.append("%d Hunter%s" % [hunters, "" if hunters == 1 else "s"])
	if rigs > 0:
		bits.append("%d Outrider%s" % [rigs, "" if rigs == 1 else "s"])
	if heavies > 0:
		bits.append("%d Bulwark%s" % [heavies, "" if heavies == 1 else "s"])
	return ", ".join(bits)


static func _count(mission: Dictionary, key: String) -> int:
	if str(mission.type) == "survive":
		var n := 0
		for e: Array in stat(mission, "events"):
			if (key == "hunters" and e[1] == "hunter") or (key == "outriders" and e[1] == "outrider") or (key == "bulwarks" and e[1] == "bulwark"):
				n += 1
		return n
	return int(stat(mission, key)) if has_stat(mission, key) else 0


static func _shuffle(list: Array, rng: RandomNumberGenerator) -> void:
	for i in range(list.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = list[i]
		list[i] = list[j]
		list[j] = tmp
