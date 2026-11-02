extends CharacterBody2D
## A rig: arcade drift handling, weapons, ramming, armor. The player's rig and
## enemy rigs share this script; enemy_rig.gd extends it with an AI brain.
##
## Driving: point the left stick where you want to go; pull it behind you while
## slow to reverse. Turret rigs aim with the right stick (push past halfway to
## fire) or, with lock on, aim and fire at the locked target by themselves.

signal wrecked
signal damaged(amount: float)

const T := preload("res://scripts/tuning.gd")
const Hostile := preload("res://scripts/hostile.gd")
const BulletPool := preload("res://scripts/bullet_pool.gd")

enum Mount { TURRET, FIXED }

const REVERSE_ANGLE := 2.27        # ~130 degrees: stick this far behind = reverse
const AIM_DEADZONE := 0.2
const FIRE_THRESHOLD := 0.5
const RAM_MIN_SPEED := 150.0       # impact speed needed to hurt anything
const WALL_DAMAGE_SPEED := 300.0   # impact speed before walls hurt you
const LOCK_FIRE_CONE := 0.15       # radians: turret must be this close to fire on lock

var body_len := 64.0
var body_wid := 36.0

# Final stats (filled from a stats dictionary, see apply_stats).
var max_speed := 0.0
var reverse_speed := 0.0
var acceleration := 0.0
var brake := 0.0
var coast := 0.0
var turn_rate := 0.0
var grip := 0.0
var armor_max := 0.0
var ram_damage := 0.0
var mount := Mount.TURRET
var fire_rate := 0.0
var bullet_damage := 0.0
var bullet_speed := 0.0
var spread := 0.0
var turret_turn_rate := 0.0
var lock_range := 0.0

var team := BulletPool.TEAM_PLAYER
var armor := 0.0
var traction := 1.0                # Slimer trails will lower this later
var is_wrecked := false
var lock_priority := 3             # when someone else locks onto this rig
var lock_radius := 40.0

# Inputs, set every tick by the player (main.gd) or the AI (enemy_rig.gd).
var drive_input := Vector2.ZERO
var aim_input := Vector2.ZERO
var fire_trigger := false          # fixed-mount weapons
var lock_enabled := false:
	set(value):
		lock_enabled = value
		if not value:
			lock_target = null
var lock_target: Node2D = null
var lock_candidates := Callable()  # returns Array[Node2D] of things to lock onto

# Wall contact this tick, read by Hunters clinging to the hull.
var touching_wall := false
var wall_normal := Vector2.ZERO
var wall_impact := 0.0             # crash speed of a fresh impact this tick, else 0
var latched: Array[Node2D] = []    # Hunters on the hull

var bullets: Node2D                # BulletPool
var fx: Node2D                     # Fx

var _turret: Node2D
var _fire_cooldown := 0.0
var _flash := 0.0
var _reversing := false
var _burn_timer := 0.0
var _burn_left := 0.0
var _barrel_side := 1.0
var _lock_check := 0.0
var _lock_blind := 0.0
var _ray := PhysicsRayQueryParameters2D.new()


func _init() -> void:
	apply_stats(T.STARTER_RIG)


func apply_stats(s: Dictionary) -> void:
	max_speed = s.max_speed
	reverse_speed = s.reverse_speed
	acceleration = s.acceleration
	brake = s.brake
	coast = s.coast
	turn_rate = s.turn_rate
	grip = s.grip
	armor_max = s.armor
	ram_damage = s.ram_damage
	mount = s.mount
	fire_rate = s.fire_rate
	bullet_damage = s.bullet_damage
	bullet_speed = s.bullet_speed
	spread = deg_to_rad(s.spread_deg)
	turret_turn_rate = s.turret_turn_rate
	lock_range = s.lock_range
	armor = armor_max


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	if team == BulletPool.TEAM_PLAYER:
		collision_layer = T.LAYER_VEHICLE
		collision_mask = T.LAYER_WORLD | T.LAYER_ZOMBIE | T.LAYER_ENEMY
	else:
		collision_layer = T.LAYER_ENEMY
		collision_mask = T.LAYER_WORLD | T.LAYER_ZOMBIE | T.LAYER_VEHICLE | T.LAYER_ENEMY
	_ray.collision_mask = T.LAYER_WORLD
	var capsule := CapsuleShape2D.new()
	capsule.radius = body_wid * 0.5
	capsule.height = body_len
	var shape := CollisionShape2D.new()
	shape.shape = capsule
	shape.rotation = PI / 2.0
	add_child(shape)
	if mount == Mount.TURRET:
		_turret = TurretSprite.new()
		_turret.position = Vector2(-4.0, 0.0)
		add_child(_turret)


func is_targetable() -> bool:
	return not is_wrecked and is_inside_tree()


func gun_range() -> float:
	return bullet_speed * BulletPool.LIFETIME


func _physics_process(delta: float) -> void:
	if is_wrecked:
		velocity = velocity.move_toward(Vector2.ZERO, 900.0 * delta)
		move_and_slide()
		touching_wall = false
		wall_impact = 0.0
		_burn(delta)
		return
	_drive(delta)
	_update_lock(delta)
	_weapons(delta)
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 5.0, 0.0)
		queue_redraw()


# --- Driving -------------------------------------------------------------------

func _drive(delta: float) -> void:
	var forward := Vector2.RIGHT.rotated(rotation)
	var fwd_speed := velocity.dot(forward)
	var stick := drive_input.length()
	var throttle := 0.0

	if stick > 0.0:
		var desired := drive_input.angle()
		var diff := wrapf(desired - rotation, -PI, PI)
		if absf(diff) > REVERSE_ANGLE and (fwd_speed < max_speed * 0.2 or _reversing):
			# Stick points behind us and we're slow: back up, steering the tail.
			_reversing = true
			diff = wrapf(desired + PI - rotation, -PI, PI)
			throttle = -stick
		else:
			_reversing = false
			# Ease off the gas while turning hard; that's where drifts come from.
			throttle = stick * clampf(0.35 + 0.65 * cos(diff), 0.15, 1.0)
		var authority := clampf(absf(fwd_speed) / (max_speed * 0.3), 0.3, 1.0)
		var max_turn := turn_rate * authority * delta
		rotation += clampf(diff, -max_turn, max_turn)
	else:
		_reversing = false

	# Re-project velocity onto the new heading. Leftover sideways speed is the
	# drift, and grip decides how quickly it dies.
	forward = Vector2.RIGHT.rotated(rotation)
	var side := forward.orthogonal()
	fwd_speed = velocity.dot(forward)
	var side_speed := velocity.dot(side)

	if throttle > 0.0:
		var target := throttle * max_speed
		var rate := acceleration if fwd_speed < target else coast
		if fwd_speed < 0.0:
			rate = brake
		fwd_speed = move_toward(fwd_speed, target, rate * delta)
	elif throttle < 0.0:
		var rate := brake if fwd_speed > 0.0 else acceleration
		fwd_speed = move_toward(fwd_speed, throttle * reverse_speed, rate * delta)
	else:
		fwd_speed = move_toward(fwd_speed, 0.0, coast * delta)

	side_speed *= exp(-grip * traction * delta)
	velocity = forward * fwd_speed + side * side_speed

	var pre_velocity := velocity
	move_and_slide()
	_resolve_collisions(pre_velocity)


func _resolve_collisions(pre_velocity: Vector2) -> void:
	var hit_wall := false
	var plowed_through := false
	var already_hit: Array[Object] = []
	var normal := Vector2.ZERO
	var impact_max := 0.0
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		var other := collision.get_collider()
		var impact := -pre_velocity.dot(collision.get_normal())
		if other is Hostile:
			var hostile := other as Hostile
			if already_hit.has(hostile) or impact < RAM_MIN_SPEED:
				continue
			already_hit.append(hostile)
			var damage := ram_damage * clampf(impact / max_speed, 0.0, 1.2)
			hostile.take_hit(damage, pre_velocity.normalized() * impact * 0.6, "rammed")
			if not hostile.active:
				plowed_through = true
		elif other != null and other.has_method("receive_ram"):
			# Another rig. Hit it hard enough and it hurts; it'll hit back from its side.
			if already_hit.has(other) or impact < RAM_MIN_SPEED:
				continue
			already_hit.append(other)
			other.call("receive_ram", ram_damage * clampf(impact / max_speed, 0.0, 1.2))
		else:
			hit_wall = true
			normal = collision.get_normal()
			impact_max = maxf(impact_max, impact)

	# Only a fresh crash counts as an impact; grinding along a wall doesn't.
	wall_impact = impact_max if hit_wall and not touching_wall else 0.0
	if wall_impact > WALL_DAMAGE_SPEED:
		take_damage((wall_impact - WALL_DAMAGE_SPEED) * 0.05)
	touching_wall = hit_wall
	wall_normal = normal

	if plowed_through and not hit_wall:
		# Plowing through a body that died shouldn't stop the rig dead.
		velocity = pre_velocity * 0.88
	else:
		# Keep only the speed we actually achieved, so pinning the rig against
		# a wall doesn't leave phantom speed in the model.
		velocity = get_real_velocity()


# --- Lock-on -------------------------------------------------------------------

func _update_lock(delta: float) -> void:
	if not lock_enabled or lock_range <= 0.0 or not lock_candidates.is_valid():
		lock_target = null
		return
	if lock_target != null and not _lock_still_valid(lock_target):
		lock_target = null
	if lock_target != null:
		# Drop a target we've lost sight of for a moment.
		_lock_blind = 0.0 if _has_los(lock_target.global_position) else _lock_blind + delta
		if _lock_blind > 0.5:
			lock_target = null
	_lock_check -= delta
	if lock_target == null or _lock_check <= 0.0:
		_lock_check = 0.25
		var best := _best_lock_target()
		# Only switch if nothing locked yet or something more dangerous showed up.
		if best != null and (lock_target == null or _priority_of(best) > _priority_of(lock_target)):
			lock_target = best
			_lock_blind = 0.0


func _lock_still_valid(target: Node2D) -> bool:
	if not is_instance_valid(target) or not target.call("is_targetable"):
		return false
	return global_position.distance_to(target.global_position) <= lock_range * 1.15


func _priority_of(target: Node2D) -> int:
	if latched.has(target):
		return 10  # a Hunter on the hull beats everything
	return int(target.get("lock_priority"))


func _best_lock_target() -> Node2D:
	var candidates: Array = lock_candidates.call()
	var best: Node2D = null
	var best_score := -INF
	var checks := 0
	# Score: priority first, then distance. Check line of sight on the best few.
	candidates.sort_custom(func(a: Node2D, b: Node2D) -> bool:
		return _score(a) > _score(b))
	for c: Node2D in candidates:
		if global_position.distance_to(c.global_position) > lock_range:
			continue
		if not c.call("is_targetable"):
			continue
		if checks >= 4:
			break
		checks += 1
		if _has_los(c.global_position):
			var s := _score(c)
			if s > best_score:
				best_score = s
				best = c
	return best


func _score(c: Node2D) -> float:
	return _priority_of(c) * 10000.0 - global_position.distance_to(c.global_position)


func _has_los(to: Vector2) -> bool:
	_ray.from = global_position
	_ray.to = to
	return get_world_2d().direct_space_state.intersect_ray(_ray).is_empty()


# --- Weapons -------------------------------------------------------------------

func _weapons(delta: float) -> void:
	_fire_cooldown = maxf(_fire_cooldown - delta, 0.0)
	if bullets == null:
		return
	var wants_fire := false
	var direction := Vector2.RIGHT.rotated(rotation)
	var muzzle := global_position + direction * (body_len * 0.25)

	if mount == Mount.TURRET:
		var manual := aim_input.length() >= AIM_DEADZONE
		var locked := lock_target != null
		var want_angle := 0.0
		if manual:
			want_angle = aim_input.angle()
		elif locked:
			want_angle = (_lead_point(lock_target) - _turret.global_position).angle()
		if manual or locked:
			_turret.rotation = rotate_toward(_turret.rotation, wrapf(want_angle - rotation, -PI, PI), turret_turn_rate * delta)
		else:
			_turret.rotation = lerp_angle(_turret.rotation, 0.0, 1.0 - exp(-4.0 * delta))
		direction = Vector2.RIGHT.rotated(_turret.global_rotation)
		# Rays start at the turret pivot, not the muzzle tip, so a zombie
		# pressed against the hull is still in the line of fire.
		muzzle = _turret.global_position
		if manual:
			wants_fire = aim_input.length() >= FIRE_THRESHOLD
		elif locked:
			wants_fire = absf(angle_difference(_turret.global_rotation, want_angle)) < LOCK_FIRE_CONE
	else:
		wants_fire = fire_trigger
		# Twin fixed guns alternate barrels.
		muzzle += direction.orthogonal() * 9.0 * _barrel_side

	if wants_fire and _fire_cooldown <= 0.0:
		_fire_cooldown = 1.0 / fire_rate
		_barrel_side = -_barrel_side
		_shoot(muzzle, direction)


func _lead_point(target: Node2D) -> Vector2:
	var at := target.global_position
	if latched.has(target):
		return at
	var vel: Vector2 = target.get("velocity")
	var t := clampf(global_position.distance_to(at) / bullet_speed, 0.0, 0.5)
	return at + vel * t


func _shoot(muzzle: Vector2, direction: Vector2) -> void:
	# A Hunter clinging to the hull is too close for a bullet to travel:
	# if the gun is pointing at it, it's a point-blank hit.
	for h in latched:
		var to_h := h.global_position - global_position
		if absf(direction.angle_to(to_h)) < 0.6:
			h.call("take_hit", bullet_damage, Vector2.ZERO, "shot")
			if fx != null:
				fx.sparks(h.global_position, -to_h.normalized())
			bullets.record_direct_hit()
			return
	var dir := direction.rotated(randf_range(-spread, spread))
	bullets.fire(muzzle, dir * bullet_speed, bullet_damage, team)


# --- Damage ----------------------------------------------------------------------

func take_hit(damage: float, impulse: Vector2, _cause := "shot") -> void:
	if not is_wrecked:
		velocity += impulse * 0.15
	take_damage(damage)


func receive_ram(damage: float) -> void:
	take_damage(damage)


func take_damage(amount: float) -> void:
	if is_wrecked or amount <= 0.0:
		return
	armor -= amount
	if amount >= 2.0:
		_flash = 1.0
		queue_redraw()
	damaged.emit(amount)
	if armor <= 0.0:
		armor = 0.0
		_wreck()


func _wreck() -> void:
	is_wrecked = true
	lock_target = null
	_burn_left = 6.0
	if _turret != null:
		_turret.visible = false
	queue_redraw()
	if fx != null:
		fx.explosion(global_position, velocity)
	wrecked.emit()


func _burn(delta: float) -> void:
	if _burn_left <= 0.0 or fx == null:
		return
	_burn_left -= delta
	_burn_timer -= delta
	if _burn_timer <= 0.0:
		_burn_timer = 0.06
		var jitter := Vector2(randf_range(-22.0, 22.0), randf_range(-12.0, 12.0)).rotated(rotation)
		fx.flame(global_position + jitter)


# --- Look ----------------------------------------------------------------------

func _draw() -> void:
	var half_l := body_len * 0.5
	var half_w := body_wid * 0.5
	var hull := T.COL_STEEL
	if is_wrecked:
		hull = Color(0.11, 0.1, 0.095)
	elif _flash > 0.0:
		hull = hull.lerp(Color(1.0, 0.85, 0.7), _flash * 0.6)

	# Wheels first so the hull overlaps them.
	var tyre := Color(0.07, 0.07, 0.075)
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			draw_rect(Rect2(Vector2(sx * half_l * 0.55 - 8.0, sy * half_w - 5.0), Vector2(16.0, 10.0)), tyre)

	draw_rect(Rect2(-half_l, -half_w + 3.0, body_len, body_wid - 6.0), hull)
	if is_wrecked:
		draw_rect(Rect2(-10.0, -8.0, 22.0, 16.0), Color(0.05, 0.04, 0.04))
		return
	# Cab and armor details.
	draw_rect(Rect2(-half_l + 8.0, -half_w + 7.0, 26.0, body_wid - 14.0), hull.darkened(0.25))
	draw_rect(Rect2(half_l - 11.0, -half_w + 2.0, 11.0, body_wid - 4.0), T.COL_RUST)
	draw_rect(Rect2(half_l - 4.0, -half_w + 2.0, 4.0, body_wid - 4.0), T.COL_RUST.darkened(0.3))
	# Practical lights: cyan edge strips, white headlights, orange tail lights.
	draw_rect(Rect2(-half_l + 6.0, -half_w + 3.0, body_len - 20.0, 2.0), T.COL_CYAN)
	draw_rect(Rect2(-half_l + 6.0, half_w - 5.0, body_len - 20.0, 2.0), T.COL_CYAN)
	draw_rect(Rect2(half_l - 2.0, -half_w + 5.0, 3.0, 6.0), Color(1.0, 0.96, 0.82))
	draw_rect(Rect2(half_l - 2.0, half_w - 11.0, 3.0, 6.0), Color(1.0, 0.96, 0.82))
	draw_rect(Rect2(-half_l - 1.0, -half_w + 5.0, 3.0, 6.0), T.COL_ORANGE)
	draw_rect(Rect2(-half_l - 1.0, half_w - 11.0, 3.0, 6.0), T.COL_ORANGE)


class TurretSprite extends Node2D:
	const T := preload("res://scripts/tuning.gd")

	func _draw() -> void:
		draw_rect(Rect2(0.0, -3.0, 30.0, 6.0), Color(0.18, 0.18, 0.19))
		draw_rect(Rect2(26.0, -3.0, 4.0, 6.0), T.COL_ORANGE)
		draw_circle(Vector2.ZERO, 11.0, Color(0.22, 0.225, 0.235))
		draw_arc(Vector2.ZERO, 11.0, 0.0, TAU, 20, T.COL_CYAN, 2.0)
		draw_rect(Rect2(-4.0, -4.0, 8.0, 8.0), Color(0.14, 0.14, 0.15))
