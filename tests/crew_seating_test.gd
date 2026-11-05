extends SceneTree
## Playtest 2 #10: after a wreck and a rebuild, crew hired at the Saloon stayed
## in the Inn ("DRIVER empty GUNNER empty") and DEPLOY was still lit with no
## Driver. Now hires made with no rig take their seats when the rig is
## rebuilt, a hire takes an empty seat, seated crew are never swapped out,
## and DEPLOY is off while no Driver is seated.
##
## Run:  godot --headless --fixed-fps 60 --path . -s res://tests/crew_seating_test.gd

const Garage := preload("res://scripts/garage.gd")
const ProfileScript := preload("res://scripts/profile.gd")

var profile: ProfileScript
var garage: Garage
var frame := 0
var failures: Array[String] = []


func _initialize() -> void:
	profile = root.get_node("Profile")
	profile.persist = false
	profile.new_game()
	garage = (load("res://scenes/garage.tscn") as PackedScene).instantiate() as Garage
	root.add_child(garage)


func _take_job() -> void:
	garage.show_tab("COMMS")
	garage._comms.select(0)
	garage._comms.take_selected()
	garage._refresh()


func _process(_delta: float) -> bool:
	frame += 1
	if frame != 3:
		return false
	_take_job()
	_check(profile.has_mission() and not garage._deploy.disabled, "new game: Driver seated, job taken, DEPLOY on")

	# No Driver seated: DEPLOY is off; seat them again and it's back.
	var driver := profile.seated_in("driver")
	profile.unseat_member(int(driver.id))
	garage._refresh()
	_check(garage._deploy.disabled, "no Driver seated: DEPLOY is off")
	profile.seat_member(int(driver.id))
	garage._refresh()
	_check(not garage._deploy.disabled, "Driver seated again: DEPLOY is on")

	# Wreck: the seated crew die and the rig is gone.
	profile.record_wreck()
	_check(not profile.has_rig() and profile.seated_crew().is_empty(), "a wreck leaves no rig and no one seated")
	# Hire a Driver and a Gunner with no rig (the playtest order: Saloon before REBUILD).
	_check(profile.hire_basic("driver") and profile.hire_basic("gunner"), "free Driver and Gunner hired")
	var d: Dictionary = profile.crew[profile.crew.size() - 2]
	var g: Dictionary = profile.crew[profile.crew.size() - 1]
	_check(not bool(d.seated) and not bool(g.seated), "with no rig there's no seat yet")
	_check(garage.rebuild() and profile.has_rig(), "REBUILD")
	_check(bool(d.seated) and bool(g.seated) and profile.seated_in("driver") == d and profile.seated_in("gunner") == g,
		"after the rebuild the new hires are seated (%s, %s)" % [str(d.name), str(g.name)])
	if not profile.has_mission():
		_take_job()
	garage._refresh()
	_check(not garage._deploy.disabled, "seated Driver after the rebuild: DEPLOY is on")

	# A second Gunner hire doesn't bump the seated one; with the seat empty, a hire takes it.
	_check(profile.hire_basic("gunner"), "a second Gunner hired")
	var g2: Dictionary = profile.crew[profile.crew.size() - 1]
	_check(not bool(g2.seated) and profile.seated_in("gunner") == g, "a seated Gunner is never swapped out by a hire")
	profile.dismiss(int(g.id))
	profile.dismiss(int(g2.id))
	_check(profile.hire_basic("gunner"), "a Gunner hired into the empty seat")
	var g3: Dictionary = profile.crew[profile.crew.size() - 1]
	_check(bool(g3.seated), "a hire takes an empty seat on a built rig")

	# Wreck again with no hires: the rebuild seats whoever is free in the roster, the Driver's seat stays
	# empty when there's no Driver, and DEPLOY stays off.
	profile.record_wreck()
	_check(profile.hire_basic("gunner"), "only a Gunner hired")
	garage.rebuild()
	if not profile.has_mission():
		_take_job()
	garage._refresh()
	_check(profile.seated_in("driver").is_empty() and not profile.seated_in("gunner").is_empty(), "rebuilt: Gunner seated, no Driver")
	_check(garage._deploy.disabled, "no Driver after the rebuild: DEPLOY stays off")
	_finish()
	return false


func _finish() -> void:
	if failures.is_empty():
		print("CREW SEATING TEST PASSED")
		quit(0)
	else:
		for f in failures:
			print("TEST FAILED: " + f)
		quit(1)


func _check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + what)
	if not ok:
		failures.append(what)
