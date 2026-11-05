extends SceneTree
## Regression test: one blast that kills several zombies must hit every zombie
## in range. Deaths remove zombies from the director's list straight away, so a
## loop over the live list used to skip the zombie after each kill.
## Covers the Tail Swipe (vehicle.gd) and Powder Keg (mission.gd _rig_wreck_perks).
##
## Run:  godot --headless --fixed-fps 60 --path . -s res://tests/kill_loops_test.gd

const Mission := preload("res://scripts/mission.gd")
const Missions := preload("res://scripts/missions.gd")
const Crew := preload("res://scripts/crew.gd")

const SPOT := Vector2(1600, 1200)
const COUNT := 5

var main: Mission
var frame := 0
var failures: Array[String] = []


func _initialize() -> void:
	seed(20261105)
	var profile: Node = root.get_node("Profile")
	profile.set("persist", false)
	profile.call("new_game")
	main = (load("res://scenes/mission.tscn") as PackedScene).instantiate() as Mission
	main.mission_override = Missions.make("clear", 1, 7)
	main.auto_spawn_specials = false
	main.push_override = 0
	root.add_child(main)


## COUNT fragile zombies packed around `at` (all well inside any blast radius).
func _pack(at: Vector2) -> Array:
	main.zombies.clear_all()
	main.zombies.spawn_budget = 0
	var out := []
	for i in COUNT:
		var z: Node2D = main.zombies.spawn_at(at + Vector2(float(i % 3) * 4.0 - 4.0, float(i / 3) * 4.0 - 2.0), "shambler")
		if z != null:
			z.set("hp", 0.01)
			out.append(z)
	return out


func _alive(list: Array) -> int:
	var n := 0
	for z in list:
		if bool(z.get("active")):
			n += 1
	return n


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 5:
		var rig := main.vehicle
		rig.global_position = SPOT
		rig.rotation = 0.0
		# --- Tail Swipe: every zombie at the rear takes the hit ---
		var back := -Vector2.RIGHT.rotated(rig.rotation)
		var tail := rig.global_position + back * float(rig.body_len) * 0.5
		var pack := _pack(tail)
		_check(pack.size() == COUNT, "spawned %d zombies at the tail" % COUNT)
		rig.set("_tail_hit", [])
		rig.call("_tail_swipe")
		_check(_alive(pack) == 0, "Tail Swipe kills all %d zombies in reach (%d left)" % [COUNT, _alive(pack)])
		# --- Powder Keg: the wreck burst hits every zombie in range ---
		var m := Crew.make("gunner", "Mythic", RandomNumberGenerator.new(), "")
		m.perks = ["sp_powder_keg"]
		m.id = 901
		rig.set_crew([m])
		(rig.get("_active") as Dictionary)["cook_off"] = {}
		var at := SPOT + Vector2(600, 0)
		pack = _pack(at)
		main.call("_rig_wreck_perks", at)
		_check(_alive(pack) == 0, "Powder Keg burst kills all %d zombies in range (%d left)" % [COUNT, _alive(pack)])
		(rig.get("_active") as Dictionary).erase("cook_off")
		# --- The director's list is safe to loop while killing ---
		pack = _pack(at)
		for z in main.zombies.active_zombies():
			z.call("take_hit", 100.0, Vector2.ZERO, "shot")
		_check(_alive(pack) == 0, "killing while looping active_zombies() reaches every zombie")
	if frame == 8:
		if failures.is_empty():
			print("KILL LOOPS TEST PASSED")
			quit(0)
		else:
			for f in failures:
				print("TEST FAILED: " + f)
			quit(1)
	return false


func _check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + what)
	if not ok:
		failures.append(what)
