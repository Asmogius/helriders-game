extends SceneTree
## Playtester retest 2 (d7a909b): REBUILD hides once the rig is rebuilt; the
## HUD power bar reads 0 draw on a dead rig; Courier checkpoints count within
## 130 px; and (already fixed on main, kept as regressions) the WRECKED card
## freezes the fight and stops the scrap count, and the Escort driver's radio
## call pauses the game.
##
## Run:  godot --headless --fixed-fps 60 --path . -s res://tests/retest2_test.gd

const Mission := preload("res://scripts/mission.gd")
const Missions := preload("res://scripts/missions.gd")
const Garage := preload("res://scripts/garage.gd")
const T := preload("res://scripts/tuning.gd")

var profile: Node
var garage: Garage
var main: Mission
var frame := 0
var phase := 0
var failures: Array[String] = []
var mark := {}


func _initialize() -> void:
	seed(20261105)
	profile = root.get_node("Profile")
	profile.set("persist", false)
	profile.call("new_game")
	garage = (load("res://scenes/garage.tscn") as PackedScene).instantiate() as Garage
	root.add_child(garage)


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		failures.append(what)


func _snap() -> Dictionary:
	var zs: Array = []
	for z in main.zombies.active_zombies():
		zs.append(z.global_position)
	return {"v": main.vehicle.global_position, "t": main.truck.global_position if main.truck != null else Vector2.ZERO, "el": main.elapsed, "z": zs, "scrap": main.scrap}


func _moved(a: Dictionary, b: Dictionary) -> float:
	var mv := maxf((a.v - b.v).length(), (a.t - b.t).length())
	for i in mini(a.z.size(), b.z.size()):
		mv = maxf(mv, (a.z[i] - b.z[i]).length())
	return mv


func _process(_delta: float) -> bool:
	frame += 1
	if phase == 0 and frame == 5:
		_check(is_equal_approx(T.COURIER_RADIUS, 130.0), "Courier checkpoint radius is 130")
		profile.call("record_wreck")
		garage._refresh()
		_check(garage._rebuild.visible, "after a wreck REBUILD shows")
		_check(garage.rebuild() and profile.call("has_rig"), "REBUILD builds the rig")
		garage._refresh()
		_check(not garage._rebuild.visible, "after the rebuild REBUILD is gone (the layout pass used to show it again)")
		garage.queue_free()
		main = (load("res://scenes/mission.tscn") as PackedScene).instantiate() as Mission
		main.mission_override = Missions.make("escort", 2, 33)
		main.push_override = 0
		root.add_child(main)
		phase = 1
		frame = 0
	elif phase == 1:
		if frame == 60:
			main.hud.left_stick.output = Vector2(1, 0)
			for i in 6:
				main.zombies.spawn_at(main.vehicle.global_position + Vector2(220 + 30 * i, 100), "shambler")
		if frame == 90:
			main._offer_optional()
			mark.a = _snap()
		if frame == 150:
			_check(paused and _moved(mark.a, _snap()) == 0.0 and main.elapsed == mark.a.el, "the driver's radio call freezes rig, truck, horde and clock")
			main._on_optional_choice(false)
			_check(not paused, "answering resumes")
		if frame == 170:
			main.vehicle.take_damage(1.0e7, Vector2.RIGHT)
			main.vehicle.hp = 0.0
		if frame == 180:
			var pb: Object = main.hud.get("_power_bar")
			_check(float(pb.get("used")) == 0.0, "a dead rig's power bar reads 0 draw (was %s)" % str(pb.get("used")))
		if frame == 520:
			_check(main.hud.is_result_visible() and paused, "the WRECKED card freezes the fight")
			mark.w = _snap()
			main.call("_add_kill", 50)
		if frame == 580:
			var w := _snap()
			_check(_moved(mark.w, w) == 0.0 and w.scrap == mark.w.scrap, "behind the card nothing moves and scrap stays put")
			_check(main.vehicle.global_position.distance_to(main.vehicle.global_position + Vector2(120, 0)) < T.COURIER_RADIUS, "120 px off a checkpoint now counts")
			print("RETEST2 TEST " + ("PASSED" if failures.is_empty() else "FAILED: %s" % ", ".join(failures)))
			paused = false
			main.queue_free()
			phase = 2
			frame = 0
	elif phase == 2 and frame == 3:
		quit(0 if failures.is_empty() else 1)
	return false
