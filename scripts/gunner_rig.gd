extends "res://scripts/enemy_rig.gd"
## Gunner Rig: standoff enemy turret rig (DESIGN §8; agreed with the owner).
## It keeps 350-550 px from you, circling, backing off when you close in and
## closing in when you pull away. A slow turret on top tracks you and fires
## bursts; drive fast across its line and the turret can't keep up. It turns
## the turret on any zombie that gets within 120 px of it, so a horde dragged
## onto it keeps it busy. In a Courier job it guards a checkpoint instead of
## roaming. Like every enemy rig it only decides stick inputs.

var guard_point := Vector2.INF   # Courier: the checkpoint it covers
var shooting_at: Node2D          # what the turret is on (tests)
var self_defense := true         # turn the turret on zombies at the door

var _threat: Node2D
var _threat_timer := 0.0
var _query := PhysicsShapeQueryParameters2D.new()
var _circle_side := 1.0


func _init() -> void:
	team = BulletPool.TEAM_ENEMY
	apply_stats(T.GUNNER)
	body_len = 74.0
	body_wid = 40.0
	lock_priority = 3
	lock_radius = 46.0
	var shape := CircleShape2D.new()
	shape.radius = T.GUNNER_SELF_DEFENSE
	_query.shape = shape
	_query.collision_mask = T.LAYER_ZOMBIE


## Pick a side when it rolls in, not when it's built: rigs are built up front,
## and rolling dice then would shift every other random spawn in the job.
func _enter_tree() -> void:
	_circle_side = 1.0 if randf() < 0.5 else -1.0


func is_guarding() -> bool:
	return guard_point != Vector2.INF


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

	var engaging := not player_down
	if is_guarding() and player.global_position.distance_to(guard_point) > T.GUNNER_GUARD_LEASH:
		engaging = false
	var goal := _steer(delta, engaging, to_player, forward)
	var throttle := goal.length()
	if goal != Vector2.ZERO:
		goal = goal.normalized()
	if mode != Mode.UNSTICK and goal != Vector2.ZERO:
		goal = _avoid_walls(goal, forward)
	drive_input = goal * throttle

	# Wedged against something: back out, and circle the other way after.
	if mode != Mode.UNSTICK and goal != Vector2.ZERO and get_real_velocity().length() < 40.0:
		_stuck_time += delta
		if _stuck_time > 0.8:
			mode = Mode.UNSTICK
			_mode_time = 0.9
			_side = 1.0 if randf() < 0.5 else -1.0
			_circle_side = -_circle_side
			_stuck_time = 0.0
	else:
		_stuck_time = 0.0
	_aim(delta, engaging, dist)


## The stick this tick: direction times throttle. Override for other drivers.
## Holds the ring around the player (or the guard post).
func _steer(_delta: float, engaging: bool, to_player: Vector2, forward: Vector2) -> Vector2:
	var dist := to_player.length()
	var goal := Vector2.ZERO
	var throttle := 1.0
	match mode:
		Mode.UNSTICK:
			goal = -forward.rotated(_side * 0.6)
			if _mode_time <= 0.0:
				mode = Mode.ATTACK
		_:
			if not engaging:
				var home := guard_point if is_guarding() else player.global_position
				var to_home := home - global_position
				if to_home.length() > (60.0 if is_guarding() else T.GUNNER_RANGE_MAX):
					goal = to_home.normalized()
					throttle = 0.6
			elif dist < T.GUNNER_RANGE_MIN:
				# Too close: pull away (a rig that's slow enough reverses).
				goal = (-to_player.normalized()).rotated(_circle_side * 0.5)
			elif dist > T.GUNNER_RANGE_MAX:
				goal = to_player.normalized().rotated(_circle_side * 0.3)
			else:
				# In the ring: circle the player at a steady clip.
				goal = to_player.normalized().rotated(_circle_side * PI * 0.5)
				throttle = 0.6
			if is_guarding() and engaging and global_position.distance_to(guard_point) > T.GUNNER_GUARD_RADIUS:
				goal = (guard_point - global_position).normalized()
				throttle = 0.8
	return goal * throttle


## Turret: zombies at the door first (if self_defense), then the player.
func _aim(delta: float, engaging: bool, dist: float) -> void:
	_threat_timer -= delta
	if _threat_timer <= 0.0:
		_threat_timer = 0.25
		_threat = _nearest_threat() if self_defense else null
	var target: Node2D = null
	if _threat != null and bool(_threat.call("is_targetable")):
		target = _threat
	elif engaging and _sees_player and dist < gun_range():
		target = player
	shooting_at = target
	fire_trigger = false
	if target == null or _turrets.is_empty() or _turrets[0] == null:
		aim_input = Vector2.ZERO
		return
	var turret := _turrets[0]
	var aim_at := _lead_point(target, bullet_speed)
	var want := (aim_at - turret.global_position).angle()
	var on_target := absf(angle_difference(turret.global_rotation, want)) < T.GUNNER_FIRE_CONE
	# A light push turns the turret; a full push fires (same rules as your stick).
	aim_input = Vector2.RIGHT.rotated(want) * (1.0 if on_target else 0.4)


## The closest zombie (or Hunter) within reach of the hull, or null.
func _nearest_threat() -> Node2D:
	_query.transform = Transform2D(0.0, global_position)
	var best: Node2D = null
	var best_d := INF
	for hit: Dictionary in get_world_2d().direct_space_state.intersect_shape(_query, 8):
		var body := hit.collider as Node2D
		if body == null or not body.has_method("is_targetable") or not bool(body.call("is_targetable")):
			continue
		var d := global_position.distance_squared_to(body.global_position)
		if d < best_d:
			best_d = d
			best = body
	return best


func _draw() -> void:
	var half_l := body_len * 0.5
	var half_w := body_wid * 0.5
	var hull := Color(0.26, 0.24, 0.2)
	if is_wrecked:
		hull = Color(0.1, 0.09, 0.085)
	elif _flash > 0.0:
		hull = hull.lerp(Color(1.0, 0.85, 0.7), _flash * 0.6)
	var tyre := Color(0.07, 0.07, 0.075)
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			draw_rect(Rect2(Vector2(sx * half_l * 0.62 - 10.0, sy * half_w - 6.0), Vector2(20.0, 12.0)), tyre)
	# Boxy armored carrier with a raised gun deck.
	draw_rect(Rect2(-half_l, -half_w + 3.0, body_len, body_wid - 6.0), hull)
	draw_rect(Rect2(half_l - 12.0, -half_w + 6.0, 12.0, body_wid - 12.0), hull.darkened(0.25))
	if is_wrecked:
		draw_rect(Rect2(-14.0, -8.0, 24.0, 16.0), Color(0.05, 0.04, 0.04))
		return
	draw_rect(Rect2(-18.0, -half_w + 7.0, 34.0, body_wid - 14.0), hull.darkened(0.15))   # gun deck
	draw_rect(Rect2(-half_l + 4.0, -half_w + 4.0, body_len - 18.0, 2.0), T.COL_ENEMY)
	draw_rect(Rect2(-half_l + 4.0, half_w - 6.0, body_len - 18.0, 2.0), T.COL_ENEMY)
	draw_rect(Rect2(-half_l - 1.0, -5.0, 3.0, 10.0), T.COL_ENEMY)
	# Ammo crates on the back.
	draw_rect(Rect2(-half_l + 4.0, -8.0, 10.0, 7.0), T.COL_RUST)
	draw_rect(Rect2(-half_l + 4.0, 1.0, 10.0, 7.0), T.COL_RUST)
	if vuln_left > 0.0:
		draw_arc(Vector2.ZERO, half_l + 8.0, 0.0, TAU, 28, Color(0.95, 0.3, 0.25, 0.85), 2.5)
