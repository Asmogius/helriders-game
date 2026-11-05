extends "res://tools/art/capture_step.gd"
## Escort (playtest 2): the truck off-screen and under attack: the pulsing
## edge arrow and the TRUCK UNDER ATTACK banner.

const Missions := preload("res://scripts/missions.gd")

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
	_m = (load("res://scenes/mission.tscn") as PackedScene).instantiate()
	_m.set("mission_override", Missions.make("escort", 2, 33))
	_m.set("push_override", 0)
	_m.ready.connect(func() -> void:
		_m.vehicle.armor_max = 100000.0
		_m.vehicle.armor = 100000.0
		_m.zombies.spawn_budget = 0
		_m.truck.global_position = _m.vehicle.global_position + Vector2(1500, 300)
		_m.truck.facing_armor[0] = 0.0
		_m.truck.hp = _m.truck.hp_max * 0.3
		for i in 4:
			_m.zombies.spawn_at(_m.truck.global_position + Vector2(-50 + i * 30, -60), "shambler")
		_m.truck.set_physics_process(false)
	, CONNECT_DEFERRED)
	cap.root.add_child(_m)


func wait() -> int:
	return 110


func after(_cap: SceneTree) -> void:
	_m.queue_free()
