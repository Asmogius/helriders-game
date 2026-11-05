extends Node
## Quickplay QP6: placeable spawner runtime. Triggers (Cameron v1):
## level_start, player_radius, spawner_cleared. Caps at LevelData.MAX_SPAWNERS.
## Zombies via ZombieDirector.spawn_at; rigs via mission.spawn_*. No combat-loop
## alloc beyond waking pooled actors. Campaign missions leave this unused.

const LevelData := preload("res://scripts/quickplay/level_data.gd")
const Registry := preload("res://scripts/quickplay/placeable_registry.gd")

signal spawner_cleared(key: String)
signal unit_spawned(kind: String, at: Vector2, from_key: String)

var zombies: Node2D = null          # ZombieDirector
var mission: Node = null            # Mission (for spawn_*)
var player: Node2D = null
var max_spawners := LevelData.MAX_SPAWNERS

## [{key, placeable_id, pos, data, emitted, timer, armed, done}]
var _spawners: Array = []
var _started := false


## Build from a sanitized level's placeables. Extra spawners beyond the cap are ignored.
func setup_from_placeables(placeables: Array) -> void:
	_spawners.clear()
	_started = false
	var n := 0
	for i in placeables.size():
		if n >= max_spawners:
			break
		var raw: Variant = placeables[i]
		if not raw is Dictionary:
			continue
		var p: Dictionary = raw
		var pid := str(p.get("id", ""))
		if not Registry.is_spawner(pid):
			continue
		var key := str(p.get("key", ""))
		if key == "":
			key = "spawner_%d" % i
		var data: Dictionary = p.get("data", {}) if p.get("data", {}) is Dictionary else {}
		var pos := LevelData.arr_to_vec2(p.get("pos", [0, 0]), Vector2.ZERO)
		_spawners.append({
			"key": key,
			"placeable_id": pid,
			"pos": pos,
			"data": data.duplicate(true),
			"emitted": 0,
			"timer": 0.0,
			"armed": false,
			"done": false,
		})
		n += 1


func spawner_count() -> int:
	return _spawners.size()


func keys() -> Array[String]:
	var out: Array[String] = []
	for s: Dictionary in _spawners:
		out.append(str(s.key))
	return out


func zombie_spawn_points() -> Array[Vector2]:
	var pts: Array[Vector2] = []
	for s: Dictionary in _spawners:
		if str(s.placeable_id) == "spawner_zombie":
			pts.append(s.pos as Vector2)
	return pts


func start() -> void:
	if not spawner_cleared.is_connected(_on_cleared):
		spawner_cleared.connect(_on_cleared)
	_started = true
	for s: Dictionary in _spawners:
		s.emitted = 0
		s.timer = 0.0
		s.done = false
		s.armed = str(s.data.get("trigger", "level_start")) == "level_start"
		if s.armed:
			# Fire the first unit immediately on level start.
			s.timer = 0.0


func stop() -> void:
	_started = false


func _physics_process(delta: float) -> void:
	if not _started:
		return
	_tick(delta)


## Tests call this directly without relying on the tree physics tick.
func _tick(delta: float) -> void:
	_update_arms()
	for s: Dictionary in _spawners:
		if s.done or not s.armed:
			continue
		s.timer = float(s.timer) - delta
		if float(s.timer) > 0.0:
			continue
		if not _try_spawn(s):
			# Cap / pool empty: retry next tick without burning a count.
			s.timer = 0.05
			continue
		var rate := maxf(float(s.data.get("rate", 2.5)), 0.1)
		s.timer = rate
		var count := int(s.data.get("count", 0))
		if count > 0 and int(s.emitted) >= count:
			s.done = true
			s.armed = false
			spawner_cleared.emit(str(s.key))


func _update_arms() -> void:
	for s: Dictionary in _spawners:
		if s.done or s.armed:
			continue
		var trigger := str(s.data.get("trigger", "level_start"))
		match trigger:
			"player_radius":
				if player == null:
					continue
				var radius := maxf(float(s.data.get("radius", 400.0)), 0.0)
				if player.global_position.distance_to(s.pos as Vector2) <= radius:
					s.armed = true
					s.timer = 0.0
			"spawner_cleared":
				pass  # armed by _on_cleared
			_:
				s.armed = true


func _on_cleared(cleared_key: String) -> void:
	for s: Dictionary in _spawners:
		if s.done or s.armed:
			continue
		if str(s.data.get("trigger", "")) != "spawner_cleared":
			continue
		if str(s.data.get("source_spawner", "")) == cleared_key:
			s.armed = true
			s.timer = 0.0


func _try_spawn(s: Dictionary) -> bool:
	var pid := str(s.placeable_id)
	var enemy := str(s.data.get("enemy", "shambler"))
	var at: Vector2 = s.pos
	var ok := false
	if pid == "spawner_zombie":
		if zombies == null:
			return false
		var z: Variant = zombies.call("spawn_at", at, enemy)
		ok = z != null
	elif pid == "spawner_rig":
		ok = _spawn_rig(enemy, at)
	if ok:
		s.emitted = int(s.emitted) + 1
		unit_spawned.emit(enemy, at, str(s.key))
	return ok


func _spawn_rig(kind: String, at: Vector2) -> bool:
	if mission == null:
		return false
	var node: Variant = null
	match kind:
		"outrider":
			node = mission.call("spawn_outrider", at)
		"bulwark":
			node = mission.call("spawn_bulwark", at)
		"gunner":
			node = mission.call("spawn_gunner", at)
		"scrapper":
			node = mission.call("spawn_scrapper", at)
		"scrapper_gunner":
			node = mission.call("spawn_scrapper", at, true)
		"convoy":
			node = mission.call("spawn_convoy", at)
		"torcher":
			node = mission.call("spawn_torcher", at)
		"sludger":
			node = mission.call("spawn_sludger", at)
		"patcher":
			node = mission.call("spawn_patcher", at)
		_:
			return false
	return node != null
