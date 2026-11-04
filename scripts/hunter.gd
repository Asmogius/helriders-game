extends "res://scripts/hostile.gd"
## Hunter: fast, leaps at the rig after a short tell, and latches onto the hull
## to chew through armor. Get it off by crushing it into a wall, scraping it
## along one, or shooting it (the turret can hit it point-blank).

signal latched_on
signal let_go

enum State { CHASE, WINDUP, POUNCE, LATCHED, RECOVER }

const Rig := preload("res://scripts/vehicle.gd")
const NavGrid := preload("res://scripts/nav_grid.gd")

const HULL_HALF := Vector2(30.0, 17.0)   # where it clings, in rig-local space

var target: Rig                           # the player's rig
var nav: NavGrid
var damage_mult := 1.0     # the skull's enemy damage (the mission sets it)
var state := State.CHASE

var _shape: CollisionShape2D
var _timer := 0.0
var _dir := Vector2.ZERO
var _latch_pos := Vector2.ZERO
var _flash := 0.0
var _knock := Vector2.ZERO
var _stuck_time := 0.0
var _detour := Vector2.ZERO
var _detour_time := 0.0
var _detour_sign := 1.0
var _anim := 0.0
var _nav_timer := 0.0
var _nav_point := Vector2.ZERO
var _ray := PhysicsRayQueryParameters2D.new()


var pinned_left := 0.0


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	lock_priority = 2
	lock_radius = 20.0
	var circle := CircleShape2D.new()
	circle.radius = T.HUNTER_RADIUS
	_shape = CollisionShape2D.new()
	_shape.shape = circle
	add_child(_shape)
	_ray.collision_mask = T.LAYER_WORLD
	deactivate()


func activate(at: Vector2) -> void:
	position = at
	hp = T.HUNTER_HP
	state = State.CHASE
	velocity = Vector2.ZERO
	_knock = Vector2.ZERO
	_detour_time = 0.0
	_nav_timer = 0.0
	_detour_sign = 1.0 if randf() < 0.5 else -1.0
	clear_status()
	active = true
	visible = true
	z_index = 0
	_set_solid(true)
	queue_redraw()


func deactivate() -> void:
	_detach()
	active = false
	visible = false
	_set_solid(false)
	position = Vector2(-10000.0, -10000.0)


func is_latched() -> bool:
	return active and state == State.LATCHED


## Test hook: start latched at a point on the hull (rig-local).
func force_latch(on: Rig, local_point: Vector2) -> void:
	target = on
	global_position = on.to_global(local_point)
	_latch()


func _set_solid(solid: bool) -> void:
	if solid:
		collision_layer = T.LAYER_ZOMBIE
		collision_mask = T.LAYER_WORLD | T.LAYER_VEHICLE | T.LAYER_ENEMY
		_shape.set_deferred("disabled", false)
	else:
		collision_layer = 0
		collision_mask = 0
		_shape.set_deferred("disabled", true)


func _physics_process(delta: float) -> void:
	if not active or target == null:
		return
	_anim += delta
	_flash = maxf(_flash - delta * 5.0, 0.0)
	tick_status(delta)
	_knock = _knock.move_toward(Vector2.ZERO, 900.0 * delta)
	match state:
		State.CHASE:
			_chase(delta)
		State.WINDUP:
			velocity = _knock
			move_and_slide()
			_timer -= delta
			_flash = 0.5 + 0.5 * sin(_anim * 40.0)  # the tell: rapid pulse
			if _timer <= 0.0:
				var lead := target.global_position + target.velocity * 0.15
				_dir = (lead - global_position).normalized()
				rotation = _dir.angle()
				state = State.POUNCE
				_timer = T.HUNTER_POUNCE_TIME
		State.POUNCE:
			velocity = _dir * T.HUNTER_POUNCE_SPEED
			move_and_slide()
			_timer -= delta
			if global_position.distance_to(target.global_position) < 46.0 and not target.is_wrecked:
				_latch()
			elif _timer <= 0.0 or _hit_world():
				state = State.RECOVER
				_timer = 0.7
		State.LATCHED:
			_hold_on(delta)
		State.RECOVER:
			velocity = velocity.move_toward(Vector2.ZERO, 1400.0 * delta) + _knock
			move_and_slide()
			_timer -= delta
			if _timer <= 0.0:
				state = State.CHASE
	queue_redraw()


func _chase(delta: float) -> void:
	var to_target := target.global_position - global_position
	var dist := to_target.length()
	_nav_timer -= delta
	if _nav_timer <= 0.0 or global_position.distance_squared_to(_nav_point) < 576.0:
		_nav_timer = 0.3
		_nav_point = target.global_position
		if nav != null:
			_nav_point = nav.next_waypoint(get_world_2d().direct_space_state, global_position, target.global_position)
	var to_point := _nav_point - global_position
	if nav == null or _nav_point.distance_squared_to(target.global_position) < 1.0:
		to_point = to_target  # in sight: go straight for it
	var desired := to_point.normalized() * T.HUNTER_SPEED * speed_mult()
	if _detour_time > 0.0:
		_detour_time -= delta
		desired = _detour * T.HUNTER_SPEED * speed_mult()
	velocity = desired + _knock
	rotation = lerp_angle(rotation, desired.angle(), 1.0 - exp(-10.0 * delta))
	move_and_slide()

	# Same wall-following trick as shamblers when a building is in the way.
	var wall := Vector2.ZERO
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		if collision.get_collider() != target:
			wall = collision.get_normal()
	if wall != Vector2.ZERO and get_real_velocity().length() < T.HUNTER_SPEED * 0.35:
		_stuck_time += delta
		if _stuck_time > 0.25 and _detour_time <= 0.0:
			_detour = wall.orthogonal() * _detour_sign
			_detour_time = randf_range(1.0, 1.8)
			_stuck_time = 0.0
	else:
		_stuck_time = 0.0

	if pinned_left > 0.0:
		pinned_left -= delta   # Pinned (Scout perk): no pounce inside the Flare
		return
	if dist < T.HUNTER_POUNCE_RANGE and not target.is_wrecked and _can_see(target.global_position):
		state = State.WINDUP
		_timer = T.HUNTER_WINDUP


func _hit_world() -> bool:
	for i in get_slide_collision_count():
		if get_slide_collision(i).get_collider() != target:
			return true
	return false


func _can_see(point: Vector2) -> bool:
	_ray.from = global_position
	_ray.to = point
	return get_world_2d().direct_space_state.intersect_ray(_ray).is_empty()


func _latch() -> void:
	# Snap onto the nearest point of the hull outline.
	var local := target.to_local(global_position)
	var sx := 1.0 if local.x >= 0.0 else -1.0
	var sy := 1.0 if local.y >= 0.0 else -1.0
	if absf(local.x) / HULL_HALF.x > absf(local.y) / HULL_HALF.y:
		local = Vector2(sx * HULL_HALF.x, clampf(local.y, -HULL_HALF.y, HULL_HALF.y))
	else:
		local = Vector2(clampf(local.x, -HULL_HALF.x, HULL_HALF.x), sy * HULL_HALF.y)
	_latch_pos = local
	state = State.LATCHED
	z_index = 3  # drawn on top of the rig
	_set_solid(false)
	var self_node: Node2D = self
	if not target.latched.has(self_node):
		target.latched.append(self_node)
	latched_on.emit()
	_follow_rig()


func _follow_rig() -> void:
	global_position = target.to_global(_latch_pos)
	rotation = (target.global_position - global_position).angle()


func _hold_on(delta: float) -> void:
	if target.is_wrecked:
		_knock_off(Vector2.RIGHT.rotated(randf() * TAU))
		return
	_follow_rig()
	target.take_damage(T.HUNTER_DPS * damage_mult * delta * float(target.get("latch_mult")), global_position - target.global_position)

	# The rig ran this tick already, so its wall contact is current.
	if target.touching_wall:
		var side := (global_position - target.global_position).normalized()
		var facing_wall := side.dot(-target.wall_normal) > 0.35
		if facing_wall and target.wall_impact > T.HUNTER_CRUSH_SPEED:
			take_hit(hp + 1.0, Vector2.ZERO, "crushed")
		elif facing_wall and target.velocity.length() > T.HUNTER_SCRAPE_SPEED:
			take_hit(T.HUNTER_SCRAPE_DPS * delta, Vector2.ZERO, "scraped")
			if randf() < 0.5:
				target.fx.call("sparks", global_position, target.wall_normal)
		elif target.wall_impact > T.HUNTER_JOLT_SPEED:
			_knock_off(side)


## Thrown off the hull (a Mechanic's Field Repair, a Bruiser's ram).
func knock_off(direction: Vector2) -> void:
	if state == State.LATCHED:
		_knock_off(direction)


func _knock_off(direction: Vector2) -> void:
	_detach()
	global_position = target.global_position + direction * 48.0
	velocity = direction * 380.0
	state = State.RECOVER
	_timer = 1.2
	z_index = 0
	_set_solid(true)


func _detach() -> void:
	if target != null:
		var self_node: Node2D = self
		if target.latched.has(self_node):
			target.latched.erase(self_node)
			let_go.emit()


func _on_hit(_damage: float, impulse: Vector2) -> void:
	_flash = 1.0
	if state != State.LATCHED:
		_knock += impulse


func _draw() -> void:
	var skin := T.COL_HUNTER.lerp(Color(1.0, 0.92, 0.88), clampf(_flash, 0.0, 1.0) * 0.7)
	var dark := T.COL_HUNTER.darkened(0.45)
	var stretch := 1.0
	if state == State.POUNCE:
		stretch = 1.35
	elif state == State.WINDUP:
		stretch = 0.8
	# Drawn a size up from its collision circle so it reads as the threat it is.
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(stretch, 1.0) * 1.3)
	draw_rect(Rect2(-14.0, -6.0, 20.0, 12.0), dark)               # lean body
	for i in 3:                                                     # spine ridge
		draw_rect(Rect2(-12.0 + i * 6.0, -1.5, 3.0, 3.0), skin.darkened(0.2))
	draw_rect(Rect2(4.0, -5.0, 9.0, 10.0), skin)                    # head
	var reach := 3.0 * sin(_anim * 14.0) if state == State.CHASE else 0.0
	draw_rect(Rect2(8.0 + reach, -10.0, 14.0, 3.0), Color(0.9, 0.86, 0.78))   # claws
	draw_rect(Rect2(8.0 - reach, 7.0, 14.0, 3.0), Color(0.9, 0.86, 0.78))
	draw_rect(Rect2(10.0, -3.0, 2.0, 2.0), Color(1.0, 0.85, 0.2))  # eyes
	draw_rect(Rect2(10.0, 1.0, 2.0, 2.0), Color(1.0, 0.85, 0.2))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if state == State.WINDUP:
		draw_arc(Vector2.ZERO, 28.0, 0.0, TAU, 24, Color(T.COL_ENEMY, 0.4 + 0.5 * _flash), 3.0)
	draw_status(24.0)
