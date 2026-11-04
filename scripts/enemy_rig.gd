extends "res://scripts/vehicle.gd"
## Outrider: light enemy flanker with twin guns fixed forward. Same driving
## model as the player's rig; this script just decides the stick inputs.
## It makes strafing passes: lines up on you, fires, overshoots, loops back.
## It rams zombies in its way and its bullets hit them too.

enum Mode { ATTACK, PASS, UNSTICK, FLANK, BREAK, WINDUP, CHARGE, RECOVER }

const FEELER_ANGLE := 0.45   # radians either side of the nose
const PASS_DISTANCE := 260.0 # start peeling off this close to the player
const FIRE_CONE := 0.22      # radians off the nose it will still shoot at

var player: Node2D            # the player's rig
var mode := Mode.ATTACK
var elite_name := ""         # set on a Hunt target; empty for a regular Outrider

var _mode_time := 0.0
var _side := 1.0
var _stuck_time := 0.0
var _sight_timer := 0.0
var _sees_player := false
var _break_to := Vector2.ZERO
var breaks := 0              # Outrider breaks (tests)
var strafes := 0             # Outrider strafe passes started (tests)


func _init() -> void:
	team = BulletPool.TEAM_ENEMY
	apply_stats(T.OUTRIDER)
	body_len = 68.0
	body_wid = 30.0
	lock_priority = 3


## Turn this rig into a named Hunt target: tougher, harder-hitting, gold-marked,
## and first in line for the player's lock after a Hunter on the hull.
func make_elite(title: String, armor_mult: float, damage_mult: float) -> void:
	if is_elite():
		return   # once only: the multipliers don't stack
	# Any rig type: scale every defense layer of its own sheet (§14) -- HP,
	# each facing, the shield (also one that only comes up at higher skulls) --
	# and the damage of every gun and its ram.
	_base_hp *= armor_mult
	for i in 4:
		_base_facings[i] *= armor_mult
	_sheet_shield *= armor_mult
	shield_max *= armor_mult
	_apply_armor_mods()
	hp = hp_max
	for i in 4:
		facing_armor[i] = facing_max[i]
	shield = shield_max
	bullet_damage *= damage_mult
	for w in gun_stats:
		w.bullet_damage = float(w.bullet_damage) * damage_mult
		if w.has("zombie_damage"):
			w.zombie_damage = float(w.zombie_damage) * damage_mult
	ram_damage *= damage_mult
	elite_name = title
	lock_priority = 4
	if _flanker():
		lock_radius = 46.0
		body_len = 74.0
		body_wid = 32.0
	else:
		lock_radius *= 1.1
	if is_inside_tree():
		queue_redraw()


func is_elite() -> bool:
	return elite_name != ""


func _physics_process(delta: float) -> void:
	if not is_wrecked and player != null:
		_think(delta)
	super(delta)


## The plain Outrider (and a Hunt elite) flanks and breaks (proposal 01
## §1.1); rigs built on this script keep their own _think.
func _flanker() -> bool:
	return get_script() == preload("res://scripts/enemy_rig.gd")


func _think(delta: float) -> void:
	if _flanker():
		_think_flank(delta)
		return
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
			var player_vel: Vector2 = player.get("velocity")
			var lead := player.global_position + player_vel * clampf(dist / bullet_speed, 0.0, 0.6)
			goal = (lead - global_position).normalized()
			if player_down:
				throttle = 0.35  # circle the wreck
			elif dist < PASS_DISTANCE:
				# Close enough: peel off to one side and come around for another
				# run. It's a flanker, not a rammer; that's the Bulwark's job.
				mode = Mode.PASS
				_mode_time = randf_range(0.9, 1.4)
				_side = 1.0 if forward.cross(to_player) < 0.0 else -1.0
		Mode.PASS:
			goal = forward.rotated(_side * 1.0)
			if _mode_time <= 0.0:
				mode = Mode.ATTACK
		Mode.UNSTICK:
			# Pointing the stick behind a slow rig makes it reverse.
			goal = -forward.rotated(_side * 0.6)
			if _mode_time <= 0.0:
				mode = Mode.ATTACK

	if mode != Mode.UNSTICK:
		goal = _avoid_walls(goal, forward)
	drive_input = goal * throttle

	fire_trigger = (
		mode != Mode.UNSTICK
		and not player_down
		and _sees_player
		and dist < gun_range()
		and absf(forward.angle_to(to_player)) < FIRE_CONE
	)

	# Wedged against something: back out.
	if mode != Mode.UNSTICK and get_real_velocity().length() < 40.0:
		_stuck_time += delta
		if _stuck_time > 0.8:
			mode = Mode.UNSTICK
			_mode_time = 0.9
			_side = 1.0 if randf() < 0.5 else -1.0
			_stuck_time = 0.0
	else:
		_stuck_time = 0.0


## Two feelers off the nose; steer away from whichever one touches a wall.
func _avoid_walls(goal: Vector2, forward: Vector2) -> Vector2:
	var reach := 90.0 + velocity.length() * 0.35
	var space := get_world_2d().direct_space_state
	var steer := 0.0
	for s: float in [-1.0, 1.0]:
		_ray.from = global_position
		_ray.to = global_position + forward.rotated(s * FEELER_ANGLE) * reach
		if not space.intersect_ray(_ray).is_empty():
			steer -= s
	if steer == 0.0:
		return goal
	return forward.rotated(steer * 1.1)


func _draw() -> void:
	var half_l := body_len * 0.5
	var half_w := body_wid * 0.5
	var hull := Color(0.3, 0.2, 0.16)
	if is_wrecked:
		hull = Color(0.1, 0.09, 0.085)
	elif _flash > 0.0:
		hull = hull.lerp(Color(1.0, 0.85, 0.7), _flash * 0.6)

	var tyre := Color(0.07, 0.07, 0.075)
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			draw_rect(Rect2(Vector2(sx * half_l * 0.6 - 9.0, sy * half_w - 5.0), Vector2(18.0, 10.0)), tyre)
	# Long, low wedge.
	draw_colored_polygon(PackedVector2Array([
		Vector2(-half_l, -half_w + 2.0), Vector2(half_l - 10.0, -half_w + 4.0),
		Vector2(half_l, 0.0), Vector2(half_l - 10.0, half_w - 4.0), Vector2(-half_l, half_w - 2.0),
	]), hull)
	if is_wrecked:
		draw_rect(Rect2(-12.0, -6.0, 20.0, 12.0), Color(0.05, 0.04, 0.04))
		return
	# Twin guns on the nose.
	draw_rect(Rect2(half_l - 16.0, -11.0, 22.0, 4.0), Color(0.15, 0.15, 0.16))
	draw_rect(Rect2(half_l - 16.0, 7.0, 22.0, 4.0), Color(0.15, 0.15, 0.16))
	# Cockpit and red running lights: enemies read red, the player reads cyan.
	draw_rect(Rect2(-8.0, -6.0, 18.0, 12.0), hull.darkened(0.35))
	draw_rect(Rect2(-half_l + 4.0, -half_w + 3.0, body_len - 22.0, 2.0), T.COL_ENEMY)
	draw_rect(Rect2(-half_l + 4.0, half_w - 5.0, body_len - 22.0, 2.0), T.COL_ENEMY)
	draw_rect(Rect2(-half_l - 1.0, -4.0, 3.0, 8.0), T.COL_ENEMY)
	if vuln_left > 0.0:
		draw_arc(Vector2.ZERO, half_l + 8.0, 0.0, TAU, 28, Color(0.95, 0.3, 0.25, 0.85), 2.5)
	# A Hunt target wears gold: a stripe down the spine and a nose chevron.
	if is_elite():
		draw_rect(Rect2(-half_l + 2.0, -2.0, body_len - 14.0, 4.0), T.COL_ELITE)
		draw_colored_polygon(PackedVector2Array([Vector2(half_l - 22.0, -6.0), Vector2(half_l - 12.0, 0.0), Vector2(half_l - 22.0, 6.0)]), T.COL_ELITE)
	# Spikes along the flanks.
	for i in 3:
		var x := -half_l + 14.0 + i * 14.0
		draw_colored_polygon(PackedVector2Array([Vector2(x, -half_w + 1.0), Vector2(x + 6.0, -half_w - 6.0), Vector2(x + 8.0, -half_w + 1.0)]), T.COL_RUST)
		draw_colored_polygon(PackedVector2Array([Vector2(x, half_w - 1.0), Vector2(x + 6.0, half_w + 6.0), Vector2(x + 8.0, half_w - 1.0)]), T.COL_RUST)


# --- Outrider: flank, strafe, break ---------------------------------------------------

func _think_flank(delta: float) -> void:
	_mode_time -= delta
	var to_player := player.global_position - global_position
	var dist := to_player.length()
	var forward := Vector2.RIGHT.rotated(rotation)
	var player_down: bool = player.get("is_wrecked")
	_sight_timer -= delta
	if _sight_timer <= 0.0:
		_sight_timer = 0.2
		_sees_player = _has_los(player.global_position)
	if mode == Mode.ATTACK or mode == Mode.PASS:
		mode = Mode.FLANK
	var goal := Vector2.ZERO
	var throttle := 1.0
	var firing := false
	match mode:
		Mode.FLANK:
			var p_fwd := Vector2.RIGHT.rotated(float(player.get("rotation")))
			var off := absf(p_fwd.angle_to(-to_player))   # our bearing off the player's nose
			var in_arc := off > T.OUTRIDER_FRONT_ARC
			if player_down:
				goal = to_player.normalized()
			elif in_arc and dist <= float(T.OUTRIDER_ORBIT[1]) + 60.0:
				# Strafe: swing the nose onto the player and fire.
				var player_vel: Vector2 = player.get("velocity")
				goal = (player.global_position + player_vel * clampf(dist / bullet_speed, 0.0, 0.6) - global_position).normalized()
				firing = absf(forward.angle_to(to_player)) < T.OUTRIDER_STRAFE_CONE
				# Hold the orbit band while it strafes: ease off as it closes,
				# and inside 220 px slide past sideways instead of ramming.
				throttle = clampf((dist - float(T.OUTRIDER_ORBIT[0])) / (float(T.OUTRIDER_ORBIT[1]) - float(T.OUTRIDER_ORBIT[0])), 0.25, 1.0)
				if dist < float(T.OUTRIDER_ORBIT[0]):
					# Pass made: overshoot and loop back out to the orbit band.
					_start_break(to_player, false)
			else:
				# Head for a point in the player's side/rear arc on our side.
				if _side == 0.0:
					_side = 1.0
				var side_now := signf(p_fwd.cross(-to_player))
				if side_now != 0.0:
					_side = side_now
				var orbit := (float(T.OUTRIDER_ORBIT[0]) + float(T.OUTRIDER_ORBIT[1])) * 0.5
				var spot: Vector2 = player.global_position + (-p_fwd).rotated(_side * (PI * 0.5 - T.OUTRIDER_FRONT_ARC * 0.5)) * orbit
				goal = (spot - global_position).normalized()
			if firing and not _was_firing:
				strafes += 1
			# Break when the guns overheat (once per overheat: it doesn't keep
			# fleeing while they cool) or one of our facings is stripped.
			var hot := _guns_hot()
			if (hot and not _broke_hot) or _facing_stripped():
				_start_break(to_player)
				_broke_hot = hot
			elif not hot:
				_broke_hot = false
		Mode.BREAK:
			goal = (_break_to - global_position).normalized()
			if global_position.distance_to(_break_to) < 80.0 or _mode_time <= 0.0:
				mode = Mode.FLANK
		Mode.UNSTICK:
			goal = -forward.rotated(_side * 0.6)
			if _mode_time <= 0.0:
				mode = Mode.FLANK
	_was_firing = firing
	if mode != Mode.UNSTICK:
		goal = _avoid_walls(goal, forward)
	drive_input = goal * throttle
	fire_trigger = firing and not player_down and _sees_player and dist < gun_range()
	if mode != Mode.UNSTICK and get_real_velocity().length() < 40.0:
		_stuck_time += delta
		if _stuck_time > 0.8:
			mode = Mode.UNSTICK
			_mode_time = 0.9
			_side = 1.0 if randf() < 0.5 else -1.0
			_stuck_time = 0.0
	else:
		_stuck_time = 0.0


var _was_firing := false
var _broke_hot := false   # already broke off for this overheat
var _stripped_seen := 0


func _guns_hot() -> bool:
	for i in _heat.size():
		if is_overheated(i):
			return true
	return false


## True once per newly stripped facing.
func _facing_stripped() -> bool:
	var n := 0
	for i in 4:
		if facing_max[i] > 0.0 and facing_armor[i] <= 0.0:
			n += 1
	if n > _stripped_seen:
		_stripped_seen = n
		return true
	return false


func _start_break(to_player: Vector2, real := true) -> void:
	mode = Mode.BREAK
	_mode_time = T.OUTRIDER_BREAK_MAX
	var away := -to_player.normalized()
	if away == Vector2.ZERO:
		away = Vector2.RIGHT.rotated(rotation)
	var reach := randf_range(float(T.OUTRIDER_BREAK[0]), float(T.OUTRIDER_BREAK[1])) if real else float(T.OUTRIDER_ORBIT[1])
	_break_to = player.global_position + away.rotated(randf_range(-0.5, 0.5)) * reach
	if real:
		breaks += 1
