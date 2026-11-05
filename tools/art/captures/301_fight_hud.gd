extends "res://tools/art/capture_step.gd"
## Playtest #4: HP, PWR, status and mission title each have their own space.

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
	_m.set("mission_override", Missions.make("escort", 1, 7))
	_m.set("auto_spawn_specials", false)
	_m.ready.connect(func() -> void:
		_m.zombies.spawn_budget = 0
		_m.zombies.clear_all()
		var hud: Node = _m.hud
		hud.set_lock_available(true)
		var kinds: Array[String] = ["overcharge", "hard_line", "spikes"]
		hud.set_abilities(kinds)
		hud.set_status_text("ESCORT  SITE 1 / 2     DRIVING     TRUCK 100%     SCRAP  0")
		hud.set_power(100.0, 100.0)
		hud.banner("ESCORT - SALVAGE CREW", T.COL_UI_ACCENT, 8.0)
		_m.set_process(false)
		_m.set_physics_process(false), CONNECT_DEFERRED)
	cap.root.add_child(_m)


func wait() -> int:
	return 90


func after(_cap: SceneTree) -> void:
	if _m != null:
		_m.queue_free()
		_m = null
