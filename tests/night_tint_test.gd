extends SceneTree
## World night tint only. Content owns the roll (Missions.is_night / roll_night).
## A night job multiplies the map, stains, zombies and Hunters by COL_NIGHT_WORLD.
## A day job, including the tutorial's brighter street, is not night-graded.
## FX, rigs and hazards stay white.
##
## Run:  godot --headless --fixed-fps 60 --path . -s res://tests/night_tint_test.gd

const Missions := preload("res://scripts/missions.gd")
const Mission := preload("res://scripts/mission.gd")
const T := preload("res://scripts/tuning.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var profile: Node = root.get_node("Profile")
	profile.set("persist", false)
	profile.call("new_game")
	_check_roll_stays_with_content()
	_check_tint.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + what)
	if not ok:
		failures.append(what)


func _check_roll_stays_with_content() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/missions.gd")
	_check(not src.contains("DISTRICT_NIGHT") and not src.contains("normalize_district"), "the district night table is not in this branch")
	var job := Missions.make("clear", 3, 4)
	job["layout"] = "lots"
	var rolled: bool = Missions.roll_night(job, 0)
	_check(rolled == false or rolled == true, "Content's roll_night(mission, clears) is the roll")
	_check(T.COL_NIGHT_WORLD.to_html(false) == "2a3550", "the world tint colour is #2a3550")
	var bay: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://art/garage/workshop_bay.json"))
	var colours: Dictionary = bay.sample_colours
	var rgb: Array = colours.GARAGE_STREET_NIGHT
	_check(int(rgb[0]) == 42 and int(rgb[1]) == 53 and int(rgb[2]) == 80, "workshop bay night metadata is 42, 53, 80")


func _boot(spec: Dictionary) -> Mission:
	var scene: PackedScene = load("res://scenes/mission.tscn")
	var mission := scene.instantiate() as Mission
	mission.auto_spawn_specials = false
	mission.mission_override = spec
	root.add_child(mission)
	return mission


func _world_is(mission: Mission, tint: Color) -> bool:
	return mission.arena.modulate == tint and mission.splats.modulate == tint and mission.zombies.modulate == tint and mission.hunters[0].modulate == tint


func _lights_are_white(mission: Mission) -> bool:
	var white := mission.fx.modulate == Color.WHITE and mission.bullets.modulate == Color.WHITE
	white = white and mission.vehicle.modulate == Color.WHITE and mission.rigs.modulate == Color.WHITE
	white = white and mission.hazards.modulate == Color.WHITE and mission.shells.modulate == Color.WHITE
	if mission.fx.glow != null:
		white = white and mission.fx.glow.modulate == Color.WHITE
	return white


func _check_tint() -> void:
	var day := Missions.make("clear", 3, 5)
	day["layout"] = "lots"
	day["night"] = false
	_check(not Missions.is_night(day), "an Outer Blocks day flag is day")
	var day_run := _boot(day)
	_check(not day_run.night and day_run.arena.modulate == Color.WHITE and _lights_are_white(day_run), "a day job is not night-graded")
	day_run.free()

	var night := day.duplicate(true)
	night["night"] = true
	_check(Missions.is_night(night), "the saved night flag is night")
	var night_run := _boot(night)
	_check(night_run.night and _world_is(night_run, T.COL_NIGHT_WORLD), "night multiplies the map, stains, zombies and Hunters by COL_NIGHT_WORLD")
	_check(_lights_are_white(night_run), "night leaves rigs, hazards, tracers and FX white")
	night_run.free()

	var core := Missions.make("clear", 4, 8)
	core["layout"] = "crater_rim"
	core["night"] = false
	_check(Missions.is_night(core), "a Core layout is night even with the flag off")
	var core_run := _boot(core)
	_check(core_run.night and core_run.arena.modulate == T.COL_NIGHT_WORLD, "the tint follows Missions.is_night")
	core_run.free()

	var tut := Missions.make("clear", 4, 9)
	tut["night"] = true
	tut["tutorial"] = true
	var tut_run := _boot(tut)
	_check(not tut_run.night and tut_run.arena.modulate == T.COL_TUTORIAL_GRADE, "the tutorial keeps its street grade")
	tut_run.free()

	if failures.is_empty():
		print("NIGHT TINT TEST PASSED")
		quit(0)
	else:
		print("NIGHT TINT TEST FAILED: %s" % ", ".join(failures))
		quit(1)
