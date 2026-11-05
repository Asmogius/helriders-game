extends SceneTree
## Headless test (playtest 06/07): the Training Run lifts the arena's grade
## and rings its zombies so a first-timer can find them; a real job keeps the
## normal look.
##
## Run:  godot --headless --fixed-fps 60 --path . -s res://tests/tutorial_readability_test.gd

const Mission := preload("res://scripts/mission.gd")
const Missions := preload("res://scripts/missions.gd")
const T := preload("res://scripts/tuning.gd")

var main: Mission
var frame := 0
var step := 0
var failures: Array[String] = []


func _initialize() -> void:
	var profile := root.get_node("Profile")
	profile.set("persist", false)
	profile.call("new_game")
	_start({"tutorial": true})


func _start(spec: Dictionary) -> void:
	if main != null:
		main.queue_free()
	main = (load("res://scenes/mission.tscn") as PackedScene).instantiate() as Mission
	main.mission_override = spec
	main.push_override = 0
	root.add_child(main)
	frame = 0


func _process(_delta: float) -> bool:
	frame += 1
	if frame != 5:
		return false
	var z: Node = main.zombies.spawn_at(main.vehicle.global_position + Vector2(300, 0), "shambler")
	if step == 0:
		var g := main.arena.modulate
		_check(g.r > 1.2 and g.g > 1.2 and g.b > 1.2, "Training Run: the arena is brightened (%s)" % str(g))
		_check(bool(z.get("highlight")), "Training Run: zombies are ringed")
		step = 1
		_start(Missions.make("clear", 1, 3))
	else:
		_check(main.arena.modulate == Color.WHITE, "a real job keeps the normal grade")
		_check(not bool(z.get("highlight")), "a real job's zombies aren't ringed")
		_finish()
	return false


func _check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + what)
	if not ok:
		failures.append(what)


func _finish() -> void:
	main.queue_free()
	if failures.is_empty():
		print("TUTORIAL READABILITY TEST PASSED")
		quit(0)
	else:
		print("TUTORIAL READABILITY TEST FAILED: %s" % ", ".join(failures))
		quit(1)
