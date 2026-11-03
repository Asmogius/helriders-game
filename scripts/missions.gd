extends RefCounted
## The Comms board: which missions are on offer each day, and what each one
## puts in the block. A board is generated from the day number, so it stays
## the same however many times you open Comms that day.
##
## A mission is a plain dictionary (it goes in the save file):
##   type     "clear" | "survive" | "hunt" | "courier"
##   threat   1..3
##   name     flavor name ("Pharmacy Siege"); for Hunt, the Elite's name
##   seed     drives anything random in the run (Courier route)
##   reward   scrap paid on success, before Courier time tiers

const T := preload("res://scripts/tuning.gd")

const TYPES := ["clear", "survive", "hunt", "courier"]


## Today's board: `count` missions, covering as many types as fit, threat
## weighted toward the middle. `quality` (Better Leads level) raises pay.
static func make_board(day: int, count: int, quality: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("helriders-board-%d" % day)
	var types: Array = TYPES.duplicate()
	_shuffle(types, rng)
	var board: Array = []
	for i in count:
		var type: String = types[i % types.size()]
		var roll := rng.randf()
		var threat := 1 if roll < 0.3 else (2 if roll < 0.75 else 3)
		board.append(make(type, threat, rng.randi(), quality, day, i))
	return board


static func make(type: String, threat: int, mission_seed: int, quality := 0, day := 0, index := 0) -> Dictionary:
	var info: Dictionary = T.MISSIONS[type]
	var names: Array = T.MISSION_NAMES[type]
	var base: int = (info.reward as Array)[threat - 1]
	return {
		"id": "d%d_%d" % [day, index],
		"type": type,
		"threat": threat,
		"name": str(names[absi(mission_seed) % names.size()]),
		"seed": mission_seed,
		"reward": roundi(base * (1.0 + float(T.UPGRADES.quality.per_level) * quality)),
	}


## The mission tests and a fresh mission scene fall back to.
static func default_mission() -> Dictionary:
	return make("clear", 2, 1)


static func label(mission: Dictionary) -> String:
	return str(T.MISSIONS[mission.type].label)


static func brief(mission: Dictionary) -> String:
	return str(T.MISSIONS[mission.type].brief)


## One number from the type's table at this mission's threat.
static func stat(mission: Dictionary, key: String) -> Variant:
	var list: Array = T.MISSIONS[mission.type][key]
	return list[clampi(int(mission.threat), 1, 3) - 1]


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
	if hunters > 0:
		bits.append("%d Hunter%s" % [hunters, "" if hunters == 1 else "s"])
	if rigs > 0:
		bits.append("%d Outrider%s" % [rigs, "" if rigs == 1 else "s"])
	return ", ".join(bits)


static func _count(mission: Dictionary, key: String) -> int:
	if str(mission.type) == "survive":
		var n := 0
		for e: Array in stat(mission, "events"):
			if (key == "hunters" and e[1] == "hunter") or (key == "outriders" and e[1] == "outrider"):
				n += 1
		return n
	return int(stat(mission, key)) if has_stat(mission, key) else 0


static func _shuffle(list: Array, rng: RandomNumberGenerator) -> void:
	for i in range(list.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = list[i]
		list[i] = list[j]
		list[j] = tmp
