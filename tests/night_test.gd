extends SceneTree
## Night is rolled per job from its seed: district weight, then the job rule.
## The same seed is the same night. A day job leaves the world untinted; a
## night job multiplies the world by T.COL_NIGHT_WORLD and leaves FX white.
##
## Run:  godot --headless --fixed-fps 60 --path . -s res://tests/night_test.gd

const Missions := preload("res://scripts/missions.gd")
const Mission := preload("res://scripts/mission.gd")
const ProfileScript := preload("res://scripts/profile.gd")
const T := preload("res://scripts/tuning.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var profile: Node = root.get_node("Profile")
	profile.set("persist", false)
	profile.call("new_game")
	_check_chances()
	_check_rolls()
	_check_boards()
	_check_save()
	# The mission scene only enters the tree once this script's _initialize
	# has returned, so the tint checks run on the next idle frame.
	_check_tint.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + what)
	if not ok:
		failures.append(what)


func _near(got: float, want: float, what: String) -> void:
	_check(absf(got - want) <= 0.08, "%s (got %.3f, want %.2f)" % [what, got, want])


func _rate(type: String, skulls: int, district: String, n := 800) -> float:
	var hits := 0
	for seed in n:
		if Missions.roll_night(type, skulls, district, seed):
			hits += 1
	return float(hits) / float(n)


func _check_chances() -> void:
	_check(is_equal_approx(Missions.night_chance("clear", 2, "outer_blocks"), 0.0), "Outer Clear is day")
	_check(is_equal_approx(Missions.night_chance("retrieve", 4, "outer_blocks"), 0.0), "Outer Retrieve is day")
	_check(is_equal_approx(Missions.night_chance("survive", 3, "outer_blocks"), 0.0), "Outer Survive below 4 skulls is day")
	_check(is_equal_approx(Missions.night_chance("hunt", 2, "outer_blocks"), 0.0), "Outer Hunt below 4 skulls is day")
	_check(is_equal_approx(Missions.night_chance("survive", 4, "outer_blocks"), 1.0), "Outer 4-skull Survive is night")
	_check(is_equal_approx(Missions.night_chance("hunt", 4, "outer_blocks"), 1.0), "Outer 4-skull Hunt is night")
	_check(is_equal_approx(Missions.night_chance("clear", 3, "midtown"), 0.35), "Midtown Clear is 35%")
	_check(is_equal_approx(Missions.night_chance("retrieve", 5, "midtown"), 0.35), "Midtown Retrieve follows the district")
	_check(is_equal_approx(Missions.night_chance("survive", 3, "midtown"), 0.60), "Midtown Survive is district +25%")
	_check(is_equal_approx(Missions.night_chance("hunt", 5, "midtown"), 0.60), "Midtown Hunt leans night by the same +25%")
	_check(is_equal_approx(Missions.night_chance("clear", 4, "industrial"), 0.60), "Industrial Clear is 60%")
	_check(is_equal_approx(Missions.night_chance("survive", 6, "industrial"), 0.85), "Industrial Survive is 60% +25%")
	_check(is_equal_approx(Missions.night_chance("hunt", 3, "industrial"), 0.85), "Industrial Hunt leans night")
	_check(is_equal_approx(Missions.night_chance("clear", 4, "core"), 1.0), "Core Clear is always night")
	_check(is_equal_approx(Missions.night_chance("survive", 6, "core"), 1.0), "Core Survive is always night")
	_check(is_equal_approx(Missions.night_chance("hunt", 5, "core"), 1.0), "Core Hunt is always night")
	_check(is_equal_approx(Missions.night_chance("retrieve", 4, "core"), 1.0), "Core Retrieve is always night")
	_check(is_equal_approx(Missions.night_chance("courier", 1, "outer_blocks"), 0.5), "Courier is 50/50 in Outer Blocks")
	_check(is_equal_approx(Missions.night_chance("courier", 6, "core"), 0.5), "Courier is 50/50 in Core, not always night")
	_check(is_equal_approx(Missions.night_chance("escort", 4, "core"), 0.0), "Escort at 4 skulls is day, even in Core")
	_check(is_equal_approx(Missions.night_chance("escort", 4, "outer_blocks"), 0.0), "Outer Escort is day")
	_check(is_equal_approx(Missions.night_chance("escort", 5, "midtown"), 1.0), "Escort at 5 skulls is night")
	_check(is_equal_approx(Missions.night_chance("escort", 6, "industrial"), 1.0), "Escort at 6 skulls is night")
	_check(Missions.normalize_district("nope") == "outer_blocks", "an unknown district counts as Outer Blocks")


func _check_rolls() -> void:
	var stable := true
	for seed in range(-3, 400):
		var a := Missions.roll_night("courier", 3, "industrial", seed)
		var b := Missions.roll_night("courier", 3, "industrial", seed)
		var c := Missions.roll_night("survive", 4, "midtown", seed)
		var d := Missions.roll_night("survive", 4, "midtown", seed)
		stable = stable and a == b and c == d
	_check(stable, "the same seed rolls the same night")
	_check(_rate("clear", 1, "outer_blocks") == 0.0, "Outer Clear never rolls night")
	_check(_rate("survive", 3, "outer_blocks") == 0.0, "Outer 3-skull Survive never rolls night")
	_check(_rate("survive", 4, "outer_blocks") == 1.0, "Outer 4-skull Survive always rolls night")
	_check(_rate("hunt", 4, "outer_blocks") == 1.0, "Outer 4-skull Hunt always rolls night")
	_check(_rate("clear", 4, "core") == 1.0, "Core Clear always rolls night")
	_check(_rate("escort", 4, "core") == 0.0, "Core 4-skull Escort always rolls day")
	_check(_rate("escort", 5, "midtown") == 1.0, "5-skull Escort always rolls night")
	_near(_rate("clear", 3, "midtown"), 0.35, "Midtown Clear rolls about 35% night")
	_near(_rate("retrieve", 4, "industrial"), 0.60, "Industrial Retrieve rolls about 60% night")
	_near(_rate("survive", 3, "midtown"), 0.60, "Midtown Survive rolls about 60% night")
	_near(_rate("hunt", 4, "midtown"), 0.60, "Midtown Hunt rolls about 60% night")
	_near(_rate("survive", 5, "industrial"), 0.85, "Industrial Survive rolls about 85% night")
	_near(_rate("hunt", 6, "industrial"), 0.85, "Industrial Hunt rolls about 85% night")
	_near(_rate("courier", 2, "outer_blocks"), 0.50, "Outer Courier rolls about 50% night")
	_near(_rate("courier", 6, "core"), 0.50, "Core Courier rolls about 50% night")
	var job := Missions.make("survive", 4, 11, 0, 2, 1, "midtown")
	_check(str(job.district) == "midtown" and bool(job.night) == Missions.roll_night("survive", 4, "midtown", 11), "make() stamps the district and the seeded night")
	_check(str(Missions.make("clear", 1, 7)) == str(Missions.make("clear", 1, 7)), "making the same job twice matches, night included")
	var forced := {"type": "clear", "skulls": 4, "district": "core", "seed": 9, "night": false}
	_check(not Missions.is_night(forced), "a stored day flag stays day")
	forced.erase("night")
	_check(Missions.is_night(forced), "a Core Clear with no flag rolls night")
	forced["night"] = true
	forced["tutorial"] = true
	_check(not Missions.is_night(forced), "a tutorial job is day even if the flag says night")


func _check_boards() -> void:
	_check(str(Missions.make_board(4, 6, 0, "industrial")) == str(Missions.make_board(4, 6, 0, "industrial")), "a district board is the same every time that day")
	var saw_outer_night := false
	var saw_outer_day := false
	var courier_n := 0
	var courier_all := 0
	var agreed := true
	for day in 400:
		for job: Dictionary in Missions.make_board(day, 6, 0, "outer_blocks"):
			var type := str(job.type)
			var level := int(job.skulls)
			var night := bool(job.night)
			agreed = agreed and str(job.district) == "outer_blocks"
			agreed = agreed and night == Missions.roll_night(type, level, "outer_blocks", int(job.seed))
			if type == "courier":
				courier_all += 1
				if night:
					courier_n += 1
			elif type == "survive" or type == "hunt":
				agreed = agreed and night == (level == 4)
				if level == 4:
					saw_outer_night = true
				else:
					saw_outer_day = true
			else:
				agreed = agreed and not night
				saw_outer_day = true
	_check(agreed and saw_outer_night and saw_outer_day, "Outer Blocks jobs are day except 4-skull Survive and Hunt")
	var courier_rate := float(courier_n) / float(maxi(courier_all, 1))
	_check(absf(courier_rate - 0.5) <= 0.10, "Outer Blocks Courier jobs on the board are about 50/50 (got %.3f)" % courier_rate)
	var core_ok := true
	var saw_escort_day := false
	var saw_escort_night := false
	for day in 160:
		for job: Dictionary in Missions.make_board(day + 3, 6, 0, "core"):
			var type := str(job.type)
			var level := int(job.skulls)
			var night := bool(job.night)
			core_ok = core_ok and str(job.district) == "core" and level >= 4 and level <= 6
			core_ok = core_ok and night == Missions.roll_night(type, level, "core", int(job.seed))
			if type == "escort":
				core_ok = core_ok and night == (level >= 5)
				if night:
					saw_escort_night = true
				else:
					saw_escort_day = true
			elif type != "courier":
				core_ok = core_ok and night
	_check(core_ok and saw_escort_day and saw_escort_night, "Core is night, except Courier and a 4-skull Escort")


func _check_save() -> void:
	var old: Dictionary = ProfileScript._clean_mission({"type": "hunt", "threat": 3, "name": "Rustjaw", "seed": 1, "reward": 170})
	_check(int(old.skulls) == 6 and str(old.district) == "outer_blocks" and not bool(old.night), "an old save with no district stays a day Outer Blocks job")
	var kept: Dictionary = ProfileScript._clean_mission({"type": "clear", "skulls": 4, "name": "A", "seed": 9, "reward": 1, "district": "core", "night": false})
	_check(not bool(kept.night) and str(kept.district) == "core", "a saved day flag is not re-rolled into Core's always-night")
	var filled: Dictionary = ProfileScript._clean_mission({"type": "clear", "skulls": 4, "name": "A", "seed": 9, "reward": 1, "district": "core"})
	_check(bool(filled.night), "an old Core Clear with no flag rolls night from its seed")
	var again: Dictionary = ProfileScript._clean_mission(filled)
	_check(bool(again.night) == bool(filled.night), "loading the same job again keeps its night")


func _boot(spec: Dictionary, tutorial := false) -> Mission:
	var scene: PackedScene = load("res://scenes/mission.tscn")
	var mission := scene.instantiate() as Mission
	mission.auto_spawn_specials = false
	if tutorial:
		spec["tutorial"] = true
	mission.mission_override = spec
	root.add_child(mission)
	return mission


func _world_is(mission: Mission, tint: Color) -> bool:
	return mission.arena.modulate == tint and mission.splats.modulate == tint and mission.zombies.modulate == tint and mission.hunters[0].modulate == tint


func _lights_are_white(mission: Mission) -> bool:
	var white := mission.modulate == Color.WHITE and mission.fx.modulate == Color.WHITE
	white = white and mission.bullets.modulate == Color.WHITE and mission.shells.modulate == Color.WHITE
	white = white and mission.vehicle.modulate == Color.WHITE and mission.rigs.modulate == Color.WHITE
	white = white and mission.hazards.modulate == Color.WHITE and mission.barrel_layer.modulate == Color.WHITE
	white = white and mission.markers.modulate == Color.WHITE and mission.pickups.modulate == Color.WHITE
	white = white and mission.mines.modulate == Color.WHITE
	if mission.fx.glow != null:
		white = white and mission.fx.glow.modulate == Color.WHITE
	return white


func _check_tint() -> void:
	var day := _boot(Missions.make("clear", 2, 5))
	_check(not day.night and _world_is(day, Color.WHITE) and _lights_are_white(day), "a day job leaves the world and the lights untinted")
	day.free()
	var night_spec := Missions.make("clear", 4, 5, 0, 0, 0, "core")
	var night := _boot(night_spec)
	_check(night.night and bool(night_spec.night), "a Core Clear job is night")
	_check(_world_is(night, T.COL_NIGHT_WORLD), "night multiplies the map, stains, zombies and Hunters by COL_NIGHT_WORLD")
	_check(_lights_are_white(night), "night leaves rigs, hazards, tracers and FX unmodulated")
	night.free()
	var training := _boot(Missions.make("clear", 4, 5, 0, 0, 0, "core"), true)
	_check(not training.night and _world_is(training, Color.WHITE), "the tutorial is day even when the override job was night")
	training.free()
	if failures.is_empty():
		print("NIGHT TEST PASSED")
		quit(0)
	else:
		print("NIGHT TEST FAILED: %s" % ", ".join(failures))
		quit(1)
