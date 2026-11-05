extends SceneTree
## Playtest 2 #7: the pause menu had no way to give up a hopeless job. ABANDON
## JOB (two taps) goes back to the garage: the day passes and the job is gone,
## no pay and nothing picked up comes home, but it isn't a wreck: the rig,
## every part on it and the seated crew are kept. The Training Run has no
## ABANDON (it has LEAVE TUTORIAL).
##
## Run:  godot --headless --fixed-fps 60 --path . -s res://tests/abandon_job_test.gd

const Mission := preload("res://scripts/mission.gd")
const Missions := preload("res://scripts/missions.gd")
const GameMenu := preload("res://scripts/game_menu.gd")
const ProfileScript := preload("res://scripts/profile.gd")

var profile: ProfileScript
var main: Mission
var frame := 0
var failures: Array[String] = []
var mark := {}


func _initialize() -> void:
	seed(20261105)
	profile = root.get_node("Profile")
	profile.persist = false
	profile.new_game()
	profile.active_mission = Missions.make("clear", 2, 7)
	main = (load("res://scenes/mission.tscn") as PackedScene).instantiate() as Mission
	main.mission_override = profile.active_mission
	main.auto_spawn_specials = false
	root.add_child(main)


func _labels(m: Control) -> Array[String]:
	var out: Array[String] = []
	for b in m.find_children("*", "Button", true, false):
		out.append((b as Button).text)
	return out


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 30:
		main.scrap = 75.0   # kill scrap picked up this run
		mark.scrap = profile.scrap
		mark.day = profile.day
		mark.wrecks = int(profile.record.wrecks)
		mark.rig = profile.rig.duplicate(true)
		mark.crew = profile.crew.size()
		mark.seated = profile.seated_crew().size()
		mark.schematics = profile.schematics.size()
		var m := main.open_menu()
		_check(m != null and _labels(m).has("ABANDON JOB"), "the pause menu has ABANDON JOB")
		_check(not m.abandon() and m.abandon_armed and get_tree_paused(), "ABANDON JOB asks for a second tap (still paused)")
		_check(_labels(main.menu).any(func(t: String) -> bool: return t.contains("ABANDON (DAY PASSES")), "the armed button says what it costs")
		_check(main.menu.abandon() and main.abandoned, "the second tap abandons the job")
	if frame == 40:
		_check(current_scene != null and current_scene.name != "Mission" and not paused, "back to the garage, unpaused (%s)" % (current_scene.name if current_scene else "none"))
		_check(profile.day == int(mark.day) + 1 and profile.active_mission.is_empty() and not profile.run_active, "the day passes and the job is gone")
		_check(profile.scrap == int(mark.scrap), "no pay and no kill scrap (%d, was %d)" % [profile.scrap, int(mark.scrap)])
		_check(profile.schematics.size() == int(mark.schematics), "no schematics banked")
		_check(int(profile.record.wrecks) == int(mark.wrecks) and profile.has_rig() and profile.rig == mark.rig, "not a wreck: the rig and its parts are kept")
		_check(profile.crew.size() == int(mark.crew) and profile.seated_crew().size() == int(mark.seated), "the crew are kept and still seated")
		# The Training Run's menu has no ABANDON.
		var tm := GameMenu.new()
		tm.setup(profile, true, true)
		root.add_child(tm)
		_check(not _labels(tm).has("ABANDON JOB") and not tm.abandon(), "no ABANDON JOB in the Training Run")
		tm.queue_free()
	if frame == 45:
		_finish()
	return false


func get_tree_paused() -> bool:
	return paused


func _finish() -> void:
	if failures.is_empty():
		print("ABANDON JOB TEST PASSED")
		quit(0)
	else:
		for f in failures:
			print("TEST FAILED: " + f)
		quit(1)


func _check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + what)
	if not ok:
		failures.append(what)
