extends SceneTree
## Headless test for the optional tutorial: the Training Run on its loaner
## rig (lock-on fitted, loaner crew, can't be wrecked), its five steps
## (drive, shoot, lock, wreck an Outrider, grab the crate), that it costs no
## day and touches nothing of yours, then the garage tour on a sandbox copy
## (fit the salvaged part, the stations, the crew rule) and that finishing
## it puts everything back. Also the MENU's TUTORIAL button.
##
## Run:  godot --headless --fixed-fps 60 --path . -s res://tests/tutorial_test.gd

const Mission := preload("res://scripts/mission.gd")
const Garage := preload("res://scripts/garage.gd")
const ProfileScript := preload("res://scripts/profile.gd")
const T := preload("res://scripts/tuning.gd")
const Missions := preload("res://scripts/missions.gd")

var profile: ProfileScript
var main: Mission
var garage: Garage
var frame := 0
var step := 0
var failures: Array[String] = []
var before := {}


func _initialize() -> void:
	profile = root.get_node("Profile")
	profile.persist = false
	profile.new_game()
	before = {"save": _state()}
	profile.tutorial_active = true
	main = (load("res://scenes/mission.tscn") as PackedScene).instantiate() as Mission
	root.add_child(main)


func _process(_delta: float) -> bool:
	frame += 1
	match step:
		0:  # setup and DRIVE
			if frame == 3:
				_check(main.tutorial and main.spec.name == "Training Run", "MENU's tutorial starts the Training Run")
				_check(main.vehicle.can_lock() and main.vehicle.cannot_wreck, "the loaner rig has lock-on and can't be wrecked")
				_check(not main.vehicle.is_overloaded(), "and isn't overloaded")
				var ids: Array = []
				for m: Dictionary in profile.crew:
					ids.append(str(m.name))
				var riders: Array = []
				for m: Dictionary in main.vehicle.crew:
					riders.append(str(m.name))
				_check(main.vehicle.crew.size() == 2 and not ids.has(riders[0]), "a loaner crew rides, not yours")
				_check(not profile.run_active and main.zombies.active_zombies().is_empty() and main.hud.tip.visible, "no run starts, nothing spawns on its own, the first tip shows")
				main.vehicle.take_damage(1000000.0)
				_check(not main.vehicle.is_wrecked, "a killing blow patches the loaner up instead")
				main.vehicle.global_position += Vector2(0, 400)
			if frame == 6:
				_check(main.tut_step == 1 and main.zombies.active_zombies().size() == 4, "driving off moves on to SHOOT, and four zombies come")
				_kill_all()
			if frame == 9:
				_check(main.tut_step == 2 and main.zombies.active_zombies().is_empty(), "four kills move on to LOCK; nothing comes until LOCK is on")
				main.vehicle.lock_enabled = true
			if frame == 12:
				_check(main.zombies.active_zombies().size() == 4, "LOCK on: a pack to practise on")
				_kill_all()
			if frame == 15:
				_check(main.tut_step == 3 and main.outrider.is_inside_tree(), "then an Outrider rolls in")
				main.outrider.take_damage(1000000.0)
			if frame == 18:
				_check(main.tut_step == 4 and main.pickups.get_child_count() == 1, "wrecked, it leaves a crate")
				var crate := main.pickups.get_child(0) as Node2D
				_check(str(crate.get("part").get("id", "")) == T.TUTORIAL_PART, "holding the tour's part")
				main.vehicle.global_position = crate.global_position
			if frame == 22:
				_check(main.tut_step == 5 and main.hud.is_result_visible() and main.hud.result_text().contains("TRAINING DONE"), "grab it: TRAINING DONE")
				_check(_state() == str(before.save), "nothing of yours changed: no day, no scrap, no crew, no run")
				_check(int(profile.record.clears) == 0 and profile.new_job_types.is_empty(), "the tutorial isn't a clear and unlocks no job types")
				var locked := true
				for m: Dictionary in profile.board:
					locked = locked and Missions.unlocked_types(0).has(str(m.type))
				_check(locked, "after the tutorial the board is still Clear / Survive only")
				_check(profile.is_discovered("enemies", "outrider"), "what you met still goes in the Database")
				# What the result card's button does, minus the scene change.
				profile.tutorial_active = false
				profile.begin_tour()
				main.queue_free()
				_next()
		1:  # the garage tour
			if frame == 2:
				garage = (load("res://scenes/garage.tscn") as PackedScene).instantiate() as Garage
				garage.auto_resume = false
				root.add_child(garage)
			if frame == 5:
				_check(garage.tour != null and garage.tour.step == 0 and not garage.tour._next.visible, "the tour starts on the salvaged part, waiting for it to go on")
				_check(not profile.persist and int(profile.storage.get(T.TUTORIAL_PART, 0)) == 1, "the tour runs on a sandbox copy with the part in storage")
				garage.deploy()
				_check(profile.tour_active, "no deploying mid-tour")
				garage.open_slot(3)
				_check(garage.choose(T.TUTORIAL_PART) and str(profile.rig.armor_front) == T.TUTORIAL_PART, "fit it on ARMOR FRONT")
			if frame == 7:
				_check(garage.tour._next.visible, "fitted: NEXT shows")
				var tabs: Array = []
				for i in 5:
					garage.tour.next()
					tabs.append(garage.tab)
				_check(tabs == ["COMMS", "INN", "SALOON", "RESEARCH", "GARAGE"], "NEXT walks Comms, the Inn, the Saloon, Research (%s)" % str(tabs))
				_check(garage.tour._text.text.contains("lost only if your rig is wrecked"), "and ends on the crew rule")
				garage.tour.next()
			if frame == 9:
				_check(garage.tour == null and not profile.tour_active and profile.persist == false, "FINISH closes the tour")
				_check(_state() == str(before.save), "and puts the garage back exactly as it was")
				var m := garage.open_menu()
				var asked := [false]
				m.tutorial_requested.connect(func() -> void: asked[0] = true)
				for b: Node in m.find_children("*", "Button", true, false):
					if (b as Button).text == "TUTORIAL":
						(b as Button).pressed.emit()
				_check(asked[0], "the garage MENU has a TUTORIAL button")
				_finish()
	return false


## The save, minus the Database (the tutorial does count toward what you've met).
func _state() -> String:
	var d: Dictionary = JSON.parse_string(JSON.stringify(profile.save_data()))
	d.erase("discovered")
	return JSON.stringify(d)


func _kill_all() -> void:
	for z in main.zombies.active_zombies().duplicate():
		z.take_hit(10000.0, Vector2.ZERO)


func _next() -> void:
	frame = 0
	step += 1


func _check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + what)
	if not ok:
		failures.append(what)


func _finish() -> void:
	if failures.is_empty():
		print("TUTORIAL TEST PASSED")
		quit(0)
	else:
		print("TUTORIAL TEST FAILED: %s" % ", ".join(failures))
		quit(1)
