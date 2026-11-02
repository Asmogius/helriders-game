extends Node2D
## Owns every zombie: a fixed pool (no runtime allocation), spawning off-screen,
## and one central steering loop so each zombie doesn't run its own script.

signal zombie_killed(at: Vector2)

const T := preload("res://scripts/tuning.gd")
const Zombie := preload("res://scripts/zombie.gd")
const NavGrid := preload("res://scripts/nav_grid.gd")

var target: Node2D
var nav: NavGrid
var spawn_points: Array[Vector2] = []
var spawn_budget := T.CLEAR_SHAMBLERS

var _pool: Array[Zombie] = []
var _active: Array[Zombie] = []
var _elapsed := 0.0
var _spawn_timer := 0.0


func _ready() -> void:
	for i in T.ZOMBIE_CAP:
		var zombie := Zombie.new()
		add_child(zombie)
		zombie.died.connect(_on_zombie_died.bind(zombie))
		_pool.append(zombie)
	while _active.size() < T.ZOMBIE_START and spawn_budget > 0:
		_spawn_pack(T.ZOMBIE_START)


func active_count() -> int:
	return _active.size()


func active_positions() -> PackedVector2Array:
	var out := PackedVector2Array()
	for zombie in _active:
		out.append(zombie.global_position)
	return out


func active_zombies() -> Array[Zombie]:
	return _active


## Shamblers still to kill: alive now plus not yet spawned.
func remaining() -> int:
	return _active.size() + spawn_budget


## Removes every live shambler without counting kills (mission end, tests).
func clear_all() -> void:
	for zombie in _active:
		zombie.deactivate()
	_active.clear()


func _physics_process(delta: float) -> void:
	_elapsed += delta
	_spawn_timer -= delta
	var allowed := mini(T.ZOMBIE_CAP, T.ZOMBIE_START + int(_elapsed / T.ZOMBIE_RAMP_SECONDS))
	if _spawn_timer <= 0.0 and _active.size() < allowed and spawn_budget > 0:
		_spawn_timer = 2.5
		_spawn_pack(allowed)
	_steer(delta)


func _steer(delta: float) -> void:
	if target == null:
		return
	var goal := target.position
	var space := get_world_2d().direct_space_state
	var sep_dist := T.SHAMBLER_SEPARATION
	var sep_dist2 := sep_dist * sep_dist
	var count := _active.size()
	for a in count:
		var zombie := _active[a]
		# Re-plan a few times a second (staggered): straight at the target when
		# it's in sight, otherwise along the nav grid around buildings.
		zombie.nav_timer -= delta
		var reached := not zombie.nav_direct and zombie.position.distance_squared_to(zombie.nav_point) < 576.0
		if nav != null and (zombie.nav_timer <= 0.0 or reached):
			zombie.nav_timer = randf_range(0.35, 0.55)
			var waypoint := nav.next_waypoint(space, zombie.position, goal)
			zombie.nav_direct = waypoint == goal
			zombie.nav_point = waypoint
		var aim := goal if zombie.nav_direct else zombie.nav_point
		var to_goal := aim - zombie.position
		var desired := Vector2.ZERO
		if to_goal.length_squared() > 400.0:
			desired = to_goal.normalized() * zombie.speed
		# Cheap O(n^2) separation; n is capped at ~28, so ~800 checks a tick.
		var push := Vector2.ZERO
		for b in count:
			if a == b:
				continue
			var away := zombie.position - _active[b].position
			var d2 := away.length_squared()
			if d2 < sep_dist2 and d2 > 0.01:
				push += away * ((sep_dist2 - d2) / sep_dist2) / sqrt(d2)
		desired += push * zombie.speed * 0.9
		zombie.step(delta, desired, target)


## Spawns a pack at one off-screen point so they arrive as a mob, without
## exceeding `limit` alive or the mission's remaining budget.
func _spawn_pack(limit: int) -> void:
	if spawn_points.is_empty():
		return
	var at := pick_spawn_point()
	var size := randi_range(T.HORDE_SIZE.x, T.HORDE_SIZE.y)
	for i in size:
		if spawn_budget <= 0 or _active.size() >= limit:
			return
		var zombie: Zombie = null
		for candidate in _pool:
			if not candidate.active:
				zombie = candidate
				break
		if zombie == null:
			return
		zombie.activate(at + Vector2(randf_range(-6.0, 6.0), randf_range(-6.0, 6.0)))
		_active.append(zombie)
		spawn_budget -= 1


func pick_spawn_point() -> Vector2:
	var from := target.position if target != null else T.WORLD_SIZE * 0.5
	var far: Array[Vector2] = []
	var best := spawn_points[0]
	for point in spawn_points:
		if point.distance_to(from) >= T.SPAWN_MIN_DISTANCE:
			far.append(point)
		if point.distance_to(from) > best.distance_to(from):
			best = point
	return far.pick_random() as Vector2 if not far.is_empty() else best


func _on_zombie_died(at: Vector2, zombie: Zombie) -> void:
	_active.erase(zombie)
	zombie_killed.emit(at)
