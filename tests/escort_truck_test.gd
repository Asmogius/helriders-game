extends SceneTree
## Headless test for the Escort truck's warnings (playtest 15): the HUD shows
## the truck's HP (what wrecks it), not armor + HP across all four facings; a
## pulsing warning at low HP; GOOPED is explained on screen; a GOOPED player
## pulls the frenzied horde nearby off the truck (it used to rush the truck at
## frenzy speed); the truck keeps its 230 top speed.
##
## Run:  godot --headless --fixed-fps 60 --path . -s res://tests/escort_truck_test.gd

const Mission := preload("res://scripts/mission.gd")
const Missions := preload("res://scripts/missions.gd")
const StatusBars := preload("res://scripts/status_bars.gd")
const T := preload("res://scripts/tuning.gd")

var main: Mission
var frame := 0
var failures: Array[String] = []
var mark := {}


func _initialize() -> void:
	seed(20261105)
	var profile := root.get_node("Profile")
	profile.set("persist", false)
	profile.call("new_game")
	main = (load("res://scenes/mission.tscn") as PackedScene).instantiate() as Mission
	main.mission_override = Missions.make("escort", 2, 33)
	main.push_override = 0
	root.add_child(main)


func _process(_delta: float) -> bool:
	frame += 1
	var truck := main.truck
	var rig := main.vehicle
	if frame == 3:
		rig.armor_max = 100000.0
		rig.armor = rig.armor_max
		main.zombies.clear_all()
		main.zombies.spawn_budget = 0
		_check(is_equal_approx(truck.max_speed, 230.0), "the truck's top speed stays 230")
		# One facing stripped and HP at 40%: the old line (armor + HP) said ~60%.
		truck.facing_armor[0] = 0.0
		truck.hp = truck.hp_max * 0.4

	if frame == 30:
		var line := (main.hud.get("_status") as Label).text
		_check(line.contains("TRUCK HP 40%"), "the HUD shows the truck's HP share: " + line)
		_check(not (main.hud.get("_alert") as Label).visible, "no warning above %d%%" % roundi(T.TRUCK_LOW_WARN * 100.0))
		truck.hp = truck.hp_max * 0.3
	if frame == 60:
		var alert := main.hud.get("_alert") as Label
		_check(alert.visible and alert.text.contains("TRUCK HP LOW"), "a pulsing warning at low truck HP")
		truck.hp = truck.hp_max
	if frame == 90:
		_check(not (main.hud.get("_alert") as Label).visible, "the warning clears once it's patched up")
		# GOOPED: the player is marked; a zombie nearer the truck goes for you.
		truck.global_position = rig.global_position + Vector2(0, 300)
		truck.set_physics_process(false)
		var z := main.zombies.spawn_at(rig.global_position + Vector2(0, 200), "shambler")
		z.set("speed", 80.0)
		mark.z = z
		mark.zd = z.global_position.distance_to(rig.global_position)
		rig.call("fill_status", StatusBars.GOOP)
	if frame == 93:
		var banner := main.hud.get("_banner") as Label
		_check(banner.text.contains("GOOPED") and banner.text.contains("RUSH YOU"), "GOOPED is explained when it starts: " + banner.text)
		_check(main.hazards.is_marked(rig), "GOOPED marks you for the horde")
	if frame == 150:
		var z: Node2D = mark.z
		_check(z.global_position.distance_to(rig.global_position) < float(mark.zd) - 20.0, "GOOPED: the horde near you rushes you, not the truck")
		_finish()
	return false


func _check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + what)
	if not ok:
		failures.append(what)


func _finish() -> void:
	main.queue_free()
	if failures.is_empty():
		print("ESCORT TRUCK TEST PASSED")
		quit(0)
	else:
		print("ESCORT TRUCK TEST FAILED: %s" % ", ".join(failures))
		quit(1)
