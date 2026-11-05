extends SceneTree
## Hand-playtest bugs on 0.1.75:
##  1. A Slimer swarm pinned the rig (about 17 px in 2.5 s, stuck twice): the
##     rig must shove through a pack in front of it.
##  2. The fight kept running behind the WRECKED overlay and the HUD scrap kept
##     rising: the mission freezes once the wreck result shows.
##  3. The wreck screen named crew who weren't the just-hired ones: the free
##     Saloon hire must be the person its card shows, and the wreck lists them.
##
## Run:  godot --headless --fixed-fps 60 --path . -s res://tests/wreck_and_swarm_test.gd

const Mission := preload("res://scripts/mission.gd")
const Missions := preload("res://scripts/missions.gd")
const Saloon := preload("res://scripts/saloon.gd")

const SPOT := Vector2(1600, 1200)
const PIN_TIME := 150   # frames (2.5 s at 60 fps)
const SLOW_SPEED := 60.0   # a slow rig, well under the old ~260 px/s shove threshold
const CRAWL_SPEED := 5.0   # near stopped: the pack holds it

var main: Mission
var profile: Node
var frame := 0
var step := 0
var failures: Array[String] = []
var start := Vector2.ZERO
var hired_names: Array[String] = []
var scrap_at_result := 0.0
var zombie_pos := Vector2.ZERO
var full_speed := 0.0


## 15 Slimers (huge HP) packed ahead of a rig at SPOT; `speed` caps the rig's
## top speed (-1 = its own).
func _swarm_ahead(speed: float) -> void:
	var rig := main.vehicle
	if full_speed == 0.0:
		full_speed = rig.max_speed
	main.zombies.clear_all()
	main.zombies.spawn_budget = 0
	main.hud.left_stick.output = Vector2.ZERO
	rig.velocity = Vector2.ZERO
	rig.max_speed = full_speed if speed < 0.0 else speed
	rig.global_position = SPOT + Vector2(0, 700.0 * step)
	rig.rotation = 0.0
	rig.armor_max = 1000000.0
	rig.armor = rig.armor_max
	for row in 3:
		for col in 5:
			var z: Node2D = main.zombies.spawn_at(rig.global_position + Vector2.RIGHT * (70.0 + row * 30.0) + Vector2(0, (col - 2) * 30.0), "slimer")
			if z != null:
				z.set("hp", 1000000.0)
	start = rig.global_position


func _initialize() -> void:
	seed(20261105)
	profile = root.get_node("Profile")
	profile.set("persist", false)
	profile.call("new_game")
	# --- 3: hire the free Driver and Gunner the way the Saloon does ---
	for m: Dictionary in profile.crew.duplicate():
		profile.crew.erase(m)
	var saloon: Node = Saloon.new()
	saloon.set("profile", profile)
	for i in 2:
		var idx := int(profile.saloon.size()) + i
		var card: Dictionary = saloon.call("offer", idx)
		saloon.set("selected", idx)
		var before: int = profile.crew.size()
		var ok := bool(saloon.call("hire_selected"))
		var got: Dictionary = profile.crew[profile.crew.size() - 1] if profile.crew.size() > before else {}
		_check(ok and not got.is_empty() and str(got.name) == str(card.name) and str(got.specialty) == str(card.specialty),
			"free %s card shows the crew you get (card %s/%s, hired %s/%s)" % [str(card.role), str(card.name), str(card.specialty), str(got.get("name", "")), str(got.get("specialty", ""))])
		if not got.is_empty():
			hired_names.append(str(got.name))
	saloon.free()
	main = (load("res://scenes/mission.tscn") as PackedScene).instantiate() as Mission
	main.mission_override = Missions.make("courier", 2, 7)
	main.auto_spawn_specials = false
	main.push_override = 0
	root.add_child(main)


func _process(_delta: float) -> bool:
	frame += 1
	var rig := main.vehicle
	match step:
		0, 1, 2:  # --- 1: a pack of Slimers in front: full speed, slow, near-stopped ---
			var speed: float = [-1.0, SLOW_SPEED, CRAWL_SPEED][step]
			if frame == 5:
				_swarm_ahead(speed)
			if frame > 5:
				main.hud.left_stick.output = Vector2.RIGHT   # stick held toward the pack (full throttle)
			if frame == 5 + PIN_TIME:
				var moved := rig.global_position.distance_to(start)
				main.hud.left_stick.output = Vector2.ZERO
				match step:
					0:
						print("  full speed: rig moved %.0f px through the Slimer pack in 2.5 s" % moved)
						_check(moved > 120.0, "the rig shoves through a Slimer pack (%.0f px in 2.5 s, was ~17)" % moved)
					1:
						print("  %.0f px/s rig: moved %.0f px through the pack in 2.5 s" % [SLOW_SPEED, moved])
						_check(moved > 0.5 * SLOW_SPEED * 2.5, "a slow rig (%.0f px/s) still pushes through (%.0f px, want > %.0f)" % [SLOW_SPEED, moved, 0.5 * SLOW_SPEED * 2.5])
					2:
						print("  %.0f px/s rig: moved %.0f px against the pack in 2.5 s" % [CRAWL_SPEED, moved])
						_check(moved < 12.0, "a near-stopped rig (%.0f px/s) stays held by the pack (%.0f px)" % [CRAWL_SPEED, moved])
						rig.max_speed = full_speed
				_next()
		3:  # --- 2 and 3: wreck the rig ---
			if frame == 2:
				main.zombies.clear_all()
				var z: Node2D = main.zombies.spawn_at(rig.global_position + Vector2(300, 0), "shambler")
				z.set("hp", 1000000.0)
				rig.call("_wreck")
			if frame > 2 and main.hud.is_result_visible() and scrap_at_result == 0.0 and zombie_pos == Vector2.ZERO:
				scrap_at_result = main.scrap + 0.001
				zombie_pos = main.zombies.active_positions()[0] if main.zombies.active_count() > 0 else Vector2.INF
				var text := str(main.hud._subtitle.text)
				var all_named := true
				for n in hired_names:
					all_named = all_named and text.contains(n)
				_check(not hired_names.is_empty() and all_named, "the wreck screen names the crew just hired %s" % str(hired_names))
				_check(get_paused(), "the fight is paused behind the WRECKED overlay")
				main.call("_add_kill", 50)
				_check(main.scrap + 0.001 <= scrap_at_result, "no scrap is added after the wreck")
				frame = 1000
			if frame == 1060:
				var now := main.zombies.active_positions()[0] if main.zombies.active_count() > 0 else Vector2.INF
				_check(now == zombie_pos, "zombies stand still behind the overlay")
				_check(main.hud._overlay.process_mode == Node.PROCESS_MODE_ALWAYS and main.hud._overlay.modulate.a > 0.99, "the result overlay fades in and keeps running while paused")
				_finish()
			if frame == 900:
				_check(false, "the wreck result never showed")
				_finish()
	return false


func get_paused() -> bool:
	return paused


func _next() -> void:
	frame = 0
	step += 1


func _finish() -> void:
	paused = false
	if failures.is_empty():
		print("WRECK AND SWARM TEST PASSED")
		quit(0)
	else:
		for f in failures:
			print("TEST FAILED: " + f)
		quit(1)


func _check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + what)
	if not ok:
		failures.append(what)
