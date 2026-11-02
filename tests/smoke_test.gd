extends SceneTree
## Headless smoke test. Boots the main scene, fakes thumb-stick input, and
## checks that driving, steering, shooting, killing, and wrecking all work.
##
## Run:  godot --headless --fixed-fps 60 --path . -s res://tests/smoke_test.gd
## Exit code 0 = pass, 1 = fail. CI also fails on any "SCRIPT ERROR" output.

const Main := preload("res://scripts/main.gd")

var main: Main
var frame := 0
var failures: Array[String] = []
var start_pos := Vector2.ZERO
var started_usec := 0


func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	main = scene.instantiate() as Main
	root.add_child(main)


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 30:
		started_usec = Time.get_ticks_usec()

	match frame:
		10:
			start_pos = main.vehicle.global_position
			_check(main.zombies.active_count() > 0, "zombies spawned at start")
			# Face south (the clearest straight lane from spawn) and floor it.
			main.vehicle.rotation = PI / 2.0
			main.hud.left_stick.output = Vector2.DOWN
		130:
			var moved := main.vehicle.global_position.distance_to(start_pos)
			print("  drove %.0f px, speed %.0f" % [moved, main.vehicle.velocity.length()])
			_check(moved > 300.0, "vehicle drives forward")
			main.hud.left_stick.output = Vector2.RIGHT  # hard right turn
		190:
			var heading := wrapf(main.vehicle.rotation, -PI, PI)
			print("  heading after turn %.2f rad" % heading)
			_check(absf(heading) < 0.8, "vehicle steers toward the stick")
			main.hud.left_stick.output = Vector2.ZERO

	# From frame 200, aim at the nearest live zombie and hold fire.
	if frame >= 200 and frame < 2400 and main.state == Main.State.RUNNING:
		main.hud.right_stick.output = _aim_at_nearest()
		# Circle slowly so the crowd doesn't pin us.
		main.hud.left_stick.output = Vector2.RIGHT.rotated(frame * 0.01) * 0.6

	if frame == 2400:
		print("  shots %d, hits %d, kills %d, armor %.0f" % [main.bullets.shots_fired, main.bullets.hits, main.kills, main.vehicle.armor])
		_check(main.bullets.shots_fired > 20, "turret fires")
		_check(main.bullets.hits > 0, "bullets hit zombies")
		_check(main.kills > 0, "zombies die")
		_check(main.zombies.active_count() <= 28, "zombie cap respected")
		main.hud.right_stick.output = Vector2.ZERO
		if main.state == Main.State.RUNNING:
			main.vehicle.take_damage(99999.0)
	if frame == 2410:
		_check(main.state == Main.State.WRECKED or main.state == Main.State.CLEARED, "wreck ends the run")
	if frame == 2560:
		_check(main.hud.is_result_visible(), "results card shown")
		var cost_ms := (Time.get_ticks_usec() - started_usec) / 1000.0 / (frame - 30)
		print("  avg CPU cost %.2f ms/frame (headless, no rendering, this machine)" % cost_ms)
		_finish()
	return false


func _aim_at_nearest() -> Vector2:
	var best := Vector2.ZERO
	var best_d := INF
	var from := main.vehicle.global_position
	for child in main.zombies.get_children():
		if child.get("active") == true:
			var d := from.distance_to(child.global_position)
			if d < best_d:
				best_d = d
				best = (child.global_position - from).normalized()
	return best


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
