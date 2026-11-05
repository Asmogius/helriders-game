extends "res://tools/art/capture_step.gd"
## Training Run 2/5 (playtest 06/07): the street and the four shamblers the
## "point at a zombie" tip asks for. Checks the arena and zombies read at a
## glance under the Compatibility renderer.

var _m: Node


func run(cap: SceneTree) -> void:
	if cap.strip != null:
		cap.strip.queue_free()
		cap.strip = null
	if cap.garage != null:
		cap.garage.queue_free()
		cap.garage = null
	if cap.current_scene != null:
		cap.current_scene.queue_free()
	seed(4)
	_m = (load("res://scenes/mission.tscn") as PackedScene).instantiate()
	_m.set("mission_override", {"tutorial": true})
	_m.ready.connect(func() -> void:
		_m.set("tut_step", 1), CONNECT_DEFERRED)
	cap.root.add_child(_m)


func wait() -> int:
	return 150


func after(_cap: SceneTree) -> void:
	_m.queue_free()
