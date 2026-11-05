extends "res://tools/art/capture_step.gd"
## Controller HUD: touch chrome hidden, pad glyphs on the control line.

const Missions := preload("res://scripts/missions.gd")
var _m: Node

func run(cap: SceneTree) -> void:
	if cap.strip != null:
		cap.strip.queue_free(); cap.strip = null
	if cap.garage != null:
		cap.garage.queue_free(); cap.garage = null
	if cap.current_scene != null:
		cap.current_scene.queue_free()
	var pad: Node = cap.root.get_node_or_null("Pad")
	if pad != null:
		pad.set("kbm", false)
		pad.set("joy_connected", true)
		pad.call("set_active", true)
		pad.set("last_scheme", "pad")
	_m = (load("res://scenes/mission.tscn") as PackedScene).instantiate()
	_m.set("mission_override", Missions.make("clear", 1, 7))
	_m.set("auto_spawn_specials", false)
	_m.ready.connect(func() -> void:
		_m.zombies.spawn_budget = 0
		_m.zombies.clear_all()
		_m.hud.set_lock_available(true)
		_m.hud.set_crew_wheel([{"kind":"driver","ability":"Hard Line","name":"Tess","role":"driver"}])
		var pad2: Node = cap.root.get_node_or_null("Pad")
		if pad2 != null:
			pad2.set("kbm", false)
			pad2.set("joy_connected", true)
			pad2.call("set_active", true)
			pad2.set("last_scheme", "pad")
		_m.hud._pad_badges()
		_m.set_process(false)
		_m.set_physics_process(false), CONNECT_DEFERRED)
	cap.root.add_child(_m)

func wait() -> int:
	return 90

func after(_cap: SceneTree) -> void:
	if _m != null:
		_m.queue_free(); _m = null
