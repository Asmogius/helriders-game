extends SceneTree
## Headless smoke test. Boots the main scene, fakes thumb-stick and button
## input, and checks each core mechanic in its own short scenario:
## driving, lock-on, the Hunter (latch, shoot off, crush), the Outrider
## (hunts and shoots you, drops salvage), and the wreck.
##
## Run:  godot --headless --fixed-fps 60 --path . -s res://tests/smoke_test.gd
## Exit code 0 = pass, 1 = fail. CI also fails on any "SCRIPT ERROR" output.

const Main := preload("res://scripts/main.gd")
const Hunter := preload("res://scripts/hunter.gd")

const OPEN_SPOT := Vector2(1600, 1200)     # clear ground around the start
const ROAD_WEST := Vector2(400, 720)       # straight run west to the boundary wall

var main: Main
var frame := 0
var failures: Array[String] = []
var started_usec := 0
var mark := Vector2.ZERO
var armor_mark := 0.0
var shots_mark := 0
var lock_frames := 0
var enemy_damage := 0.0


func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	main = scene.instantiate() as Main
	main.auto_spawn_specials = false  # this test places the Hunter and Outrider
	root.add_child(main)


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 30:
		started_usec = Time.get_ticks_usec()
	var rig := main.vehicle

	# --- Driving ----------------------------------------------------------------
	if frame == 10:
		_check(main.zombies.active_count() > 0, "zombies spawned at start")
		rig.rotation = PI / 2.0  # face south, the clearest straight lane
		mark = rig.global_position
		main.hud.left_stick.output = Vector2.DOWN
	if frame == 130:
		var moved := rig.global_position.distance_to(mark)
		print("  drove %.0f px, speed %.0f" % [moved, rig.velocity.length()])
		_check(moved > 300.0, "rig drives forward")
		main.hud.left_stick.output = Vector2.RIGHT
	if frame == 190:
		print("  heading after turn %.2f rad" % wrapf(rig.rotation, -PI, PI))
		_check(absf(wrapf(rig.rotation, -PI, PI)) < 0.8, "rig steers toward the stick")

	# --- Lock-on: no aim input at all, lock does the aiming and firing ------------
	if frame == 200:
		main.hud.press_lock()
		_check(rig.lock_enabled, "lock button turns lock on")
		shots_mark = main.bullets.shots_fired
	if frame > 200 and frame < 1200:
		main.hud.left_stick.output = Vector2.RIGHT.rotated(frame * 0.01) * 0.6
		main.hud.right_stick.output = Vector2.ZERO
		if rig.lock_target != null:
			lock_frames += 1
		rig.armor = rig.armor_max  # this scenario tests lock, not survival
	if frame == 1200:
		var shots := main.bullets.shots_fired - shots_mark
		print("  locked %d frames, %d shots, %d hits, %d kills" % [lock_frames, shots, main.bullets.hits, main.kills])
		_check(lock_frames > 60, "lock acquires targets")
		_check(shots > 20, "lock aims and fires on its own")
		_check(main.kills > 0, "locked fire kills zombies")
		_check(main.zombies.active_count() <= 28, "zombie cap respected")
		main.hud.press_lock()
		_check(not rig.lock_enabled and rig.lock_target == null, "lock button turns lock off")

	# --- Hunter: pounces and latches, then gets shot off --------------------------
	if frame == 1210:
		_reset_rig(OPEN_SPOT, 0.0)
		main.zombies.clear_all()
		main.zombies.spawn_budget = 0
		main.spawn_hunter(OPEN_SPOT + Vector2(260, 0))
	if frame > 1210 and frame < 1330:
		main.hud.left_stick.output = Vector2.ZERO
	if frame == 1300:
		armor_mark = rig.armor
	if frame == 1330:
		print("  hunter state %d, latched list %d" % [main.hunter.state, rig.latched.size()])
		_check(main.hunter.is_latched(), "hunter pounces and latches on")
		_check(rig.armor < armor_mark, "latched hunter chews armor")
		main.hud.press_lock()
	if frame == 1450:
		print("  hunter active %s, cause %s" % [main.hunter.active, main.hunter.last_hit_cause])
		_check(not main.hunter.active and main.hunter.last_hit_cause == "shot", "lock shoots a latched hunter off the hull")
		_check(rig.latched.is_empty(), "hull is clear after the hunter dies")
		main.hud.press_lock()

	# --- Hunter: crushed by driving into a wall -----------------------------------
	if frame == 1460:
		_reset_rig(ROAD_WEST, PI)
		main.hunter.activate(ROAD_WEST)
		main.hunter.force_latch(rig, Vector2(30.0, 0.0))  # on the nose
		main.hud.left_stick.output = Vector2.LEFT
	if frame == 1600:
		print("  hunter active %s, cause %s" % [main.hunter.active, main.hunter.last_hit_cause])
		_check(not main.hunter.active and main.hunter.last_hit_cause == "crushed", "ramming a wall crushes a latched hunter")
		main.hud.left_stick.output = Vector2.ZERO

	# --- Outrider: hunts the parked rig and shoots it, then drops salvage ---------
	if frame == 1610:
		_reset_rig(OPEN_SPOT, 0.0)
		main.spawn_outrider(Vector2(2240, 700))
		mark = Vector2(2240, 700)
		rig.damaged.connect(func(amount: float) -> void: enemy_damage += amount)
	if frame > 1610 and frame < 2200:
		main.hud.left_stick.output = Vector2.ZERO
		rig.armor = rig.armor_max  # parked on purpose; keep it alive to observe
	if frame == 2200:
		var traveled := main.outrider.global_position.distance_to(mark)
		print("  outrider traveled %.0f px, enemy shots %d, damage dealt %.0f" % [traveled, main.bullets.enemy_shots, enemy_damage])
		_check(traveled > 200.0, "outrider drives at the player")
		_check(main.bullets.enemy_shots > 0, "outrider opens fire")
		_check(enemy_damage > 0.0, "outrider hurts the rig")
		main.outrider.take_damage(9999.0)
	if frame == 2205:
		_check(main.outrider.is_wrecked, "outrider can be wrecked")
		_check(main.pickups.get_child_count() == 1, "wrecked outrider drops salvage")
		if main.pickups.get_child_count() > 0:
			rig.global_position = (main.pickups.get_child(0) as Node2D).global_position
	if frame == 2215:
		_check(main.salvage.size() == 1, "driving over salvage collects it")

	# --- Wreck -------------------------------------------------------------------
	if frame == 2220:
		rig.take_damage(99999.0)
	if frame == 2230:
		_check(main.state == Main.State.WRECKED, "wreck ends the run")
	if frame == 2360:
		_check(main.hud.is_result_visible(), "results card shown")
		_check(main.hud.result_text().contains("Salvage lost"), "results card reports lost salvage")
		var cost_ms := (Time.get_ticks_usec() - started_usec) / 1000.0 / (frame - 30)
		print("  avg CPU cost %.2f ms/frame (headless, no rendering, this machine)" % cost_ms)
		_finish()
	return false


func _reset_rig(at: Vector2, facing: float) -> void:
	var rig := main.vehicle
	rig.global_position = at
	rig.rotation = facing
	rig.velocity = Vector2.ZERO
	rig.armor = rig.armor_max
	main.hud.left_stick.output = Vector2.ZERO
	main.hud.right_stick.output = Vector2.ZERO


func _check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + what)
	if not ok:
		failures.append(what)


func _finish() -> void:
	if failures.is_empty():
		print("SMOKE TEST PASSED")
		quit(0)
	else:
		print("SMOKE TEST FAILED: %s" % ", ".join(failures))
		quit(1)
