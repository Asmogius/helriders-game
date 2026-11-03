extends "res://scripts/enemy_rig.gd"
## Bulwark: heavy enemy rammer (DESIGN §8; numbers approved in the
## "Helriders: Bulwark Draft" doc). A relentless bull: it always drives at
## where you're heading, never telegraphs, and turns slowly, so you beat it by
## out-turning it and shooting its sides. After ramming you it backs off for a
## moment, then comes again. A light gun fixed forward plinks you while it
## lines up. Hits on its armored front quarter do half damage.

const BACKOFF_STEER := 0.5   # radians off straight back while reversing

var backoffs := 0            # times it rammed you and backed off (tests)
var front_hits := 0          # hits its armor blunted (tests)


func _init() -> void:
	team = BulletPool.TEAM_ENEMY
	apply_stats(T.BULWARK)
	body_len = 84.0
	body_wid = 46.0
	lock_priority = 3
	lock_radius = 50.0


func _physics_process(delta: float) -> void:
	super(delta)
	if is_wrecked or player == null or mode == Mode.UNSTICK:
		return
	# Rammed the player this tick: back off, then come again.
	for i in get_slide_collision_count():
		if get_slide_collision(i).get_collider() == player and mode != Mode.PASS:
			mode = Mode.PASS   # PASS doubles as "backing off" for the Bulwark
			_mode_time = T.BULWARK_BACKOFF
			_side = 1.0 if randf() < 0.5 else -1.0
			backoffs += 1
			break


func _think(delta: float) -> void:
	_mode_time -= delta
	var to_player := player.global_position - global_position
	var dist := to_player.length()
	var forward := Vector2.RIGHT.rotated(rotation)
	var player_down: bool = player.get("is_wrecked")

	_sight_timer -= delta
	if _sight_timer <= 0.0:
		_sight_timer = 0.2
		_sees_player = _has_los(player.global_position)

	var goal := Vector2.ZERO
	var throttle := 1.0
	match mode:
		Mode.ATTACK:
			# Aim at where the player is heading, not where they are.
			var player_vel: Vector2 = player.get("velocity")
			goal = (player.global_position + player_vel * clampf(dist / max_speed, 0.0, 0.5) - global_position).normalized()
			if player_down:
				throttle = 0.3
		Mode.PASS:
			# Backing off after a ram: stick behind us reverses a slow rig.
			goal = -forward.rotated(_side * BACKOFF_STEER)
			if _mode_time <= 0.0:
				mode = Mode.ATTACK
		Mode.UNSTICK:
			goal = -forward.rotated(_side * 0.6)
			if _mode_time <= 0.0:
				mode = Mode.ATTACK

	if mode == Mode.ATTACK:
		goal = _avoid_walls(goal, forward)
	drive_input = goal * throttle

	fire_trigger = (
		mode == Mode.ATTACK
		and not player_down
		and _sees_player
		and dist < gun_range()
		and absf(forward.angle_to(to_player)) < FIRE_CONE
	)

	# Wedged against a wall (not the player): back out.
	if mode == Mode.ATTACK and get_real_velocity().length() < 30.0 and dist > body_len:
		_stuck_time += delta
		if _stuck_time > 1.0:
			mode = Mode.UNSTICK
			_mode_time = 1.0
			_side = 1.0 if randf() < 0.5 else -1.0
			_stuck_time = 0.0
	else:
		_stuck_time = 0.0


## True if a hit coming from world point `from` lands on the armored front.
func is_front(from: Vector2) -> bool:
	var forward := Vector2.RIGHT.rotated(rotation)
	return absf(forward.angle_to(from - global_position)) < T.BULWARK_FRONT_ARC


## Bullets hitting the armored front throw grey sparks (bullet_pool.gd).
func deflects(at: Vector2) -> bool:
	return not is_wrecked and is_front(at)


func take_hit(damage: float, impulse: Vector2, cause := "shot") -> void:
	# The impulse points the way the hit travels, so it came from behind it.
	if impulse != Vector2.ZERO and is_front(global_position - impulse.normalized() * 100.0):
		damage *= T.BULWARK_FRONT_MULT
		front_hits += 1
	super(damage, impulse, cause)


func receive_ram(damage: float) -> void:
	if player != null and is_front(player.global_position):
		damage *= T.BULWARK_FRONT_MULT
		front_hits += 1
	super(damage)


func _draw() -> void:
	var half_l := body_len * 0.5
	var half_w := body_wid * 0.5
	var hull := Color(0.2, 0.21, 0.22)
	if is_wrecked:
		hull = Color(0.09, 0.085, 0.08)
	elif _flash > 0.0:
		hull = hull.lerp(Color(1.0, 0.85, 0.7), _flash * 0.6)

	# Six wheels: heavy.
	var tyre := Color(0.06, 0.06, 0.065)
	for sx: float in [-0.62, 0.0, 0.62]:
		for sy: float in [-1.0, 1.0]:
			draw_rect(Rect2(Vector2(sx * half_l - 10.0, sy * half_w - 7.0), Vector2(20.0, 14.0)), tyre)
	# Slab hull.
	draw_rect(Rect2(-half_l, -half_w + 3.0, body_len - 12.0, body_wid - 6.0), hull)
	if is_wrecked:
		draw_rect(Rect2(-14.0, -8.0, 24.0, 16.0), Color(0.05, 0.04, 0.04))
		return
	# Armor bands.
	for k in 3:
		draw_rect(Rect2(-half_l + 8.0 + k * 18.0, -half_w + 3.0, 4.0, body_wid - 6.0), hull.darkened(0.35))
	# Wide spiked plow: the armored front.
	var plow := Color(0.38, 0.33, 0.28)
	draw_colored_polygon(PackedVector2Array([
		Vector2(half_l - 14.0, -half_w - 4.0), Vector2(half_l + 2.0, -half_w + 6.0),
		Vector2(half_l + 2.0, half_w - 6.0), Vector2(half_l - 14.0, half_w + 4.0),
	]), plow)
	for k in 5:
		var y := -half_w + 4.0 + k * (body_wid - 8.0) / 4.0
		draw_colored_polygon(PackedVector2Array([Vector2(half_l + 2.0, y - 3.0), Vector2(half_l + 11.0, y), Vector2(half_l + 2.0, y + 3.0)]), Color(0.72, 0.68, 0.6))
	# The light gun, centered on the nose.
	draw_rect(Rect2(half_l - 24.0, -2.5, 26.0, 5.0), Color(0.12, 0.12, 0.13))
	if vuln_left > 0.0:
		draw_arc(Vector2.ZERO, half_l + 10.0, 0.0, TAU, 28, Color(0.95, 0.3, 0.25, 0.85), 2.5)
	# Cab, and red lights: enemies read red.
	draw_rect(Rect2(-10.0, -9.0, 22.0, 18.0), hull.darkened(0.45))
	draw_rect(Rect2(-half_l + 4.0, -half_w + 4.0, body_len - 30.0, 2.0), T.COL_ENEMY)
	draw_rect(Rect2(-half_l + 4.0, half_w - 6.0, body_len - 30.0, 2.0), T.COL_ENEMY)
	draw_rect(Rect2(-half_l - 1.0, -6.0, 3.0, 12.0), T.COL_ENEMY)
	draw_rect(Rect2(half_l - 18.0, -half_w + 2.0, 4.0, 5.0), T.COL_ENEMY)
	draw_rect(Rect2(half_l - 18.0, half_w - 7.0, 4.0, 5.0), T.COL_ENEMY)
