extends SceneTree
## Endless tuning (Quickplay QP8): the ENDLESS_* consts exist and are sane, and
## the three starter rigs build from real parts within power and weight.
##
## Run:  godot --headless --fixed-fps 60 --path . -s res://tests/endless_tuning_test.gd

const T := preload("res://scripts/tuning.gd")
const Parts := preload("res://scripts/parts.gd")
const Loadout := preload("res://scripts/loadout.gd")

var failures: Array[String] = []

func _check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)

func _rows_ok(rows: Array, name: String) -> void:
	_check(rows.size() > 0 and int(rows[0][0]) == 1, name + " starts at wave 1")
	for i in range(1, rows.size()):
		_check(int(rows[i][0]) > int(rows[i - 1][0]), name + " waves ascend")

func _initialize() -> void:
	_check(T.ENDLESS_WAVE_SECONDS > 0.0 and T.ENDLESS_INTERMISSION_SECONDS >= 0.0, "wave timing")
	_check(T.ENDLESS_ZOMBIES_BASE > 0 and T.ENDLESS_ZOMBIES_BASE <= T.ZOMBIE_CAP, "zombie base within cap")
	_check(T.ENDLESS_ZOMBIES_PER_WAVE >= 0 and T.ENDLESS_ZOMBIES_CAP <= T.ZOMBIE_CAP, "zombie growth / cap")
	_check(T.ENDLESS_RAMP_MIN > 0.0 and T.ENDLESS_RAMP_START >= T.ENDLESS_RAMP_MIN and T.ENDLESS_RAMP_STEP >= 0.0, "ramp")
	_rows_ok(T.ENDLESS_MIX_BY_WAVE, "mix")
	for row: Array in T.ENDLESS_MIX_BY_WAVE:
		var total := 0.0
		for kind: String in row[1]:
			_check(T.ZOMBIE_KINDS.has(kind), "mix kind %s exists" % kind)
			total += float(row[1][kind])
		_check(total >= 0.0 and total < 1.0, "mix shares leave room for Shamblers")
	_check(T.ENDLESS_RIG_FIRST_WAVE >= 1 and T.ENDLESS_RIG_EVERY >= 1 and T.ENDLESS_RIG_COUNT_STEP >= 1, "rig cadence")
	_check(T.ENDLESS_RIG_MAX >= 1 and T.ENDLESS_RIG_MAX <= 3, "rig cap <= 3")
	_rows_ok(T.ENDLESS_RIG_POOL_BY_WAVE, "rig pool")
	var spawnable := ["outrider", "bulwark", "gunner", "scrapper", "convoy", "torcher", "sludger", "patcher"]
	for row: Array in T.ENDLESS_RIG_POOL_BY_WAVE:
		_check(row[1].size() > 0, "rig pool row non-empty")
		for kind: String in row[1]:
			_check(spawnable.has(kind), "rig kind %s spawnable" % kind)
	_check(T.ENDLESS_SCRAP_KILL_MULT > 0.0 and T.ENDLESS_SCRAP_PER_RIG > 0, "kill/rig scrap")
	_check(T.ENDLESS_WAVE_SCRAP_BASE >= 0 and T.ENDLESS_WAVE_SCRAP_PER_WAVE >= 0, "wave scrap")
	_check(T.ENDLESS_WRECK_KEEP >= 0.0 and T.ENDLESS_WRECK_KEEP <= 1.0, "wreck keep share")
	_check(T.ENDLESS_START_SCRAP >= 0 and T.ENDLESS_UNLOCK_COST_MULT > 0.0, "start scrap / unlock mult")
	_check(T.ENDLESS_SCORE_PER_KILL > 0 and T.ENDLESS_SCORE_PER_RIG > 0 and T.ENDLESS_SCORE_PER_WAVE > 0, "score")
	_check(T.ENDLESS_STARTER_RIG_IDS == ["fast", "balanced", "tough"], "three starter rigs")
	_check(T.ENDLESS_STARTER_RIG_IDS.has(T.ENDLESS_STARTER_RIG_DEFAULT), "default rig is a starter")
	for id: String in T.ENDLESS_STARTER_RIG_IDS:
		_check(Parts.ENDLESS_STARTER_RIGS.has(id), "rig %s defined" % id)
		var lo: Dictionary = Parts.ENDLESS_STARTER_RIGS.get(id, {})
		for key: String in ["chassis", "engine", "drive", "armor_front", "armor_sides", "armor_rear"]:
			_check(Parts.CATALOG.has(str(lo.get(key, ""))), "rig %s %s in CATALOG" % [id, key])
		for key: String in ["weapons", "utility", "internal"]:
			for pid in lo.get(key, []):
				_check(Parts.CATALOG.has(str(pid)), "rig %s part %s in CATALOG" % [id, pid])
		var s := Loadout.build(lo)
		_check(float(s.power_draw) <= float(s.power_output), "rig %s within power" % id)
		_check(float(s.weight) <= float(s.weight_capacity), "rig %s within weight" % id)
		print("rig %s: power %s/%s weight %s/%s" % [id, s.power_draw, s.power_output, s.weight, s.weight_capacity])
	var fast := Loadout.build(Parts.ENDLESS_STARTER_RIGS.fast)
	var tough := Loadout.build(Parts.ENDLESS_STARTER_RIGS.tough)
	_check(float(fast.get("max_speed", 0)) > float(tough.get("max_speed", 0)), "fast is faster than tough")
	if failures.is_empty():
		print("ENDLESS TUNING TEST PASSED")
	else:
		for f in failures:
			print("FAIL: " + f)
		print("ENDLESS TUNING TEST FAILED")
	quit(0 if failures.is_empty() else 1)
