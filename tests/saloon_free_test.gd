extends SceneTree
## Other Playtester on a9f8fff: (a) after a wreck, REBUILD seats the crew who
## stayed at the Inn (not just new hires); (b) the Saloon's free Driver is the
## same person all day, whatever else you hire; (c) free hires stop at the
## roster cap (no 7/6).
##
## Run:  godot --headless --fixed-fps 60 --path . -s res://tests/saloon_free_test.gd

const Parts := preload("res://scripts/parts.gd")

var failures: Array[String] = []


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		failures.append(what)


func _initialize() -> void:
	var p: Node = root.get_node("Profile")
	p.set("persist", false)
	p.call("new_game")

	# (a) Survivors: a Gunner left at the Inn during the wreck climbs aboard on rebuild.
	var gunner: Dictionary = p.call("seated_in", "gunner")
	gunner.seated = false
	p.call("record_wreck")   # the seated Driver is lost
	_check(not p.call("has_rig"), "wrecked: no rig")
	_check(p.call("hire_basic", "driver"), "hire a free Driver after the wreck")
	_check(p.call("apply_loadout", Parts.STARTER_LOADOUT), "REBUILD")
	_check(bool(gunner.seated) and not (p.call("seated_in", "driver") as Dictionary).is_empty(), "the surviving Gunner and the new Driver are both seated")

	# (b) Stable free Driver.
	p.call("new_game")
	var first: String = str((p.call("basic_offer", "driver") as Dictionary).name)
	p.set("scrap", 100000)
	p.call("ensure_saloon")
	p.call("hire_basic", "gunner")
	if not (p.get("saloon") as Array).is_empty():
		p.call("hire_offer", 0)
	_check(str((p.call("basic_offer", "driver") as Dictionary).name) == first, "the free Driver stays the same after other hires (%s)" % first)
	var data: Dictionary = p.call("save_data")
	p.call("apply_data", JSON.parse_string(JSON.stringify(data)))
	_check(str((p.call("basic_offer", "driver") as Dictionary).name) == first, "and after a save and load")
	_check(p.call("hire_basic", "driver") and str((p.get("crew") as Array)[-1].name) == first, "hiring gets that person")
	var next: String = str((p.call("basic_offer", "driver") as Dictionary).name)
	_check(next != first, "the next free Driver is someone new")
	p.call("finish_day")
	_check(int((p.get("basic_hires") as Dictionary).get("driver", 0)) == 0, "a new day resets the count")

	# (c) Cap.
	p.call("new_game")
	while not p.call("roster_full"):
		p.call("hire_basic", "gunner")
	var cap: int = p.call("roster_cap")
	_check(not p.call("can_hire_basic") and not p.call("hire_basic", "driver") and (p.get("crew") as Array).size() == cap, "a full roster takes no free hire (%d/%d)" % [(p.get("crew") as Array).size(), cap])
	print("SALOON FREE TEST " + ("PASSED" if failures.is_empty() else "FAILED: %s" % ", ".join(failures)))
	quit(0 if failures.is_empty() else 1)
