extends Node2D
## Owns every zombie: a fixed pool (no runtime allocation), spawning off-screen,
## and one central steering loop so each zombie doesn't run its own script.
## Packs mix in Brutes, Boomers and Slimers by the job's skulls (set_mix), and
## a few Tanks per job. The director also lays Slimer trails, pops Boomers into
## bile pools (marking the rig if it's caught in the burst) and frenzies
## zombies in bile or near a marked rig.

signal zombie_killed(at: Vector2, kind: String)

const T := preload("res://scripts/tuning.gd")
const Zombie := preload("res://scripts/zombie.gd")
const NavGrid := preload("res://scripts/nav_grid.gd")
const GroundHazards := preload("res://scripts/ground_hazards.gd")
const StatusBars := preload("res://scripts/status_bars.gd")

var target: Node2D
var nav: NavGrid
var hazards: GroundHazards
var mix := {}                            # kind -> share of each pack (set_mix)
var tanks_left := 0                      # Tanks still to come this job
var alt_target: Node2D                   # Escort: the truck; each zombie goes for the nearer one
var bait: Node2D                         # a GOOPED enemy rig (proposal 01): zombies near it go for it
var bait_left := 0.0
var speed_bonus := 1.0                   # Retrieve: the horde speeds up as the danger climbs
var spawn_points: Array[Vector2] = []
var spawn_budget := T.CLEAR_SHAMBLERS   # shamblers left to spawn this mission
# Crowd shape; the mission sets these before the director enters the tree.
var cap := T.ZOMBIE_CAP                  # most alive at once (can rise mid-job up to pool_size)
var pool_size := 0                       # zombies built up front; 0 = cap
var start_count := T.ZOMBIE_START        # alive at the start
var ramp_seconds := T.ZOMBIE_RAMP_SECONDS  # +1 allowed alive every N seconds

var _pool: Array[Zombie] = []
var _active: Array[Zombie] = []
var _elapsed := 0.0
var _spawn_timer := 0.0


func _ready() -> void:
	for i in maxi(pool_size, cap):
		var zombie := Zombie.new()
		add_child(zombie)
		zombie.died.connect(_on_zombie_died.bind(zombie))
		_pool.append(zombie)
	var opening := mini(start_count, cap)
	while _active.size() < opening and spawn_budget > 0:
		_spawn_pack(opening)


## The pack mix for a job of `skulls` (T.ZOMBIE_MIX, T.TANKS_PER_MISSION).
## Courier jobs only get the kinds in T.COURIER_KINDS and no Tanks.
func set_mix(skulls: int, courier := false) -> void:
	var i := clampi(skulls, 1, T.MAX_SKULLS) - 1
	mix = {}
	for kind: String in T.ZOMBIE_MIX:
		if courier and not T.COURIER_KINDS.has(kind):
			continue
		var share := float(T.ZOMBIE_MIX[kind][i])
		if share > 0.0:
			mix[kind] = share
	tanks_left = 0 if courier else int(T.TANKS_PER_MISSION[i])


## Kind for the next zombie in a pack.
func roll_kind() -> String:
	var roll := randf()
	for kind: String in mix:
		roll -= float(mix[kind])
		if roll < 0.0:
			return kind
	return "shambler"


func count_kind(kind: String) -> int:
	var n := 0
	for zombie in _active:
		if zombie.kind == kind:
			n += 1
	return n


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
	var allowed := mini(cap, start_count + int(_elapsed / ramp_seconds))
	if _spawn_timer <= 0.0 and _active.size() < allowed and spawn_budget > 0:
		_spawn_timer = 2.5
		_spawn_pack(allowed)
	_steer(delta)


func _steer(delta: float) -> void:
	if target == null:
		return
	var player_goal := target.position
	var alt := alt_target != null and alt_target.is_inside_tree() and not bool(alt_target.get("is_wrecked"))
	var space := get_world_2d().direct_space_state
	var sep_dist := T.SHAMBLER_SEPARATION
	var sep_dist2 := sep_dist * sep_dist
	var marked := hazards != null and hazards.is_marked(target)
	var mark_range2 := T.BILE_MARK_RANGE * T.BILE_MARK_RANGE
	var count := _active.size()
	if bait_left > 0.0:
		bait_left -= delta
	var baited := bait != null and bait_left > 0.0 and is_instance_valid(bait) and bait.is_inside_tree() and not bool(bait.get("is_wrecked"))
	for a in count:
		var zombie := _active[a]
		var chase: Node2D = target
		if baited and zombie.position.distance_squared_to(bait.position) < mark_range2:
			chase = bait
		elif alt and zombie.position.distance_squared_to(alt_target.position) < zombie.position.distance_squared_to(player_goal):
			chase = alt_target
		var goal := chase.position
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
		var burning := zombie.status.active(StatusBars.FIRE)
		var touch2 := T.BURNING_TOUCH * T.BURNING_TOUCH
		for b in count:
			if a == b:
				continue
			var away := zombie.position - _active[b].position
			var d2 := away.length_squared()
			if d2 < sep_dist2 and d2 > 0.01:
				push += away * ((sep_dist2 - d2) / sep_dist2) / sqrt(d2)
			if burning and d2 < touch2:
				_active[b].add_buildup(StatusBars.FIRE, T.BURNING_SPREAD * delta)   # BURNING spreads on touch
		desired += push * zombie.speed * 0.9
		if hazards != null:
			zombie.frenzy = (marked and zombie.position.distance_squared_to(player_goal) < mark_range2) or hazards.bile_at(zombie.position) or (baited and chase == bait)
			if hazards.acid_at(zombie.position):
				zombie.add_buildup(StatusBars.ACID, T.STATUS_POOL_BUILDUP * delta)
			zombie.oiled = hazards.oil_at(zombie.position)
			if hazards.fire_at(zombie.position):
				zombie.add_buildup(StatusBars.FIRE, T.STATUS_POOL_BUILDUP * delta)
			zombie.spiked = hazards.spike_at(zombie.position)
			if zombie.kind != "slimer" and hazards.slime_at(zombie.position):
				zombie.add_buildup(StatusBars.SLIME, T.STATUS_POOL_BUILDUP * delta)
			if zombie.kind == "slimer":
				zombie.slime_timer -= delta
				if zombie.slime_timer <= 0.0:
					zombie.slime_timer = T.SLIME_DROP_EVERY
					hazards.add_slime(zombie.position, T.SLIME_RADIUS)
		zombie.step(delta, desired * speed_bonus, chase)
	# Boomers that reached the rig pop now, and burning / toxic damage lands,
	# outside the loop over _active (a death there would shift the list).
	for i in range(_active.size() - 1, -1, -1):
		var zombie := _active[i]
		if zombie.burst:
			zombie.take_hit(zombie.hp + 1.0, Vector2.ZERO, "burst")
		elif zombie.pending_damage >= 3.0:
			var dmg := zombie.pending_damage
			zombie.pending_damage = 0.0
			zombie.take_hit(dmg, Vector2.ZERO, "status")


## Spawns a pack at one off-screen point so they arrive as a mob, without
## exceeding `limit` alive or the mission's remaining budget.
func _spawn_pack(limit: int) -> void:
	if spawn_points.is_empty():
		return
	var at := pick_spawn_point()
	var size := randi_range(T.HORDE_SIZE.x, T.HORDE_SIZE.y)
	var tank := tanks_left > 0 and _elapsed >= T.TANK_EARLIEST and randf() < T.TANK_PACK_CHANCE
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
		var kind := roll_kind()
		if tank and i == 0:
			kind = "tank"
			tanks_left -= 1
		zombie.activate(at + Vector2(randf_range(-6.0, 6.0), randf_range(-6.0, 6.0)), kind)
		_active.append(zombie)
		spawn_budget -= 1


## Wake one pooled zombie of `kind` at `at`, outside the spawn budget (tests).
func spawn_at(at: Vector2, kind := "shambler") -> Zombie:
	for candidate in _pool:
		if not candidate.active:
			candidate.activate(at, kind)
			_active.append(candidate)
			return candidate
	return null


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
	if hazards != null:
		match zombie.kind:
			"boomer":
				hazards.add_bile(at)
				if target != null and target.global_position.distance_to(at) < T.BOOMER_POOL_RADIUS + 32.0:
					target.call("fill_status", StatusBars.GOOP)   # GOOPED: the mission marks the rig
			"slimer":
				hazards.add_slime(at, T.SLIME_PUDDLE_RADIUS)
	zombie_killed.emit(at, zombie.kind)
