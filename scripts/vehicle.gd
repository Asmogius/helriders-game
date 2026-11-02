extends CharacterBody2D
## The player's rig: arcade drift handling, a free-aiming turret, ramming,
## and armor. Point the left stick where you want to go; pull it behind you
## while slow to reverse. Right stick aims, push it past halfway to fire.

signal wrecked
signal damaged(amount: float)

const T := preload("res://scripts/tuning.gd")
const Zombie := preload("res://scripts/zombie.gd")

const BODY_LEN := 64.0
const BODY_WID := 36.0
const REVERSE_ANGLE := 2.27        # ~130 degrees: stick this far behind = reverse
const AIM_DEADZONE := 0.2
const FIRE_THRESHOLD := 0.5
const RAM_MIN_SPEED := 150.0       # impact speed needed to hurt a zombie
const WALL_DAMAGE_SPEED := 300.0   # impact speed before walls hurt you

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
var fire_rate := 0.0
var bullet_damage := 0.0
var bullet_speed := 0.0
var spread := 0.0
var turret_turn_rate := 0.0

var armor := 0.0
var traction := 1.0                # Slimer trails will lower this later
var drive_input := Vector2.ZERO
var aim_input := Vector2.ZERO
var is_wrecked := false

var bullets: Node2D                # BulletPool
var fx: Node2D                     # Fx

var _turret: Node2D
var _fire_cooldown := 0.0
var _flash := 0.0
var _reversing := false
var _touching_wall := false
var _burn_timer := 0.0
var _burn_left := 0.0


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
	fire_rate = s.fire_rate
	bullet_damage = s.bullet_damage
	bullet_speed = s.bullet_speed
	spread = deg_to_rad(s.spread_deg)
	turret_turn_rate = s.turret_turn_rate
	armor = armor_max


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	collision_layer = T.LAYER_VEHICLE
	collision_mask = T.LAYER_WORLD | T.LAYER_ZOMBIE
	var capsule := CapsuleShape2D.new()
	capsule.radius = BODY_WID * 0.5
	capsule.height = BODY_LEN
	var shape := CollisionShape2D.new()
	shape.shape = capsule
	shape.rotation = PI / 2.0
	add_child(shape)
	_turret = TurretSprite.new()
	_turret.position = Vector2(-4.0, 0.0)
	add_child(_turret)


func _physics_process(delta: float) -> void:
	if is_wrecked:
		velocity = velocity.move_toward(Vector2.ZERO, 900.0 * delta)
		move_and_slide()
		_burn(delta)
		return
	_drive(delta)
	_aim_and_fire(delta)
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 5.0, 0.0)
		queue_redraw()


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
	var killed_any := false
	var already_hit: Array[Object] = []
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		var other := collision.get_collider()
		var impact := -pre_velocity.dot(collision.get_normal())
		if other is Zombie:
			var zombie := other as Zombie
			if already_hit.has(zombie) or impact < RAM_MIN_SPEED:
				continue
			already_hit.append(zombie)
			var damage := ram_damage * clampf(impact / max_speed, 0.0, 1.2)
			zombie.take_hit(damage, pre_velocity.normalized() * impact * 0.6)
			if not zombie.active:
				killed_any = true
		else:
			hit_wall = true
			# Only a fresh crash hurts; grinding along a wall doesn't.
			if impact > WALL_DAMAGE_SPEED and not _touching_wall:
				take_damage((impact - WALL_DAMAGE_SPEED) * 0.05)
	_touching_wall = hit_wall
	if killed_any and not hit_wall:
		# Plowing through a body that died shouldn't stop the rig dead.
		velocity = pre_velocity * 0.88
	else:
		# Keep only the speed we actually achieved, so pinning the rig against
		# a wall doesn't leave phantom speed in the model.
		velocity = get_real_velocity()


func _aim_and_fire(delta: float) -> void:
	_fire_cooldown = maxf(_fire_cooldown - delta, 0.0)
	var aim := aim_input.length()
	if aim < AIM_DEADZONE:
		_turret.rotation = lerp_angle(_turret.rotation, 0.0, 1.0 - exp(-4.0 * delta))
		return
	var local_target := wrapf(aim_input.angle() - rotation, -PI, PI)
	_turret.rotation = rotate_toward(_turret.rotation, local_target, turret_turn_rate * delta)
	if aim >= FIRE_THRESHOLD and _fire_cooldown <= 0.0 and bullets != null:
		_fire_cooldown = 1.0 / fire_rate
		var barrel := Vector2.RIGHT.rotated(_turret.global_rotation)
		var direction := barrel.rotated(randf_range(-spread, spread))
		var muzzle := _turret.global_position + barrel * 30.0
		bullets.fire(muzzle, direction * bullet_speed, bullet_damage)


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
	_burn_left = 6.0
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


func _draw() -> void:
	var half_l := BODY_LEN * 0.5
	var half_w := BODY_WID * 0.5
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

	draw_rect(Rect2(-half_l, -half_w + 3.0, BODY_LEN, BODY_WID - 6.0), hull)
	if is_wrecked:
		draw_rect(Rect2(-10.0, -8.0, 22.0, 16.0), Color(0.05, 0.04, 0.04))
		return
	# Cab and armor details.
	draw_rect(Rect2(-half_l + 8.0, -half_w + 7.0, 26.0, BODY_WID - 14.0), hull.darkened(0.25))
	draw_rect(Rect2(half_l - 11.0, -half_w + 2.0, 11.0, BODY_WID - 4.0), T.COL_RUST)
	draw_rect(Rect2(half_l - 4.0, -half_w + 2.0, 4.0, BODY_WID - 4.0), T.COL_RUST.darkened(0.3))
	# Practical lights: cyan edge strips, white headlights, orange tail lights.
	draw_rect(Rect2(-half_l + 6.0, -half_w + 3.0, BODY_LEN - 20.0, 2.0), T.COL_CYAN)
	draw_rect(Rect2(-half_l + 6.0, half_w - 5.0, BODY_LEN - 20.0, 2.0), T.COL_CYAN)
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
