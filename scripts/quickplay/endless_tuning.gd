extends RefCounted
## Quickplay: read Content's ENDLESS_* from tuning.gd (PR #91 / QP8) when
## present. Falls back to the same draft numbers so QP6 can land before #91
## merges. Never writes tuning.gd.

const T := preload("res://scripts/tuning.gd")

## Draft fallbacks mirrored from origin/content/qp8-endless-tuning (PR #91).
## Used only when the constant is missing from tuning.gd.
const FALLBACKS := {
	"ENDLESS_WAVE_SECONDS": 60.0,
	"ENDLESS_INTERMISSION_SECONDS": 10.0,
	"ENDLESS_ZOMBIES_BASE": 12,
	"ENDLESS_ZOMBIES_PER_WAVE": 2,
	"ENDLESS_ZOMBIES_CAP": 28,
	"ENDLESS_RAMP_START": 3.0,
	"ENDLESS_RAMP_STEP": 0.1,
	"ENDLESS_RAMP_MIN": 1.5,
	"ENDLESS_MIX_BY_WAVE": [
		[1, {"slimer": 0.0, "boomer": 0.0, "brute": 0.0, "tank": 0.0}],
		[3, {"slimer": 0.06, "boomer": 0.0, "brute": 0.0, "tank": 0.0}],
		[5, {"slimer": 0.08, "boomer": 0.05, "brute": 0.05, "tank": 0.0}],
		[8, {"slimer": 0.10, "boomer": 0.07, "brute": 0.08, "tank": 0.02}],
		[12, {"slimer": 0.10, "boomer": 0.08, "brute": 0.10, "tank": 0.04}],
	],
	"ENDLESS_RIG_FIRST_WAVE": 3,
	"ENDLESS_RIG_EVERY": 2,
	"ENDLESS_RIG_COUNT_STEP": 3,
	"ENDLESS_RIG_MAX": 3,
	"ENDLESS_RIG_POOL_BY_WAVE": [
		[1, ["scrapper"]],
		[5, ["scrapper", "outrider"]],
		[8, ["scrapper", "outrider", "gunner", "bulwark"]],
		[12, ["outrider", "gunner", "bulwark", "torcher", "sludger", "patcher"]],
		[16, ["outrider", "gunner", "bulwark", "torcher", "sludger", "patcher", "convoy"]],
	],
	"ENDLESS_SCORE_PER_KILL": 10,
	"ENDLESS_SCORE_PER_RIG": 100,
	"ENDLESS_SCORE_PER_WAVE": 250,
}


static func get_value(name: String, overrides: Dictionary = {}) -> Variant:
	if overrides.has(name):
		return overrides[name]
	var script: GDScript = load("res://scripts/tuning.gd") as GDScript
	var map: Dictionary = script.get_script_constant_map()
	if map.has(name):
		var v: Variant = map[name]
		# ENDLESS_ZOMBIES_CAP may alias ZOMBIE_CAP on the QP8 branch.
		return v
	if name == "ENDLESS_ZOMBIES_CAP" and map.has("ZOMBIE_CAP"):
		return map["ZOMBIE_CAP"]
	return FALLBACKS.get(name, null)


static func has_content_constants() -> bool:
	var script: GDScript = load("res://scripts/tuning.gd") as GDScript
	return script.get_script_constant_map().has("ENDLESS_WAVE_SECONDS")
